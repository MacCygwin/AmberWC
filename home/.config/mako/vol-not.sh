#!/usr/bin/env bash
OUT=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)   # e.g. "Volume: 0.45" or "Volume: 0.45 [MUTED]"
VOL=$(awk '{printf "%.0f", $2*100}' <<< "$OUT")

if [[ $OUT == *MUTED* ]]; then
    ICON=$'\uf026'; VAL=0; TXT="Muted"
else
    [ "$VOL" -lt 50 ] && ICON=$'\uf027' || ICON=$'\uf028'
    VAL=$VOL; TXT="${VOL}%"
fi
[ "$VAL" -gt 100 ] && VAL=100

notify-send -a osd -u low -t 1200 \
    -h string:x-canonical-private-synchronous:osd \
    -h int:value:"$VAL" "$ICON" "$TXT"
