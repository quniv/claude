# Terminal setup

A snapshot of the shell + terminal environment behind the rest of this repo:
**Ghostty** as the emulator, **zsh** (oh-my-zsh) as the shell, **Starship** as the
prompt — all on a shared cyberpunk-neon palette (magenta `#ff00ff`, cyan
`#00ffff`, yellow `#ffff00` on a `#0d0d1a` background).

| File | Installs to | What it does |
|---|---|---|
| `zshrc` | `~/.zshrc` | oh-my-zsh plugins, PATH/toolchain setup, aliases, fzf theme, tool hooks |
| `zprofile` | `~/.zprofile` | login-shell PATH for `pipx` binaries |
| `starship.toml` | `~/.config/starship.toml` | two-line neon prompt — os, dir, git, k8s, language versions, clock |
| `ghostty/config` | `~/.config/ghostty/config` | fonts, colors, splits/tabs keybinds, shell integration |
| `gnome-shortcut.sh` | GNOME dconf | binds `Alt+T` to open Ghostty |

## Install

`ln -s` refuses to clobber, so back up any existing file first and re-run.
Paths assume the clone lives at `~/claude`, matching the root [README](../README.md):

```bash
mkdir -p ~/.config/ghostty

ln -s ~/claude/terminal/zshrc          ~/.zshrc
ln -s ~/claude/terminal/zprofile       ~/.zprofile
ln -s ~/claude/terminal/starship.toml  ~/.config/starship.toml
ln -s ~/claude/terminal/ghostty/config ~/.config/ghostty/config
```

Then open a new terminal (or `source ~/.zshrc`).

On GNOME, bind `Alt+T` to open Ghostty:

```bash
~/claude/terminal/gnome-shortcut.sh            # or pass another key, e.g. '<Super>Return'
```

The script adds its own custom shortcut and keeps the others. It changes
nothing when the key is already bound.

## Requirements

**Hard** — the shell breaks or the prompt vanishes without these:

- [oh-my-zsh](https://ohmyz.sh) — `.zshrc` sources `$ZSH/oh-my-zsh.sh` unconditionally
- Four custom oh-my-zsh plugins, cloned into `~/.oh-my-zsh/custom/plugins/`
  (they are third-party repos, not vendored here):

  ```bash
  ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}
  git clone https://github.com/zsh-users/zsh-autosuggestions          "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  git clone https://github.com/zsh-users/zsh-completions              "$ZSH_CUSTOM/plugins/zsh-completions"
  git clone https://github.com/zsh-users/zsh-history-substring-search "$ZSH_CUSTOM/plugins/zsh-history-substring-search"
  git clone https://github.com/zsh-users/zsh-syntax-highlighting      "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  ```

- [Homebrew (linuxbrew)](https://brew.sh) — `brew shellenv` is `eval`'d unguarded
- [Ghostty](https://ghostty.org) and **JetBrains Mono** (`sudo dnf install jetbrains-mono-fonts` on Fedora)

**Soft** — every one of these is `command -v`-guarded, so a missing tool just
means that feature is silently absent:

| Tool | Gives you |
|---|---|
| [starship](https://starship.rs) | the prompt itself (falls back to a bare zsh prompt) |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | smart `cd` |
| [direnv](https://direnv.net) | per-directory env |
| [fzf](https://github.com/junegunn/fzf) + [fd](https://github.com/sharkdp/fd) | fuzzy find, neon-themed |
| [eza](https://eza.rocks) *or* [lsd](https://github.com/lsd-rs/lsd) | `ls`/`ll`/`la`/`lt` |
| [bat](https://github.com/sharkdp/bat) | `cat`, colored man pages |
| [btop](https://github.com/aristocratos/btop) | `top` |
| [delta](https://github.com/dandavison/delta) | git pager |
| [forgit](https://github.com/wfxr/forgit) | fzf-powered git UI |
| `gh` | exports `GITHUB_PERSONAL_ACCESS_TOKEN` from `gh auth token` |

Unguarded *aliases* (`lg`→lazygit, `k`→kubectl, `j`→just, `v`→vagrant, …) are
harmless when the tool is missing — the alias just fails on use.

## Notes

- **Nothing secret is committed.** `GITHUB_PERSONAL_ACCESS_TOKEN` is resolved at
  shell startup from `gh auth token`; there are no literal credentials in these
  files. A legacy `~/.config/fish/` setup exists on the machine and is **not**
  included — zsh is the login shell, and fish's `fish_variables` can hold tokens.
- **Paths are absolute** (`/home/qitpydev/...`) in a few `.zshrc` spots — nvm,
  pipx, tfswitch, bun. Search-and-replace for your own `$HOME` after cloning.
- The setup assumes **Fedora Linux**; the Starship `[os.symbols]` block covers
  other distros and macOS, but package names in this README are `dnf`.
