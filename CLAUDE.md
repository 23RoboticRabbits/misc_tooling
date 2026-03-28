# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A macOS development environment bootstrap project — standalone Bash scripts that automate setup of a new MacBook (Homebrew, CLI tools, GUI apps, Ruby via rbenv, Sublime Text, iTerm2, Git config, Superpowers plugin integration).

## Scripts

- `setup-macbook.sh` — main bootstrap script (~764 lines)

## Syntax Validation

```bash
bash -n setup-macbook.sh
```

No test framework is present. Syntax validation is the primary automated check.

## Architecture

Both scripts follow the same pattern: small helper functions grouped by responsibility, a `main()` function that orchestrates them in order, and a final warnings summary.

**Key helpers (defined in both scripts):**
- `log()` / `warn()` / `die()` — structured logging; `warn()` collects into `WARNINGS=()` array printed at end; `die()` exits immediately
- `append_block_if_missing()` — idempotent file appending using marker delimiters (used for `~/.zprofile` and `~/.zshrc`)
- `brew_install_formula()` / `brew_install_cask()` — idempotent Homebrew wrappers (check before install)
- `install_with_fallback()` — tries multiple install candidates in order, stops at first success
- `latest_stable_ruby_for_major()` / `configure_rbenv_rubies()` — discovers and installs latest Ruby 3.x and 4.x
- `json_merge_superpowers_claude_state()` — uses inline Ruby to manipulate JSON config for Superpowers

**Error handling philosophy:**
- Homebrew installation is mandatory — uses `die()` on failure
- Package installs, GUI config, Ruby setup are warning-only — use `warn()` and continue

**Idempotency requirements:** Every operation must be safe to run repeatedly. Check before install/append/symlink.

**Bash 3.2 compatibility required** — no associative arrays, no `mapfile`, no Bash 4+ features. Use parameter expansion for string manipulation.

**macOS architecture:** Scripts detect Intel (`/usr/local/bin/brew`) vs Apple Silicon (`/opt/homebrew/bin/brew`) for Homebrew paths.

## Documentation

Design specs and implementation plans live under `docs/superpowers/`:
- `docs/superpowers/specs/` — design specifications (authoritative requirements)
- `docs/superpowers/plans/` — implementation plans with task breakdowns

When implementing changes, check the relevant spec first for constraints and scope.
