# Dock Setup Design

## Goal

Extend `setup-macbook.sh` to install `dockutil` and seed the macOS Dock with Mike's core apps when they are missing.

## Scope

The script must:

- install `dockutil` via Homebrew
- check for these app bundles in `/Applications`:
  - `iTerm.app`
  - `Claude.app`
  - `ChatGPT.app`
  - `Visual Studio Code.app`
  - `Cursor.app`
  - `Sublime Text.app`
  - `Sublime Merge.app`
- add each app to the Dock only when it is not already present
- preserve existing Dock items and existing order

## Constraints

- The behavior must remain safe to rerun.
- Missing apps or Dock update failures should warn and continue.
- The script must stay compatible with macOS system Bash 3.2.

## Approach

Add `dockutil` to the requested Homebrew formula list, then add a `configure_dock()` helper that:

1. exits with a warning if `dockutil` is unavailable
2. checks whether each app bundle exists
3. checks whether the Dock already contains that app
4. appends the app to the Dock only when missing

Appending only missing apps means the requested order is preserved for newly added entries, while existing Dock items remain untouched.

## Error Handling

- warn if `dockutil` is unavailable after installation
- warn if an app bundle is missing
- warn if adding an app to the Dock fails
