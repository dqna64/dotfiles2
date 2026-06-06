#!/usr/bin/env bash

# Print (sorted, unique, one per line) the names of the variables that a
# shell-style file defines. The names are obtained by actually sourcing the
# file in a clean bash subshell and diffing the set of defined variables — so
# this is robust to comments, indentation, quoting, values containing '=',
# line continuations, and `export`/`declare` prefixes, unlike regex-scraping
# assignment lines.
#
# Values are never printed, only variable names. Used to detect drift between
# an example config file (tracked) and a user's actual config (gitignored,
# created once from the example and never auto-updated), by comparing which
# variable NAMES each defines. Current callers:
# - git/git-setup.sh + zsh/.zshrc: git/git-identity.example vs git/git-identity
# - zsh/.zshrc:                     zsh/zsh-config.example  vs zsh/zsh-config
#
# Usage: shell-var-names.sh <file>
#
# Example:
# $ shell-var-names.sh git/git-identity.example
# PRIMARY_ACC_SSH_ALIAS
# PRIMARY_ACC_SSH_PRIV_KEY
# PRIMARY_EMAIL
# ...

set -euo pipefail

file="${1:?usage: shell-var-names.sh <file>}"
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
