#!/usr/bin/env bash
set -e

echo "==> 1. Actualizando repositorios e instalando paquetes..."
sudo apt update
sudo apt install -y \
    sway waybar wofi kitty swaybg mako-notifier \
    fonts-font-awesome fonts-jetbrains-mono \
    grim slurp wl-clipboard xwayland

echo "==> 2. Creando directorios de configuración..."
mkdir -p ~/.config/{sway,waybar,kitty,wofi}

# Copia de seguridad si ya existía configuración previa
for dir in sway waybar kitty wofi; do
    if [ -d "$HOME/.config/$dir" ] && [ "$(ls -A $HOME/.config/$dir)" ]; then
        cp -r "$HOME/.config/$dir" "$HOME/.config/${dir}.bak.$(date +%s)"
    fi
done

echo "==> 3. Escribiendo configuración de Sway..."
cat << 'EOF' > ~/.config/sway/config
set $mod Mod1
set $term env LIBGL_ALWAYS_SOFTWARE=1 MESA_GL_VERSION_OVERRIDE=3.3 kitty
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

bindsym $mod+Return exec $term
bindsym $mod+d exec $menu
bindsym $mod+Shift+q kill
bindsym $mod+Shift+c reload
bindsym $mod+Shift+e exec swaynag -t warning -m '¿Salir de Sway?' -B 'Sí, salir' 'swaymsg exit'
bindsym $mod+Shift+s exec grim -g "$(slurp)" - | wl-copy

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

bar {
    swaybar_command waybar
}

exec mako

include /etc/sway/config.d/*
EOF

echo "==> 4. Escribiendo configuración de Waybar..."
cat << 'EOF' > ~/.config/waybar/config.jsonc
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,

    "modules-left": ["sway/workspaces", "sway/mode"],
    "modules-center": ["sway/window"],
    "modules-right": ["pulseaudio", "network", "cpu", "memory", "sway/language", "clock"],

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
        "format-muted": "Mudo ",
        "format-icons": {
            "default": ["", "", ""]
        }
    },
    "network": {
        "format-wifi": "{essid} ({signalStrength}%) ",
        "format-ethernet": "{ipaddr}/{cidr} ",
        "format-disconnected": "Sin red ⚠"
    },
    "cpu": {
        "format": "{usage}% ",
        "tooltip": false
    },
    "memory": {
        "format": "{}% "
    },
    "sway/language": {
        "format": "{short}"
    },
    "clock": {
        "format": "{:%H:%M}",
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>"
    }
}
EOF

cat << 'EOF' > ~/.config/waybar/style.css
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

#clock, #cpu, #memory, #network, #pulseaudio, #language {
    padding: 0 10px;
    margin: 3px 3px;
    background-color: #1e1e2e;
}

#pulseaudio { color: #f9e2af; }
#network    { color: #89b4fa; }
#cpu        { color: #a6e3a1; }
#memory     { color: #cba6f7; }
#language   { color: #94e2d5; }
#clock      { color: #f5c2e7; font-weight: bold; }
EOF

echo "==> 5. Escribiendo configuración de Kitty..."
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

echo "==> 6. Escribiendo configuración de Wofi..."
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

echo "==> 7. Añadiendo variables para VMware en ~/.profile..."
if ! grep -q "WLR_RENDERER_ALLOW_SOFTWARE" ~/.profile; then
    cat << 'EOF' >> ~/.profile

# Sway en VMware sin 3D
export WLR_RENDERER_ALLOW_SOFTWARE=1
export WLR_NO_HARDWARE_CURSORS=1
EOF
fi

echo "✅ ¡Instalación completada! Ejecuta 'sway' para iniciar tu entorno."
