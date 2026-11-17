#!/usr/bin/env bash
#
# Instalador modular de un escritorio Sway para Debian 13 (Trixie).
# Adaptable a equipos físicos, portátiles, sobremesa y máquinas virtuales.
#
# Componentes:
#   Sway, Waybar, Wofi, Kitty/Foot, Mako, swaylock, swayidle, swaybg
#   NetworkManager + nm-applet + nm-connection-editor + nmcli + nmtui
#   PipeWire + WirePlumber + pavucontrol + wpctl
#   Thunar, Mousepad, btop, htop, fastfetch, wdisplays
#   Capturas, portales XDG, polkit, herramientas de portátil y diagnóstico
#
# No instala Cockpit, Apache, Nginx ni ningún panel/servidor web.
# No instala ni modifica controladores gráficos propietarios.
#
# Uso:
#   chmod +x install-sway-debian13.sh
#   ./install-sway-debian13.sh
#
# Opciones:
#   --no-greetd       No preparar ni activar greetd
#   --enable-greetd   Preparar y activar greetd sin preguntar
#   --skip-upgrade    No ejecutar apt-get upgrade
#   --help            Mostrar ayuda
#
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_VERSION="1.0.0"
readonly TARGET_DEBIAN_MAJOR="13"

INSTALL_GREETD="ask"
RUN_UPGRADE="yes"
LOG_DIR="${HOME}/.local/state/sway-installer"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/install-${TIMESTAMP}.log"
BACKUP_ROOT="${HOME}/.config-backups/sway-${TIMESTAMP}"
CONFIG_ROOT="${HOME}/.config"
BIN_ROOT="${HOME}/.local/bin"
WALLPAPER_DIR="${HOME}/Pictures/Wallpapers"

IS_ROOT=0
IS_LAPTOP=0
IS_VM=0
GPU_SUMMARY="No detectada"
GPU_VENDOR="unknown"
HAS_NVIDIA=0
HAS_AMD=0
HAS_INTEL=0
HAS_BATTERY=0
HAS_BRIGHTNESS=0
HAS_TOUCHPAD=0
HAS_ETHERNET=0
HAS_WIFI=0
HAS_BLUETOOTH=0
HAS_X86=0
CURRENT_DM=""
LAYOUT="es"
VARIANT=""

# ---------------------------------------------------------------------------
# Ayuda y argumentos
# ---------------------------------------------------------------------------

show_help() {
    cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Instala y configura un escritorio Sway ligero para Debian 13 (Trixie).

Opciones:
  --no-greetd       No preparar ni activar greetd.
  --enable-greetd   Preparar y activar greetd sin preguntar.
  --skip-upgrade    Omitir apt-get upgrade.
  --help            Mostrar esta ayuda.

El instalador:
  - Detecta GPU AMD, Intel, NVIDIA y entornos virtuales.
  - Detecta portátil, batería, brillo, Wi-Fi y Bluetooth.
  - Instala herramientas gráficas y CLI para red y audio.
  - Genera configuraciones Catppuccin Mocha.
  - Conserva copias de seguridad de configuraciones existentes.
  - No instala servicios web de administración.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --no-greetd) INSTALL_GREETD="no" ;;
        --enable-greetd) INSTALL_GREETD="yes" ;;
        --skip-upgrade) RUN_UPGRADE="no" ;;
        --help|-h) show_help; exit 0 ;;
        *) echo "Opción desconocida: $arg" >&2; show_help; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Utilidades generales, log y manejo de errores
# ---------------------------------------------------------------------------

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

info()    { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn()    { printf '\033[1;33m[AVISO]\033[0m %s\n' "$*"; }
error()   { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()     { error "$*"; exit 1; }

on_error() {
    local exit_code=$?
    error "Fallo en la línea ${BASH_LINENO[0]:-desconocida} (código ${exit_code})."
    error "Consulta el registro: ${LOG_FILE}"
    exit "$exit_code"
}
trap on_error ERR

command_exists() { command -v "$1" >/dev/null 2>&1; }

ask_yes_no() {
    local prompt="$1"
    local default="${2:-N}"
    local reply
    if [[ ! -t 0 ]]; then
        [[ "$default" == "Y" ]]
        return
    fi
    if [[ "$default" == "Y" ]]; then
        read -r -p "${prompt} [S/n]: " reply || true
        reply="${reply:-S}"
    else
        read -r -p "${prompt} [s/N]: " reply || true
        reply="${reply:-N}"
    fi
    [[ "$reply" =~ ^([sS]|[sS][iI])$ ]]
}

require_sudo() {
    if [[ "$EUID" -eq 0 ]]; then
        IS_ROOT=1
        SUDO=()
    else
        command_exists sudo || die "Necesitas sudo instalado."
        sudo -v || die "No se pudo obtener autorización sudo."
        SUDO=(sudo)
    fi
}

run_root() {
    "${SUDO[@]}" "$@"
}

backup_path() {
    local path="$1"
    [[ -e "$path" ]] || return 0
    local relative="${path#/}"
    local destination="${BACKUP_ROOT}/${relative}"
    mkdir -p "$(dirname "$destination")"
    cp -a "$path" "$destination"
    info "Copia de seguridad: $path -> $destination"
}

# ---------------------------------------------------------------------------
# Comprobaciones de sistema
# ---------------------------------------------------------------------------

check_os() {
    [[ -r /etc/os-release ]] || die "No encuentro /etc/os-release."
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "debian" ]] || die "Este instalador está preparado para Debian."
    [[ "${VERSION_ID:-}" == "$TARGET_DEBIAN_MAJOR" ]] || {
        die "Se requiere Debian ${TARGET_DEBIAN_MAJOR} (Trixie). Detectado: ${PRETTY_NAME:-desconocido}"
    }
    info "Sistema detectado: ${PRETTY_NAME}"
    if [[ "${VERSION_CODENAME:-}" != "trixie" ]]; then
        warn "El identificador de versión no indica trixie; comprueba tus repositorios."
    fi
}

check_session() {
    if [[ -z "${HOME:-}" || "$HOME" == "/" ]]; then
        die "HOME no es válido. Ejecuta el instalador desde tu usuario normal, no con sudo."
    fi
    if [[ "$EUID" -eq 0 && -z "${SUDO_USER:-}" ]]; then
        warn "Estás ejecutando como root directamente. Las configuraciones se escribirán en ${HOME}."
    fi
    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        info "Sesión Wayland detectada: ${WAYLAND_DISPLAY}"
    fi
}

# ---------------------------------------------------------------------------
# Detección de hardware: GPU, VM, portátil, dispositivos
# ---------------------------------------------------------------------------

detect_hardware() {
    info "Detectando hardware..."

    if command_exists lspci; then
        local display_devices
        display_devices="$(lspci -nn 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)"
        if [[ -n "$display_devices" ]]; then
            GPU_SUMMARY="$(printf '%s' "$display_devices" | sed 's/^[[:space:]]*//')"
            grep -qi 'NVIDIA' <<<"$display_devices" && HAS_NVIDIA=1
            grep -qiE 'AMD|ATI' <<<"$display_devices" && HAS_AMD=1
            grep -qi 'Intel' <<<"$display_devices" && HAS_INTEL=1
        fi
    fi

    if [[ "$HAS_NVIDIA" -eq 1 ]]; then
        GPU_VENDOR="nvidia"
    elif [[ "$HAS_AMD" -eq 1 && "$HAS_INTEL" -eq 1 ]]; then
        GPU_VENDOR="hybrid-amd-intel"
    elif [[ "$HAS_AMD" -eq 1 ]]; then
        GPU_VENDOR="amd"
    elif [[ "$HAS_INTEL" -eq 1 ]]; then
        GPU_VENDOR="intel"
    fi

    if grep -qiE 'KVM|QEMU|VMware|VirtualBox|Virtual Machine|Microsoft Corporation Virtual' /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null; then
        IS_VM=1
    fi
    if command_exists systemd-detect-virt && systemd-detect-virt --quiet; then
        IS_VM=1
    fi

    if [[ -d /sys/class/power_supply ]]; then
        for p in /sys/class/power_supply/*; do
            [[ -e "$p" ]] || continue
            [[ "$(cat "$p/type" 2>/dev/null || true)" == "Battery" ]] && HAS_BATTERY=1
        done
    fi

    [[ -d /sys/class/backlight ]] && compgen -G '/sys/class/backlight/*' >/dev/null && HAS_BRIGHTNESS=1
    [[ -d /sys/class/input ]] && HAS_TOUCHPAD=1

    if command_exists ip; then
        ip -o link show 2>/dev/null | grep -qE 'wl[a-zA-Z0-9]+' && HAS_WIFI=1 || true
        ip -o link show 2>/dev/null | grep -qE 'en[a-zA-Z0-9]+|eth[0-9]+' && HAS_ETHERNET=1 || true
    fi

    if [[ -d /sys/class/bluetooth ]] || compgen -G '/sys/class/bluetooth/*' >/dev/null; then
        HAS_BLUETOOTH=1
    fi

    [[ "$(uname -m)" == "x86_64" || "$(uname -m)" == "i686" ]] && HAS_X86=1

    info "GPU: ${GPU_VENDOR} — ${GPU_SUMMARY}"
    [[ "$IS_VM" -eq 1 ]] && info "Entorno virtualizado detectado."
    [[ "$HAS_BATTERY" -eq 1 ]] && info "Batería detectada."
    [[ "$HAS_BRIGHTNESS" -eq 1 ]] && info "Dispositivo de brillo detectado."
    [[ "$HAS_WIFI" -eq 1 ]] && info "Interfaz Wi-Fi detectada."
    [[ "$HAS_ETHERNET" -eq 1 ]] && info "Interfaz Ethernet detectada."
    [[ "$HAS_BLUETOOTH" -eq 1 ]] && info "Bluetooth detectado."
}

choose_layout() {
    local detected=""
    if command_exists localectl; then
        detected="$(localectl status 2>/dev/null | awk -F: '/X11 Layout/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')"
    fi
    if [[ -n "$detected" ]]; then
        LAYOUT="${detected%%,*}"
    else
        LAYOUT="es"
    fi

    if [[ -t 0 ]]; then
        read -r -p "Distribución de teclado XKB [${LAYOUT}]: " reply || true
        LAYOUT="${reply:-$LAYOUT}"
    fi
    [[ "$LAYOUT" =~ ^[a-zA-Z0-9_-]+$ ]] || LAYOUT="es"
    info "Distribución de teclado: ${LAYOUT}"
}

# ---------------------------------------------------------------------------
# Paquetes: listas separadas para facilitar mantenimiento
# ---------------------------------------------------------------------------

BASE_PACKAGES=(
    sway swaybg swayidle swaylock waybar wofi
    kitty foot
    mako-notifier
    grim slurp wl-clipboard
    xwayland
    dbus-user-session dbus-x11
    xdg-utils xdg-user-dirs
    xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    fonts-jetbrains-mono fonts-font-awesome fonts-noto-color-emoji
    thunar thunar-archive-plugin file-roller
    mousepad
    btop htop fastfetch
    wdisplays
    lxpolkit
    network-manager network-manager-gnome nm-connection-editor
    iproute2 iputils-ping dnsutils ethtool iw wireless-tools
    pipewire-audio pipewire-pulse wireplumber pavucontrol
    alsa-utils
    pciutils usbutils lshw
    curl wget ca-certificates git
    brightnessctl
)

OPTIONAL_PACKAGES=(
    blueman bluez
    rfkill
    playerctl
    p7zip-full unzip zip
    gvfs gvfs-backends gvfs-fuse
    tumbler
    policykit-1
)

LAPTOP_PACKAGES=(
    upower power-profiles-daemon
)

VM_PACKAGES=(
    spice-vdagent
)

# Add package only if apt knows it. Prevent a single optional package typo
# from aborting the entire installation.
filter_available_packages() {
    local package
    AVAILABLE_PACKAGES=()
    for package in "$@"; do
        if apt-cache show "$package" >/dev/null 2>&1; then
            AVAILABLE_PACKAGES+=("$package")
        else
            warn "Paquete no disponible en los repositorios configurados: ${package} (se omite)"
        fi
    done
}

install_packages() {
    info "Actualizando índices APT..."
    run_root apt-get update

    if [[ "$RUN_UPGRADE" == "yes" ]] && ask_yes_no "¿Quieres ejecutar también apt-get upgrade?" "N"; then
        run_root apt-get upgrade -y
    fi

    filter_available_packages "${BASE_PACKAGES[@]}" "${OPTIONAL_PACKAGES[@]}"
    local packages=("${AVAILABLE_PACKAGES[@]}")

    if [[ "$HAS_BATTERY" -eq 1 ]]; then
        filter_available_packages "${LAPTOP_PACKAGES[@]}"
        packages+=("${AVAILABLE_PACKAGES[@]}")
    fi

    if [[ "$IS_VM" -eq 1 ]]; then
        filter_available_packages "${VM_PACKAGES[@]}"
        packages+=("${AVAILABLE_PACKAGES[@]}")
    fi

    info "Instalando ${#packages[@]} paquetes..."
    run_root apt-get install -y --no-install-recommends "${packages[@]}"
    success "Paquetes instalados."
}

# ---------------------------------------------------------------------------
# Servicios base
# ---------------------------------------------------------------------------

enable_services() {
    info "Configurando servicios del sistema..."

    run_root systemctl enable NetworkManager.service
    if command_exists rfkill && [[ "$HAS_BLUETOOTH" -eq 1 ]]; then
        run_root systemctl enable bluetooth.service || warn "No se pudo habilitar Bluetooth."
    fi

    # No forzamos ni cambiamos controladores de GPU.
    # El stack Mesa incluido en Debian se gestiona por dependencias normales.
    if [[ "$HAS_NVIDIA" -eq 1 ]]; then
        warn "Se ha detectado NVIDIA. No se instalarán ni cambiarán drivers automáticamente."
        warn "Comprueba la compatibilidad de tu controlador NVIDIA con wlroots/Sway antes de migrar tu sesión."
    fi

    if [[ "$IS_VM" -eq 1 ]]; then
        info "Se detectó una VM: se han considerado herramientas de integración opcionales."
    fi
}

# ---------------------------------------------------------------------------
# Copias de seguridad y directorios
# ---------------------------------------------------------------------------

prepare_directories() {
    mkdir -p "$BACKUP_ROOT"
    mkdir -p "$CONFIG_ROOT"/{sway,waybar,kitty,foot,wofi,mako}
    mkdir -p "$BIN_ROOT" "$WALLPAPER_DIR"
    mkdir -p "${HOME}/Pictures/Screenshots"
    mkdir -p "${HOME}/.local/share"
    mkdir -p "${HOME}/.local/state"

    local item
    for item in sway waybar kitty foot wofi mako; do
        backup_path "${CONFIG_ROOT}/${item}"
    done

    backup_path "${CONFIG_ROOT}/mimeapps.list"
    success "Directorios preparados y copias de seguridad realizadas."
}

# ---------------------------------------------------------------------------
# Configuración de Sway
# ---------------------------------------------------------------------------

write_sway_config() {
    cat > "${CONFIG_ROOT}/sway/config" <<EOF
# Sway — Debian 13 / Catppuccin Mocha
# Generado por ${SCRIPT_NAME} v${SCRIPT_VERSION}
# Modifica este archivo libremente; el instalador conserva backups.

set \\$mod Mod4
set \\$term kitty
set \\$browser firefox
font pango:JetBrains Mono 10

# Teclado
input type:keyboard {
    xkb_layout "${LAYOUT}"
}

# Touchpad: opciones comunes. Si el equipo no tiene touchpad, no se aplica.
input type:touchpad {
    tap enabled
    natural_scroll enabled
    dwt enabled
    middle_emulation enabled
}

# Aspecto general
default_border pixel 2
default_floating_border pixel 2
gaps inner 6
gaps outer 3
smart_gaps on
focus_follows_mouse no
mouse_warping container
titlebar_padding 6 3

# Catppuccin Mocha
client.focused          #cba6f7 #313244 #cdd6f4 #cba6f7 #cba6f7
client.focused_inactive #45475a #181825 #a6adc8 #45475a #45475a
client.unfocused        #313244 #181825 #bac2de #313244 #313244
client.urgent           #f38ba8 #181825 #f38ba8 #f38ba8 #f38ba8
client.placeholder      #313244 #181825 #cdd6f4 #313244 #313244
client.background       #11111b

# Terminal y aplicaciones
bindsym \\$mod+Return exec \\$term
bindsym \\$mod+Shift+Return exec foot
bindsym \\$mod+d exec wofi --show drun
bindsym \\$mod+e exec thunar
bindsym \\$mod+Shift+e exec swaynag -t warning -m '¿Cerrar la sesión de Sway?' -B 'Sí, salir' 'swaymsg exit'
bindsym \\$mod+Shift+w exec firefox
bindsym \\$mod+Shift+n exec mousepad

# Gestión de ventanas
bindsym \\$mod+q kill
bindsym \\$mod+f fullscreen toggle
bindsym \\$mod+Shift+space floating toggle
bindsym \\$mod+space focus mode_toggle
bindsym \\$mod+h focus left
bindsym \\$mod+j focus down
bindsym \\$mod+k focus up
bindsym \\$mod+l focus right
bindsym \\$mod+Left focus left
bindsym \\$mod+Down focus down
bindsym \\$mod+Up focus up
bindsym \\$mod+Right focus right
bindsym \\$mod+Shift+h move left
bindsym \\$mod+Shift+j move down
bindsym \\$mod+Shift+k move up
bindsym \\$mod+Shift+l move right
bindsym \\$mod+Shift+Left move left
bindsym \\$mod+Shift+Down move down
bindsym \\$mod+Shift+Up move up
bindsym \\$mod+Shift+Right move right

# Layout
bindsym \\$mod+b splith
bindsym \\$mod+v splitv
bindsym \\$mod+s layout stacking
bindsym \\$mod+w layout tabbed
bindsym \\$mod+a focus parent
bindsym \\$mod+Shift+c reload

# Workspaces
set \\$ws1 "1"
set \\$ws2 "2"
set \\$ws3 "3"
set \\$ws4 "4"
set \\$ws5 "5"
set \\$ws6 "6"
set \\$ws7 "7"
set \\$ws8 "8"
set \\$ws9 "9"
bindsym \\$mod+1 workspace number \\$ws1
bindsym \\$mod+2 workspace number \\$ws2
bindsym \\$mod+3 workspace number \\$ws3
bindsym \\$mod+4 workspace number \\$ws4
bindsym \\$mod+5 workspace number \\$ws5
bindsym \\$mod+6 workspace number \\$ws6
bindsym \\$mod+7 workspace number \\$ws7
bindsym \\$mod+8 workspace number \\$ws8
bindsym \\$mod+9 workspace number \\$ws9
bindsym \\$mod+Shift+1 move container to workspace number \\$ws1
bindsym \\$mod+Shift+2 move container to workspace number \\$ws2
bindsym \\$mod+Shift+3 move container to workspace number \\$ws3
bindsym \\$mod+Shift+4 move container to workspace number \\$ws4
bindsym \\$mod+Shift+5 move container to workspace number \\$ws5
bindsym \\$mod+Shift+6 move container to workspace number \\$ws6
bindsym \\$mod+Shift+7 move container to workspace number \\$ws7
bindsym \\$mod+Shift+8 move container to workspace number \\$ws8
bindsym \\$mod+Shift+9 move container to workspace number \\$ws9

# Audio (PipeWire vía wpctl)
bindsym XF86AudioRaiseVolume exec wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
bindsym XF86AudioLowerVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym XF86AudioMute exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindsym XF86AudioMicMute exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
bindsym \\$mod+Shift+a exec pavucontrol
bindsym \\$mod+F10 exec pavucontrol

# Brillo: no hace nada si no existe un dispositivo compatible.
bindsym XF86MonBrightnessUp exec brightnessctl set +5%
bindsym XF86MonBrightnessDown exec brightnessctl set 5%-

# Reproducción multimedia
bindsym XF86AudioPlay exec playerctl play-pause
bindsym XF86AudioNext exec playerctl next
bindsym XF86AudioPrev exec playerctl previous

# Capturas de pantalla
bindsym Print exec grim - | wl-copy
bindsym \\$mod+Shift+s exec grim -g "$(slurp)" "${HOME}/Pictures/Screenshots/$(date +'%Y%m%d-%H%M%S').png"
bindsym \\$mod+Print exec grim -g "$(slurp)" - | wl-copy

# Bloqueo manual
bindsym \\$mod+l exec swaylock -f -c 181825

# Recarga y salida
bindsym \\$mod+Shift+r reload
bindsym \\$mod+Shift+q exec swaynag -t warning -m '¿Salir de Sway?' -B 'Salir' 'swaymsg exit'

# Notificaciones
exec mako

# Applet de red y agente polkit
exec nm-applet --indicator
exec lxpolkit

# Barra
bar {
    swaybar_command waybar
}

# Variables y portales para aplicaciones Wayland
exec dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway
exec_always --no-startup-id systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
EOF

    # Sustituimos swaybar_command por la forma recomendada: Waybar se lanza
    # como proceso de usuario, no como barra interna de swaybar.
    sed -i '/^bar {$/,/^}/d' "${CONFIG_ROOT}/sway/config"
    cat >> "${CONFIG_ROOT}/sway/config" <<'EOF'

# Waybar se ejecuta como aplicación independiente.
exec waybar

# Bloqueo automático y ahorro de energía.
exec swayidle -w \
    timeout 300 'swaylock -f -c 181825' \
    timeout 600 'swaymsg "output * power off"' \
        resume 'swaymsg "output * power on"' \
    before-sleep 'swaylock -f -c 181825'
EOF

    chmod 644 "${CONFIG_ROOT}/sway/config"
    success "Configuración de Sway escrita."
}

# ---------------------------------------------------------------------------
# Waybar
# ---------------------------------------------------------------------------

write_waybar_config() {
    cat > "${CONFIG_ROOT}/waybar/config" <<'EOF'
{
  "layer": "top",
  "position": "top",
  "height": 32,
  "spacing": 6,
  "margin-top": 4,
  "margin-left": 6,
  "margin-right": 6,
  "modules-left": ["sway/workspaces", "sway/mode", "sway/window"],
  "modules-center": ["clock"],
  "modules-right": [
    "pulseaudio",
    "network",
    "cpu",
    "memory",
    "temperature",
    "battery",
    "tray"
  ],

  "sway/workspaces": {
    "disable-scroll": true,
    "all-outputs": true,
    "format": "{name}",
    "format-icons": {
      "1": "一",
      "2": "二",
      "3": "三",
      "4": "四",
      "5": "五",
      "urgent": "",
      "focused": "",
      "default": ""
    }
  },
  "sway/mode": {
    "format": " {}",
    "max-length": 40
  },
  "sway/window": {
    "max-length": 50,
    "format": "{}"
  },
  "clock": {
    "format": "  {:%a %d %b  %H:%M}",
    "tooltip-format": "<big>{:%A, %d de %B de %Y}</big>\n<tt>{calendar}</tt>"
  },
  "pulseaudio": {
    "format": "{icon} {volume}%",
    "format-muted": " silenciado",
    "format-icons": {
      "default": ["", "", ""]
    },
    "on-click": "pavucontrol",
    "on-click-right": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
    "scroll-step": 5
  },
  "network": {
    "format-wifi": "  {essid} ({signalStrength}%)",
    "format-ethernet": "󰈀  {ipaddr}",
    "format-disconnected": " sin red",
    "tooltip-format": "{ifname}: {ipaddr}/{cidr}\nGateway: {gwaddr}",
    "on-click": "nm-connection-editor",
    "on-click-right": "foot -e nmtui"
  },
  "cpu": {
    "interval": 3,
    "format": " {usage}%",
    "tooltip": true
  },
  "memory": {
    "interval": 5,
    "format": " {percentage}%",
    "tooltip-format": "RAM: {used:0.1f} GiB / {total:0.1f} GiB"
  },
  "temperature": {
    "critical-threshold": 80,
    "format": " {temperatureC}°C",
    "format-critical": " {temperatureC}°C",
    "tooltip": true
  },
  "battery": {
    "states": {
      "warning": 30,
      "critical": 15
    },
    "format": "{icon} {capacity}%",
    "format-charging": " {capacity}%",
    "format-plugged": " {capacity}%",
    "format-icons": ["", "", "", "", ""],
    "tooltip": true
  },
  "tray": {
    "icon-size": 16,
    "spacing": 8
  }
}
EOF

    cat > "${CONFIG_ROOT}/waybar/style.css" <<'EOF'
/* Catppuccin Mocha */
* {
    font-family: "JetBrains Mono", "FontAwesome", sans-serif;
    font-size: 12px;
    min-height: 0;
    border: none;
    border-radius: 0;
}

window#waybar {
    background: rgba(24, 24, 37, 0.96);
    color: #cdd6f4;
    border: 1px solid #313244;
    border-radius: 10px;
}

#workspaces button {
    padding: 0 8px;
    color: #a6adc8;
    background: transparent;
    border-radius: 7px;
}

#workspaces button.focused {
    color: #1e1e2e;
    background: #cba6f7;
}

#workspaces button.urgent {
    color: #1e1e2e;
    background: #f38ba8;
}

#mode, #window, #clock, #pulseaudio, #network,
#cpu, #memory, #temperature, #battery, #tray {
    padding: 0 9px;
    margin: 4px 2px;
    background: #313244;
    border-radius: 7px;
}

#clock {
    color: #f5c2e7;
    font-weight: bold;
}

#pulseaudio { color: #89b4fa; }
#network { color: #94e2d5; }
#cpu { color: #fab387; }
#memory { color: #cba6f7; }
#temperature { color: #f9e2af; }
#battery.warning { color: #fab387; }
#battery.critical { color: #f38ba8; }

tooltip {
    background: #181825;
    border: 1px solid #45475a;
    border-radius: 8px;
}
EOF
    success "Configuración de Waybar escrita."
}

# ---------------------------------------------------------------------------
# Aplicaciones: terminales, launcher, notificaciones
# ---------------------------------------------------------------------------

write_kitty_config() {
    cat > "${CONFIG_ROOT}/kitty/kitty.conf" <<'EOF'
# Kitty — Catppuccin Mocha
font_family      JetBrains Mono
bold_font        auto
italic_font      auto
font_size        10.0
cursor_shape     block
enable_audio_bell no
confirm_os_window_close 0
window_padding_width 8
background_opacity 0.96

foreground            #cdd6f4
background            #1e1e2e
selection_foreground  #1e1e2e
selection_background  #f5e0dc
cursor                #f5e0dc
cursor_text_color     #1e1e2e

color0  #45475a
color1  #f38ba8
color2  #a6e3a1
color3  #f9e2af
color4  #89b4fa
color5  #f5c2e7
color6  #94e2d5
color7  #bac2de
color8  #585b70
color9  #f38ba8
color10 #a6e3a1
color11 #f9e2af
color12 #89b4fa
color13 #f5c2e7
color14 #94e2d5
color15 #a6adc8
EOF
}

write_foot_config() {
    mkdir -p "${CONFIG_ROOT}/foot"
    cat > "${CONFIG_ROOT}/foot/foot.ini" <<'EOF'
[main]
font=JetBrains Mono:size=10
pad=8x8
dpi-aware=yes

[colors]
alpha=0.96
foreground=cdd6f4
background=1e1e2e
regular0=45475a
regular1=f38ba8
regular2=a6e3a1
regular3=f9e2af
regular4=89b4fa
regular5=f5c2e7
regular6=94e2d5
regular7=bac2de
bright0=585b70
bright1=f38ba8
bright2=a6e3a1
bright3=f9e2af
bright4=89b4fa
bright5=f5c2e7
bright6=94e2d5
bright7=a6adc8
EOF
}

write_wofi_config() {
    cat > "${CONFIG_ROOT}/wofi/config" <<'EOF'
show=drun
width=42%
height=48%
location=center
prompt=Buscar aplicaciones
allow_images=true
insensitive=true
matching=fuzzy
gtk_dark=true
EOF

    cat > "${CONFIG_ROOT}/wofi/style.css" <<'EOF'
window {
    margin: 0;
    border: 1px solid #585b70;
    border-radius: 12px;
    background-color: #1e1e2e;
    color: #cdd6f4;
    font-family: "JetBrains Mono", sans-serif;
    font-size: 13px;
}
#input {
    margin: 10px;
    padding: 9px;
    border: 1px solid #45475a;
    border-radius: 8px;
    background-color: #313244;
    color: #cdd6f4;
}
#inner-box { margin: 6px; }
#outer-box { margin: 6px; }
#scroll { margin: 4px; }
#entry {
    padding: 8px;
    border-radius: 7px;
}
#entry:selected {
    background-color: #cba6f7;
    color: #1e1e2e;
}
#text { margin: 0 8px; }
EOF
}

write_mako_config() {
    cat > "${CONFIG_ROOT}/mako/config" <<'EOF'
font=JetBrains Mono 10
background-color=#1e1e2e
text-color=#cdd6f4
border-color=#cba6f7
border-size=2
border-radius=9
padding=12
default-timeout=5000
ignore-timeout=0
max-visible=5
anchor=top-right
outer-margin=8
width=360
height=120
EOF
}

# ---------------------------------------------------------------------------
# Helpers de usuario: wallpaper, red, audio, información
# ---------------------------------------------------------------------------

write_user_helpers() {
    cat > "${BIN_ROOT}/sway-wallpaper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
    echo "Uso: sway-wallpaper /ruta/al/archivo [modo]"
    echo "Modos: fill, fit, stretch, center, tile"
    exit 2
fi
image="$1"
mode="${2:-fill}"
[[ -f "$image" ]] || { echo "No existe: $image" >&2; exit 1; }
case "$mode" in fill|fit|stretch|center|tile) ;; *) echo "Modo no válido: $mode" >&2; exit 2 ;; esac
pkill -x swaybg 2>/dev/null || true
nohup swaybg -i "$image" -m "$mode" >/dev/null 2>&1 &
echo "Fondo aplicado: $image ($mode)"
EOF

    cat > "${BIN_ROOT}/sway-network" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-help}" in
    gui) exec nm-connection-editor ;;
    tui) exec nmtui ;;
    status) exec nmcli device status ;;
    connections) exec nmcli connection show ;;
    wifi) exec nmcli device wifi list ;;
    ip) exec ip -brief address ;;
    routes) exec ip route show ;;
    dns) resolvectl status 2>/dev/null || cat /etc/resolv.conf ;;
    help|*)
        cat <<'HELP'
sway-network — herramientas de red
  sway-network gui          Editor gráfico de conexiones
  sway-network tui          Interfaz de texto de NetworkManager
  sway-network status       Estado de interfaces
  sway-network connections  Conexiones guardadas
  sway-network wifi         Redes Wi-Fi visibles
  sway-network ip           Direcciones IP
  sway-network routes       Tabla de rutas
  sway-network dns          Estado DNS
HELP
        ;;
esac
EOF

    cat > "${BIN_ROOT}/sway-audio" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-gui}" in
    gui) exec pavucontrol ;;
    sinks) exec wpctl status ;;
    volume-up) exec wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+ ;;
    volume-down) exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
    mute) exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    mic-mute) exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
    *) echo "Uso: sway-audio [gui|sinks|volume-up|volume-down|mute|mic-mute]" ;;
esac
EOF

    cat > "${BIN_ROOT}/sway-system-info" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "=== Sistema ==="
fastfetch 2>/dev/null || uname -a
echo
echo "=== CPU y memoria ==="
btop --version 2>/dev/null || true
free -h
echo
echo "=== GPU ==="
lspci 2>/dev/null | grep -Ei 'VGA|3D controller|Display controller' || true
echo
echo "=== Red ==="
ip -brief address 2>/dev/null || true
echo
echo "=== Audio ==="
wpctl status 2>/dev/null || true
EOF

    chmod 755 "${BIN_ROOT}"/sway-wallpaper "${BIN_ROOT}"/sway-network \
        "${BIN_ROOT}"/sway-audio "${BIN_ROOT}"/sway-system-info

    # Añadir ~/.local/bin al PATH para shells Bash si todavía no está.
    if ! grep -qF 'HOME/.local/bin' "${HOME}/.profile" 2>/dev/null; then
        cat >> "${HOME}/.profile" <<'EOF'

# Aplicaciones y utilidades instaladas localmente
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH
EOF
    fi

    success "Utilidades de usuario instaladas en ${BIN_ROOT}."
}

# ---------------------------------------------------------------------------
# XDG, MIME y carpetas de usuario
# ---------------------------------------------------------------------------

configure_xdg() {
    export XDG_CURRENT_DESKTOP=sway
    export XDG_SESSION_TYPE=wayland
    export XDG_SESSION_DESKTOP=sway

    if command_exists xdg-user-dirs-update; then
        xdg-user-dirs-update || warn "No se pudieron actualizar las carpetas XDG."
    fi

    cat > "${CONFIG_ROOT}/mimeapps.list" <<'EOF'
[Default Applications]
inode/directory=thunar.desktop;
text/plain=mousepad.desktop;
EOF
    success "Entorno XDG preparado."
}

# ---------------------------------------------------------------------------
# Configuración opcional de greetd/tuigreet
# ---------------------------------------------------------------------------

detect_display_manager() {
    CURRENT_DM=""
    if [[ -L /etc/systemd/system/display-manager.service ]]; then
        CURRENT_DM="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)")"
    fi
    [[ -n "$CURRENT_DM" ]] && info "Gestor de inicio actual: ${CURRENT_DM}"
}

configure_greetd() {
    [[ "$INSTALL_GREETD" == "no" ]] && {
        info "Se ha indicado no configurar greetd."
        return
    }

    detect_display_manager
    local do_enable="no"
    if [[ "$INSTALL_GREETD" == "yes" ]]; then
        do_enable="yes"
    elif ask_yes_no "¿Quieres configurar greetd + tuigreet como pantalla de inicio de sesión?" "N"; then
        do_enable="yes"
    fi

    if [[ "$do_enable" != "yes" ]]; then
        info "greetd queda instalado, pero no se habilita. Conservas tu gestor de inicio actual."
        return
    fi

    backup_path "/etc/greetd/config.toml"
    backup_path "/etc/systemd/system/display-manager.service"

    run_root install -d -m 755 /etc/greetd
    run_root tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session --cmd sway"
user = "_greetd"
EOF

    # La activación es explícita porque puede cambiar la pantalla de login.
    if [[ -n "$CURRENT_DM" && "$CURRENT_DM" != "greetd.service" ]]; then
        local old_service="${CURRENT_DM}"
        warn "Se deshabilitará el gestor actual (${old_service}) para activar greetd."
        run_root systemctl disable "$old_service" || warn "No se pudo deshabilitar ${old_service}."
    fi

    run_root systemctl enable greetd.service
    success "greetd configurado y habilitado. Reinicia para probarlo."
}

# ---------------------------------------------------------------------------
# PipeWire para el usuario
# ---------------------------------------------------------------------------

configure_audio_user() {
    info "Comprobando configuración de audio..."
    if command_exists wpctl; then
        success "wpctl está instalado."
    else
        warn "wpctl no está disponible; revisa la instalación de PipeWire."
    fi

    # No se usa systemctl --user desde una sesión sin bus de usuario.
    # Debian activa los servicios de PipeWire mediante sus unidades de usuario
    # y el gestor de sesión. Si hay bus disponible, intentamos habilitarlos.
    if [[ -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/bus" ]] && command_exists systemctl; then
        systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null \
            || warn "No se pudieron habilitar unidades de audio en esta sesión; se iniciarán al entrar en Sway si están disponibles."
    else
        info "Sin bus systemd de usuario en esta ejecución; PipeWire se configurará al iniciar sesión."
    fi
}

# ---------------------------------------------------------------------------
# Validación de configuraciones y comandos
# ---------------------------------------------------------------------------

validate_configs() {
    info "Validando configuraciones..."
    if command_exists sway; then
        if sway -C -c "${CONFIG_ROOT}/sway/config"; then
            success "La configuración de Sway supera la validación."
        else
            warn "Sway detectó errores de configuración. Revisa ${CONFIG_ROOT}/sway/config y el log."
        fi
    fi

    if command_exists python3; then
        python3 - <<PY
import json
from pathlib import Path
p = Path("${CONFIG_ROOT}/waybar/config")
with p.open(encoding="utf-8") as f:
    json.load(f)
print("Configuración JSON de Waybar válida.")
PY
    fi

    local cmd
    for cmd in sway waybar wofi kitty foot mako grim slurp nmcli nmtui \
               nm-connection-editor wpctl pavucontrol thunar wdisplays \
               swaylock swayidle swaybg; do
        if command_exists "$cmd"; then
            printf '  [OK] %s\n' "$cmd"
        else
            printf '  [--] %s no encontrado\n' "$cmd"
        fi
    done
}

# ---------------------------------------------------------------------------
# Fuentes y permisos
# ---------------------------------------------------------------------------

refresh_fonts() {
    if command_exists fc-cache; then
        fc-cache -f >/dev/null 2>&1 || warn "No se pudo actualizar la caché de fuentes."
    fi
    if command_exists fc-match; then
        info "Fuente JetBrains Mono: $(fc-match 'JetBrains Mono' | head -n1)"
        info "Fuente de iconos: $(fc-match 'Font Awesome' | head -n1)"
    fi
}

set_user_ownership() {
    local owner="${SUDO_USER:-$(id -un)}"
    local group
    group="$(id -gn "$owner" 2>/dev/null || echo "$owner")"
    if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
        chown -R "${owner}:${group}" "$CONFIG_ROOT/sway" "$CONFIG_ROOT/waybar" \
            "$CONFIG_ROOT/kitty" "$CONFIG_ROOT/foot" "$CONFIG_ROOT/wofi" \
            "$CONFIG_ROOT/mako" "$BIN_ROOT" "$WALLPAPER_DIR" \
            "${HOME}/Pictures/Screenshots" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Resumen final
# ---------------------------------------------------------------------------

print_summary() {
    cat <<EOF

====================================================================
 Instalación de Sway preparada
====================================================================

Sistema:
  Debian 13 (Trixie)
  GPU detectada: ${GPU_VENDOR}
  Virtualización: $([[ "$IS_VM" -eq 1 ]] && echo "sí" || echo "no")
  Batería: $([[ "$HAS_BATTERY" -eq 1 ]] && echo "sí" || echo "no")
  Teclado XKB: ${LAYOUT}

Componentes:
  - Sway + Waybar + Wofi
  - Kitty y Foot
  - Mako, swaylock y swayidle
  - NetworkManager: nm-applet, nm-connection-editor, nmcli y nmtui
  - PipeWire + WirePlumber + pavucontrol + wpctl
  - Thunar, Mousepad, btop, htop, fastfetch y wdisplays
  - grim, slurp y wl-clipboard
  - Catppuccin Mocha

Atajos principales:
  SUPER + ENTER       Terminal Kitty
  SUPER + SHIFT + ENTER  Terminal Foot
  SUPER + D           Lanzador Wofi
  SUPER + E           Thunar
  SUPER + Q           Cerrar ventana
  SUPER + F           Pantalla completa
  SUPER + L           Bloquear pantalla
  SUPER + SHIFT + A   Control de audio
  SUPER + SHIFT + S   Captura de región a archivo
  PRINT               Captura de pantalla al portapapeles

Herramientas:
  sway-network gui    Editor gráfico de red
  sway-network tui    Configuración de red en terminal
  sway-audio gui      Mezclador de audio
  sway-system-info    Resumen del sistema
  sway-wallpaper FILE Establecer fondo de pantalla

Red:
  nm-connection-editor permite configurar Ethernet, Wi-Fi,
  DHCP, IP manual, DNS, rutas y direcciones IPv4 adicionales.
  Para ajustes avanzados también tienes nmcli, nmtui e iproute2.

Seguridad y alcance:
  - No se ha instalado Cockpit ni ningún servidor web.
  - No se han instalado ni cambiado drivers NVIDIA.
  - greetd solo se activa si lo has autorizado expresamente.
  - Bloqueo automático a los 5 minutos; pantalla apagada a los 10.

Registro:
  ${LOG_FILE}

Copias de seguridad:
  ${BACKUP_ROOT}

Reinicia el equipo cuando te venga bien. Si has activado greetd,
el próximo arranque mostrará tuigreet.

====================================================================
EOF
}

main() {
    info "Iniciando ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    info "Registro: ${LOG_FILE}"

    require_sudo
    check_os
    check_session

    # lspci se instala en el conjunto base, pero puede no existir antes.
    detect_hardware
    choose_layout

    if [[ "$HAS_BATTERY" -eq 1 && "$INSTALL_GREETD" == "ask" ]]; then
        IS_LAPTOP=1
    fi

    install_packages
    enable_services
    prepare_directories

    write_sway_config
    write_waybar_config
    write_kitty_config
    write_foot_config
    write_wofi_config
    write_mako_config
    write_user_helpers
    configure_xdg
    configure_audio_user
    configure_greetd

    refresh_fonts
    validate_configs
    set_user_ownership
    print_summary

    success "Proceso finalizado."
}

main "$@"
