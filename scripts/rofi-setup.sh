#!/usr/bin/env bash
# Writes the rofi config + two themes in the amber/ink palette:
#   launcher.rasi  ChromeOS-style app grid, anchored bottom-left above the shelf
#   list.rasi      centered list for dmenu use (cliphist picker)
# Safe to re-run. Existing files are backed up once as *.bak.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}/rofi"
SEARCH=$'\xef\x80\x82'   # U+F002 nerd font magnifier, as raw UTF-8 bytes (locale-independent)

write() {
    local f="$1"
    mkdir -p "$(dirname "$f")"
    if [ -e "$f" ] && [ ! -e "$f.bak" ]; then cp "$f" "$f.bak"; fi
    cat > "$f"
    echo "wrote $f"
}

write "$CFG/config.rasi" <<EOF
configuration {
    modi: "drun";
    show-icons: true;
    icon-theme: "Papirus-Dark";
    drun-display-format: "{name}";
    display-drun: "${SEARCH}";
}
EOF

# ---------------------------------------------------------------- launcher
write "$CFG/themes/launcher.rasi" <<'EOF'
* {
    bg:       #16120CEE;
    bg-alt:   #221A0E;
    border-c: #3A2C14;
    fg:       #F5E1B5;
    fg-dim:   #A8895A;
    accent:   #FFC766;

    font: "Roboto 12";
    background-color: transparent;
    text-color: @fg;
}

window {
    location: south west;
    anchor: south west;
    x-offset: 12px;
    y-offset: -12px;
    width: 640px;
    background-color: @bg;
    border: 1px;
    border-color: @border-c;
    border-radius: 28px;
}

mainbox {
    padding: 20px;
    spacing: 18px;
    children: [ "inputbar", "listview" ];
}

inputbar {
    padding: 12px 20px;
    spacing: 12px;
    background-color: @bg-alt;
    border: 1px;
    border-color: @border-c;
    border-radius: 26px;
    children: [ "prompt", "entry" ];
}

prompt {
    text-color: @accent;
}

entry {
    placeholder: "Search your apps";
    placeholder-color: @fg-dim;
}

listview {
    columns: 5;
    lines: 3;
    flow: horizontal;
    fixed-columns: true;
    spacing: 8px;
    scrollbar: false;
    cycle: false;
}

element {
    orientation: vertical;
    padding: 14px 4px 10px 4px;
    spacing: 8px;
    border-radius: 20px;
    border: 1px;
    border-color: transparent;
}

element-icon {
    size: 52px;
    horizontal-align: 0.5;
}

element-text {
    horizontal-align: 0.5;
    text-color: inherit;
}

element selected.normal {
    background-color: @bg-alt;
    border-color: @accent;
    text-color: @accent;
}
EOF

# -------------------------------------------------------------------- list
write "$CFG/themes/list.rasi" <<'EOF'
* {
    bg:       #16120CEE;
    bg-alt:   #221A0E;
    border-c: #3A2C14;
    fg:       #F5E1B5;
    fg-dim:   #A8895A;
    accent:   #FFC766;

    font: "Roboto 12";
    background-color: transparent;
    text-color: @fg;
}

window {
    location: center;
    anchor: center;
    width: 680px;
    background-color: @bg;
    border: 1px;
    border-color: @border-c;
    border-radius: 24px;
}

mainbox {
    padding: 16px;
    spacing: 14px;
    children: [ "inputbar", "listview" ];
}

inputbar {
    padding: 12px 20px;
    spacing: 12px;
    background-color: @bg-alt;
    border: 1px;
    border-color: @border-c;
    border-radius: 24px;
    children: [ "prompt", "entry" ];
}

prompt {
    text-color: @accent;
}

entry {
    placeholder: "Search";
    placeholder-color: @fg-dim;
}

listview {
    columns: 1;
    lines: 10;
    fixed-height: false;
    spacing: 4px;
    scrollbar: false;
    cycle: false;
}

element {
    padding: 10px 16px;
    border-radius: 14px;
    border: 1px;
    border-color: transparent;
}

element-text {
    vertical-align: 0.5;
    text-color: inherit;
}

element selected.normal {
    background-color: @bg-alt;
    border-color: @accent;
    text-color: @accent;
}
EOF

echo
echo "Done. Test with:"
echo "  rofi -show drun -theme $CFG/themes/launcher.rasi"
