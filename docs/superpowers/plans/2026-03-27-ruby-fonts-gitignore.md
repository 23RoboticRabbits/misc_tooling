# Ruby Gems, Font Regex, and Gitignore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four issues in `setup-macbook.sh`: tighten font regexes, fix Ruby install false-failure, install gems for both Ruby versions with an expanded list, and expand the global gitignore.

**Architecture:** All changes are in `setup-macbook.sh`. Tasks are independent and ordered from simplest to most complex. No new files are created.

**Tech Stack:** Bash 3.2, rbenv, Homebrew

---

### Task 1: Fix font regex to exclude unintended casks

**Files:**
- Modify: `setup-macbook.sh` — `install_requested_fonts` (~line 370)

- [ ] **Step 1: Tighten the Fira and iA Writer regexes**

In `install_requested_fonts`, replace the two `collect_cask_matches` calls:

```bash
  fira_fonts=$(collect_cask_matches "^font-fira-(code|mono)" "font-fira-code,font-fira-mono")
  ia_fonts=$(collect_cask_matches "^font-ia-writer" "font-ia-writer-duo,font-ia-writer-mono,font-ia-writer-quattro")
```

(Leave the `jetbrains_fonts` line unchanged.)

- [ ] **Step 2: Verify syntax**

```bash
bash -n setup-macbook.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Commit**

Note: directory is NOT a git repository. Skip this step.

---

### Task 2: Fix Ruby install false-failure

**Files:**
- Modify: `setup-macbook.sh` — `install_ruby_version_with_rbenv` (~line 527)

- [ ] **Step 1: Replace exit-code check with post-install version verification**

In `install_ruby_version_with_rbenv`, find:

```bash
  log "Installing Ruby via rbenv: $version"
  RUBY_CONFIGURE_OPTS="--with-openssl-dir=${openssl_prefix} --with-readline-dir=${readline_prefix} --with-libyaml-dir=${libyaml_prefix}" \
    rbenv install "$version" >/dev/null 2>&1 || return 1
```

Replace with:

```bash
  log "Installing Ruby via rbenv: $version"
  RUBY_CONFIGURE_OPTS="--with-openssl-dir=${openssl_prefix} --with-readline-dir=${readline_prefix} --with-libyaml-dir=${libyaml_prefix}" \
    rbenv install "$version" >/dev/null 2>&1
  rbenv versions --bare | grep -Fxq "$version"
```

The function returns the exit code of `grep`, which is 0 only if the version actually landed. `rbenv install`'s own exit code is discarded.

- [ ] **Step 2: Verify syntax**

```bash
bash -n setup-macbook.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Commit**

Note: directory is NOT a git repository. Skip this step.

---

### Task 3: Refactor gem installation to cover both Ruby versions with expanded list

**Files:**
- Modify: `setup-macbook.sh` — replace `install_ruby_gems_for_sublime` (~line 561) with two new functions; update `main()` call (~line 877)

- [ ] **Step 1: Replace `install_ruby_gems_for_sublime` with `install_gems_for_ruby_version` and `install_ruby_gems`**

Delete the entire `install_ruby_gems_for_sublime` function (lines ~561–587) and replace it with these two functions:

```bash
install_gems_for_ruby_version() {
  local version="$1"
  local gems
  local gem_name

  if [ -z "$version" ]; then
    return 1
  fi

  if ! rbenv versions --bare | grep -Fxq "$version"; then
    warn "Skipping gem installation because Ruby ${version} is not installed in rbenv"
    return 0
  fi

  gems="bundler ruby-lsp rubocop rubocop-rails rubocop-rspec rubocop-shopify rails playwright-ruby-client"

  for gem_name in $gems; do
    log "Installing gem in Ruby ${version}: ${gem_name}"
    RBENV_VERSION="$version" rbenv exec gem install --no-document "$gem_name" >/dev/null 2>&1 || warn "Failed to install gem ${gem_name} in Ruby ${version}"
  done

  RBENV_VERSION="$version" rbenv rehash >/dev/null 2>&1 || warn "Failed to rehash rbenv after gem installation in Ruby ${version}"
}

install_ruby_gems() {
  local ruby_3
  local ruby_4

  load_rbenv_env_current_shell

  ruby_3="$(latest_stable_ruby_for_major 3)"
  ruby_4="$(latest_stable_ruby_for_major 4)"

  if [ -z "$ruby_3" ]; then
    warn "Skipping gem installation for Ruby 3.x: no stable version found"
  else
    install_gems_for_ruby_version "$ruby_3"
  fi

  if [ -z "$ruby_4" ]; then
    warn "Skipping gem installation for Ruby 4.x: no stable version found"
  else
    install_gems_for_ruby_version "$ruby_4"
  fi
}
```

- [ ] **Step 2: Update the call in `main()`**

In `main()`, find:

```bash
  install_ruby_gems_for_sublime
```

Replace with:

```bash
  install_ruby_gems
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n setup-macbook.sh
```

Expected: no output, exit 0.

- [ ] **Step 4: Commit**

Note: directory is NOT a git repository. Skip this step.

---

### Task 4: Expand global gitignore

**Files:**
- Modify: `setup-macbook.sh` — `configure_git` (~line 379)

- [ ] **Step 1: Replace the body of `configure_git` with the expanded entry list**

```bash
configure_git() {
  local gitignore_file="${HOME}/.gitignore_global"

  log "Configuring Git"
  git config --global user.name "Your Name" || warn "Unable to set git user.name"
  git config --global user.email "you@example.com" || warn "Unable to set git user.email"
  git config --global core.excludesfile "$gitignore_file" || warn "Unable to set git core.excludesfile"

  # AI tools
  ensure_line_in_file "$gitignore_file" ".worktree/"
  ensure_line_in_file "$gitignore_file" ".claude/"
  ensure_line_in_file "$gitignore_file" ".codex/"

  # macOS
  ensure_line_in_file "$gitignore_file" ".DS_Store"
  ensure_line_in_file "$gitignore_file" "._*"
  ensure_line_in_file "$gitignore_file" ".AppleDouble"
  ensure_line_in_file "$gitignore_file" ".LSOverride"
  ensure_line_in_file "$gitignore_file" ".Spotlight-V100"
  ensure_line_in_file "$gitignore_file" ".Trashes"
  ensure_line_in_file "$gitignore_file" ".fseventsd"
  ensure_line_in_file "$gitignore_file" ".TemporaryItems"
  ensure_line_in_file "$gitignore_file" ".VolumeIcon.icns"
  ensure_line_in_file "$gitignore_file" ".com.apple.timemachine.donotpresent"

  # Editors
  ensure_line_in_file "$gitignore_file" ".idea/"
  ensure_line_in_file "$gitignore_file" "*.iml"
  ensure_line_in_file "$gitignore_file" "*.swp"
  ensure_line_in_file "$gitignore_file" "*.swo"
  ensure_line_in_file "$gitignore_file" "*~"
  ensure_line_in_file "$gitignore_file" ".vscode/"

  # Node
  ensure_line_in_file "$gitignore_file" "node_modules/"
  ensure_line_in_file "$gitignore_file" "npm-debug.log*"
  ensure_line_in_file "$gitignore_file" "yarn-error.log*"

  # Ruby/Rails
  ensure_line_in_file "$gitignore_file" ".bundle/"
  ensure_line_in_file "$gitignore_file" "vendor/bundle/"
  ensure_line_in_file "$gitignore_file" "log/"
  ensure_line_in_file "$gitignore_file" "tmp/"
  ensure_line_in_file "$gitignore_file" "coverage/"

  # Environment
  ensure_line_in_file "$gitignore_file" ".env"
  ensure_line_in_file "$gitignore_file" ".env.local"
  ensure_line_in_file "$gitignore_file" ".env.*.local"
}
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n setup-macbook.sh
```

Expected: no output, exit 0.

- [ ] **Step 3: Commit**

Note: directory is NOT a git repository. Skip this step.
