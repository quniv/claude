#!/usr/bin/env bash
# Link ~/.claude config to this repo, per claude/links.tsv.
# Usage: sync.sh status | link [--dry-run] | adopt <path-under-home> <repo-path> | scan
# shellcheck disable=SC2088  # "~/" in messages is display text
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
REPO=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
MANIFEST="$REPO/claude/links.tsv"
BACKUP_ROOT="$HOME/.claude/backups/claude-sync-$(date +%Y%m%d-%H%M%S)"

die() { echo "error: $*" >&2; exit 1; }

entries() {
  [[ -f $MANIFEST ]] || die "manifest not found: $MANIFEST"
  grep -vE '^\s*(#|$)' "$MANIFEST"
}

# Prints one of: ok missing same differs wrong-link repo-missing
state() {
  local src=$1 dest=$2
  [[ -e $src ]] || { echo repo-missing; return; }
  if [[ -L $dest ]]; then
    [[ $(readlink -f "$dest") == "$(readlink -f "$src")" ]] && echo ok || echo wrong-link
  elif [[ ! -e $dest ]]; then
    echo missing
  elif diff -rq "$src" "$dest" >/dev/null 2>&1; then
    echo same
  else
    echo differs
  fi
}

branch_check() {
  local b
  b=$(git -C "$REPO" branch --show-current)
  # ~/.claude follows this working tree; a feature branch would swap the live config.
  [[ $b == main ]] || die "clone at $REPO is on '${b:-detached}', not main"
}

cmd_status() {
  echo "repo: $REPO ($(git -C "$REPO" branch --show-current || true))"
  local src dest
  while IFS=$'\t' read -r src dest; do
    printf '%-12s ~/%s\n' "$(state "$REPO/$src" "$HOME/$dest")" "$dest"
  done < <(entries)
}

link_one() {
  local src=$1 dest=$2 dry=$3 st
  st=$(state "$src" "$dest")
  case $st in
    ok) return 0 ;;
    missing) ;;
    same)
      [[ $dry == 1 ]] || { mkdir -p "$(dirname "$BACKUP_ROOT/${dest#"$HOME"/}")"; mv "$dest" "$BACKUP_ROOT/${dest#"$HOME"/}"; } ;;
    *) echo "skip  $st  $dest" >&2; return 1 ;;
  esac
  echo "link  $dest -> $src"
  [[ $dry == 1 ]] || { mkdir -p "$(dirname "$dest")"; ln -s "$src" "$dest"; }
}

cmd_link() {
  local dry=0 rc=0 src dest
  [[ ${1:-} == --dry-run ]] && dry=1
  branch_check
  while IFS=$'\t' read -r src dest; do
    link_one "$REPO/$src" "$HOME/$dest" "$dry" || rc=1
  done < <(entries)
  [[ -d $BACKUP_ROOT ]] && echo "originals moved to $BACKUP_ROOT"
  [[ $rc == 0 ]] || echo "some entries skipped: resolve 'differs'/'wrong-link' by hand, then rerun" >&2
  return $rc
}

cmd_adopt() {
  local home_rel=${1:?path under \$HOME} repo_rel=${2:?repo path}
  home_rel=${home_rel#"$HOME"/}; home_rel=${home_rel#\~/}
  local dest="$HOME/$home_rel" src="$REPO/$repo_rel"
  branch_check
  [[ -e $dest && ! -L $dest ]] || die "~/$home_rel must be a real file or directory"
  [[ ! -e $src ]] || die "$repo_rel already exists in the repo"
  cut -f2 <(entries) | grep -qxF "$home_rel" && die "~/$home_rel is already in the manifest"
  mkdir -p "$(dirname "$src")"
  cp -a "$dest" "$src"
  printf '%s\t%s\n' "$repo_rel" "$home_rel" >> "$MANIFEST"
  if [[ $repo_rel == skills/* ]]; then
    ln -s "../../$repo_rel" "$REPO/.agents/skills/$(basename "$repo_rel")"
  fi
  link_one "$src" "$dest" 0
}

cmd_scan() {
  command -v gitleaks >/dev/null || die "gitleaks not installed; do not publish without a scan"
  # gitleaks < 8.19 (e.g. Ubuntu's) has no `git` subcommand; `protect` is its equivalent.
  if gitleaks git --help >/dev/null 2>&1; then
    gitleaks git --staged --redact --no-banner "$REPO"
  else
    gitleaks protect --staged --redact --no-banner -s "$REPO"
  fi
}

case ${1:-} in
  status) cmd_status ;;
  link) shift; cmd_link "$@" ;;
  adopt) shift; cmd_adopt "$@" ;;
  scan) cmd_scan ;;
  *) sed -n '2,3p' "$0" >&2; exit 2 ;;
esac
