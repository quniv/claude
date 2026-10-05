# GNOME Shell setup

```bash
~/claude/gnome/install.sh   # install, enable and configure the extensions
# Log out and back in.
```

After you change an extension's settings, run `~/claude/gnome/export.sh` and publish the diff.

```text
extensions.gnome.org ──zip──▶ install.sh ──▶ ~/.local/share/gnome-shell/extensions/
extensions.txt ─────────────▶ install.sh ──▶ dconf /org/gnome/shell/enabled-extensions
extensions.dconf ───────────▶ install.sh ──▶ dconf /org/gnome/shell/extensions/

dconf /org/gnome/shell/extensions/ ──▶ export.sh ──▶ extensions.dconf
```

The setup targets GNOME Shell 46 on Ubuntu 24.04.

## Extensions

| Extension | Purpose |
|---|---|
| [Astra Monitor](https://extensions.gnome.org/extension/6682/) | CPU, memory, storage, network and temperature in the top bar |
| [Clipboard Indicator](https://extensions.gnome.org/extension/779/) | Clipboard history, opened with `Alt+V` |
| [Notification Timeout](https://extensions.gnome.org/extension/3795/) | Custom timeout for notifications |
| [Brightness control using ddcutil](https://extensions.gnome.org/extension/2645/) | External monitor brightness slider |
| [Caffeine](https://extensions.gnome.org/extension/517/) | Toggle that blocks suspend and screen lock |
| [Claude Code Usage Monitor](https://extensions.gnome.org/extension/10086/) | Claude Code usage in the top bar |
| [Space Bar](https://extensions.gnome.org/extension/5090/) | Workspace labels in the top bar |

Ubuntu Dock ships with Ubuntu. It reads its settings from the `dash-to-dock` section of `extensions.dconf`.

## Files

| File | Holds |
|---|---|
| `extensions.txt` | The UUIDs that `install.sh` installs and enables |
| `extensions.dconf` | Their settings, exported by `export.sh` |
| `install.sh` | Downloads missing extensions for the running GNOME version, enables them and loads the settings |
| `export.sh` | Rewrites `extensions.dconf` from the live settings |

`install.sh` is safe to re-run. It skips installed extensions and keeps other enabled extensions.
GNOME loads a newly installed extension only after the next login.

## Not exported

- Workspace names are not exported, because they hold project names.
- Astra Monitor GPU and disk IDs are not exported, because they are machine-specific. Its `profiles` key is rebuilt on first start.
- The Caffeine on and off state is not exported.
- The Claude Code Usage profile holds a home path. The extension creates it on first start.
- Look Desktop Integration ships with the Look app and is not on extensions.gnome.org.

## Requirements

- `curl`, `jq`, `python3` and `dconf`.
- Brightness control needs `ddcutil` and I2C access:

  ```bash
  sudo apt install ddcutil
  sudo usermod -aG i2c "$USER"   # takes effect after the next login
  ```
