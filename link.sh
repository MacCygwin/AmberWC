#!/usr/bin/env bash
# Symlinks everything under home/ into $HOME, so the repo is the single source
# of truth. A real file already in the way is kept as <name>.pre-dotfiles.<time>.
set -euo pipefail
DOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find "$DOT/home" \( -type f -o -type l \) -print0 | while IFS= read -r -d '' src; do
    rel=${src#"$DOT/home/"}
    dst="$HOME/$rel"
    mkdir -p "$(dirname "$dst")"
    case "$(readlink -f "$dst" 2>/dev/null)" in
        "$DOT/home/"*) continue ;;                 # already managed by the repo (also keeps
    esac                                           # waybar's currently selected style)
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mv "$dst" "$dst.pre-dotfiles.$(date +%s)"
    fi
    ln -s "$src" "$dst"
    echo "linked $rel"
done
