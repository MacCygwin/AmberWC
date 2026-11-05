#!/usr/bin/env bash
# Installs:
#   ~/.local/bin/qs-panel         ChromeOS-style quick settings panel (rofi)
#   ~/.local/bin/notif-history    notification history list (rofi + mako)
#   ~/.local/bin/calendar-popup   month calendar popup (rofi)
#   ~/.local/bin/settings-hub     list that opens the right tool per setting (rofi)
#   ~/.config/rofi/themes/panel.rasi and calendar.rasi
# Needs rofi-setup.sh to have been run first (it provides list.rasi).
# Safe to re-run. Existing files are backed up once as *.bak.
set -euo pipefail

BIN="$HOME/.local/bin"
THEMES="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/themes"

write() {
    local f="$1"
    mkdir -p "$(dirname "$f")"
    if [ -e "$f" ] && [ ! -e "$f.bak" ]; then cp "$f" "$f.bak"; fi
    cat > "$f"
    echo "wrote $f"
}

# ---------------------------------------------------------------- qs-panel
write "$BIN/qs-panel" <<'PANEL_EOF'
#!/usr/bin/env bash
# Quick-settings panel (rofi).
# Enter = toggle / open    Left/Right = adjust sliders, or open the Wi-Fi / Bluetooth list    Esc = close
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME="$CFG/rofi/themes/panel.rasi"
LIST="$CFG/rofi/themes/list.rasi"
BIN="$HOME/.local/bin"

# Opening it again (e.g. clicking the status area) closes it.
if pgrep -x rofi >/dev/null; then pkill -x rofi; exit 0; fi

# Nerd Font glyphs as raw UTF-8 bytes (work in any locale)
G_WIFI=$'\xef\x87\xab'; G_BT=$'\xef\x8a\x93'; G_BELL=$'\xef\x83\xb3'; G_BELL_OFF=$'\xef\x87\xb6'
G_MOON=$'\xef\x86\x86'; G_VOL=$'\xef\x80\xa8'; G_MUTE=$'\xef\x80\xa6'; G_BRI=$'\xef\x86\x85'
G_BOLT=$'\xef\x83\xa7'; G_HIST=$'\xef\x87\x9a'; G_GEAR=$'\xef\x80\x93'; G_LOCK=$'\xef\x80\xa3'
G_POWER=$'\xef\x80\x91'; G_CHEV=$'\xe2\x80\xba'
FULL=$'\xe2\x96\x88'; EMPTY=$'\xe2\x96\x91'
ACC='#FFC766'; DIM='#A8895A'; FADE='#5A4A30'

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
dim() { printf '<span foreground="%s">%s</span>' "$DIM" "$1"; }
bar() {  # $1 = percent -> 12-cell bar
    local p=$1 n=12 f i on="" off=""
    [ "$p" -lt 0 ] && p=0; [ "$p" -gt 100 ] && p=100
    f=$(( (p * n + 50) / 100 ))
    for ((i=0; i<n; i++)); do if [ "$i" -lt "$f" ]; then on+=$FULL; else off+=$EMPTY; fi; done
    printf "<span font_family='JetBrainsMono Nerd Font'><span foreground='%s'>%s</span><span foreground='%s'>%s</span></span>" "$ACC" "$on" "$FADE" "$off"
}

# ---- state ---------------------------------------------------------------
wifi_on()   { [ "$(nmcli -t -f WIFI general 2>/dev/null)" = enabled ]; }
wifi_ssid() {
    nmcli -t -f ACTIVE,SSID device wifi list --rescan no 2>/dev/null |
        awk -F: '$1=="yes"{sub(/^yes:/,""); print; exit}' | sed 's/\\:/:/g'
}
have_bt()   { command -v bluetoothctl >/dev/null && bluetoothctl show >/dev/null 2>&1; }
bt_on()     { bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; }
dnd_on()    { makoctl mode 2>/dev/null | grep -qx do-not-disturb; }
have_night(){ command -v wlsunset >/dev/null; }
night_on()  { pgrep -x wlsunset >/dev/null; }
vol_pct()   { wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%d", $2*100+0.5}'; }
vol_muted() { wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED; }
have_bri()  { brightnessctl -m >/dev/null 2>&1; }
bri_pct()   { brightnessctl -m | cut -d, -f4 | tr -d '%'; }
have_pp()   { command -v powerprofilesctl >/dev/null && powerprofilesctl get >/dev/null 2>&1; }
pp_next() {  # power-saver -> balanced -> performance (only what this machine offers)
    local avail cur p found=0
    avail=$(powerprofilesctl list | sed -nE 's/^[ *]+([a-z-]+):$/\1/p')
    cur=$(powerprofilesctl get)
    for p in power-saver balanced performance power-saver balanced performance; do
        if [ "$found" = 1 ] && grep -qx "$p" <<<"$avail"; then echo "$p"; return; fi
        [ "$p" = "$cur" ] && found=1
    done
}
battery() {
    local d
    for d in /sys/class/power_supply/BAT*; do
        [ -r "$d/capacity" ] || continue
        printf 'Battery %s%% · %s' "$(<"$d/capacity")" "$(<"$d/status")"
        return
    done
}

# ---- rows: rows[] is what rofi shows, ids[] says what each row does --------
build() {
    rows=(); ids=()
    local s p

    if wifi_on; then
        s=$(wifi_ssid | esc)
        rows+=("$G_WIFI  Wi-Fi  $(dim "${s:-on}")  $(dim "$G_CHEV")")
    else
        rows+=("$G_WIFI  Wi-Fi  $(dim off)")
    fi
    ids+=(wifi)

    if have_bt; then
        if bt_on; then rows+=("$G_BT  Bluetooth  $(dim on)  $(dim "$G_CHEV")")
        else rows+=("$G_BT  Bluetooth  $(dim off)"); fi
        ids+=(bt)
    fi

    if dnd_on; then rows+=("$G_BELL_OFF  Do not disturb  $(dim on)")
    else rows+=("$G_BELL  Do not disturb  $(dim off)"); fi
    ids+=(dnd)

    if have_night; then
        if night_on; then rows+=("$G_MOON  Night light  $(dim on)")
        else rows+=("$G_MOON  Night light  $(dim off)"); fi
        ids+=(night)
    fi

    if vol_muted; then rows+=("$G_MUTE  Volume  $(bar 0)  $(dim muted)")
    else p=$(vol_pct); rows+=("$G_VOL  Volume  $(bar "$p")  $(dim "$p%")"); fi
    ids+=(vol)

    if have_bri; then
        p=$(bri_pct); rows+=("$G_BRI  Brightness  $(bar "$p")  $(dim "$p%")"); ids+=(bri)
    fi

    if have_pp; then
        rows+=("$G_BOLT  Power profile  $(dim "$(powerprofilesctl get)")"); ids+=(pp)
    fi

    rows+=("$G_HIST  Notifications");  ids+=(hist)
    rows+=("$G_GEAR  Settings");       ids+=(settings)
    rows+=("$G_LOCK  Lock screen");    ids+=(lock)
    rows+=("$G_POWER  Power menu");    ids+=(power)
}

mesg() {
    local b; b=$(battery)
    printf '%s%s' "${b:+$b  ·  }" "$(dim '←/→ adjust  ·  Enter toggle')"
}

# ---- pickers ---------------------------------------------------------------
wifi_picker() {
    nmcli radio wifi on >/dev/null 2>&1
    nmcli device wifi rescan >/dev/null 2>&1 || true
    local rows=() ssids=() secs=() inuse sig sec ssid mark lock idx pw
    declare -A seen
    while IFS=: read -r inuse sig sec ssid; do
        ssid=${ssid//\\:/:}
        [ -n "$ssid" ] || continue
        [ -z "${seen[$ssid]:-}" ] || continue
        seen[$ssid]=1
        mark=""; [ "$inuse" = '*' ] && mark="  $(dim '● connected')"
        lock=""; if [ -n "$sec" ] && [ "$sec" != "--" ]; then lock="  $(dim "$sec")"; fi
        rows+=("$G_WIFI  $(printf '%s' "$ssid" | esc)  $(dim "$sig%")$lock$mark")
        ssids+=("$ssid"); secs+=("$sec")
    done < <(nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan no 2>/dev/null | sort -t: -k2 -nr)

    if [ "${#rows[@]}" -eq 0 ]; then notify-send "Wi-Fi" "No networks found"; return; fi
    idx=$(printf '%s\n' "${rows[@]}" | rofi -dmenu -markup-rows -no-custom -format i -p "Wi-Fi" -theme "$LIST") || return
    ssid=${ssids[$idx]}; sec=${secs[$idx]}

    if [ -z "$sec" ] || [ "$sec" = "--" ] || nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$ssid"; then
        if nmcli device wifi connect "$ssid" >/dev/null 2>&1; then notify-send "Wi-Fi" "Connected to $ssid"
        else notify-send "Wi-Fi" "Could not connect to $ssid"; fi
    else
        pw=$(rofi -dmenu -password -p "Password for $ssid" -theme "$LIST" </dev/null) || return
        if nmcli device wifi connect "$ssid" password "$pw" >/dev/null 2>&1; then notify-send "Wi-Fi" "Connected to $ssid"
        else notify-send "Wi-Fi" "Wrong password or could not connect"; fi
    fi
}

bt_picker() {
    local rows=() macs=() mac name conn idx
    while read -r _ mac name; do
        [ -n "$mac" ] || continue
        conn=""; bluetoothctl info "$mac" 2>/dev/null | grep -q 'Connected: yes' && conn="  $(dim '● connected')"
        rows+=("$G_BT  $(printf '%s' "$name" | esc)$conn"); macs+=("$mac")
    done < <(bluetoothctl devices 2>/dev/null)

    if [ "${#rows[@]}" -eq 0 ]; then notify-send "Bluetooth" "No paired devices (pair new ones in Settings)"; return; fi
    idx=$(printf '%s\n' "${rows[@]}" | rofi -dmenu -markup-rows -no-custom -format i -p "Bluetooth" -theme "$LIST") || return
    mac=${macs[$idx]}
    if bluetoothctl info "$mac" 2>/dev/null | grep -q 'Connected: yes'; then
        bluetoothctl disconnect "$mac" >/dev/null 2>&1 && notify-send "Bluetooth" "Disconnected"
    else
        if bluetoothctl connect "$mac" >/dev/null 2>&1; then notify-send "Bluetooth" "Connected"
        else notify-send "Bluetooth" "Could not connect"; fi
    fi
}

# ---- actions ---------------------------------------------------------------
enter() {
    case $1 in
        wifi)     if wifi_on; then nmcli radio wifi off; else nmcli radio wifi on; fi; sleep 0.4 ;;
        bt)       if bt_on; then bluetoothctl power off >/dev/null; else bluetoothctl power on >/dev/null; fi; sleep 0.4 ;;
        dnd)      if dnd_on; then makoctl mode -r do-not-disturb >/dev/null; else makoctl mode -a do-not-disturb >/dev/null; fi ;;
        night)    if night_on; then pkill -x wlsunset; else setsid -f wlsunset -T 3500 -t 3500 -S 07:00 -s 19:00 >/dev/null 2>&1; fi; sleep 0.3 ;;
        vol)      wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
        pp)       powerprofilesctl set "$(pp_next)" ;;
        hist)     exec "$BIN/notif-history" ;;
        settings) exec "$BIN/settings-hub" ;;
        lock)     swaylock -f; exit 0 ;;
        power)    exec wlogout -b 4 ;;
    esac
}

more() {   # Right: open a list, or raise a slider
    case $1 in
        wifi) wifi_on && wifi_picker ;;
        bt)   bt_on && bt_picker ;;
        vol)  wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ ;;
        bri)  brightnessctl set 5%+ >/dev/null ;;
    esac
}

less() {   # Left: lower a slider
    case $1 in
        vol)  wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
        bri)  brightnessctl set 5%- >/dev/null ;;
    esac
}

# ---- loop: the panel stays open until Esc, like ChromeOS ------------------
sel=0
while :; do
    build
    out=$(printf '%s\n' "${rows[@]}" | rofi -dmenu -markup-rows -no-custom -format i \
            -selected-row "$sel" -mesg "$(mesg)" -theme "$THEME" \
            -kb-custom-1 "Right" -kb-custom-2 "Left" \
            -kb-move-char-forward "Control+f" -kb-move-char-back "Control+b")
    code=$?
    case $code in 0|10|11) ;; *) exit 0 ;; esac
    sel=$out
    act=${ids[$sel]}
    case $code in
        0)  enter "$act" ;;
        10) more  "$act" ;;
        11) less  "$act" ;;
    esac
done
PANEL_EOF

# ----------------------------------------------------------- notif-history
write "$BIN/notif-history" <<'HIST_EOF'
#!/usr/bin/env bash
# Notification history list. Enter copies the selected notification's text.
THEME="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/themes/list.rasi"

if pgrep -x rofi >/dev/null; then pkill -x rofi; exit 0; fi

json=$(makoctl history -j 2>/dev/null) || json=""
n=$(jq '.data[0] | length' <<<"$json" 2>/dev/null || echo 0)

if [ "${n:-0}" -gt 0 ]; then
    rows=$(jq -r '.data[0][] |
        (.["app-name"].data // "") as $a |
        (.summary.data // "") as $s |
        ((.body.data // "") | gsub("\n"; " ") | .[0:70]) as $b |
        "<span foreground=\"#A8895A\">\($a | @html)</span>  <b>\($s | @html)</b>  \($b | @html)"' <<<"$json")
    idx=$(printf '%s\n' "$rows" | rofi -dmenu -markup-rows -no-custom -format i \
            -p Notifications -mesg "Enter copies the text" -theme "$THEME") || exit 0
    jq -r --argjson i "$idx" '.data[0][$i] | [.summary.data, .body.data] | map(select(. != null and . != "")) | join("\n")' \
        <<<"$json" | wl-copy
else
    # Empty history, or JSON output unavailable: show whatever makoctl prints.
    raw=$(makoctl history 2>/dev/null)
    printf '%s\n' "${raw:-No notifications yet}" |
        rofi -dmenu -no-custom -p Notifications -theme "$THEME" >/dev/null
fi
HIST_EOF

# ----------------------------------------------------------- settings-hub
write "$BIN/settings-hub" <<'HUB_EOF'
#!/usr/bin/env bash
# Settings hub: one list that opens the right tool for each setting.
# Only shows entries whose tool is installed.
THEME="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/themes/list.rasi"

# Opening it again closes it.
if pgrep -x rofi >/dev/null; then pkill -x rofi; exit 0; fi

G_WIFI=$'\xef\x87\xab'; G_BT=$'\xef\x8a\x93'; G_VOL=$'\xef\x80\xa8'; G_DESK=$'\xef\x84\x88'
G_BRUSH=$'\xef\x87\xbc'; G_BAR=$'\xef\x87\x9e'; G_REFRESH=$'\xef\x80\xa1'; G_INFO=$'\xef\x81\x9a'

rows=(); cmds=()
add() {  # add <glyph> <label> <tool that must exist> <command to run>
    command -v "$3" >/dev/null || return 0
    rows+=("$1  $2"); cmds+=("$4")
}
tui() { echo "foot -a qs-nmtui -e $*"; }     # small floating terminal window (see windowRules in rc.xml)

add "$G_WIFI"    "Network"          nmtui         "$(tui nmtui)"
add "$G_BT"      "Bluetooth"        bluetui       "$(tui bluetui)"
if   command -v wiremix >/dev/null;    then add "$G_VOL" "Sound" wiremix    "$(tui wiremix)"
elif command -v pavucontrol >/dev/null; then add "$G_VOL" "Sound" pavucontrol "pavucontrol"
fi
add "$G_DESK"    "Display"          wdisplays     "wdisplays"
add "$G_BRUSH"   "Appearance"       nwg-look      "nwg-look"
[ -x "$HOME/.config/waybar/waybar_switch.sh" ] && { rows+=("$G_BAR  Bar style"); cmds+=("$HOME/.config/waybar/waybar_switch.sh"); }
add "$G_REFRESH" "Reload desktop"   labwc         "sh -c 'labwc --reconfigure; makoctl reload; pkill waybar; waybar &'"
add "$G_INFO"    "System info"      fastfetch     "$(tui sh -c "'fastfetch; echo; read -rn1 -p \"Press any key to close\"'")"

[ "${#rows[@]}" -gt 0 ] || { notify-send "Settings" "No settings tools found"; exit 1; }

idx=$(printf '%s\n' "${rows[@]}" | rofi -dmenu -no-custom -format i -p "Settings" -theme "$THEME") || exit 0
setsid -f sh -c "${cmds[$idx]}" >/dev/null 2>&1
HUB_EOF


# ----------------------------------------------------------- calendar-popup
write "$BIN/calendar-popup" <<'CAL_EOF'
#!/usr/bin/env bash
# Month calendar popup on rofi.
# Left/Right = previous/next month   Enter = back to today   Esc = close
THEME="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/themes/calendar.rasi"
FIRST_DAY=1   # 0 = Sunday, 1 = Monday

# Opening it again (e.g. right-clicking the clock) closes it.
if pgrep -x rofi >/dev/null; then pkill -x rofi; exit 0; fi

DIM='#A8895A'; FADE='#5A4A30'; ACC='#FFC766'; INK='#0B0A08'
cy=$(date +%Y); cm=$((10#$(date +%m))); cday=$((10#$(date +%d)))
names=(Su Mo Tu We Th Fr Sa)

render() {  # $1 = year, $2 = month (1-12); fills rows[] (header + 6 weeks) and title
    local y=$1 m=$2 mm first ndays prevlen offset line cell i n d col is_today
    printf -v mm '%02d' "$m"
    first=$(date -d "$y-$mm-01" +%w)
    ndays=$((10#$(date -d "$y-$mm-01 +1 month -1 day" +%d)))
    prevlen=$((10#$(date -d "$y-$mm-01 -1 day" +%d)))
    offset=$(( (first - FIRST_DAY + 7) % 7 ))
    title=$(date -d "$y-$mm-01" '+%B %Y')

    line=""
    for ((i=0; i<7; i++)); do
        printf -v cell ' %2s ' "${names[(FIRST_DAY+i)%7]}"; line+=$cell
    done
    rows=("<span foreground=\"$DIM\">$line</span>")

    # Always 6 full weeks: days of the neighbouring months fill the gaps (faded),
    # so every row is the same width and the grid never jumps or shifts.
    line=""; col=0
    for ((i=0; i<42; i++)); do
        n=$((i - offset + 1))
        if   [ "$n" -lt 1 ];       then d=$((prevlen + n)); printf -v cell ' %2d ' "$d"; cell="<span foreground=\"$FADE\">$cell</span>"
        elif [ "$n" -gt "$ndays" ]; then d=$((n - ndays));   printf -v cell ' %2d ' "$d"; cell="<span foreground=\"$FADE\">$cell</span>"
        else
            printf -v cell ' %2d ' "$n"
            if [ "$y" -eq "$cy" ] && [ "$m" -eq "$cm" ] && [ "$n" -eq "$cday" ]; then
                cell="<span background=\"$ACC\" foreground=\"$INK\"><b>$cell</b></span>"
            fi
        fi
        line+=$cell; col=$((col+1))
        if [ "$col" -eq 7 ]; then rows+=("$line"); line=""; col=0; fi
    done
}

y=$cy; m=$cm
while :; do
    render "$y" "$m"
    out=$(printf '%s\n' "${rows[@]}" | rofi -dmenu -markup-rows -no-custom -format i \
            -mesg "<span size=\"large\" foreground=\"$ACC\"><b>$title</b></span>" -theme "$THEME" \
            -kb-custom-1 "Right" -kb-custom-2 "Left" \
            -kb-move-char-forward "Control+f" -kb-move-char-back "Control+b")
    code=$?
    case $code in
        0)  y=$cy; m=$cm ;;
        10) m=$((m+1)); if [ "$m" -gt 12 ]; then m=1;  y=$((y+1)); fi ;;
        11) m=$((m-1)); if [ "$m" -lt 1 ];  then m=12; y=$((y-1)); fi ;;
        *)  exit 0 ;;
    esac
done
CAL_EOF

chmod +x "$BIN/qs-panel" "$BIN/notif-history" "$BIN/calendar-popup" "$BIN/settings-hub"

# ------------------------------------------------------------------- theme
write "$THEMES/panel.rasi" <<'THEME_EOF'
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
    location: south east;
    anchor: south east;
    x-offset: -12px;
    y-offset: -12px;
    width: 420px;
    background-color: @bg;
    border: 1px;
    border-color: @border-c;
    border-radius: 28px;
}

mainbox {
    padding: 14px;
    spacing: 10px;
    children: [ "message", "listview" ];
}

message {
    padding: 6px 12px;
    border: 0;
}

textbox {
    text-color: @fg-dim;
}

listview {
    columns: 1;
    lines: 8;
    fixed-height: false;
    spacing: 4px;
    scrollbar: false;
    cycle: false;
}

element {
    padding: 12px 16px;
    border-radius: 18px;
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
THEME_EOF

# calendar.rasi = panel.rasi + a few overrides (monospace grid, no row highlight)
{ cat "$THEMES/panel.rasi"; cat <<'THEME_EOF'

/* calendar overrides */
window {
    width: 360px;
}
message {
    padding: 10px 12px 2px;
}

textbox {
    horizontal-align: 0.5;
}

listview {
    lines: 7;
    spacing: 2px;
}

element {
    padding: 3px 8px;
    border-radius: 12px;
}

element-text {
    horizontal-align: 0.5;
    font: "JetBrainsMono Nerd Font 13";
}

element selected.normal {
    background-color: transparent;
    border-color: transparent;
    text-color: @fg;
}
THEME_EOF
} | write "$THEMES/calendar.rasi"

echo
echo "Done. Try:  $BIN/qs-panel   $BIN/settings-hub   $BIN/calendar-popup"
