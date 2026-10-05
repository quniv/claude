#!/usr/bin/env bash
# Export the live extension settings to extensions.dconf.
set -euo pipefail
cd "$(dirname "$0")"

# dconf dirs of the extensions in extensions.txt. Ubuntu Dock stores its settings under dash-to-dock.
dirs="astra-monitor caffeine claude-usage clipboard-indicator dash-to-dock display-brightness-ddcutil notification-timeout space-bar"

# Hardware IDs, on/off state and home paths do not belong on another machine.
drop="astra-monitor:gpu-data astra-monitor:gpu-main astra-monitor:storage-main astra-monitor:profiles
astra-monitor:queued-pref-category caffeine:user-enabled caffeine:indicator-position-max
claude-usage:profiles claude-usage:profiles-initialized"

dconf dump /org/gnome/shell/extensions/ | DIRS=$dirs DROP=$drop python3 -c '
import os, sys
dirs, drop = os.environ["DIRS"].split(), set(os.environ["DROP"].split())
sections, name = {}, None
for line in sys.stdin.read().splitlines():
    if line.startswith("["):
        name = line[1:-1]
    elif "=" in line and name.split("/")[0] in dirs and name + ":" + line.split("=", 1)[0] not in drop:
        sections.setdefault(name, []).append(line)
print("\n\n".join("[%s]\n%s" % (n, "\n".join(k)) for n, k in sections.items()))
' >extensions.dconf

echo "Wrote $(grep -c '^\[' extensions.dconf) sections to gnome/extensions.dconf."
