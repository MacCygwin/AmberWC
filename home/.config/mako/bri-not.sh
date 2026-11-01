#!/usr/bin/env bash
BRI=$(brightnessctl -m | cut -d, -f4 | tr -d '%')

notify-send -a osd -u low -t 1200 \
    -h string:x-canonical-private-synchronous:osd \
    -h int:value:"$BRI" $'\uf185' "${BRI}%"
