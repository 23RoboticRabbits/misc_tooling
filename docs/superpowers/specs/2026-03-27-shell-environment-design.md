# Shell Environment Enhancements Design

**Date:** 2026-03-27
**Scope:** Additions to `setup-macbook.sh` for starship prompt, zsh plugins, JetBrains Mono Nerd Font, and iTerm2 font update.

---

## Overview

Extend `setup-macbook.sh` to install and configure a modern zsh shell environment: starship prompt with a two-line layout, zsh-autosuggestions, zsh-syntax-highlighting, and JetBrains Mono Nerd Font as the iTerm2 terminal font.

No changes to `setup-sublime-text.sh`. Fira Code remains installed for Sublime Text.

---

## 1. New Packages

### Formulae (added to `install_requested_packages`)
- `starship`
- `zsh-autosuggestions`
- `zsh-syntax-highlighting`

### Fonts (added to `install_requested_fonts`)
- JetBrains Mono Nerd Font via `collect_cask_matches` with regex `^font-jetbrains-mono-nerd` and fallback token `font-jetbrains-mono-nerd-font`.
- Fira Code and iA Writer fonts remain unchanged.

---

## 2. zsh Configuration

Two new functions, called from `main()` after `ensure_zsh_rbenv_config`.

### `ensure_zsh_plugins_config`

Appends to `~/.zshrc` using the existing `append_block_if_missing` pattern (marker: `# >>> macbook-bootstrap: zsh plugins >>>`):

```zsh
# >>> macbook-bootstrap: zsh plugins >>>
if [ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
if [ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
# <<< macbook-bootstrap: zsh plugins <<<
```

Both sources are guarded by `-f` checks so the block is safe even if a package failed to install.

### `ensure_zsh_starship_config`

Appends to `~/.zshrc` using `append_block_if_missing` (marker: `# >>> macbook-bootstrap: starship >>>`):

```zsh
# >>> macbook-bootstrap: starship >>>
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
# <<< macbook-bootstrap: starship <<<
```

### Ordering

Final `~/.zshrc` block order:
1. `homebrew completions` (existing)
2. `rbenv` (existing)
3. `zsh plugins` (new — autosuggestions + syntax-highlighting)
4. `starship` (new — must come after syntax-highlighting per zsh-syntax-highlighting requirement)

### Error handling

Both functions are `warn`-only: inline `-f` / `command -v` guards prevent hard failures; if a plugin file is missing the shell simply skips sourcing it.

---

## 3. Starship Configuration

### `configure_starship`

Called from `main()` alongside the other `configure_*` functions.

1. If `~/.config/starship.toml` exists, copy it to `~/.config/starship.toml.bak.YYYYMMDD-HHMMSS` (timestamp via `date +%Y%m%d-%H%M%S`). Backup failure warns and continues.
2. `mkdir -p ~/.config`
3. Write `~/.config/starship.toml` with the config below. Write failure warns and continues.

### starship.toml content

Two-line prompt layout:
- **Line 1 left:** directory, git_branch, git_status, ruby, nodejs
- **Line 1 right:** cmd_duration, status, time (pushed right via `$fill`)
- **Line 2:** character (prompt symbol, green/red based on exit code)

```toml
format = """
$directory$git_branch$git_status$ruby$nodejs$fill$cmd_duration$status$time
$character"""

[fill]
symbol = " "

[directory]
style = "bold cyan"
truncation_length = 3
truncate_to_repo = true

[git_branch]
symbol = " "
style = "bold yellow"
format = "[$symbol$branch(:$remote_branch)]($style) "

[git_status]
style = "red"
format = '([$all_status$ahead_behind]($style) )'
conflicted = "⚡"
ahead = "↑${count}"
behind = "↓${count}"
diverged = "↕↑${ahead_count}↓${behind_count}"
modified = "~${count}"
staged = "+${count}"
untracked = "?${count}"
deleted = "✘${count}"

[ruby]
symbol = " "
style = "bold red"
detect_files = ["Gemfile", ".ruby-version", "*.gemspec"]
format = "[$symbol($version)]($style) "

[nodejs]
symbol = " "
style = "bold green"
detect_files = ["package.json", ".nvmrc", ".node-version"]
format = "[$symbol($version)]($style) "

[cmd_duration]
min_time = 2_000
format = "[$duration]($style) "
style = "bold yellow"

[status]
disabled = false
format = "[$symbol $status]($style) "
symbol = "✘"
style = "bold red"

[time]
disabled = false
format = "[$time]($style) "
time_format = "%H:%M:%S"
style = "dimmed white"

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
```

---

## 4. iTerm2 Font Update

In `configure_iterm2`, the `"Normal Font"` key in the DynamicProfile JSON changes from:

```
"FiraCode-Regular 14"
```

to:

```
"JetBrainsMonoNerdFont-Regular 14"
```

`JetBrainsMonoNerdFont-Regular` is the PostScript name derived from the TTF filename `JetBrainsMonoNerdFont-Regular.ttf` installed by the current `font-jetbrains-mono-nerd-font` cask. Size remains 14. All other iTerm2 profile values (colors, GUID, name) are unchanged.

---

## Out of Scope

- `setup-sublime-text.sh` — no changes
- Sublime Text font — remains Fira Code
- rbenv zsh config — already implemented in `ensure_zsh_rbenv_config`
- Starship config preservation / merge — backup-and-overwrite is sufficient for a bootstrap script
