# zsh-plugins-installer

Baseline zsh setup in one command: **Oh My Zsh** plus the four plugins:

| Plugin | What you get |
|---|---|
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | grey "ghost" suggestion from history — accept with `→`, `End` or `Ctrl+Space` |
| [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | commands coloured as you type |
| [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting) | richer, faster highlighting |
| [zsh-autocomplete](https://github.com/marlonrichert/zsh-autocomplete) | live "list as you type" completion menu |

## Install

```sh
git clone https://github.com/ejlucianojr/zsh-plugins-installer.git
cd zsh-plugins-installer
./install-zsh-plugins.sh            # add --p10k for the Powerlevel10k theme
exec zsh
```

## What it does

1. Installs `zsh`, `git`, `curl`, `perl` if missing (apt, pacman, dnf, zypper)
2. Installs Oh My Zsh if missing (an existing non-Oh-My-Zsh `~/.zshrc` is backed up)
3. Clones the four plugins into `$ZSH_CUSTOM/plugins`
4. Adds baseline settings to `~/.zshrc` (grey suggestions, `Ctrl+Space` accept, 50k shared history) in a marker block, so re-runs don't duplicate it
5. Runs `fix-zsh-autocomplete.sh`, which sets `plugins=(...)` and works around the zsh-autocomplete Tab bug (`command not found: _autocomplete__unambiguous`) and the offline `zasync` clone that triggers the Powerlevel10k instant-prompt warning — see [fix-zsh-autosuggest-script](https://github.com/ejlucianojr/fix-zsh-autosuggest-script)
6. Sets zsh as your login shell

## Options

| Flag | Effect |
|---|---|
| `--p10k` | also install Powerlevel10k and set it as the theme |
| `--update` | `git pull` plugins that are already installed |
| `--no-chsh` | don't change the login shell |
| `--no-deps` | skip package installation |

## Offline machines

On a machine where the setup already works:

```sh
./fix-zsh-autocomplete.sh --make-bundle      # -> zsh-bundle.tar.gz
```

Copy this folder (with `zsh-bundle.tar.gz`) to the offline machine and run `./install-zsh-plugins.sh`; everything is installed from the bundle.
