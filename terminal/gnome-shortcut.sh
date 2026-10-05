#!/usr/bin/env bash
# Bind a GNOME custom shortcut (default Alt+T) that opens Ghostty.
# Safe to re-run. Other custom shortcuts are kept.
set -euo pipefail

key=${1:-<Alt>t}
base=/org/gnome/settings-daemon/plugins/media-keys
path=$base/custom-keybindings/ghostty/

cmd=$(command -v ghostty) || { echo "ghostty is not in PATH" >&2; exit 1; }

list=$(dconf read "$base/custom-keybindings")
case $list in "" | "@as []") list="[]" ;; esac

# A shortcut set by hand (customN) already owns the key: leave it alone.
for p in $(grep -oE "'[^']+'" <<<"$list" | tr -d "'"); do
  [[ $p == "$path" ]] && continue
  if [[ $(dconf read "${p}binding") == "'$key'" ]]; then
    echo "$key is already bound to $(dconf read "${p}command") ($p). Nothing changed."
    exit 0
  fi
done

dconf write "${path}name" "'ghostty'"
dconf write "${path}command" "'$cmd'"
dconf write "${path}binding" "'$key'"

if [[ $list != *"'$path'"* ]]; then
  [[ $list == "[]" ]] && list="['$path']" || list="${list%]}, '$path']"
  dconf write "$base/custom-keybindings" "$list"
fi

echo "$key now opens $cmd."
