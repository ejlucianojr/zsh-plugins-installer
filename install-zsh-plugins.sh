#!/usr/bin/env bash
# install-zsh-plugins.sh
#
# Baseline zsh setup: Oh My Zsh + the 4 plugins we always use
#   - zsh-autosuggestions        grey "ghost" suggestion from history (accept: → / End / Ctrl+Space)
#   - zsh-syntax-highlighting    colours commands as you type
#   - fast-syntax-highlighting   richer/faster highlighting
#   - zsh-autocomplete           live "list as you type" completion menu
#
# Steps
#   1. installs zsh / git / curl / perl if missing (apt, pacman, dnf, zypper)
#   2. installs Oh My Zsh (unattended) if missing
#   3. clones the 4 plugins into $ZSH_CUSTOM/plugins (or updates them with --update)
#   4. optional: Powerlevel10k theme (--p10k)
#   5. adds baseline autosuggestion settings to ~/.zshrc (marker block, idempotent)
#   6. runs fix-zsh-autocomplete.sh (sibling file, else downloaded from GitHub),
#      which sets plugins=(...) and works around the zsh-autocomplete Tab bug
#   7. makes zsh the login shell (skip with --no-chsh)
#
# Usage
#   ./install-zsh-plugins.sh [--p10k] [--update] [--no-chsh] [--no-deps]
#
# Offline machines: put fix-zsh-autocomplete.sh and zsh-bundle.tar.gz (made with
# `fix-zsh-autocomplete.sh --make-bundle` on a working machine) next to this
# script; everything is then installed from the bundle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$ZSH_DIR/custom}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
FIX_URL="https://raw.githubusercontent.com/ejlucianojr/fix-zsh-autosuggest-script/main/fix-zsh-autocomplete.sh"

declare -A PLUGINS=(
  [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
  [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
  [fast-syntax-highlighting]="https://github.com/zdharma-continuum/fast-syntax-highlighting"
  [zsh-autocomplete]="https://github.com/marlonrichert/zsh-autocomplete"
)
ORDER=(zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete)

P10K=0 UPDATE=0 CHSH=1 DEPS=1
c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_off=$'\e[0m'
say()  { printf '%s==>%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s!!%s  %s\n' "$c_warn" "$c_off" "$*" >&2; }
die()  { printf '%sxx%s  %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }

while (( $# )); do
  case $1 in
    --p10k)    P10K=1 ;;
    --update)  UPDATE=1 ;;
    --no-chsh) CHSH=0 ;;
    --no-deps) DEPS=0 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

SUDO=""; (( EUID == 0 )) || SUDO="sudo"
online() { git ls-remote --exit-code https://github.com/zsh-users/zsh-autosuggestions HEAD >/dev/null 2>&1; }

# 1. dependencies -------------------------------------------------------------
if (( DEPS )); then
  missing=()
  for c in zsh git curl perl; do command -v "$c" >/dev/null || missing+=("$c"); done
  if (( ${#missing[@]} )); then
    say "Installing packages: ${missing[*]}"
    if   command -v apt-get >/dev/null; then $SUDO apt-get update -qq && $SUDO apt-get install -y "${missing[@]}"
    elif command -v pacman  >/dev/null; then $SUDO pacman -S --needed --noconfirm "${missing[@]}"
    elif command -v dnf     >/dev/null; then $SUDO dnf install -y "${missing[@]}"
    elif command -v zypper  >/dev/null; then $SUDO zypper install -y "${missing[@]}"
    else die "no supported package manager; install ${missing[*]} manually"; fi
  fi
fi
command -v zsh >/dev/null || die "zsh is required"

# Offline with a bundle: the fix script installs everything from it.
BUNDLE_MODE=0
if [[ -f $SCRIPT_DIR/zsh-bundle.tar.gz ]] && ! online; then
  BUNDLE_MODE=1
  say "Offline, using $SCRIPT_DIR/zsh-bundle.tar.gz for everything"
elif ! online; then
  die "no internet and no zsh-bundle.tar.gz next to this script"
fi

if (( ! BUNDLE_MODE )); then
  # 2. Oh My Zsh --------------------------------------------------------------
  if [[ ! -f $ZSH_DIR/oh-my-zsh.sh ]]; then
    say "Installing Oh My Zsh -> $ZSH_DIR"
    git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR"
  fi
  if [[ ! -f $ZSHRC ]] || ! grep -q 'oh-my-zsh.sh' "$ZSHRC"; then
    if [[ -f $ZSHRC ]]; then
      bak="$ZSHRC.pre-oh-my-zsh.$(date +%Y%m%d_%H%M%S)"
      cp "$ZSHRC" "$bak"; say "Existing non-Oh-My-Zsh .zshrc saved as $bak"
    fi
    cp "$ZSH_DIR/templates/zshrc.zsh-template" "$ZSHRC"
    say "Created $ZSHRC from the Oh My Zsh template"
  fi

  # 3. the 4 plugins ----------------------------------------------------------
  mkdir -p "$ZSH_CUSTOM_DIR/plugins"
  for p in "${ORDER[@]}"; do
    dest="$ZSH_CUSTOM_DIR/plugins/$p"
    if [[ -d $dest/.git ]]; then
      if (( UPDATE )); then say "Updating $p"; git -C "$dest" pull --ff-only -q
      else say "$p already installed"; fi
    else
      say "Installing $p"; rm -rf "$dest"
      git clone --depth 1 -q "${PLUGINS[$p]}" "$dest"
    fi
  done

  # 4. Powerlevel10k (optional) ----------------------------------------------
  if (( P10K )); then
    t="$ZSH_CUSTOM_DIR/themes/powerlevel10k"
    [[ -d $t ]] || { say "Installing Powerlevel10k"; git clone --depth 1 -q https://github.com/romkatv/powerlevel10k.git "$t"; }
    if ! grep -q '^ZSH_THEME="powerlevel10k/powerlevel10k"' "$ZSHRC"; then
      perl -pi -e 's{^ZSH_THEME=.*}{ZSH_THEME="powerlevel10k/powerlevel10k"}' "$ZSHRC"
      say "Theme set to Powerlevel10k (run 'p10k configure' in a new shell)"
    fi
  fi
fi

# 5. baseline settings block ----------------------------------------------------
BLOCK='# >>> zsh-baseline >>>
# zsh-autosuggestions: grey ghost text; accept with Right/End or Ctrl+Space
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=8"
bindkey "^ " autosuggest-accept
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS SHARE_HISTORY
# <<< zsh-baseline <<<
'
if [[ -f $ZSHRC ]]; then
  perl -0pi -e 's/^# >>> zsh-baseline >>>.*?# <<< zsh-baseline <<<\n//gms' "$ZSHRC"
  # insert after `source $ZSH/oh-my-zsh.sh` (and after the fix block if present)
  BLOCK="$BLOCK" perl -0pi -e '
    s{^(\s*source\s+["\x27]?\$ZSH/oh-my-zsh\.sh["\x27]?[^\n]*\n(?:# >>> zsh-autocomplete-fix:post >>>.*?# <<< zsh-autocomplete-fix:post <<<\n)?)}{$1$ENV{BLOCK}}ms' "$ZSHRC"
fi

# 6. zsh-autocomplete fix (plugins line, zasync, Tab workaround) -----------------
FIX="$SCRIPT_DIR/fix-zsh-autocomplete.sh"
if [[ ! -f $FIX ]]; then
  FIX="$(mktemp)"; trap 'rm -f "$FIX"' EXIT
  say "Downloading fix-zsh-autocomplete.sh"
  curl -fsSL "$FIX_URL" -o "$FIX" || die "could not download $FIX_URL"
fi
say "Running fix-zsh-autocomplete.sh"
bash "$FIX"

# Baseline block needs to come after the fix block; re-place it if the fix ran
# on a fresh .zshrc and inserted its block after ours.
perl -0pi -e 's/^(# >>> zsh-baseline >>>.*?# <<< zsh-baseline <<<\n)(# >>> zsh-autocomplete-fix:post >>>.*?# <<< zsh-autocomplete-fix:post <<<\n)/$2$1/ms' "$ZSHRC"

# 7. login shell -----------------------------------------------------------------
if (( CHSH )); then
  zsh_path="$(command -v zsh)"
  current="$(getent passwd "$USER" | cut -d: -f7 || true)"
  if [[ $current != "$zsh_path" ]]; then
    say "Setting login shell to $zsh_path"
    $SUDO chsh -s "$zsh_path" "$USER" || warn "chsh failed; run: chsh -s $zsh_path"
  fi
fi

say "Baseline installed. Open a new terminal (or run: exec zsh)."
