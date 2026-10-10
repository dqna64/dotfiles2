# Extension repos (overlays) - how it works

Usage (listing an overlay, creating one) is in `README.md` -> "Extension repos
(overlays)"; rules for changing the mechanism are in `CLAUDE.md` -> "Extension
repos (overlays)"; moving a machine onto it: `docs/overlay-migration.md`.

## Roots and load order

The base repo plus every overlay listed in `DOTFILES_OVERLAYS` (gitignored
`zsh/zsh-config`) form the *roots*, base first, then overlays in list order.
`utils/overlays.sh` turns each entry (`url`, `url=path`, or a bare absolute
path) into a name (the URL/dir basename) and a local path (default
`$HOME/<name>`), and `dotfiles_roots` prints the roots that exist on disk.
Every script that links or sources config walks that list; the base stores
nothing about which overlays exist.

## What the base reads from each root

What an overlay may contain, and how it combines with the base:

| Path | Kind | Rule |
|---|---|---|
| `bin/` | collection | every repo's `bin/` is prepended to `PATH` by `.zshenv`, base first (a later repo's same-named script wins; `dotdoctor` reports these) |
| `zsh/zshrc.d/`, `zsh/zshrc.d.<machine>/` | collection | all repos' files are sourced, base first |
| `claude/skills/`, `claude/output-styles/`, `claude/rules/` | collection | all repos' items are linked; a duplicate name is an error |
| `claude/settings.json`, `tmux/.tmux.conf`, `karabiner/karabiner.json`, `yabai/yabairc` (+ machine variants: `settings.<machine>.json`, `.tmux.<machine>.conf`, `yabairc.<machine>`) | single file | most specific wins: the machine variant in any repo, else an overlay's file, else the base's; a tie is an error |
| `install.d/*.sh` | hooks | run by `install.sh` after its own steps |
| `git/gitconfig.template`, `ssh/config.template` | templates | rendered by `git/git-setup.sh` with the base's `git-identity` values (the only identity source), written next to the template (each overlay's own `.gitignore` must cover them; `new-overlay.sh` writes that and `git-setup.sh` warns if missing), and included from the base's rendered gitconfig (last, so overlay values win) and ssh snippet (first, so overlay Hosts are global); unknown placeholders are an error |
| `zsh/.zshrc`, `zsh/.zshenv`, `install.sh`, `uninstall.sh`, `utils/` | reserved | read only from the base; ignored in an overlay, with a warning |

Collections never override, single files never tie silently, and an overlay's
files are self-contained (a rule file does not import a base file).
Overlays are for private or work-specific config, not secrets: keys and
identities stay in the gitignored `zsh/zsh-config` and `git/git-identity`.

## Resolution helpers (`utils/common.sh`)

- `resolve_single <rel> <machine> <roots...>`: the machine variant (id,
  lowercased, before the last extension or appended if none) in any root wins;
  else `<rel>` in an overlay; else `<rel>` in the base. Two matches at one level
  print both paths and return 2; `install.sh` stops, `sync-agent-links.sh`
  leaves the target alone.
- `collect_collisions <subdir> <glob> <roots...>`: names provided by more than
  one root. `sync-agent-links.sh` links nothing while any exist (all or
  nothing, so a half-synced machine cannot hide the clash); `dotdoctor` reports
  them, including same-named scripts in `bin/` (there, the later root wins).

## git and ssh templates

`git/git-setup.sh` renders an overlay's `git/gitconfig.template` and
`ssh/config.template` with the base `git-identity` values (a placeholder the
identity does not define aborts) into `git/dqna64-dotfiles.gitconfig` and
`ssh/dqna64-dotfiles.conf` beside the templates. The base's rendered gitconfig
includes the overlay files last (overlay values win); the base ssh snippet
`Include`s them first (overlay `Host` blocks are global). Each overlay's own
`.gitignore` covers the rendered files; `git-setup.sh` warns if it does not.
`.zshrc`'s drift check covers overlay templates too.

## Other mechanics

- `bin/`: `.zshenv` prepends each root's `bin/` to `PATH`, base first.
- `zsh/zshrc.d/` and `zsh/zshrc.d.<machine>/`: `.zshrc` sources every root's
  files in filename order, no `case` on machine ids anywhere.
- `install.d/*.sh`: run by `install.sh` on every run with `DOTFILES_DIR`,
  `DOTFILES_OVERLAY_DIR` and `DQNA64_MACHINE` in the environment; must be
  idempotent; a failing hook is reported and does not stop the install.
- Reserved paths (`zsh/.zshrc`, `zsh/.zshenv`, `install.sh`, `uninstall.sh`,
  `utils/`) are only read from the base; `install.sh` and `dotdoctor` warn
  when an overlay carries one. Any other path is ignored silently; `dotdoctor`
  lists such files (`dotfiles_unread_paths_in`, whose case list must grow
  whenever the base starts reading a new overlay path).
- Removing an overlay: delete its line from `zsh-config`, re-run
  `sync-agent-links.sh` (prunes its dangling links) and `install.sh`.
