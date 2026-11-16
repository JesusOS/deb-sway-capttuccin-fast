#!/usr/bin/env bash
set -e

echo "=================================================================="
echo "   Instalador Completo de Sway + Waybar + Kitty + Wofi"
echo "=================================================================="

# Deteccion automatica de portatil
AUTO_LAPTOP=false
if ls /sys/class/power_supply/BAT* >/dev/null 2>&1 || [ -f /sys/class/dmi/id/chassis_type ]; then
    CHASSIS=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "")
    if ls /sys/class/power_supply/BAT* >/dev/null 2>&1 || [[ "$CHASSIS" =~ ^(8|9|10|14|31|32)$ ]]; then
        AUTO_LAPTOP=true
    fi
fi

if [ "$AUTO_LAPTOP" = true ]; then
    DEFAULT_OPT="s"
    echo "-> Hardware detectado: PORTATIL."
else
    DEFAULT_OPT="n"
    echo "-> Hardware detectado: SOBREMESA o MAQUINA VIRTUAL."
fi

read -p "¿Activar opciones de portatil (bateria, brillo, touchpad)? [s/n] (Por defecto: $DEFAULT_OPT): " RESP
RESP=${RESP:-$DEFAULT_OPT}

if [[ "$RESP" =~ ^[SsYy]$ ]]; then
    IS_LAPTOP=true
    echo "   [OK] Modo PORTATIL activado."
else
    IS_LAPTOP=false
    echo "   [OK] Modo SOBREMESA / VM activado."
fi

echo ""
echo "==> 1. Actualizando repositorios e instalando paquetes oficiales..."
sudo apt update

BASE_PKGS=(
    sway waybar wofi kitty swaybg mako-notifier
    swaylock swayidle wdisplays
    greetd tuigreet
    fonts-font-awesome fonts-jetbrains-mono fonts-nerd-fonts-symbols
    grim slurp wl-clipboard xwayland
    network-manager network-manager-gnome
    pasystray pavucontrol btop pciutils
)

if [ "$IS_LAPTOP" = true ]; then
    BASE_PKGS+=(brightnessctl)
fi

sudo apt install -y "${BASE_PKGS[@]}"

# Limpiar posibles fuentes corruptas previas
rm -f ~/.local/share/fonts/JetBrainsMonoNerdFont*.ttf
fc-cache -fv > /dev/null 2>&1 || true

echo "==> 2. Habilitando NetworkManager..."
sudo systemctl enable --now NetworkManager

echo "==> 3. Creando directorios y copias de seguridad..."
mkdir -p ~/.config/{sway,waybar,kitty,wofi}

for dir in sway waybar kitty wofi; do
    if [ -d "$HOME/.config/$dir" ] && [ "$(ls -A $HOME/.config/$dir)" ]; then
        cp -r "$HOME/.config/$dir" "$HOME/.config/${dir}.bak.$(date +%s)"
    fi
done

echo "==> 4. Analizando arquitectura grafica y entorno..."
GPUS=$(lspci | grep -iE "vga|3d|display")
HAS_NVIDIA=false
HAS_IGPU=false
IS_VM=false

if systemd-detect-virt -q 2>/dev/null || echo "$GPUS" | grep -qiE "vmware|virtualbox|qemu|virtio|qxl"; then
    IS_VM=true
fi

if echo "$GPUS" | grep -qi "nvidia"; then
    HAS_NVIDIA=true
fi

if echo "$GPUS" | grep -qiE "amd|ati|intel"; then
    HAS_IGPU=true
fi

# Limpiar configuraciones previas
sudo rm -f /etc/environment.d/90-nvidia-wayland.conf
sudo rm -f /etc/environment.d/90-vm-wayland.conf

if [ "$IS_VM" = true ]; then
    echo "    -> Entorno VIRTUALIZADO detectado. Configurando cursor y renderizado estable."
    SWAY_CMD="sway"
    cat << 'EOF' | sudo tee /etc/environment.d/90-vm-wayland.conf > /dev/null
WLR_RENDERER_ALLOW_SOFTWARE=1
WLR_NO_HARDWARE_CURSORS=1
EOF
elif [ "$HAS_NVIDIA" = true ] && [ "$HAS_IGPU" = true ]; then
    echo "    -> Sistema HIBRIDO detectado (Integrada + NVIDIA)."
    SWAY_CMD="sway --unsupported-gpu"
    if ! grep -q "nvidia-run" ~/.bashrc; then
        echo 'alias nvidia-run="__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only"' >> ~/.bashrc
    fi
elif [ "$HAS_NVIDIA" = true ] && [ "$HAS_IGPU" = false ]; then
    echo "    -> Sistema SOLO NVIDIA detectado."
    SWAY_CMD="sway --unsupported-gpu"
    cat << 'EOF' | sudo tee /etc/environment.d/90-nvidia-wayland.conf > /dev/null
WLR_NO_HARDWARE_CURSORS=1
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
else
    echo "    -> Sistema AMD/Intel nativo detectado."
    SWAY_CMD="sway"
fi

echo "==> 5. Configurando gestor de inicio de sesion..."
sudo mkdir -p /etc/greetd
cat << EOF | sudo tee /etc/greetd/config.toml > /dev/null
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd '$SWAY_CMD'"
user = "_greetd"
EOF

sudo systemctl disable getty@tty1 || true
sudo systemctl enable greetd

####################

echo "==> 6. Escribiendo configuracion de Sway..."
cat << 'EOF' > ~/.config/sway/config
set $mod Mod1
set $term kitty
set $menu wofi --show drun

input "type:keyboard" {
    xkb_layout es
}

output * bg #1e1e2e solid_color

gaps inner 8
gaps outer 4
default_border pixel 2

client.focused          #89b4fa  #1e1e2e  #cdd6f4  #89b4fa   #89b4fa
client.focused_inactive #313244  #1e1e2e  #cdd6f4  #313244   #313244
client.unfocused        #313244  #1e1e2e  #6c7086  #313244   #313244
client.urgent           #f38ba8  #1e1e2e  #cdd6f4  #f38ba8   #f38ba8

### Atajos principales
bindsym $mod+Return exec $term
bindsym $mod+d exec $menu
bindsym $mod+Shift+q kill
bindsym $mod+Shift+c reload
bindsym $mod+Shift+e exec swaynag -t warning -m 'Salir de Sway?' -B 'Si, salir' 'swaymsg exit'
bindsym $mod+Shift+s exec sh -c 'grim -g "$(slurp)" - | wl-copy'

### Bloqueo de pantalla e inactividad
bindsym $mod+l exec swaylock -f -c 1e1e2e --ring-color 89b4fa --key-hl-color a6e3a1 --inside-color 181825 --text-color cdd6f4

exec swayidle -w \
    timeout 300 'swaylock -f -c 1e1e2e --ring-color 89b4fa --key-hl-color a6e3a1 --inside-color 181825 --text-color cdd6f4' \
    timeout 600 'swaymsg "output * power off"' \
    resume 'swaymsg "output * power on"' \
    before-sleep 'swaylock -f -c 1e1e2e --ring-color 89b4fa --key-hl-color a6e3a1 --inside-color 181825 --text-color cdd6f4'

### Teclas multimedia
bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle

### Navegacion, Ventanas y Multimonitor
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

bindsym $mod+Control+Left move workspace to output left
bindsym $mod+Control+Right move workspace to output right

bindsym $mod+b splith
bindsym $mod+v splitv
bindsym $mod+f fullscreen toggle
bindsym $mod+Shift+space floating toggle

### Workspaces
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5

bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5

### Barra y Applets
bar {
    swaybar_command waybar
}

exec mako
exec nm-applet --indicator
exec pasystray

include /etc/sway/config.d/*
EOF

if [ "$IS_LAPTOP" = true ]; then
    cat << 'EOF' >> ~/.config/sway/config

### Configuracion especifica de Portatil
input "type:touchpad" {
    tap enabled
    natural_scroll enabled
}

bindsym XF86MonBrightnessUp exec brightnessctl set +5%
bindsym XF86MonBrightnessDown exec brightnessctl set 5%-
EOF
fi

echo "==> 7. Escribiendo configuracion de Waybar..."
if [ "$IS_LAPTOP" = true ]; then
    MODULES_RIGHT='["pulseaudio", "network", "cpu", "memory", "battery", "sway/language", "clock", "tray"]'
else
    MODULES_RIGHT='["pulseaudio", "network", "cpu", "memory", "sway/language", "clock", "tray"]'
fi

cat << EOF > ~/.config/waybar/config.jsonc
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,

    "modules-left": ["sway/workspaces", "sway/mode"],
    "modules-center": ["sway/window"],
    "modules-right": $MODULES_RIGHT,

    "sway/workspaces": {
        "disable-scroll": true,
        "all-outputs": true,
        "format": "{name}"
    },
    "sway/window": {
        "max-length": 40
    },
    "pulseaudio": {
        "format": "{volume}% {icon}",
        "format-muted": "Mudo \uf6a9",
        "format-icons": {
            "default": ["\uf026", "\uf027", "\uf028"]
        },
        "on-click": "pavucontrol"
    },
    "network": {
        "format-wifi": "{essid} ({signalStrength}%) \uf1eb",
        "format-ethernet": "{ipaddr}/{cidr} \uf796",
        "format-disconnected": "Sin red \uf071",
        "on-click": "nm-connection-editor"
    },
    "cpu": {
        "format": "{usage}% \uf2db",
        "on-click": "kitty -e btop"
    },
    "memory": {
        "format": "{}% \uf538",
        "on-click": "kitty -e btop"
    },
    "battery": {
        "states": {
            "warning": 30,
            "critical": 15
        },
        "format": "{capacity}% {icon}",
        "format-charging": "{capacity}% \uf0e7",
        "format-icons": ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240"]
    },
    "sway/language": {
        "format": "{short}"
    },
    "clock": {
        "format": "{:%H:%M}",
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>"
    },
    "tray": {
        "icon-size": 16,
        "spacing": 8
    }
}
EOF

cat << 'EOF' > ~/.config/waybar/style.css
* {
    font-family: "JetBrains Mono", "Symbols Nerd Font", "Font Awesome 6 Free", sans-serif;
    font-size: 13px;
    border: none;
    border-radius: 6px;
}

window#waybar {
    background-color: #181825;
    color: #cdd6f4;
    border-bottom: 2px solid #89b4fa;
    border-radius: 0;
}

#workspaces button {
    padding: 0 10px;
    margin: 3px 2px;
    color: #6c7086;
    background-color: #1e1e2e;
}

#workspaces button.focused {
    color: #1e1e2e;
    background-color: #89b4fa;
    font-weight: bold;
}

#window {
    color: #cdd6f4;
    padding: 0 10px;
}

#clock, #cpu, #memory, #network, #pulseaudio, #battery, #language, #tray {
    padding: 0 10px;
    margin: 3px 3px;
    background-color: #1e1e2e;
}

#pulseaudio { color: #f9e2af; }
#network    { color: #89b4fa; }
#cpu        { color: #a6e3a1; }
#memory     { color: #cba6f7; }
#battery    { color: #a6e3a1; }
#battery.warning  { color: #fab387; }
#battery.critical { color: #f38ba8; }
#language   { color: #94e2d5; }
#clock      { color: #f5c2e7; font-weight: bold; }
EOF

echo "==> 8. Escribiendo configuracion de Kitty..."
cat << 'EOF' > ~/.config/kitty/kitty.conf
font_family             JetBrains Mono
font_size               11.5
window_padding_width    10
confirm_os_window_close 0
background_opacity      0.90

foreground              #CDD6F4
background              #1E1E2E
cursor                  #F5E0DC
selection_foreground    #1E1E2E
selection_background    #F5E0DC

color0                  #45475A
color8                  #585B70
color1                  #F38BA8
color9                  #F38BA8
color2                  #A6E3A1
color10                 #A6E3A1
color3                  #F9E2AF
color11                 #F9E2AF
color4                  #89B4FA
color12                 #89B4FA
color5                  #F5C2E7
color13                 #F5C2E7
color6                  #94E2D5
color14                 #94E2D5
color7                  #BAC2DE
color15                 #A6ADC8
EOF

echo "==> 9. Escribiendo configuracion de Wofi..."
cat << 'EOF' > ~/.config/wofi/style.css
window {
    margin: 0px;
    border: 2px solid #89b4fa;
    border-radius: 10px;
    background-color: #1e1e2e;
    font-family: "JetBrains Mono", sans-serif;
    font-size: 14px;
}

#input {
    margin: 10px;
    padding: 6px 10px;
    border: none;
    color: #cdd6f4;
    background-color: #313244;
    border-radius: 6px;
}

#inner-box {
    margin: 0 10px 10px 10px;
}

#entry {
    padding: 6px 10px;
    color: #cdd6f4;
}

#entry:selected {
    background-color: #89b4fa;
    color: #1e1e2e;
    border-radius: 6px;
    font-weight: bold;
}
EOF

echo ""
echo "=================================================================="
echo " Instalacion completada con exito."
echo " Ejecuta 'sudo reboot' para entrar en tu nuevo escritorio Sway."
echo "=================================================================="