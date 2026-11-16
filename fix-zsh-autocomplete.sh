#!/usr/bin/env bash
# fix-zsh-autocomplete.sh
#
# Fixes an Oh My Zsh + Powerlevel10k + zsh-autocomplete setup where:
#   1. Tab prints  "command not found: _autocomplete__unambiguous" /
#      "_autocomplete__should_add_space"          (upstream bug #907 / PR #903)
#   2. The live "list as you type" menu never appears  (zasync not loaded)
#   3. p10k warns "Console output during zsh initialization detected" with
#      "Cloning into ~/.cache/zsh/zasync ... Could not resolve host: github.com"
#      (zsh-autocomplete git-clones zasync on first prompt; fails offline)
#
# Mirrors the known-working config on the Omarchy host.
#
# Usage
#   ./fix-zsh-autocomplete.sh                 fix this account (clones from GitHub
#                                             if pieces are missing, or uses a
#                                             bundle sitting next to the script)
#   ./fix-zsh-autocomplete.sh --from FILE     fix using an offline bundle
#   ./fix-zsh-autocomplete.sh --make-bundle [FILE]
#                                             on a WORKING machine: pack Oh My Zsh,
#                                             plugins, p10k and zasync into FILE
#                                             (default: zsh-bundle.tar.gz next to
#                                             this script) for offline machines
#   ./fix-zsh-autocomplete.sh --dry-run       show what would change
#
# Offline lab VM (e.g. REMnux on an isolated network):
#   host$  ./fix-zsh-autocomplete.sh --make-bundle
#   copy fix-zsh-autocomplete.sh + zsh-bundle.tar.gz to the VM, then
#   vm$    ./fix-zsh-autocomplete.sh          (picks up the bundle automatically)
#
# Safe to re-run: .zshrc edits live between marker comments and are replaced,
# not duplicated. A timestamped .zshrc backup is made before any edit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$ZSH_DIR/custom}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
ZASYNC_DIR="$CACHE/zsh/zasync"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

REQUIRED_PLUGINS=(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete)

declare -A REPOS=(
  [ohmyzsh]="https://github.com/ohmyzsh/ohmyzsh.git"
  [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
  [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
  [fast-syntax-highlighting]="https://github.com/zdharma-continuum/fast-syntax-highlighting"
  [zsh-autocomplete]="https://github.com/marlonrichert/zsh-autocomplete"
  [powerlevel10k]="https://github.com/romkatv/powerlevel10k.git"
  [zasync]="https://github.com/marlonrichert/zasync.git"
)

DRY=0
BUNDLE=""
MODE=fix

c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_off=$'\e[0m'
say()  { printf '%s==>%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s!!%s  %s\n' "$c_warn" "$c_off" "$*" >&2; }
die()  { printf '%sxx%s  %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }
run()  { if (( DRY )); then echo "   [dry-run] $*"; else "$@"; fi; }

while (( $# )); do
  case $1 in
    --from)        BUNDLE="$(realpath "${2:?--from needs a file}")"; shift 2 ;;
    --make-bundle) MODE=bundle
                   if [[ ${2:-} && $2 != --* ]]; then BUNDLE="$2"; shift; fi
                   shift ;;
    --dry-run)     DRY=1; shift ;;
    -h|--help)     sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "unknown option: $1 (see --help)" ;;
  esac
done

# --------------------------------------------------------------------------
# --make-bundle: pack the working setup for offline machines
# --------------------------------------------------------------------------
if [[ $MODE == bundle ]]; then
  out="${BUNDLE:-$SCRIPT_DIR/zsh-bundle.tar.gz}"
  [[ -f $ZSH_DIR/oh-my-zsh.sh ]] || die "no Oh My Zsh at $ZSH_DIR"
  [[ -f $ZASYNC_DIR/zasync ]]    || die "no zasync at $ZASYNC_DIR (open one zsh on this machine first)"
  stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
  mkdir -p "$stage/zsh-bundle"
  say "Packing Oh My Zsh + custom plugins/themes from $ZSH_DIR"
  tar -C "$(dirname "$ZSH_DIR")" --exclude='cache/*' --exclude='log/*' \
      -cf - "$(basename "$ZSH_DIR")" | tar -C "$stage/zsh-bundle" -xf -
  [[ $(basename "$ZSH_DIR") == .oh-my-zsh ]] || mv "$stage/zsh-bundle/$(basename "$ZSH_DIR")" "$stage/zsh-bundle/.oh-my-zsh"
  say "Packing zasync from $ZASYNC_DIR"
  cp -a "$ZASYNC_DIR" "$stage/zsh-bundle/zasync"
  if [[ -f $HOME/.p10k.zsh ]]; then
    say "Packing ~/.p10k.zsh (only installed on targets that have none)"
    cp "$HOME/.p10k.zsh" "$stage/zsh-bundle/p10k.zsh"
  fi
  tar -C "$stage" -czf "$out" zsh-bundle
  say "Bundle written: $out ($(du -h "$out" | cut -f1))"
  exit 0
fi

# --------------------------------------------------------------------------
# fix mode
# --------------------------------------------------------------------------
command -v zsh >/dev/null || die "zsh is not installed (sudo apt install zsh)"
[[ -f $ZSHRC ]] || die "$ZSHRC not found"

# Auto-detect a bundle next to the script.
if [[ -z $BUNDLE && -f $SCRIPT_DIR/zsh-bundle.tar.gz ]]; then
  BUNDLE="$SCRIPT_DIR/zsh-bundle.tar.gz"
fi
SRC=""
if [[ -n $BUNDLE ]]; then
  [[ -f $BUNDLE ]] || die "bundle not found: $BUNDLE"
  SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT
  tar -C "$SRC" -xzf "$BUNDLE"
  SRC="$SRC/zsh-bundle"
  say "Using offline bundle: $BUNDLE"
fi

have_net() { git ls-remote --exit-code "${REPOS[zasync]}" HEAD >/dev/null 2>&1; }

# fetch <bundle-relative-path> <repo-key> <dest>
fetch() {
  local rel=$1 key=$2 dest=$3
  if [[ -n $SRC && -e $SRC/$rel ]]; then
    run mkdir -p "$(dirname "$dest")"
    run cp -a "$SRC/$rel" "$dest"
  elif command -v git >/dev/null && have_net; then
    run git clone --depth 1 -- "${REPOS[$key]}" "$dest"
  else
    die "$dest is missing and there is no bundle / no internet.
    Run '$0 --make-bundle' on a working machine and copy zsh-bundle.tar.gz next to this script."
  fi
}

# 1. Oh My Zsh, plugins, theme ---------------------------------------------
if [[ ! -f $ZSH_DIR/oh-my-zsh.sh ]]; then
  say "Installing Oh My Zsh -> $ZSH_DIR"
  fetch .oh-my-zsh ohmyzsh "$ZSH_DIR"
fi
for p in zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete; do
  if [[ ! -d $ZSH_CUSTOM_DIR/plugins/$p ]]; then
    say "Installing plugin $p"
    fetch ".oh-my-zsh/custom/plugins/$p" "$p" "$ZSH_CUSTOM_DIR/plugins/$p"
  fi
done
if [[ ! -d $ZSH_CUSTOM_DIR/themes/powerlevel10k ]] && grep -q '^ZSH_THEME=.*powerlevel10k' "$ZSHRC"; then
  say "Installing theme powerlevel10k"
  fetch .oh-my-zsh/custom/themes/powerlevel10k powerlevel10k "$ZSH_CUSTOM_DIR/themes/powerlevel10k"
fi
if [[ ! -f $HOME/.p10k.zsh && -n $SRC && -f $SRC/p10k.zsh ]]; then
  say "Installing ~/.p10k.zsh from bundle"
  run cp "$SRC/p10k.zsh" "$HOME/.p10k.zsh"
fi

# 2. zasync (the async helper behind the live menu) ------------------------
#    A half-finished clone from a failed offline start leaves an empty dir.
if [[ ! -f $ZASYNC_DIR/zasync ]]; then
  say "Installing zasync -> $ZASYNC_DIR"
  run rm -rf "$ZASYNC_DIR"
  fetch zasync zasync "$ZASYNC_DIR"
fi
# zsh-autocomplete runs `git pull` whenever the plugin file is newer than
# .git/FETCH_HEAD. Offline that prints an error at startup -> p10k warning.
# The fpath entry added below makes the plugin skip this path entirely; the
# touch is a second safety net.
if [[ -d $ZASYNC_DIR/.git ]]; then
  run touch "$ZASYNC_DIR/.git/FETCH_HEAD"
fi

# 3. .zshrc ----------------------------------------------------------------
grep -q 'oh-my-zsh.sh' "$ZSHRC" || die "$ZSHRC does not source oh-my-zsh.sh; fix it by hand"

tmp="$(mktemp)"
cp "$ZSHRC" "$tmp"

# 3a. drop any blocks from a previous run of this script
perl -0pi -e 's/^# >>> zsh-autocomplete-fix:(pre|post) >>>.*?# <<< zsh-autocomplete-fix:\1 <<<\n//gms' "$tmp"

# 3b. make sure the plugins=(...) list (single- or multi-line) has what we need,
#     with zsh-autocomplete last (matches the working host)
REQ="${REQUIRED_PLUGINS[*]}" perl -0pi -e '
  my @req = split " ", $ENV{REQ};
  if (s{^plugins=\((.*?)\)}{
        my @have = grep { length } split /\s+/, $1;
        my %seen; my @out = grep { !$seen{$_}++ } (@have, @req);
        @out = ((grep { $_ ne "zsh-autocomplete" } @out), "zsh-autocomplete");
        "plugins=(\n" . join("", map { "  $_\n" } @out) . ")"
      }mse) { } else {
    s{^(\s*source\s+["\x27]?\$ZSH/oh-my-zsh\.sh)}{"plugins=(\n" . join("", map { "  $_\n" } @req) . ")\n$1"}me;
  }' "$tmp"

PRE_BLOCK='# >>> zsh-autocomplete-fix:pre >>>
# Put zasync on fpath so zsh-autocomplete finds it locally and never tries to
# git clone/pull it at startup (fails offline and trips the p10k warning).
fpath=("${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zasync" $fpath)
# <<< zsh-autocomplete-fix:pre <<<
'

POST_BLOCK='# >>> zsh-autocomplete-fix:post >>>
# WORKAROUND: zsh-autocomplete regressions (upstream bug #907, PR #903).
# Oh My Zsh runs compinit before the plugin loads, so:
#   1. zasync is not autoloaded from its file -> live menu never appears
#   2. the _autocomplete__* helpers are never registered -> Tab / Up-arrow fail
#      with "command not found: _autocomplete__unambiguous" etc.
# Re-register both from the plugin'"'"'s own files. Remove once PR #903 lands.
() {
  local zasync_file="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zasync/zasync"
  if [[ -f $zasync_file ]]; then
    unfunction zasync 2>/dev/null
    autoload -Uz "$zasync_file"
  fi
  local comp_dir="${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-autocomplete/Completions"
  if [[ -d $comp_dir ]]; then
    fpath=("$comp_dir" $fpath)
    local f
    for f in "$comp_dir"/_autocomplete__*(N:t); do
      autoload -Uz "$f"
    done
  fi
}
# <<< zsh-autocomplete-fix:post <<<
'

# 3c. insert pre-block right before, post-block right after `source $ZSH/oh-my-zsh.sh`
#     (skip the post-block if the .zshrc already has the hand-written host version)
if grep -q '_autocomplete__should_add_space' "$tmp"; then
  POST_BLOCK=""
  say ".zshrc already contains the _autocomplete__ workaround; only adding the fpath fix"
fi
PRE="$PRE_BLOCK" POST="$POST_BLOCK" perl -0pi -e '
  s{^(\s*source\s+["\x27]?\$ZSH/oh-my-zsh\.sh["\x27]?[^\n]*\n)}{$ENV{PRE}$1$ENV{POST}}m
    or die "could not find the oh-my-zsh.sh source line\n";' "$tmp"

if cmp -s "$ZSHRC" "$tmp"; then
  say ".zshrc already up to date"
elif (( DRY )); then
  echo "   [dry-run] .zshrc diff:"; diff -u "$ZSHRC" "$tmp" || true
else
  backup="$ZSHRC.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$ZSHRC" "$backup"; say "Backed up $ZSHRC -> $backup"
  cat "$tmp" > "$ZSHRC"
  say "Patched $ZSHRC"
fi
rm -f "$tmp"

# 4. clear stale caches (old compdump / p10k instant prompt) ---------------
say "Clearing completion and instant-prompt caches"
run rm -f "$HOME"/.zcompdump* "$CACHE"/zsh/compdump* "$CACHE"/oh-my-zsh/.zcompdump* \
          "$ZSH_DIR"/cache/.zcompdump* "$CACHE"/p10k-instant-prompt-* "$CACHE"/p10k-dump-*

# 5. sanity check ------------------------------------------------------------
if (( ! DRY )); then
  if out="$(zsh -i -c 'whence -w zasync _autocomplete__unambiguous _autocomplete__should_add_space' 2>&1 </dev/null)"; then
    say "Check passed:"; sed 's/^/     /' <<<"$out"
  else
    warn "Check reported problems:"; sed 's/^/     /' <<<"$out" >&2
  fi
  say "Done. Open a new terminal (or run: exec zsh)."
fi
