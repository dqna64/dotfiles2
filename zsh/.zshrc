
# DOTFILES_DIR and per-machine variables (zsh/zsh-config) are set by ~/.zshenv,
# which zsh sources before this file. PATH additions and other env-only
# exports also live there. See zsh/.zshenv in the dotfiles repo.

# === P10k instant prompt

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ "$ENABLE_P10K_INSTANT_PROMPT" == "true" && -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  [ "${VERBOSITY_DQNA64:-0}" -ge 1 ] && echo "Enabling Powerlevel10k instant prompt"
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# === Sanity-check that DOTFILES_DIR points at this dotfiles repo
# DOTFILES_DIR is set in ~/.zshenv. install.sh clones the repo to
# $HOME/dotfiles_dqna64 by default. If $DOTFILES_DIR doesn't resolve to
# a valid clone, downstream config that depends on it (RIPGREP_CONFIG_PATH,
# zsh-config sourcing, etc.) will silently break, so warn loudly here.
# Detection: $DOTFILES_DIR/zsh/.zshenv is a tracked file in this repo;
# if it's missing, $DOTFILES_DIR isn't pointing at a real clone.
if [ ! -f "$DOTFILES_DIR/zsh/.zshenv" ]; then
	cat >&2 <<EOF
Warning: dotfiles repo not found at DOTFILES_DIR=$DOTFILES_DIR
         install.sh clones the repo to \$HOME/dotfiles_dqna64 by default.
         Fix this by either:
           1. Moving the repo to \$HOME/dotfiles_dqna64, or
           2. Editing the DOTFILES_DIR default in zsh/.zshenv to point
              at the actual location of the repo.
EOF
fi

# === Warn if rendered git/ssh config has drifted from its template
# git/git-setup.sh renders templates into custom config files (git/dqna64-dotfiles.gitconfig,
# ssh/dqna64-dotfiles.conf) that are gitignored, and stamps each with the git object id of the
# template it came from. Those rendered files are only regenerated when you
# re-run git-setup.sh, so pulling an updated template leaves them stale and
# silently wrong. Detect that here and nag to regenerate the custom config files.
() {
    # Base first, then every overlay (utils/overlays.sh, sourced below for the
    # zshrc.d loader; sourced here too since this runs earlier).
    [ -f "$DOTFILES_DIR/utils/overlays.sh" ] && source "$DOTFILES_DIR/utils/overlays.sh"
    local -a pairs=()
    local root
    for root in ${(f)"$(dotfiles_roots 2>/dev/null)"}; do
        pairs+=("$root/git/gitconfig.template:$root/git/dqna64-dotfiles.gitconfig")
        pairs+=("$root/ssh/config.template:$root/ssh/dqna64-dotfiles.conf")
    done
    local pair template_file rendered_file stamped current
    for pair in "${pairs[@]}"; do
        template_file="${pair%%:*}"
        rendered_file="${pair#*:}"
        # Missing rendered file is the "not set up yet" case, handled elsewhere.
        [[ -f "$template_file" && -f "$rendered_file" ]] || continue
        # Cheap gate: only do real work if the template looks newer.
        [[ "$template_file" -nt "$rendered_file" ]] || continue
        # Confirm with content hash so an mtime-only bump isn't a false alarm.
        stamped="$(grep -m1 'dqna64-template-oid:' "$rendered_file" 2>/dev/null)"
        stamped="${stamped##*: }"
        current="$(git hash-object "$template_file" 2>/dev/null)"
        [[ -n "$stamped" && "$stamped" == "$current" ]] && continue
        print -P -u2 "%F{yellow}warning: $rendered_file is out of date with $template_file.%f"
        print -P -u2 "%F{yellow}         Re-run $DOTFILES_DIR/git/git-setup.sh to regenerate it.%f"
    done
}

# === Warn if an actual config is missing variables its example defines
# Several configs are created once from a tracked *.example and then never
# auto-updated (they hold per-machine/real values): git/git-identity (from
# git-identity.example) and zsh/zsh-config (from zsh-config.example). When the
# example gains or renames variables (e.g. after `git pull`), the actual file
# silently lacks them. git-setup.sh catches the git-identity case in a preflight
# when you run it; nag here too (and for zsh-config) so you notice sooner.
# Variable NAMES are compared (never values), obtained robustly by
# utils/shell-var-names.sh (sources each file rather than regex-scraping).
# Cheap: the `-nt` mtime gate skips the work unless the example is newer.
() {
    local vars_script="$DOTFILES_DIR/utils/shell-var-names.sh"
    [[ -f "$vars_script" ]] || return 0
    local -a pairs=(
        "$DOTFILES_DIR/git/git-identity.example:$DOTFILES_DIR/git/git-identity"
        "$DOTFILES_DIR/zsh/zsh-config.example:$DOTFILES_DIR/zsh/zsh-config"
    )
    local pair example_file actual_file missing
    for pair in "${pairs[@]}"; do
        example_file="${pair%%:*}"
        actual_file="${pair#*:}"
        [[ -f "$example_file" && -f "$actual_file" ]] || continue
        [[ "$example_file" -nt "$actual_file" ]] || continue
        missing="$(comm -23 <(bash "$vars_script" "$example_file") <(bash "$vars_script" "$actual_file"))"
        [[ -n "$missing" ]] || continue
        print -P -u2 "%F{yellow}warning: $actual_file is missing variables defined in $example_file:%f"
        echo "$missing" | sed 's/^/         + /' >&2
        print -P -u2 "%F{yellow}         Update it to define them (compare against the example).%f"
    done
}

# === Oh My Zsh and Powerlevel10k theme loading
# omz-setup.zsh is our wrapper that sets ZSH, ZSH_THEME, plugins, then sources
# OMZ's real loader at $ZSH/oh-my-zsh.sh. Sourced directly from the repo so
# edits take effect without needing a separate symlink. Warn loudly if it's
# missing (broken DOTFILES_DIR or partial install).
OMZ_SETUP="$DOTFILES_DIR/zsh/omz-setup.zsh"
if [ -f "$OMZ_SETUP" ]; then
    [ "${VERBOSITY_DQNA64:-0}" -ge 1 ] && echo "Loading Oh My Zsh from $OMZ_SETUP"
    source "$OMZ_SETUP"
else
    echo "Warning: omz-setup not found at $OMZ_SETUP" >&2
fi
unset OMZ_SETUP

# === Set zsh theme
# Must be sourced AFTER theme loading by oh my zsh
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
if [[ $ZSH_THEME_MY == "p10k" ]]; then
  [ "${VERBOSITY_DQNA64:-0}" -ge 1 ] && echo "Setting prompt theme: p10k"
  [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
elif [[ $ZSH_THEME_MY == "starship" ]]; then
  [ "${VERBOSITY_DQNA64:-0}" -ge 1 ] && echo "Setting prompt theme: starship"
  eval "$(starship init zsh)"
fi

# ===

# === Source zshrc.d from the base repo and every extension repo
# Every dotfiles repo (this one and each overlay listed in DOTFILES_OVERLAYS in
# zsh-config) may carry zsh/zshrc.d/*.zsh, sourced on every machine that uses
# the repo, and zsh/zshrc.d.<machine>/*.zsh, sourced only when DQNA64_MACHINE
# (lowercased) matches. Files load in filename order within a directory; use a
# numeric prefix (10-, 20-) when order matters. Base first, then overlays in
# the order listed. Resolver: utils/overlays.sh.
#
# Wrapped in a function so the loop variables are local; aliases and functions
# defined by the sourced files stay global. Left defined so it can be re-run.
[ -f "$DOTFILES_DIR/utils/overlays.sh" ] && source "$DOTFILES_DIR/utils/overlays.sh"
load_dqna64_zshrc_d() {
    local root dir file machine="${DQNA64_MACHINE:l}"
    for root in ${(f)"$(dotfiles_roots)"}; do
        for dir in "$root/zsh/zshrc.d" "$root/zsh/zshrc.d.$machine"; do
            [ -n "$machine" ] || [ "$dir" = "$root/zsh/zshrc.d" ] || continue
            [ -d "$dir" ] || continue
            [ "${VERBOSITY_DQNA64:-0}" -ge 1 ] && echo "Loading $dir"
            for file in "$dir"/*.zsh(Nn); do
                source "$file"
            done
        done
    done
}
load_dqna64_zshrc_d

# ===

bindkey "[D" backward-word
bindkey "[C" forward-word

# === Yabai window management
# yabairc itself is read by yabai from $HOME/.config/yabai/yabairc (symlinked
# by install.sh). start.sh and aliases.zsh are invoked/sourced directly from
# the repo so edits take effect without separate symlinks.
if [[ "$ENABLE_YABAI_DQNA64" == "true" ]]; then
    YABAI_DIR="$DOTFILES_DIR/yabai"
    if [ -x "$YABAI_DIR/start.sh" ]; then
        [ "${VERBOSITY_DQNA64:-0}" -ge 1 ] && echo "Starting yabai from $YABAI_DIR/start.sh"
        "$YABAI_DIR/start.sh"
    else
        echo "Warning: yabai start script not found/executable at $YABAI_DIR/start.sh" >&2
    fi
    [ -f "$YABAI_DIR/aliases.zsh" ] && source "$YABAI_DIR/aliases.zsh"
    unset YABAI_DIR
fi

# === PATH lines that work tooling appends to ~/.zshrc when missing
# Kept here verbatim so that tooling finds them and leaves the file alone.
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.opencode/bin:$PATH"

# BEGIN ANSIBLE MANAGED BLOCK FOR canva_git
export PATH="$HOME/.local/share/canva-git/bin:$PATH"
# END ANSIBLE MANAGED BLOCK FOR canva_git
