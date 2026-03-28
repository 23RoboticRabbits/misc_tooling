# Dock Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `dockutil` installation and append missing core apps to the macOS Dock without disturbing existing Dock items.

**Architecture:** Extend the existing package installation list with `dockutil`, then add a small Dock configuration helper inside `setup-macbook.sh`. The helper should inspect `/Applications`, detect existing Dock entries, and append only missing apps while warning on failures.

**Tech Stack:** Bash 3.2, Homebrew, `dockutil`, macOS Dock preferences

---

### Task 1: Add Dock package dependency

**Files:**
- Modify: `setup-macbook.sh`

- [ ] **Step 1: Add `dockutil` to `install_requested_packages`**

Insert one additional package install line near the other CLI formulae:

```bash
  install_with_fallback "dockutil" "formula:dockutil"
```

- [ ] **Step 2: Run syntax validation**

Run: `bash -n setup-macbook.sh`
Expected: command exits successfully with no output

### Task 2: Add Dock configuration helper

**Files:**
- Modify: `setup-macbook.sh`

- [ ] **Step 1: Add a helper to detect existing Dock entries**

Add a Bash helper that uses `dockutil --find` to determine whether a Dock item already exists:

```bash
dock_has_item() {
  local label="$1"
  dockutil --find "$label" >/dev/null 2>&1
}
```

- [ ] **Step 2: Add a helper to append missing apps**

Add a `configure_dock()` function that checks `dockutil`, verifies app bundles under `/Applications`, skips apps already present, and appends missing apps:

```bash
configure_dock() {
  local app_name
  local app_path
  local apps="iTerm Claude ChatGPT Visual Studio Code Cursor Sublime Text Sublime Merge"

  if ! command -v dockutil >/dev/null 2>&1; then
    warn "dockutil is not installed; skipping Dock configuration"
    return 0
  fi

  for app_name in \
    "iTerm" \
    "Claude" \
    "ChatGPT" \
    "Visual Studio Code" \
    "Cursor" \
    "Sublime Text" \
    "Sublime Merge"; do
    app_path="/Applications/${app_name}.app"
    if [ ! -d "$app_path" ]; then
      warn "Dock app was not found at ${app_path}; skipping"
      continue
    fi
    if dock_has_item "$app_name"; then
      log "Dock app already present: ${app_name}"
      continue
    fi
    dockutil --add "$app_path" --no-restart >/dev/null 2>&1 || warn "Failed to add ${app_name} to the Dock"
  done

  killall Dock >/dev/null 2>&1 || warn "Failed to restart Dock after updates"
}
```

- [ ] **Step 3: Run syntax validation**

Run: `bash -n setup-macbook.sh`
Expected: command exits successfully with no output

### Task 3: Wire Dock configuration into main flow

**Files:**
- Modify: `setup-macbook.sh`

- [ ] **Step 1: Invoke Dock configuration after app installs**

Call the new helper after package installation and before the final summary:

```bash
  configure_dock
```

- [ ] **Step 2: Run syntax validation**

Run: `bash -n setup-macbook.sh`
Expected: command exits successfully with no output

### Task 4: Review and verify

**Files:**
- Modify: `docs/superpowers/specs/2026-03-27-dock-setup-design.md`
- Modify: `docs/superpowers/plans/2026-03-27-dock-setup.md`
- Modify: `setup-macbook.sh`

- [ ] **Step 1: Check plan against spec**

Confirm the plan covers:

```text
- dockutil installation
- missing-app-only Dock updates
- preservation of existing Dock items
- warning-only failure handling
```

- [ ] **Step 2: Run final syntax validation**

Run: `bash -n setup-macbook.sh`
Expected: command exits successfully with no output
