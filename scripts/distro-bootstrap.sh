#!/usr/bin/env bash
# Reproduces the labwc rice on a non-NixOS distro (Arch, Fedora, Debian/Ubuntu, openSUSE).
#
#   bash distro-bootstrap.sh            install packages + apply settings + link dotfiles
#   DRY_RUN=1 bash distro-bootstrap.sh  only print what it would do
#
# Best effort: package names differ between distros and releases. For each tool the script
# tries a list of candidate names, installs the first one your repos have, and prints
# whatever it could not find so you can install it by hand (AUR, COPR, source...).
set -uo pipefail

DRY_RUN="${DRY_RUN:-0}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT="${DOT:-$(cd "$HERE/.." 2>/dev/null && pwd)}"        # repo root when run from scripts/
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
OS_RELEASE="${OS_RELEASE:-/etc/os-release}"

run() { if [ "$DRY_RUN" = 1 ]; then echo "DRY: $*"; else "$@"; fi; }

# ------------------------------------------------------------------ detect
. "$OS_RELEASE"
ID="${ID:-}"; ID_LIKE="${ID_LIKE:-}"      # Arch has no ID_LIKE
case " $ID $ID_LIKE " in
    *" arch "*)                     PM=pacman ;;
    *" fedora "*|*" rhel "*)        PM=dnf ;;
    *" debian "*|*" ubuntu "*)      PM=apt ;;
    *" suse "*|*" opensuse "*)      PM=zypper ;;
    *) echo "Unsupported distro ($ID). Install the tools in the README by hand."; exit 1 ;;
esac
echo "Distro: ${PRETTY_NAME:-$ID}  (package manager: $PM)"
[ "$PM" = apt ] && run sudo apt-get update -qq

have_pkg() {  # is this package name available in the repos?
    case $PM in
        pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
        dnf)    dnf -q info "$1" >/dev/null 2>&1 ;;
        apt)    [ -n "$(apt-cache policy "$1" 2>/dev/null | sed -n 's/^ *Candidate: *//p' | grep -v '(none)')" ] ;;
        zypper) zypper -q info "$1" >/dev/null 2>&1 ;;
    esac
}
[ "$DRY_RUN" = 1 ] && have_pkg() { return 0; }   # dry run: pretend the first candidate exists

# tool | arch | fedora | debian/ubuntu | opensuse   (candidates separated by spaces, first found wins)
TABLE='
labwc            | labwc                        | labwc                    | labwc                    | labwc
waybar           | waybar                       | waybar                   | waybar                   | waybar
mako             | mako                         | mako                     | mako-notifier            | mako
foot             | foot                         | foot                     | foot                     | foot
rofi (wayland)   | rofi-wayland rofi            | rofi-wayland rofi        | rofi-wayland rofi        | rofi-wayland rofi
swaylock         | swaylock-effects swaylock    | swaylock-effects swaylock| swaylock-effects swaylock| swaylock
swayidle         | swayidle                     | swayidle                 | swayidle                 | swayidle
swaybg           | swaybg                       | swaybg                   | swaybg                   | swaybg
wlogout          | wlogout                      | wlogout                  | wlogout                  | wlogout
wl-clipboard     | wl-clipboard                 | wl-clipboard             | wl-clipboard             | wl-clipboard
cliphist         | cliphist                     | cliphist                 | cliphist                 | cliphist
brightnessctl    | brightnessctl                | brightnessctl            | brightnessctl            | brightnessctl
grim             | grim                         | grim                     | grim                     | grim
slurp            | slurp                        | slurp                    | slurp                    | slurp
jq               | jq                           | jq                       | jq                       | jq
wlopm            | wlopm                        | wlopm                    | wlopm                    | wlopm
pipewire         | pipewire                     | pipewire                 | pipewire                 | pipewire
pipewire-pulse   | pipewire-pulse               | pipewire-pulseaudio      | pipewire-pulse           | pipewire-pulseaudio
wireplumber      | wireplumber                  | wireplumber              | wireplumber              | wireplumber
networkmanager   | networkmanager               | NetworkManager           | network-manager          | NetworkManager
power-profiles   | power-profiles-daemon        | power-profiles-daemon    | power-profiles-daemon    | power-profiles-daemon
firefox          | firefox                      | firefox                  | firefox firefox-esr      | MozillaFirefox
pcmanfm          | pcmanfm                      | pcmanfm                  | pcmanfm                  | pcmanfm
dconf/gsettings  | dconf gsettings-desktop-schemas | dconf gsettings-desktop-schemas | dconf-cli gsettings-desktop-schemas | dconf gsettings-desktop-schemas
qt5ct            | qt5ct                        | qt5ct                    | qt5ct                    | qt5ct
qt6ct            | qt6ct                        | qt6ct                    | qt6ct                    | qt6ct
kvantum          | kvantum                      | kvantum                  | qt5-style-kvantum        | kvantum
papirus icons    | papirus-icon-theme           | papirus-icon-theme       | papirus-icon-theme       | papirus-icon-theme
adw-gtk3 theme   | adw-gtk-theme                | adw-gtk3-theme           | adw-gtk3                 | adw-gtk3
bibata cursor    | bibata-cursor-theme          | bibata-cursor-themes     | bibata-cursor-theme      | bibata-cursor-theme
roboto font      | ttf-roboto                   | google-roboto-fonts      | fonts-roboto             | google-roboto-fonts
font-awesome     | ttf-font-awesome             | fontawesome-fonts-all fontawesome-fonts | fonts-font-awesome | fontawesome-fonts
jetbrains nerd   | ttf-jetbrains-mono-nerd      | jetbrains-mono-fonts     | fonts-jetbrains-mono     | jetbrains-mono-fonts
'
col=$(case $PM in pacman) echo 2;; dnf) echo 3;; apt) echo 4;; zypper) echo 5;; esac)

to_install=(); missing=()
while IFS='|' read -r -a f; do
    [ "${#f[@]}" -ge 5 ] || continue
    tool=$(echo "${f[0]}" | xargs)
    found=""
    for cand in $(echo "${f[$((col-1))]}"); do
        if have_pkg "$cand"; then found="$cand"; break; fi
    done
    if [ -n "$found" ]; then to_install+=("$found"); else missing+=("$tool"); fi
done <<< "$TABLE"

echo; echo "Installing ${#to_install[@]} packages..."
case $PM in
    pacman) run sudo pacman -S --needed --noconfirm "${to_install[@]}" ;;
    dnf)    run sudo dnf install -y "${to_install[@]}" ;;
    apt)    run sudo apt-get install -y "${to_install[@]}" ;;
    zypper) run sudo zypper --non-interactive install "${to_install[@]}" ;;
esac

# ---------------------------------------------- things packages often lack
fonts_dir="$HOME/.local/share/fonts"; icons_dir="$HOME/.local/share/icons"
if ! fc-list 2>/dev/null | grep -qi 'JetBrainsMono.*Nerd'; then
    echo "Fetching JetBrainsMono Nerd Font..."
    run mkdir -p "$fonts_dir/JetBrainsMonoNF"
    run sh -c "curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | tar -xJ -C '$fonts_dir/JetBrainsMonoNF'"
    run fc-cache -f
fi
if [ ! -d /usr/share/icons/Bibata-Modern-Amber ] && [ ! -d "$icons_dir/Bibata-Modern-Amber" ]; then
    echo "Fetching Bibata-Modern-Amber cursor..."
    run mkdir -p "$icons_dir"
    run sh -c "curl -fsSL https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata-Modern-Amber.tar.xz | tar -xJ -C '$icons_dir'"
fi
if command -v papirus-folders >/dev/null; then
    run sudo papirus-folders -t Papirus-Dark -C yellow     # amber folders, as on NixOS
else
    missing+=("papirus-folders (yellow folder icons; optional)")
fi

# ------------------------------------- what NixOS configuration.nix declared
# environment variables for labwc and apps it starts
ENVF="$CFG/labwc/environment"; run mkdir -p "$(dirname "$ENVF")"; run touch "$ENVF"
setenv() { [ "$DRY_RUN" = 1 ] && { echo "DRY: setenv $1=$2"; return; }
           grep -v "^$1=" "$ENVF" > "$ENVF.tmp"; echo "$1=$2" >> "$ENVF.tmp"; cat "$ENVF.tmp" > "$ENVF"; rm -f "$ENVF.tmp"; }
setenv XCURSOR_THEME Bibata-Modern-Amber
setenv XCURSOR_SIZE 24
setenv QT_QPA_PLATFORMTHEME qt5ct
setenv QT_QPA_PLATFORMTHEME_QT6 qt6ct
setenv QT_STYLE_OVERRIDE kvantum

# the dconf block from configuration.nix
if command -v gsettings >/dev/null; then
    gs() { run gsettings set "$@"; }
    gs org.gnome.desktop.interface color-scheme prefer-dark
    gs org.gnome.desktop.interface gtk-theme adw-gtk3-dark
    gs org.gnome.desktop.interface icon-theme Papirus-Dark
    gs org.gnome.desktop.interface cursor-theme Bibata-Modern-Amber
    gs org.gnome.desktop.interface cursor-size 24
    gs org.gnome.desktop.interface font-name 'Roboto 10'
    gs org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 10'
    gs org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'
else
    missing+=("gsettings (theme settings not applied)")
fi

# services (power-profiles-daemon, NetworkManager) and the audio stack
if command -v systemctl >/dev/null; then
    run sudo systemctl enable --now power-profiles-daemon NetworkManager
    run systemctl --user enable --now pipewire pipewire-pulse wireplumber
fi

# ------------------------------------------------ dotfiles + generated files
if [ -x "$DOT/link.sh" ]; then
    run "$DOT/link.sh"
    for s in rofi-setup.sh qs-setup.sh amber-theme-setup.sh; do
        [ -f "$DOT/scripts/$s" ] && run bash "$DOT/scripts/$s"
    done
else
    echo "No dotfiles repo found at $DOT; run its link.sh and scripts/*.sh yourself."
fi

echo
if [ "${#missing[@]}" -gt 0 ]; then
    echo "NOT found in your repos (install by hand; on Arch try the AUR, on Fedora a COPR, or build from source):"
    printf '  - %s\n' "${missing[@]}"
fi
echo "Done. Log out and pick the labwc session. labwc 0.9+ is needed for the thumbnail Alt+Tab."
