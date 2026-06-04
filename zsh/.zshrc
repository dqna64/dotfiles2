
# DOTFILES_DIR and per-machine variables (zsh/zsh-config) are set by ~/.zshenv,
# which zsh sources before this file. PATH additions and other env-only
# exports also live there. See zsh/.zshenv in the dotfiles repo.

# === P10k instant prompt

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ "$ENABLE_P10K_INSTANT_PROMPT" == "true" && -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
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

# === Oh My Zsh and Powerlevel10k theme loading
# omz-setup.zsh is our wrapper that sets ZSH, ZSH_THEME, plugins, then sources
# OMZ's real loader at $ZSH/oh-my-zsh.sh. Sourced directly from the repo so
# edits take effect without needing a separate symlink. Warn loudly if it's
# missing (broken DOTFILES_DIR or partial install).
OMZ_SETUP="$DOTFILES_DIR/zsh/omz-setup.zsh"
if [ -f "$OMZ_SETUP" ]; then
    source "$OMZ_SETUP"
else
    echo "Warning: omz-setup not found at $OMZ_SETUP" >&2
fi
unset OMZ_SETUP

# === Set zsh theme
# Must be sourced AFTER theme loading by oh my zsh
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
if [[ $ZSH_THEME_MY == "p10k" ]]; then
  [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
elif [[ $ZSH_THEME_MY == "starship" ]]; then
  eval "$(starship init zsh)"
fi

# ===

# === Source aliases
# $DOTFILES_DIR/aliases/ loads on every machine. The case adds per-machine
# dirs named aliases.<suffix>/, where <suffix> is arbitrary and several
# machines can share a dir: every machine loads git_stuff, and the Cnv
# devboxes DVBX1/2/3 share dvbx_cnv. Each dir's *.zsh files are sourced; a
# listed dir that doesn't exist warns to stderr.
#
# Wrapped in a function so the loop/temp variables are local and need no
# manual cleanup; aliases and functions defined by the sourced files stay
# global. The function is left defined so aliases can be reloaded on demand.
load_dqna64_aliases() {
    local -a dirs=("$DOTFILES_DIR/aliases")
    local dir file

    case "$DQNA64_MACHINE" in
        MB_M1)               dirs+=("$DOTFILES_DIR"/aliases.{git_stuff,mb_m1}) ;;
        MB_CNV)              dirs+=("$DOTFILES_DIR"/aliases.{git_stuff,mb_cnv}) ;;
        DVBX1|DVBX2|DVBX3)   dirs+=("$DOTFILES_DIR"/aliases.{git_stuff,dvbx_cnv}) ;;
    esac

    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            [ "${VERBOSITY_DQNA64:-0}" -ge 1 ] && echo "Loading aliases from $dir"
            for file in "$dir"/*.zsh(N); do
                source "$file"
            done
        else
            echo "Warning: alias dir not found at $dir" >&2
        fi
    done
}
load_dqna64_aliases

# ===

bindkey "[D" backward-word
bindkey "[C" forward-word

# === Machine-specific zsh config
# Source per-machine config from the dotfiles repo if a matching file
# exists. Filename convention is zsh/.zshrc.<machine>, where <machine>
# is $DQNA64_MACHINE lowercased with underscores replaced by hyphens
# (e.g. MB_M1 -> mb-m1, MB_CNV -> mb-cnv, DVBX1 -> dvbx1). To wire up
# a new machine, just drop the file in zsh/ — no edit here needed.
# Missing files are not an error (most machines won't have one).
if [ -n "$DQNA64_MACHINE" ]; then
    MACHINE_ZSHRC="$DOTFILES_DIR/zsh/.zshrc.${${DQNA64_MACHINE:l}//_/-}"
    if [ -f "$MACHINE_ZSHRC" ]; then
        [ "${VERBOSITY_DQNA64:-0}" -ge 1 ] && echo "Loading machine zshrc from $MACHINE_ZSHRC"
        source "$MACHINE_ZSHRC"
    fi
    unset MACHINE_ZSHRC
fi

# === Yabai window management
# yabairc itself is read by yabai from $HOME/.config/yabai/yabairc (symlinked
# by install.sh). start.sh and aliases.zsh are invoked/sourced directly from
# the repo so edits take effect without separate symlinks.
if [[ "$ENABLE_YABAI_DQNA64" == "true" ]]; then
    YABAI_DIR="$DOTFILES_DIR/yabai"
    if [ -x "$YABAI_DIR/start.sh" ]; then
        "$YABAI_DIR/start.sh"
    else
        echo "Warning: yabai start script not found/executable at $YABAI_DIR/start.sh" >&2
    fi
    [ -f "$YABAI_DIR/aliases.zsh" ] && source "$YABAI_DIR/aliases.zsh"
    unset YABAI_DIR
fi

