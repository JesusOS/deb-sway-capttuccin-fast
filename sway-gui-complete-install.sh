#!/usr/bin/env bash
set -e

echo "==> 1. Actualizando repositorios e instalando paquetes..."
sudo apt update
sudo apt install -y \
    sway waybar wofi kitty swaybg mako-notifier \
    swaylock swayidle brightnessctl \
    greetd tuigreet \
    fonts-font-awesome fonts-jetbrains-mono \
    grim slurp wl-clipboard xwayland \
    network-manager network-manager-gnome \
    pasystray pavucontrol btop pciutils

echo "==> 2. Habilitando NetworkManager..."
sudo systemctl enable --now NetworkManager

echo "==> 3. Creando directorios y copias de seguridad..."
mkdir -p ~/.config/{sway,waybar,kitty,wofi}

for dir in sway waybar kitty wofi; do
    if [ -d "$HOME/.config/$dir" ] && [ "$(ls -A $HOME/.config/$dir)" ]; then
        cp -r "$HOME/.config/$dir" "$HOME/.config/${dir}.bak.$(date +%s)"
    fi
done

echo "==> 4. Analizando arquitectura grÃ¡fica (GPU)..."
GPUS=$(lspci | grep -iE "vga|3d|display")
HAS_NVIDIA=false
HAS_IGPU=false

if echo "$GPUS" | grep -qi "nvidia"; then
    HAS_NVIDIA=true
fi

if echo "$GPUS" | grep -qiE "amd|ati|intel"; then
    HAS_IGPU=true
fi

if [ "$HAS_NVIDIA" = true ] && [ "$HAS_IGPU" = true ]; then
    echo "    -> Sistema HÃBRIDO detectado (Integrada + NVIDIA)."
    echo "    -> El escritorio usarÃ¡ la integrada y se aÃ±ade 'nvidia-run' para la dedicada."
    SWAY_CMD="sway --unsupported-gpu"
    sudo rm -f /etc/environment.d/90-nvidia-wayland.conf
    if ! grep -q "nvidia-run" ~/.bashrc; then
        echo 'alias nvidia-run="__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only"' >> ~/.bashrc
    fi
elif [ "$HAS_NVIDIA" = true ] && [ "$HAS_IGPU" = false ]; then
    echo "    -> Sistema SOLO NVIDIA detectado."
    echo "    -> Configurando variables globales de Wayland para NVIDIA."
    SWAY_CMD="sway --unsupported-gpu"
    cat << 'INNER_EOF' | sudo tee /etc/environment.d/90-nvidia-wayland.conf > /dev/null
WLR_NO_HARDWARE_CURSORS=1
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
INNER_EOF
else
    echo "    -> Sistema AMD/Intel nativo detectado. Usando configuraciÃ³n estÃ¡ndar."
    SWAY_CMD="sway"
    sudo rm -f /etc/environment.d/90-nvidia-wayland.conf
fi

echo "==> 5. Configurando gestor de inicio de sesiÃ³n (greetd + tuigreet)..."
sudo mkdir -p /etc/greetd
cat << INNER_EOF | sudo tee /etc/greetd/config.toml > /dev/null
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd '$SWAY_CMD'"
user = "_greetd"
INNER_EOF
sudo systemctl enable greetd

echo "==> 6. Escribiendo configuraciÃ³n de Sway..."
cat << 'INNER_EOF' > ~/.config/sway/config
set $mod Mod1
set $term kitty
set $menu wofi --show drun

### Teclado y Pantalla
input "type:keyboard" {
    xkb_layout es
}

input "type:touchpad" {
    tap enabled
    natural_scroll enabled
}

output * bg #1e1e2e solid_color

### EstÃ©tica de ventanas (Catppuccin Mocha)
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
bindsym $mod+Shift+e exec swaynag -t warning -m 'Â¿Salir de Sway?' -B 'SÃ­, salir' 'swaymsg exit'
bindsym $mod+Shift+s exec grim -g "$(slurp)" - | wl-copy

### Bloqueo de pantalla e inactividad
bindsym $mod+l exec swaylock -f -c 1e1e2e --ring-color 89b4fa --key-hl-color a6e3a1 --inside-color 181825 --text-color cdd6f4

exec swayidle -w \
    timeout 300 'swaylock -f -c 1e1e2e --ring-color 89b4fa --key-hl-color a6e3a1 --inside-color 181825 --text-color cdd6f4' \
    timeout 600 'swaymsg "output * power off"' \
    resume 'swaymsg "output * power on"' \
    before-sleep 'swaylock -f -c 1e1e2e --ring-color 89b4fa --key-hl-color a6e3a1 --inside-color 181825 --text-color cdd6f4'

### Teclas multimedia y brillo
bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle
bindsym XF86MonBrightnessUp exec brightnessctl set +5%
bindsym XF86MonBrightnessDown exec brightnessctl set 5%-

### NavegaciÃ³n y Ventanas
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

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
INNER_EOF

echo "==> 7. Escribiendo configuraciÃ³n de Waybar..."
cat << 'INNER_EOF' > ~/.config/waybar/config.jsonc
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,

    "modules-left": ["sway/workspaces", "sway/mode"],
    "modules-center": ["sway/window"],
    "modules-right": ["pulseaudio", "network", "cpu", "memory", "battery", "sway/language", "clock", "tray"],

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
        "format-muted": "Mudo ï€¦",
        "format-icons": {
            "default": ["ï€¦", "ï€§", "ï€¨"]
        },
        "on-click": "pavucontrol"
    },
    "network": {
        "format-wifi": "{essid} ({signalStrength}%) ï‡«",
        "format-ethernet": "{ipaddr}/{cidr} ïž–",
        "format-disconnected": "Sin red âš ",
        "on-click": "nm-connection-editor"
    },
    "cpu": {
        "format": "{usage}% ï‹›",
        "on-click": "kitty -e btop"
    },
    "memory": {
        "format": "{}% ïƒ‰",
        "on-click": "kitty -e btop"
    },
    "battery": {
        "states": {
            "warning": 30,
            "critical": 15
        },
        "format": "{capacity}% {icon}",
        "format-charging": "{capacity}% ï—§",
        "format-icons": ["ï‰„", "ï‰ƒ", "ï‰‚", "ï‰", "ï‰€"]
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
INNER_EOF

cat << 'INNER_EOF' > ~/.config/waybar/style.css
* {
    font-family: "JetBrains Mono", "Font Awesome 6 Free", sans-serif;
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
INNER_EOF

echo "==> 8. Escribiendo configuraciÃ³n de Kitty..."
cat << 'INNER_EOF' > ~/.config/kitty/kitty.conf
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
INNER_EOF

echo "==> 9. Escribiendo configuraciÃ³n de Wofi..."
cat << 'INNER_EOF' > ~/.config/wofi/style.css
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
INNER_EOF

echo "âœ… Â¡InstalaciÃ³n completada! Reinicia el equipo para entrar por tu nuevo gestor de sesiÃ³n."
