# Shell Environment Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `setup-macbook.sh` to install and configure starship, zsh-autosuggestions, zsh-syntax-highlighting, and JetBrains Mono Nerd Font, and update iTerm2 to use the new font.

**Architecture:** All changes are in `setup-macbook.sh`. New installer entries are added to existing `install_requested_packages` and `install_requested_fonts` functions. Two new `ensure_zsh_*` functions write idempotent `~/.zshrc` blocks. A new `configure_starship` function backs up and overwrites `~/.config/starship.toml`. The iTerm2 font PostScript name is updated in place. All new calls are wired into `main()`.

**Tech Stack:** Bash 3.2, Homebrew (formula + cask), `append_block_if_missing` pattern (already in script)

---

### Task 1: Add formula and font install entries

**Files:**
- Modify: `setup-macbook.sh` — `install_requested_packages` (~line 258) and `install_requested_fonts` (~line 325)

- [ ] **Step 1: Add three formula installs to `install_requested_packages`**

Add after the `install_with_fallback "rbenv"` line (~line 267):

```bash
  install_with_fallback "starship" "formula:starship"
  install_with_fallback "zsh-autosuggestions" "formula:zsh-autosuggestions"
  install_with_fallback "zsh-syntax-highlighting" "formula:zsh-syntax-highlighting"
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n setup-macbook.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Add JetBrains Mono Nerd Font to `install_requested_fonts`**

The function currently declares `fira_fonts` and `ia_fonts`. Add a `jetbrains_fonts` variable and install call after the iA Writer block:

```bash
install_requested_fonts() {
  local fira_fonts
  local ia_fonts
  local jetbrains_fonts

  if ! brew tap homebrew/cask-fonts >/dev/null 2>&1; then
    warn "Unable to tap homebrew/cask-fonts; font installs may fail"
  fi

  fira_fonts=$(collect_cask_matches "^font-fira" "font-fira-code,font-fira-mono")
  ia_fonts=$(collect_cask_matches "^font-ia" "font-ia-writer-duo,font-ia-writer-mono,font-ia-writer-quattro")
  jetbrains_fonts=$(collect_cask_matches "^font-jetbrains-mono-nerd" "font-jetbrains-mono-nerd-font")

  install_csv_casks "$fira_fonts" "font-fira*"
  install_csv_casks "$ia_fonts" "font-ia*"
  install_csv_casks "$jetbrains_fonts" "font-jetbrains-mono-nerd*"
}
```

- [ ] **Step 4: Verify syntax**

```bash
bash -n setup-macbook.sh
```

Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add setup-macbook.sh
git commit -m "feat: add starship, zsh plugins, and JetBrains Mono Nerd Font installs"
```

---

### Task 2: Add zsh plugin and starship shell config functions

**Files:**
- Modify: `setup-macbook.sh` — add two functions after `ensure_zsh_rbenv_config` (~line 208)

- [ ] **Step 1: Add `ensure_zsh_plugins_config` after `ensure_zsh_rbenv_config`**

```bash
ensure_zsh_plugins_config() {
  local zshrc_block

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: zsh plugins >>>
if [ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
if [ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
# <<< macbook-bootstrap: zsh plugins <<<
EOF
)

  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: zsh plugins >>>" "$zshrc_block"
}
```

- [ ] **Step 2: Add `ensure_zsh_starship_config` immediately after `ensure_zsh_plugins_config`**

```bash
ensure_zsh_starship_config() {
  local zshrc_block

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: starship >>>
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
# <<< macbook-bootstrap: starship <<<
EOF
)

  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: starship >>>" "$zshrc_block"
}
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n setup-macbook.sh
```

Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add setup-macbook.sh
git commit -m "feat: add ensure_zsh_plugins_config and ensure_zsh_starship_config"
```

---

### Task 3: Add `configure_starship` function

**Files:**
- Modify: `setup-macbook.sh` — add function before `print_summary` (~line 722)

- [ ] **Step 1: Add `configure_starship` before `print_summary`**

```bash
configure_starship() {
  local config_file="${HOME}/.config/starship.toml"
  local backup_file
  local timestamp

  log "Configuring starship"

  if [ -f "$config_file" ]; then
    timestamp="$(date +%Y%m%d-%H%M%S)"
    backup_file="${config_file}.bak.${timestamp}"
    cp "$config_file" "$backup_file" || warn "Failed to back up existing starship.toml to ${backup_file}"
  fi

  mkdir -p "${HOME}/.config"

  cat >"$config_file" <<'EOF'
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
EOF
}
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n setup-macbook.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add setup-macbook.sh
git commit -m "feat: add configure_starship with timestamped backup and toml config"
```

---

### Task 4: Update iTerm2 font and wire `main()`

**Files:**
- Modify: `setup-macbook.sh` — `configure_iterm2` (~line 688) and `main()` (~line 740)

- [ ] **Step 1: Change the iTerm2 font from Fira Code to JetBrains Mono Nerd Font**

In `configure_iterm2`, find:

```
      "Normal Font": "FiraCode-Regular 14",
```

Replace with:

```
      "Normal Font": "JetBrainsMonoNerdFont-Regular 14",
```

Also update the log message on the `configure_iterm2` first line from:

```bash
  log "Configuring iTerm2 with Fira Code and Nord"
```

to:

```bash
  log "Configuring iTerm2 with JetBrains Mono Nerd Font and Nord"
```

- [ ] **Step 2: Wire all new functions into `main()`**

Replace the current `main()` body with:

```bash
main() {
  install_homebrew
  load_homebrew_env

  brew update >/dev/null 2>&1 || warn "brew update failed"

  install_with_fallback "bash-completion" "formula:bash-completion"
  install_with_fallback "zsh-completions" "formula:zsh-completions"
  install_with_fallback "duti" "formula:duti"

  ensure_zsh_homebrew_config
  ensure_zsh_rbenv_config
  ensure_zsh_plugins_config
  ensure_zsh_starship_config
  install_requested_packages
  install_requested_fonts
  install_superpowers_plugins
  configure_rbenv_rubies
  install_ruby_gems_for_sublime
  configure_git
  configure_sublime_text
  configure_sublime_defaults
  configure_iterm2
  configure_starship
  print_summary
}
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n setup-macbook.sh
```

Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add setup-macbook.sh
git commit -m "feat: update iTerm2 font to JetBrains Mono Nerd Font and wire shell env functions into main"
```
