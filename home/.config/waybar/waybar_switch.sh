#!/usr/bin/env bash
# Cycles through waybar styles. Each style is a folder in ~/.config/waybar that
# contains config.jsonc and style.css; config.jsonc/style.css in the parent are
# symlinks to the active one.
#
#   waybar_switch.sh          switch to the next style
#   waybar_switch.sh --list   show which styles were found (and what is missing)

WAYBAR_DIR="$HOME/.config/waybar"
PREFERRED=(default floating)         # cycle order; any OTHER folder with config.jsonc + style.css is added after these

ok()   { [ -f "$WAYBAR_DIR/$1/config.jsonc" ] && [ -f "$WAYBAR_DIR/$1/style.css" ]; }

# preferred order first, then any other folder that has both files
styles=("${PREFERRED[@]}")
for d in "$WAYBAR_DIR"/*/; do
    n=$(basename "$d")
    [[ " ${styles[*]} " == *" $n "* ]] || styles+=("$n")
done

avail=(); skipped=()
for s in "${styles[@]}"; do
    if ok "$s"; then avail+=("$s")
    elif [ -d "$WAYBAR_DIR/$s" ] || [[ " ${PREFERRED[*]} " == *" $s "* ]]; then skipped+=("$s"); fi
done

if [ "$1" = "--list" ]; then
    for s in "${styles[@]}"; do
        if ok "$s"; then echo "ok       $s"
        else
            miss=""
            [ -f "$WAYBAR_DIR/$s/config.jsonc" ] || miss="config.jsonc "
            [ -f "$WAYBAR_DIR/$s/style.css" ]    || miss="${miss}style.css"
            [ -d "$WAYBAR_DIR/$s" ] && echo "MISSING  $s  (needs: $miss)" || echo "MISSING  $s  (no folder $WAYBAR_DIR/$s)"
        fi
    done
    exit 0
fi

[ "${#avail[@]}" -gt 0 ] || { notify-send "Waybar" "No styles found in $WAYBAR_DIR" -i dialog-error; exit 1; }

# which one is active now? (the folder config.jsonc points into)
cur=$(basename "$(dirname "$(readlink -f "$WAYBAR_DIR/config.jsonc")")")

next=${avail[0]}
for i in "${!avail[@]}"; do
    if [ "${avail[$i]}" = "$cur" ]; then
        next=${avail[$(( (i + 1) % ${#avail[@]} ))]}
        break
    fi
done

ln -sf "$WAYBAR_DIR/$next/config.jsonc" "$WAYBAR_DIR/config.jsonc"
ln -sf "$WAYBAR_DIR/$next/style.css"    "$WAYBAR_DIR/style.css"

msg="Switched to ${next^} Style"
[ "${#skipped[@]}" -gt 0 ] && msg="$msg  (skipped, incomplete: ${skipped[*]})"
notify-send "Waybar" "$msg" -i dialog-information

# Reload Waybar
pkill waybar
waybar &
