If you have vscode installed on your machine and you want it to use these json config files
in this directory, you'll need to copy these settings into the path that your vscode
installation expects these settings to be found.

One easy way is to create a symlink in the path that vscode expects, pointing back to these
files.

## macOS

```bash
# VS Code
ln -sf "$DOTFILES_DIR/vscode/User/settings.json" \
       "$HOME/Library/Application Support/Code/User/settings.json"
ln -sf "$DOTFILES_DIR/vscode/User/keybindings.json" \
       "$HOME/Library/Application Support/Code/User/keybindings.json"

# Cursor
ln -sf "$DOTFILES_DIR/vscode/User/settings.json" \
       "$HOME/Library/Application Support/Cursor/User/settings.json"
ln -sf "$DOTFILES_DIR/vscode/User/keybindings.json" \
       "$HOME/Library/Application Support/Cursor/User/keybindings.json"
```

`$DOTFILES_DIR` is set by `zsh/.zshenv` (defaults to `$HOME/dotfiles_dqna64`).

## Notes

- `ln -sf` overwrites the destination — back up the existing file first if you
  have unsaved settings (`mv settings.json settings.json.bak`).
- Editing the symlinked file in VS Code / Cursor edits the file in this repo,
  so changes are tracked automatically.
- Could be folded into `install.sh` using the existing `symlink_dotfile`
  helper if/when this is worth automating.
