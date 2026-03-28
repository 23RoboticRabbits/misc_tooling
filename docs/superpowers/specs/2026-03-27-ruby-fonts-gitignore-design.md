# Ruby Gems, Font Regex, and Gitignore Design

**Date:** 2026-03-27
**Scope:** Four targeted fixes to `setup-macbook.sh`: gem installation for both Ruby versions, Ruby install false-failure fix, font regex tightening, and global gitignore expansion.

---

## 1. Gem Installation Refactor

### Problem
`install_ruby_gems_for_sublime` only installs gems for Ruby 4.x. Gems need to be installed for both 3.x and 4.x. The gem list also needs `rails` and `playwright-ruby-client` added.

### New gem list (applied to both versions)
```
bundler ruby-lsp rubocop rubocop-rails rubocop-rspec rubocop-shopify rails playwright-ruby-client
```

### New function: `install_gems_for_ruby_version "<version>"`
- Takes a single rbenv version string
- Skips with `warn` if version is not installed in rbenv
- Installs every gem in the list using `RBENV_VERSION="$version" rbenv exec gem install --no-document`
- Each gem failure warns and continues
- Runs `rbenv rehash` after the loop, warn on failure

### Rename: `install_ruby_gems_for_sublime` → `install_ruby_gems`
- Calls `load_rbenv_env_current_shell`
- Resolves `ruby_3` and `ruby_4` via `latest_stable_ruby_for_major`
- Calls `install_gems_for_ruby_version` for each; missing/unavailable versions warn and skip independently
- `main()` updated: `install_ruby_gems_for_sublime` → `install_ruby_gems`

---

## 2. Ruby Install False-Failure Fix

### Problem
`install_ruby_version_with_rbenv` uses `rbenv install`'s exit code as the sole success signal. `rbenv install` can exit non-zero after a successful compile (e.g. post-install hook or rehash step fails), producing a false failure warning.

### Fix
Replace:
```bash
rbenv install "$version" >/dev/null 2>&1 || return 1
```
With:
```bash
rbenv install "$version" >/dev/null 2>&1
rbenv versions --bare | grep -Fxq "$version"
```
The function already uses `rbenv versions --bare` to detect pre-installed versions at the top — this mirrors that pattern for the post-install check.

---

## 3. Font Regex Tightening

### Problem
Overly broad regexes in `install_requested_fonts` match unintended casks:
- `^font-fira` matches `font-fira-sans-condensed`, `font-fira-sans-extra-condensed`, `font-firago`
- `^font-ia` matches `font-iansui`

### Fix
| Variable | Current regex | Fixed regex |
|---|---|---|
| `fira_fonts` | `^font-fira` | `^font-fira-(code\|mono)` |
| `ia_fonts` | `^font-ia` | `^font-ia-writer` |

`jetbrains_fonts` regex (`^font-jetbrains-mono-nerd`) is already specific — no change.

---

## 4. Global Gitignore Expansion

### Problem
`~/.gitignore_global` only has 4 entries. macOS development needs broader coverage.

### Additions via `ensure_line_in_file` (idempotent)

**macOS artifacts:**
- `._*`
- `.AppleDouble`
- `.LSOverride`
- `.Spotlight-V100`
- `.Trashes`
- `.fseventsd`
- `.TemporaryItems`
- `.VolumeIcon.icns`
- `.com.apple.timemachine.donotpresent`

**Editors:**
- `.idea/`
- `*.iml`
- `*.swp`
- `*.swo`
- `*~`
- `.vscode/`

**Node:**
- `node_modules/`
- `npm-debug.log*`
- `yarn-error.log*`

**Ruby/Rails:**
- `.bundle/`

Note: `vendor/bundle/`, `log/`, `tmp/`, and `coverage/` are intentionally excluded — they belong in per-project `.gitignore` files, not the global one.

**Environment:**
- `.env`
- `.env.local`
- `.env.*.local`

Existing entries (`.worktree/`, `.claude/`, `.codex/`, `.DS_Store`) are unchanged — `ensure_line_in_file` skips duplicates.

---

## Out of Scope
- No changes to `setup-sublime-text.sh`
- No global npm Playwright install — handled per-project
- No changes to Sublime Text font (remains Fira Code)
