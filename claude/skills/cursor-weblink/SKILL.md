---
name: cursor-weblink
description: Generate a cursor:// weblink that opens a repo on this machine remotely in Cursor (via Remote-SSH), for pasting into Slack/etc or opening from a laptop. Use when the user asks for a "cursor link", "cursor weblink", or to "open this repo in Cursor from my laptop/elsewhere".
---

# Cursor Remote-SSH Weblink

Build a `cursor://vscode-remote/ssh-remote+<host>/<path>` link. Clicking it on
another machine launches Cursor there, connects over Remote-SSH to this
machine, and opens the given folder.

## Steps

1. **Get the repo.** If the user named one, use it; otherwise ask which repo.
   Resolve it to an absolute path:
   - If they gave a path, `realpath` it and confirm the directory exists.
   - If they gave just a name, check `$HOME/<name>` first, then search
     (`find "$HOME" -maxdepth 3 -iname "<name>" -type d`) if that doesn't
     exist. Ask them to disambiguate if more than one match turns up.

2. **Get the SSH host alias.** This is the `Host` alias the *other* machine
   (e.g. the user's laptop) uses in its own `~/.ssh/config` to reach this one
   - not anything this repo's `ssh/dqna64-dotfiles.conf` manages (that file is
   GitHub account aliases only, per the golden rule that `~/.ssh/config` is
   hand-curated and never templated by these dotfiles).

   Read it from `$CURSOR_SSH_HOST_ALIAS` (sourced from `zsh/zsh-config`). If
   it's unset, ask the user for the alias they use to `ssh` into this machine
   from the other end, and suggest they save it for next time:

   ```sh
   export CURSOR_SSH_HOST_ALIAS="dvbx6"   # example
   ```

   in `zsh/zsh-config` (add the same var, left blank, to
   `zsh/zsh-config.example` if it isn't already there - see
   `utils/shell-var-names.sh` drift checks, which key off variable names).

3. **Build and print the link:**

   ```
   cursor://vscode-remote/ssh-remote+<alias><absolute-path>
   ```

   (the path already starts with `/`, so no extra separator between alias and
   path). Example: `cursor://vscode-remote/ssh-remote+dvbx6/home/coder/dotfiles_dqna64`

4. Remind the user this only works if `ssh <alias>` already succeeds from
   wherever they click the link, and Cursor + its Remote-SSH support are
   installed there.

## Alternative: CLI command

If the user is at a terminal on the other machine (rather than pasting a link
somewhere to click), the `cursor` CLI can open the same Remote-SSH connection
directly, no weblink needed:

```sh
cursor --remote ssh-remote+<alias> <absolute-path>
```

Note the path is a separate argument here (space-separated), not concatenated
onto the alias like the `cursor://` weblink form above. Example:

```sh
cursor --remote ssh-remote+dvbx6 /home/coder/dotfiles_dqna64
```

Same prerequisites apply: `ssh <alias>` must succeed from that machine, and
`cursor` must be on its `PATH`.
