#!/usr/bin/env bash

# Print (sorted, unique, one per line) the names of the variables that a
# shell-style file defines. The names are obtained by actually sourcing the
# file in a clean bash subshell and diffing the set of defined variables — so
# this is robust to comments, indentation, quoting, values containing '=',
# line continuations, and `export`/`declare` prefixes, unlike regex-scraping
# assignment lines.
#
# Values are never printed, only variable names. Used to detect drift between
# template config files and their rendered versions, eg:
# - git/gitconfig.template and git/dqna64-dotfiles.gitconfig
# - ssh/config.template and ssh/dqna64-dotfiles.conf
#
# Usage: identity-vars.sh <file>
# 
# Example:
# $ identity-vars.sh git/gitconfig.template
# PRIMARY_NAME
# PRIMARY_EMAIL
# PRIMARY_ACC_SSH_PRIV_KEY
# ...


set -euo pipefail

file="${1:?usage: identity-vars.sh <file>}"
[[ -f "$file" ]] || exit 0

# Variables present in a clean bash, before vs after sourcing the file; the
# difference is exactly what the file defined. `env -i` strips the inherited
# environment so only bash's own defaults (identical in both runs) and the
# file's variables remain. The baseline runs the SAME prologue (sourcing
# /dev/null with the same redirections/`|| true`) so any variables bash sets as
# a side effect of sourcing (e.g. PIPESTATUS) appear in both and cancel out.
baseline="$(env -i bash --noprofile --norc -c \
    'source /dev/null >/dev/null 2>&1 || true; compgen -v' | sort -u)"
sourced="$(env -i bash --noprofile --norc -c \
    'source "$1" >/dev/null 2>&1 || true; compgen -v' bash "$file" | sort -u)"

comm -13 <(printf '%s\n' "$baseline") <(printf '%s\n' "$sourced")
