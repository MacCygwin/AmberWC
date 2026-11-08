#!/usr/bin/env bash
# Creates the per-user theme files for the amber/ink palette.
# Safe to re-run. Existing files are backed up once as *.bak.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"

write() {  # write <path>  (content on stdin), backs up the original once
    local f="$1"
    mkdir -p "$(dirname "$f")"
    # old theme installers / nwg-look leave gtk.css as a symlink into a theme
    # (dangling once the theme is gone, read-only if it points into /nix/store);
    # replace the link instead of writing through it
    if [ -L "$f" ]; then rm -f "$f"
    elif [ -e "$f" ] && [ ! -e "$f.bak" ]; then cp "$f" "$f.bak"; fi
    cat > "$f"
    echo "wrote $f"
}

# ---------------------------------------------------------------- GTK 3 + 4
# adw-gtk3 (GTK3) and libadwaita (GTK4) both read these named colours.
GTK_CSS='
@define-color accent_color #FFC766;
@define-color accent_bg_color #FFC766;
@define-color accent_fg_color #0B0A08;

@define-color destructive_color #E5533D;
@define-color destructive_bg_color #E5533D;
@define-color destructive_fg_color #0B0A08;
@define-color success_color #A8B04A;
@define-color success_bg_color #A8B04A;
@define-color success_fg_color #0B0A08;
@define-color warning_color #FF9F3F;
@define-color warning_bg_color #FF9F3F;
@define-color warning_fg_color #0B0A08;
@define-color error_color #E5533D;
@define-color error_bg_color #E5533D;
@define-color error_fg_color #0B0A08;

@define-color window_bg_color #16120C;
@define-color window_fg_color #F5E1B5;
@define-color view_bg_color #0B0A08;
@define-color view_fg_color #F5E1B5;

@define-color headerbar_bg_color #16120C;
@define-color headerbar_fg_color #F5E1B5;
@define-color headerbar_border_color #3A2C14;
@define-color headerbar_backdrop_color #0B0A08;
@define-color headerbar_shade_color rgba(0, 0, 0, 0.36);

@define-color card_bg_color #1B150D;
@define-color card_fg_color #F5E1B5;
@define-color card_shade_color rgba(0, 0, 0, 0.36);

@define-color dialog_bg_color #16120C;
@define-color dialog_fg_color #F5E1B5;
@define-color popover_bg_color #221A0E;
@define-color popover_fg_color #F5E1B5;

@define-color sidebar_bg_color #16120C;
@define-color sidebar_fg_color #F5E1B5;
@define-color sidebar_backdrop_color #0B0A08;
@define-color sidebar_border_color #3A2C14;

@define-color shade_color rgba(0, 0, 0, 0.36);
@define-color scrollbar_outline_color rgba(0, 0, 0, 0.5);
'
# a leftover gtk-dark.css link from the old theme would override gtk.css in dark mode
rm -f "$CFG/gtk-4.0/gtk-dark.css" "$CFG/gtk-3.0/gtk-dark.css"
printf '%s\n' "$GTK_CSS" | write "$CFG/gtk-3.0/gtk.css"
printf '%s\n' "$GTK_CSS" | write "$CFG/gtk-4.0/gtk.css"

# Fallback for apps that read settings.ini instead of dconf
for v in 3.0 4.0; do
write "$CFG/gtk-$v/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Bibata-Modern-Amber
gtk-cursor-theme-size=24
gtk-font-name=Roboto 10
gtk-application-prefer-dark-theme=1
gtk-decoration-layout=:minimize,maximize,close
EOF
done

# A dconf user value overrides the NixOS-declared one (e.g. an old nwg-look
# choice), so clear the keys we set in configuration.nix.
if command -v dconf >/dev/null; then
    for k in gtk-theme icon-theme cursor-theme cursor-size font-name \
             monospace-font-name color-scheme; do
        dconf reset "/org/gnome/desktop/interface/$k" || true
    done
fi

# ------------------------------------------------------------------- Qt
# Role order: WindowText Button Light Midlight Dark Mid Text BrightText
# ButtonText Base Window Shadow Highlight HighlightedText Link LinkVisited
# AlternateBase NoRole ToolTipBase ToolTipText PlaceholderText Accent
ACTIVE="#ffF5E1B5, #ff221A0E, #ff3A2C14, #ff2D2312, #ff0B0A08, #ff2A2010, #ffF5E1B5, #ffFFF3D6, #ffF5E1B5, #ff0B0A08, #ff16120C, #ff000000, #ffFFC766, #ff0B0A08, #ff8FA8C8, #ffC78AA0, #ff1B150D, #ff000000, #ff221A0E, #ffF5E1B5, #ffA8895A, #ffFFC766"
INACTIVE="#ffF5E1B5, #ff221A0E, #ff3A2C14, #ff2D2312, #ff0B0A08, #ff2A2010, #ffF5E1B5, #ffFFF3D6, #ffF5E1B5, #ff0B0A08, #ff16120C, #ff000000, #ff5A4A30, #ffF5E1B5, #ff8FA8C8, #ffC78AA0, #ff1B150D, #ff000000, #ff221A0E, #ffF5E1B5, #ffA8895A, #ff5A4A30"
DISABLED="#ff5A4A30, #ff221A0E, #ff3A2C14, #ff2D2312, #ff0B0A08, #ff2A2010, #ff5A4A30, #ffFFF3D6, #ff5A4A30, #ff0B0A08, #ff16120C, #ff000000, #ff3A2C14, #ffA8895A, #ff8FA8C8, #ffC78AA0, #ff1B150D, #ff000000, #ff221A0E, #ff5A4A30, #ff5A4A30, #ff3A2C14"

# qt5ct has 21 roles (no Accent), qt6ct has 22
trim() { printf '%s' "${1%, *}"; }

write "$CFG/qt6ct/colors/amber.conf" <<EOF
[ColorScheme]
active_colors=$ACTIVE
disabled_colors=$DISABLED
inactive_colors=$INACTIVE
EOF
write "$CFG/qt5ct/colors/amber.conf" <<EOF
[ColorScheme]
active_colors=$(trim "$ACTIVE")
disabled_colors=$(trim "$DISABLED")
inactive_colors=$(trim "$INACTIVE")
EOF

for v in qt5ct qt6ct; do
write "$CFG/$v/$v.conf" <<EOF
[Appearance]
color_scheme_path=$CFG/$v/colors/amber.conf
custom_palette=true
icon_theme=Papirus-Dark
standard_dialogs=default
style=kvantum

[Fonts]
fixed="JetBrainsMono Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
general="Roboto,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
EOF
done

# Kvantum: KvAdaptaDark is built to follow the palette qt5ct/qt6ct supply
write "$CFG/Kvantum/kvantum.kvconfig" <<'EOF'
[General]
theme=KvAdaptaDark
EOF

echo
echo "Done. Log out of labwc and back in (env vars load at login), then open"
echo "a GTK app (pcmanfm) and a Qt app (e.g. qt6ct itself) to check."
