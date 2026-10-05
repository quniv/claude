#!/usr/bin/env bash
# Install the extensions in extensions.txt, enable them and load extensions.dconf. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

shell=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)
ext_dir=${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mapfile -t uuids < <(sed 's/#.*//; s/[[:space:]]//g; /^$/d' extensions.txt)

for u in "${uuids[@]}"; do
  if [[ -d $ext_dir/$u || -d /usr/share/gnome-shell/extensions/$u ]]; then
    echo "have     $u"
    continue
  fi
  url=$(curl -fsS "https://extensions.gnome.org/extension-info/?uuid=$u&shell_version=$shell" | jq -r '.download_url // empty') || true
  if [[ -z $url ]]; then
    echo "skipped  $u (no release for GNOME $shell)" >&2
    continue
  fi
  curl -fsSL -o "$tmp/$u.zip" "https://extensions.gnome.org$url"
  gnome-extensions install --force "$tmp/$u.zip"
  echo "added    $u"
done

# gnome-extensions enable fails for an extension the running shell has not loaded yet, so edit the lists.
UUIDS="${uuids[*]}" python3 - <<'EOF'
import ast, os, subprocess

def read(key):
    v = subprocess.run(["dconf", "read", "/org/gnome/shell/" + key], capture_output=True, text=True).stdout.strip()
    return [] if v in ("", "@as []") else ast.literal_eval(v)

def write(key, items):
    subprocess.run(["dconf", "write", "/org/gnome/shell/" + key, repr(items) if items else "@as []"], check=True)

want = os.environ["UUIDS"].split()
enabled = read("enabled-extensions")
write("enabled-extensions", enabled + [u for u in want if u not in enabled])
write("disabled-extensions", [u for u in read("disabled-extensions") if u not in want])
EOF
dconf write /org/gnome/shell/disable-user-extensions false

dconf load /org/gnome/shell/extensions/ <extensions.dconf
echo "Done. Log out and back in to load newly added extensions."
