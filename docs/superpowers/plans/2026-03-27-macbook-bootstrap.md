# MacBook Bootstrap Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone, rerunnable macOS bootstrap script that installs Homebrew packages, configures zsh, Git, Sublime defaults, and iTerm2.

**Architecture:** Use one Bash 3.2-compatible script with focused helper functions for package installation, file updates, app defaults, and iTerm2 profile creation. Keep mandatory steps fatal and non-critical steps warning-only so a partial failure does not block the rest of the machine setup.

**Tech Stack:** Bash, Homebrew, macOS `defaults`, `duti`, `curl`, `plutil`

---

### Task 1: Create the bootstrap script skeleton

**Files:**
- Create: `/Users/mike/temp/setup-macbook.sh`

- [ ] **Step 1: Write the script header and runtime helpers**

```bash
#!/usr/bin/env bash
set -u
set -o pipefail

log() { ... }
warn() { ... }
die() { ... }
```

- [ ] **Step 2: Run Bash syntax check**

Run: `bash -n /Users/mike/temp/setup-macbook.sh`
Expected: no output and exit code `0`

### Task 2: Add Homebrew and zsh setup

**Files:**
- Modify: `/Users/mike/temp/setup-macbook.sh`

- [ ] **Step 1: Add Homebrew install and shellenv helpers**

```bash
install_homebrew() { ... }
load_homebrew_env() { ... }
ensure_zsh_homebrew_config() { ... }
```

- [ ] **Step 2: Run Bash syntax check**

Run: `bash -n /Users/mike/temp/setup-macbook.sh`
Expected: no output and exit code `0`

### Task 3: Add package install logic

**Files:**
- Modify: `/Users/mike/temp/setup-macbook.sh`

- [ ] **Step 1: Add formula/cask install helpers and requested package list**

```bash
brew_install_formula() { ... }
brew_install_cask() { ... }
install_with_fallback() { ... }
install_requested_packages() { ... }
install_requested_fonts() { ... }
```

- [ ] **Step 2: Run Bash syntax check**

Run: `bash -n /Users/mike/temp/setup-macbook.sh`
Expected: no output and exit code `0`

### Task 4: Add Git, Sublime, and iTerm2 configuration

**Files:**
- Modify: `/Users/mike/temp/setup-macbook.sh`

- [ ] **Step 1: Add Git configuration helpers**

```bash
configure_git() { ... }
ensure_line_in_file() { ... }
```

- [ ] **Step 2: Add Sublime default association helper**

```bash
configure_sublime_defaults() { ... }
```

- [ ] **Step 3: Add iTerm2 Nord profile installation helper**

```bash
configure_iterm2() { ... }
```

- [ ] **Step 4: Run Bash syntax check**

Run: `bash -n /Users/mike/temp/setup-macbook.sh`
Expected: no output and exit code `0`

### Task 5: Add main flow and verify

**Files:**
- Modify: `/Users/mike/temp/setup-macbook.sh`

- [ ] **Step 1: Add the main execution flow and final summary**

```bash
main() {
  install_homebrew
  load_homebrew_env
  ...
}
main "$@"
```

- [ ] **Step 2: Run Bash syntax check**

Run: `bash -n /Users/mike/temp/setup-macbook.sh`
Expected: no output and exit code `0`

- [ ] **Step 3: Review for Bash 3.2 compatibility**

Run: `bash --version | head -n 1`
Expected: a Bash version string; confirm the script avoids associative arrays and `mapfile`
