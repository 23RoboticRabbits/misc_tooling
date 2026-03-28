#!/usr/bin/env bash
# Install via curl (direct pipe):
#   curl -fsSL https://raw.githubusercontent.com/23RoboticRabbits/misc_tooling/main/setup-macbook.sh | bash
#
# Install via curl (download then run):
#   curl -fsSL https://raw.githubusercontent.com/23RoboticRabbits/misc_tooling/main/setup-macbook.sh -o setup-macbook.sh && bash setup-macbook.sh

set -euo pipefail

WARNINGS=()

log() {
  printf '[setup] %s\n' "$1"
}

warn() {
  printf '[setup][warn] %s\n' "$1" >&2
  WARNINGS+=("$1")
}

die() {
  printf '[setup][error] %s\n' "$1" >&2
  exit 1
}

ensure_sudo_session() {
  log "Requesting administrator access up front so privileged installs can run without additional prompts"
  sudo -v || die "Administrator access is required to continue"
}

append_block_if_missing() {
  local file="$1"
  local marker="$2"
  local block="$3"

  touch "$file"
  if grep -Fq "$marker" "$file" 2>/dev/null; then
    return 0
  fi

  {
    printf '\n%s\n' "$block"
  } >>"$file" || warn "Failed to append block to ${file}"
}

ensure_line_in_file() {
  local file="$1"
  local line="$2"

  touch "$file"
  if grep -Fqx "$line" "$file" 2>/dev/null; then
    return 0
  fi

  printf '%s\n' "$line" >>"$file" || warn "Failed to append line to ${file}"
}

ensure_symlink() {
  local target="$1"
  local link_path="$2"

  mkdir -p "$(dirname "$link_path")"

  if [ -L "$link_path" ] && [ "$(readlink "$link_path")" = "$target" ]; then
    return 0
  fi

  if [ -L "$link_path" ] || [ -e "$link_path" ]; then
    rm -f "$link_path" || return 1
  fi

  ln -s "$target" "$link_path" || return 1
}

json_merge_superpowers_claude_state() {
  local settings_file="$1"
  local known_marketplaces_file="$2"
  local installed_plugins_file="$3"
  local install_path="$4"
  local plugin_version="$5"

  /usr/bin/ruby <<'RUBY' "$settings_file" "$known_marketplaces_file" "$installed_plugins_file" "$install_path" "$plugin_version"
require "json"
require "fileutils"
require "time"

settings_file, known_marketplaces_file, installed_plugins_file, install_path, plugin_version = ARGV
plugin_id = "superpowers@superpowers-marketplace"
marketplace_id = "superpowers-marketplace"

def load_json(path, fallback)
  return fallback unless File.exist?(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError
  fallback
end

FileUtils.mkdir_p(File.dirname(settings_file))
settings = load_json(settings_file, {})
settings["extraKnownMarketplaces"] ||= {}
settings["extraKnownMarketplaces"][marketplace_id] ||= {
  "source" => {
    "source" => "github",
    "repo" => "obra/superpowers-marketplace"
  }
}
settings["enabledPlugins"] ||= {}
settings["enabledPlugins"][plugin_id] = true
File.write(settings_file, JSON.pretty_generate(settings) + "\n")

FileUtils.mkdir_p(File.dirname(known_marketplaces_file))
known_marketplaces = load_json(known_marketplaces_file, {})
known_marketplaces[marketplace_id] ||= {}
known_marketplaces[marketplace_id]["source"] = {
  "source" => "github",
  "repo" => "obra/superpowers-marketplace"
}
known_marketplaces[marketplace_id]["installLocation"] = File.expand_path(File.join(File.dirname(known_marketplaces_file), "marketplaces", marketplace_id))
known_marketplaces[marketplace_id]["lastUpdated"] = Time.now.utc.iso8601
File.write(known_marketplaces_file, JSON.pretty_generate(known_marketplaces) + "\n")

FileUtils.mkdir_p(File.dirname(installed_plugins_file))
installed_plugins = load_json(installed_plugins_file, { "version" => 2, "plugins" => {} })
installed_plugins["version"] ||= 2
installed_plugins["plugins"] ||= {}
installed_plugins["plugins"][plugin_id] = [
  {
    "scope" => "user",
    "installPath" => install_path,
    "version" => plugin_version,
    "installedAt" => Time.now.utc.iso8601,
    "lastUpdated" => Time.now.utc.iso8601
  }
]
File.write(installed_plugins_file, JSON.pretty_generate(installed_plugins) + "\n")
RUBY
}

install_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already installed"
    return 0
  fi

  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Failed to install Homebrew"
}

load_homebrew_env() {
  if command -v brew >/dev/null 2>&1; then
    eval "$(brew shellenv)"
    return 0
  fi

  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return 0
  fi

  if [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
    return 0
  fi

  die "brew was not found after installation"
}

ensure_zsh_homebrew_config() {
  local zprofile_block
  local zshrc_block

  zprofile_block=$(cat <<'EOF'
# >>> macbook-bootstrap: homebrew shellenv >>>
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
# <<< macbook-bootstrap: homebrew shellenv <<<
EOF
)

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: homebrew completions >>>
if command -v brew >/dev/null 2>&1; then
  FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
fi
autoload -Uz compinit
if [ -n "${ZDOTDIR:-}" ]; then
  compinit -d "${ZDOTDIR}/.zcompdump"
else
  compinit -d "${HOME}/.zcompdump"
fi
# <<< macbook-bootstrap: homebrew completions <<<
EOF
)

  append_block_if_missing "${HOME}/.zprofile" "# >>> macbook-bootstrap: homebrew shellenv >>>" "$zprofile_block"
  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: homebrew completions >>>" "$zshrc_block"
}

ensure_zsh_rbenv_config() {
  local zshrc_block

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: rbenv >>>
export RBENV_ROOT="${HOME}/.rbenv"
if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init - zsh)"
fi
# <<< macbook-bootstrap: rbenv <<<
EOF
)

  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: rbenv >>>" "$zshrc_block"
}

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

ensure_zsh_fzf_config() {
  local fzf_install
  local zshrc_block

  local fzf_prefix
  fzf_prefix="$(brew --prefix 2>/dev/null)"
  fzf_install="${fzf_prefix}/opt/fzf/install"
  if [ -f "$fzf_install" ] && [ ! -f "${HOME}/.fzf.zsh" ]; then
    "$fzf_install" --all --no-update-rc >/dev/null 2>&1 || warn "Failed to run fzf shell integration installer"
  fi

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: fzf >>>
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# <<< macbook-bootstrap: fzf <<<
EOF
)

  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: fzf >>>" "$zshrc_block"
}

ensure_zsh_aliases_config() {
  local zshrc_block

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: aliases >>>
[ -f ~/.zsh_aliases ] && source ~/.zsh_aliases
# <<< macbook-bootstrap: aliases <<<
EOF
)

  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: aliases >>>" "$zshrc_block"
}

ensure_zsh_zoxide_config() {
  local zshrc_block

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: zoxide >>>
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
# <<< macbook-bootstrap: zoxide <<<
EOF
)

  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: zoxide >>>" "$zshrc_block"
}

ensure_zsh_ls_color_config() {
  local zshrc_block

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: ls colors >>>
# Enable color output for macOS BSD ls
export CLICOLOR=1
# LSCOLORS: each pair = foreground/background for a file type (macOS format)
# Uppercase = bold; x = terminal default
# Order: dir, symlink, socket, pipe, executable, block-special,
#        char-special, setuid-exec, setgid-exec, sticky-other-writable,
#        other-writable
export LSCOLORS=ExGxBxDxCxegedabagaced
# <<< macbook-bootstrap: ls colors <<<
EOF
)

  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: ls colors >>>" "$zshrc_block"
}

ensure_zsh_editor_config() {
  local zshrc_block

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: editor >>>
export EDITOR='subl --wait'
export VISUAL='subl --wait'
# <<< macbook-bootstrap: editor <<<
EOF
)

  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: editor >>>" "$zshrc_block"
}

ensure_zsh_op_completion_config() {
  local zshrc_block

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: 1password-cli completion >>>
if command -v op >/dev/null 2>&1; then
  eval "$(op completion zsh)"
  compdef _op op
fi
# <<< macbook-bootstrap: 1password-cli completion <<<
EOF
)

  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: 1password-cli completion >>>" "$zshrc_block"
}

ensure_zsh_ssh_config() {
  local zshrc_block

  zshrc_block=$(cat <<'EOF'
# >>> macbook-bootstrap: ssh >>>
export SSH_AUTH_SOCK="${HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
# <<< macbook-bootstrap: ssh <<<
EOF
)

  append_block_if_missing "${HOME}/.zshrc" "# >>> macbook-bootstrap: ssh >>>" "$zshrc_block"
}

brew_install_formula() {
  local token="$1"

  if brew list --formula "$token" >/dev/null 2>&1; then
    log "Formula already installed: $token"
    return 0
  fi

  log "Installing formula: $token"
  brew install "$token" >/dev/null 2>&1 || return 1
}

brew_install_cask() {
  local token="$1"

  if brew list --cask "$token" >/dev/null 2>&1; then
    log "Cask already installed: $token"
    return 0
  fi

  log "Installing cask: $token"
  brew install --cask "$token" >/dev/null 2>&1 || return 1
}

install_with_fallback() {
  local label="$1"
  shift

  local candidate type token
  for candidate in "$@"; do
    type="${candidate%%:*}"
    token="${candidate#*:}"

    if [ "$type" = "formula" ]; then
      if brew_install_formula "$token"; then
        return 0
      fi
    elif [ "$type" = "cask" ]; then
      if brew_install_cask "$token"; then
        return 0
      fi
    fi
  done

  warn "Unable to install ${label}; tried: $*"
}

install_requested_packages() {
  install_with_fallback "aider" "formula:aider"
  install_with_fallback "awscli" "formula:awscli"
  install_with_fallback "bat" "formula:bat"
  install_with_fallback "dockutil" "formula:dockutil"
  install_with_fallback "duti" "formula:duti"
  install_with_fallback "fzf" "formula:fzf"
  install_with_fallback "gh" "formula:gh"
  install_with_fallback "git" "formula:git"
  install_with_fallback "node" "formula:node"
  install_with_fallback "python" "formula:python"
  install_with_fallback "rbenv" "formula:rbenv"
  install_with_fallback "starship" "formula:starship"
  install_with_fallback "zsh-autosuggestions" "formula:zsh-autosuggestions"
  install_with_fallback "zsh-syntax-highlighting" "formula:zsh-syntax-highlighting"
  install_with_fallback "zoxide" "formula:zoxide"
  install_with_fallback "claude" "cask:claude"
  install_with_fallback "claude-code" "cask:claude-code"
  install_with_fallback "codex" "cask:codex"
  install_with_fallback "cursor" "cask:cursor"
  install_with_fallback "caffeine" "cask:caffeine"
  install_with_fallback "google-chrome" "cask:google-chrome"
  install_with_fallback "google-drive" "cask:google-drive"
  install_with_fallback "iterm2" "cask:iterm2"
  install_with_fallback "obsidian" "cask:obsidian"
  install_with_fallback "sublime-merge" "cask:sublime-merge"
  install_with_fallback "sublime-text" "cask:sublime-text"
  install_with_fallback "visual-studio-code" "cask:visual-studio-code"
  install_with_fallback "chatgpt" "cask:chatgpt"
  install_with_fallback "1password" "cask:1password"
  install_with_fallback "1password-cli" "cask:1password-cli"
}

collect_cask_matches() {
  local regex="$1"
  local fallback_csv="$2"
  local results=""
  local line

  while IFS= read -r line; do
    case "$line" in
      font-*)
        if [ -z "$results" ]; then
          results="$line"
        else
          results="${results},${line}"
        fi
        ;;
    esac
  done <<EOF
$(brew search --casks "/${regex}/" 2>/dev/null)
EOF

  if [ -n "$results" ]; then
    printf '%s\n' "$results"
  else
    printf '%s\n' "$fallback_csv"
  fi
}

install_csv_casks() {
  local csv="$1"
  local label="$2"
  local old_ifs="$IFS"
  local token

  IFS=','
  for token in $csv; do
    install_with_fallback "$label ($token)" "cask:$token"
  done
  IFS="$old_ifs"
}

install_requested_fonts() {
  local fira_fonts
  local ia_fonts
  local jetbrains_fonts

  fira_fonts=$(collect_cask_matches "^font-fira-(code|mono)" "font-fira-code,font-fira-mono")
  ia_fonts=$(collect_cask_matches "^font-ia-writer" "font-ia-writer-duo,font-ia-writer-mono,font-ia-writer-quattro")
  jetbrains_fonts=$(collect_cask_matches "^font-jetbrains-mono-nerd" "font-jetbrains-mono-nerd-font")

  install_csv_casks "$fira_fonts" "font-fira*"
  install_csv_casks "$ia_fonts" "font-ia*"
  install_csv_casks "$jetbrains_fonts" "font-jetbrains-mono-nerd*"
}

configure_ssh() {
  local ssh_dir="${HOME}/.ssh"
  local ssh_config="${ssh_dir}/config"

  log "Configuring SSH"

  mkdir -p "$ssh_dir" || { warn "Failed to create ${ssh_dir}"; return 0; }
  chmod 700 "$ssh_dir" || warn "Failed to set permissions on ${ssh_dir}"

  touch "$ssh_config" || { warn "Failed to create ${ssh_config}"; return 0; }
  chmod 600 "$ssh_config" || warn "Failed to set permissions on ${ssh_config}"

  append_block_if_missing "$ssh_config" "# >>> macbook-bootstrap: 1password ssh agent >>>" \
"# >>> macbook-bootstrap: 1password ssh agent >>>
Host *
  IdentityAgent \"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"
# <<< macbook-bootstrap: 1password ssh agent <<<"
}

configure_git() {
  local gitignore_file="${HOME}/.gitignore_global"

  log "Configuring Git"
  git config --global user.name "Mike Roth" || warn "Unable to set git user.name"
  git config --global user.email "mike.roth@swtchenergy.com" || warn "Unable to set git user.email"
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

  # Environment
  ensure_line_in_file "$gitignore_file" ".env"
  ensure_line_in_file "$gitignore_file" ".env.local"
  ensure_line_in_file "$gitignore_file" ".env.*.local"
}

configure_sublime_defaults() {
  local bundle_id="com.sublimetext.4"
  local ext
  local extensions="txt text md markdown mdown mkd yml yaml rb rake gemspec ru py pyw pyi"

  if ! command -v duti >/dev/null 2>&1; then
    warn "duti is not installed; skipping default app configuration"
    return 0
  fi

  log "Setting Sublime Text as the default app for requested file types"
  duti -s "$bundle_id" public.plain-text all >/dev/null 2>&1 || warn "Unable to set Sublime Text for public.plain-text"
  duti -s "$bundle_id" net.daringfireball.markdown all >/dev/null 2>&1 || warn "Unable to set Sublime Text for Markdown UTI"

  for ext in $extensions; do
    duti -s "$bundle_id" ".$ext" all >/dev/null 2>&1 || warn "Unable to set Sublime Text for .$ext"
  done
}

write_vs_editor_settings() {
  local settings_file="$1"
  local settings_dir

  settings_dir="$(dirname "$settings_file")"
  mkdir -p "$settings_dir" || { warn "Failed to create ${settings_dir}"; return 0; }

  if [ -f "$settings_file" ] && [ ! -f "${settings_file}.bak.original" ]; then
    cp "$settings_file" "${settings_file}.bak.original" || warn "Failed to back up ${settings_file} to ${settings_file}.bak.original"
  fi

  cat >"$settings_file" <<'EOF' || { warn "Failed to write ${settings_file}"; return 0; }
{
  "workbench.colorTheme": "Nord",
  "editor.fontFamily": "JetBrainsMono Nerd Font, monospace",
  "editor.fontSize": 14,
  "editor.fontLigatures": true,
  "editor.formatOnSave": true,
  "editor.tabSize": 2,
  "editor.rulers": [120],
  "editor.trimAutoWhitespace": true,
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "[ruby]": {
    "editor.defaultFormatter": "shopify.ruby-lsp"
  },
  "[javascript][typescript][javascriptreact][typescriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[json][jsonc]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "rubyLsp.formatter": "rubocop",
  "rubyLsp.linters": ["rubocop"],
  "rubyLsp.rubyVersionManager": {
    "identifier": "rbenv"
  },
  "eslint.validate": [
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact"
  ],
  "tailwindCSS.includeLanguages": {
    "erb": "html"
  },
  "tailwindCSS.experimental.classRegex": [
    "\\bclass:\\s*[\"']([^\"']*)[\"']"
  ]
}
EOF
}

install_vs_editor_extensions() {
  local cli="$1"
  local label="$2"
  local extensions
  local ext

  if [ -z "$cli" ]; then
    warn "Skipping ${label} extension install: CLI not found"
    return 0
  fi

  # Space-separated list — all IDs are single tokens, word-splitting is intentional
  extensions="shopify.ruby-lsp \
    dbaeumer.vscode-eslint \
    esbenp.prettier-vscode \
    dsznajder.es7-react-js-snippets \
    bradlc.vscode-tailwindcss \
    arcticicestudio.nord-visual-studio-code \
    eamodio.gitlens \
    usernamehw.errorlens \
    mikestead.dotenv \
    formulahendry.auto-rename-tag \
    christian-kohler.path-intellisense"

  local installed_extensions
  installed_extensions="$("$cli" --list-extensions 2>/dev/null)" || true

  for ext in $extensions; do
    if printf '%s\n' "$installed_extensions" | grep -Fxqi "$ext" 2>/dev/null; then
      log "${label} extension already installed: ${ext}"
      continue
    fi
    log "Installing ${label} extension: ${ext}"
    "$cli" --install-extension "$ext" >/dev/null 2>&1 || warn "Failed to install ${label} extension: ${ext}"
  done
}

configure_vscode() {
  local settings_file="${HOME}/Library/Application Support/Code/User/settings.json"
  local cli=""
  local known_cli="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"

  log "Configuring VS Code"
  write_vs_editor_settings "$settings_file"

  if command -v code >/dev/null 2>&1; then
    cli="code"
  elif [ -x "$known_cli" ]; then
    cli="$known_cli"
  fi
  install_vs_editor_extensions "$cli" "VS Code"
}

configure_cursor() {
  local settings_file="${HOME}/Library/Application Support/Cursor/User/settings.json"
  local cli=""
  local known_cli="/Applications/Cursor.app/Contents/Resources/app/bin/cursor"

  log "Configuring Cursor"
  write_vs_editor_settings "$settings_file"

  if command -v cursor >/dev/null 2>&1; then
    cli="cursor"
  elif [ -x "$known_cli" ]; then
    cli="$known_cli"
  fi
  install_vs_editor_extensions "$cli" "Cursor"
}

dock_has_item() {
  local label="$1"

  dockutil --find "$label" >/dev/null 2>&1
}

configure_dock() {
  local app_name
  local app_path
  local dock_changed=0

  if ! command -v dockutil >/dev/null 2>&1; then
    warn "dockutil is not installed; skipping Dock configuration"
    return 0
  fi

  for app_name in \
    "Google Chrome" \
    "iTerm" \
    "Claude" \
    "ChatGPT" \
    "Obsidian" \
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

    log "Adding Dock app: ${app_name}"
    dockutil --add "$app_path" --no-restart >/dev/null 2>&1 || {
      warn "Failed to add ${app_name} to the Dock"
      continue
    }
    dock_changed=1
  done

  if [ "$dock_changed" -eq 1 ]; then
    killall Dock >/dev/null 2>&1 || warn "Failed to restart Dock after updates"
  fi
}

download_file() {
  local url="$1"
  local destination="$2"

  mkdir -p "$(dirname "$destination")"
  curl -fsSL "$url" -o "$destination" || return 1
}

install_superpowers_for_codex() {
  local repo_dir="${HOME}/.codex/superpowers"
  local skills_link="${HOME}/.agents/skills/superpowers"

  log "Installing Superpowers for Codex"

  mkdir -p "${HOME}/.codex"
  if [ -d "$repo_dir/.git" ]; then
    git -C "$repo_dir" pull --ff-only >/dev/null 2>&1 || warn "Failed to update existing Superpowers repo for Codex"
  elif [ -d "$repo_dir" ]; then
    warn "Directory ${repo_dir} exists but is not a git clone; skipping Codex Superpowers clone"
  else
    git clone https://github.com/obra/superpowers.git "$repo_dir" >/dev/null 2>&1 || warn "Failed to clone Superpowers for Codex"
  fi

  if [ -d "$repo_dir/skills" ]; then
    ensure_symlink "$repo_dir/skills" "$skills_link" || warn "Failed to symlink Superpowers skills into ~/.agents/skills"
  else
    warn "Superpowers skills directory for Codex was not found at ${repo_dir}/skills"
  fi
}

install_superpowers_for_claude_code() {
  local repo_dir="${HOME}/.codex/superpowers"
  local settings_file="${HOME}/.claude/settings.json"
  local known_marketplaces_file="${HOME}/.claude/plugins/known_marketplaces.json"
  local installed_plugins_file="${HOME}/.claude/plugins/installed_plugins.json"
  local marketplaces_dir="${HOME}/.claude/plugins/marketplaces/superpowers-marketplace"
  local plugin_json="${repo_dir}/.claude-plugin/plugin.json"
  local marketplace_json="${repo_dir}/.claude-plugin/marketplace.json"
  local plugin_version
  local cache_dir

  log "Installing Superpowers for Claude Code"

  if [ ! -f "$plugin_json" ] || [ ! -f "$marketplace_json" ]; then
    warn "Superpowers Claude plugin assets were not found under ${repo_dir}; skipping Claude Code install"
    return 0
  fi

  plugin_version="$(/usr/bin/ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["version"]' "$plugin_json" 2>/dev/null)"
  if [ -z "$plugin_version" ]; then
    warn "Failed to determine Superpowers Claude plugin version"
    return 0
  fi

  cache_dir="${HOME}/.claude/plugins/cache/superpowers-marketplace/superpowers/${plugin_version}"
  mkdir -p "$marketplaces_dir" "$cache_dir"

  cp "$marketplace_json" "${marketplaces_dir}/marketplace.json" 2>/dev/null || warn "Failed to copy Superpowers Claude marketplace.json"
  cp "$plugin_json" "${cache_dir}/plugin.json" 2>/dev/null || warn "Failed to copy Superpowers Claude plugin.json"

  json_merge_superpowers_claude_state "$settings_file" "$known_marketplaces_file" "$installed_plugins_file" "$cache_dir" "$plugin_version" || warn "Failed to update Claude Code global Superpowers plugin metadata"
}

install_superpowers_plugins() {
  install_superpowers_for_codex
  install_superpowers_for_claude_code
}

latest_stable_ruby_for_major() {
  local major="$1"

  rbenv install -l 2>/dev/null \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -E "^${major}\.[0-9]+\.[0-9]+$" \
    | tail -n 1
}

ensure_ruby_build_dependencies() {
  install_with_fallback "ruby-build" "formula:ruby-build"
  install_with_fallback "openssl@3" "formula:openssl@3"
  install_with_fallback "readline" "formula:readline"
  install_with_fallback "libyaml" "formula:libyaml"
  install_with_fallback "gmp" "formula:gmp"
  install_with_fallback "autoconf" "formula:autoconf"
  install_with_fallback "pkgconf" "formula:pkgconf"
  install_with_fallback "libffi" "formula:libffi"
}

load_rbenv_env_current_shell() {
  export RBENV_ROOT="${HOME}/.rbenv"
  if command -v rbenv >/dev/null 2>&1; then
    eval "$(rbenv init - bash)"
  fi
}

install_ruby_version_with_rbenv() {
  local version="$1"
  local openssl_prefix
  local readline_prefix
  local libyaml_prefix

  if [ -z "$version" ]; then
    return 1
  fi

  if [ -d "${HOME}/.rbenv/versions/${version}" ]; then
    log "rbenv Ruby already installed: $version"
    return 0
  fi

  openssl_prefix="$(brew --prefix openssl@3 2>/dev/null)"
  readline_prefix="$(brew --prefix readline 2>/dev/null)"
  libyaml_prefix="$(brew --prefix libyaml 2>/dev/null)"

  log "Installing Ruby via rbenv: $version"
  local install_log
  install_log="$(mktemp)"
  RUBY_CONFIGURE_OPTS="--with-openssl-dir=${openssl_prefix} --with-readline-dir=${readline_prefix} --with-libyaml-dir=${libyaml_prefix}" \
    rbenv install "$version" >"$install_log" 2>&1 || true
  if [ -d "${HOME}/.rbenv/versions/${version}" ]; then
    rm -f "$install_log"
    return 0
  fi
  warn "Failed to install Ruby ${version}. rbenv output:"
  cat "$install_log" >&2
  rm -f "$install_log"
  return 1
}

configure_rbenv_rubies() {
  local ruby_3
  local ruby_4

  ensure_ruby_build_dependencies
  load_rbenv_env_current_shell

  ruby_3="$(latest_stable_ruby_for_major 3)"
  ruby_4="$(latest_stable_ruby_for_major 4)"

  if [ -z "$ruby_3" ]; then
    warn "Unable to determine the latest stable Ruby 3.x from rbenv"
  else
    install_ruby_version_with_rbenv "$ruby_3" || warn "Failed to install Ruby ${ruby_3} via rbenv"
  fi

  if [ -z "$ruby_4" ]; then
    warn "No stable Ruby 4.x version was found via rbenv; skipping Ruby 4 install and global version update"
  else
    install_ruby_version_with_rbenv "$ruby_4" || warn "Failed to install Ruby ${ruby_4} via rbenv"

    if [ -d "${HOME}/.rbenv/versions/${ruby_4}" ]; then
      log "Setting global Ruby to ${ruby_4}"
      rbenv global "$ruby_4" >/dev/null 2>&1 || warn "Failed to set rbenv global Ruby to ${ruby_4}"
      rbenv rehash >/dev/null 2>&1 || warn "Failed to rehash rbenv shims"
    fi
  fi

  # Install gems only for versions that are confirmed present on disk
  [ -n "$ruby_3" ] && [ -d "${HOME}/.rbenv/versions/${ruby_3}" ] && install_gems_for_ruby_version "$ruby_3"
  [ -n "$ruby_4" ] && [ -d "${HOME}/.rbenv/versions/${ruby_4}" ] && install_gems_for_ruby_version "$ruby_4"
}

install_gems_for_ruby_version() {
  local version="$1"
  local gems
  local gem_name

  if [ -z "$version" ]; then
    return 1
  fi

  if [ ! -d "${HOME}/.rbenv/versions/${version}" ]; then
    warn "Skipping gem installation because Ruby ${version} is not installed in rbenv"
    return 0
  fi

  gems="bundler ruby-lsp rubocop rubocop-rails rubocop-rspec rubocop-shopify rails playwright-ruby-client tailwindcss-rails"

  for gem_name in $gems; do
    if RBENV_VERSION="$version" rbenv exec gem list --exact -i "$gem_name" >/dev/null 2>&1; then
      log "Gem already installed in Ruby ${version}: ${gem_name}"
      continue
    fi
    log "Installing gem in Ruby ${version}: ${gem_name}"
    RBENV_VERSION="$version" rbenv exec gem install --no-document "$gem_name" >/dev/null 2>&1 || warn "Failed to install gem ${gem_name} in Ruby ${version}"
  done

  RBENV_VERSION="$version" rbenv rehash >/dev/null 2>&1 || warn "Failed to rehash rbenv after gem installation in Ruby ${version}"
}


configure_sublime_text() {
  local st_base="${HOME}/Library/Application Support/Sublime Text"
  local installed_packages_dir="${st_base}/Installed Packages"
  local user_dir="${st_base}/Packages/User"
  local package_control_file="${installed_packages_dir}/Package Control.sublime-package"
  local package_control_settings="${user_dir}/Package Control.sublime-settings"
  local preferences_file="${user_dir}/Preferences.sublime-settings"
  local lsp_settings_file="${user_dir}/LSP.sublime-settings"
  local sublimelinter_settings_file="${user_dir}/SublimeLinter.sublime-settings"

  log "Configuring Sublime Text packages and settings"

  mkdir -p "$installed_packages_dir" "$user_dir"

  if ! download_file "https://download.sublimetext.com/Package%20Control.sublime-package" "$package_control_file"; then
    warn "Unable to install Package Control for Sublime Text"
  fi

  if [ ! -f "$package_control_settings" ]; then
    cat >"$package_control_settings" <<'EOF' || warn "Failed to write ${package_control_settings}"
{
  "installed_packages": [
    "A File Icon",
    "AdvancedNewFile",
    "AutoFileName",
    "Better RSpec",
    "ERB Snippets",
    "GitSavvy",
    "LSP",
    "Nord",
    "Package Control",
    "Ruby on Rails snippets",
    "SideBarEnhancements",
    "SublimeLinter",
    "SublimeLinter-rubocop",
    "Terminus",
    "TrailingSpaces"
  ]
}
EOF
  fi

  if [ ! -f "$preferences_file" ]; then
    cat >"$preferences_file" <<'EOF' || warn "Failed to write ${preferences_file}"
{
  "tab_size": 2,
  "translate_tabs_to_spaces": true,
  "trim_trailing_white_space_on_save": true,
  "ensure_newline_at_eof_on_save": true,
  "rulers": [120],
  "folder_exclude_patterns": [".git", "tmp", "log", "node_modules", "vendor/bundle", "coverage"],
  "font_face": "Fira Code",
  "theme": "auto",
  "color_scheme": "Nord.sublime-color-scheme"
}
EOF
  fi

  if [ ! -f "$lsp_settings_file" ]; then
    cat >"$lsp_settings_file" <<'EOF' || warn "Failed to write ${lsp_settings_file}"
{
  // Global LSP behavior
  "show_diagnostics_panel_on_save": 0,
  "diagnostics_highlight_style": "underline",
  "diagnostics_gutter_marker": "dot",
  "show_code_actions": "annotation",
  "show_inlay_hints": true,
  "auto_show_diagnostics_panel": "never",
  "lsp_format_on_save": true,

  "clients": {
    "ruby-lsp": {
      "enabled": true,
      "command": ["ruby-lsp"],
      "selector": "source.ruby | text.html.ruby | text.html.erb",
      "initializationOptions": {
        "enabledFeatures": {
          "codeActions": true,
          "codeLens": true,
          "completion": true,
          "definition": true,
          "diagnostics": true,
          "documentHighlights": true,
          "documentLink": true,
          "documentSymbols": true,
          "foldingRanges": true,
          "formatting": true,
          "hover": true,
          "inlayHint": true,
          "onTypeFormatting": true,
          "references": true,
          "rename": true,
          "selectionRanges": true,
          "semanticHighlighting": true,
          "signatureHelp": true,
          "typeHierarchy": true,
          "workspaceSymbol": true
        },
        "formatter": "rubocop",
        "linters": ["rubocop"],
        "rubyVersionManager": "rbenv"
      }
    }
  }
}
EOF
  fi

  if [ ! -f "$sublimelinter_settings_file" ]; then
    cat >"$sublimelinter_settings_file" <<'EOF' || warn "Failed to write ${sublimelinter_settings_file}"
{
  "paths": {
    "osx": ["~/.rbenv/shims", "~/.rbenv/bin"]
  },
  "linters": {
    "rubocop": {
      "executable": "rubocop"
    }
  }
}
EOF
  fi
}

install_obsidian_plugin() {
  local plugin_id="$1"
  local github_owner="$2"
  local github_repo="$3"
  local plugins_dir="$4"
  local install_dir="${plugins_dir}/${plugin_id}"

  mkdir -p "$install_dir"

  if [ -f "${install_dir}/main.js" ] && [ -f "${install_dir}/manifest.json" ]; then
    log "Obsidian plugin already installed: ${plugin_id}"
    return 0
  fi

  log "Installing Obsidian plugin: ${plugin_id}"
  local base_url="https://github.com/${github_owner}/${github_repo}/releases/latest/download"

  if ! download_file "${base_url}/manifest.json" "${install_dir}/manifest.json"; then
    warn "Failed to download manifest for Obsidian plugin: ${plugin_id}"
    return 1
  fi

  if ! download_file "${base_url}/main.js" "${install_dir}/main.js"; then
    warn "Failed to download main.js for Obsidian plugin: ${plugin_id}"
    return 1
  fi

  # styles.css is optional for some plugins
  download_file "${base_url}/styles.css" "${install_dir}/styles.css" >/dev/null 2>&1 || true
}

configure_obsidian() {
  local vault_dir="${HOME}/Documents/Obsidian"
  local obsidian_dir="${vault_dir}/.obsidian"
  local plugins_dir="${obsidian_dir}/plugins"
  local themes_dir="${obsidian_dir}/themes/Minimal"
  local snippets_dir="${obsidian_dir}/snippets"
  local templates_dir="${vault_dir}/Templates"

  log "Configuring Obsidian vault at ${vault_dir}"

  mkdir -p \
    "${vault_dir}/00 - Home" \
    "${vault_dir}/10 - Daily Notes" \
    "${vault_dir}/20 - Projects" \
    "${vault_dir}/30 - Teams & People" \
    "${vault_dir}/40 - Meetings" \
    "${vault_dir}/50 - Research" \
    "${vault_dir}/60 - Resources/Attachments" \
    "$templates_dir" \
    "$plugins_dir" \
    "$themes_dir" \
    "$snippets_dir" || { warn "Failed to create Obsidian vault structure"; return 0; }

  # Download Minimal theme
  local minimal_base="https://github.com/kepano/obsidian-minimal/releases/latest/download"
  if [ ! -f "${themes_dir}/theme.css" ]; then
    download_file "${minimal_base}/theme.css" "${themes_dir}/theme.css" || warn "Failed to download Minimal theme CSS"
  fi
  if [ ! -f "${themes_dir}/manifest.json" ]; then
    download_file "${minimal_base}/manifest.json" "${themes_dir}/manifest.json" || warn "Failed to download Minimal theme manifest"
  fi

  # Install community plugins
  install_obsidian_plugin "dataview"                  "blacksmithgu"         "obsidian-dataview"         "$plugins_dir" || true
  install_obsidian_plugin "templater-obsidian"        "SilentVoid13"         "Templater"                 "$plugins_dir" || true
  install_obsidian_plugin "calendar"                  "liamcain"             "obsidian-calendar-plugin"  "$plugins_dir" || true
  install_obsidian_plugin "periodic-notes"            "liamcain"             "obsidian-periodic-notes"   "$plugins_dir" || true
  install_obsidian_plugin "obsidian-tasks-plugin"     "obsidian-tasks-group" "obsidian-tasks"            "$plugins_dir" || true
  install_obsidian_plugin "obsidian-kanban"           "mgmeyers"             "obsidian-kanban"           "$plugins_dir" || true
  install_obsidian_plugin "obsidian-minimal-settings" "kepano"               "obsidian-minimal-settings" "$plugins_dir" || true
  install_obsidian_plugin "obsidian-style-settings"   "mgmeyers"             "obsidian-style-settings"   "$plugins_dir" || true

  # Enabled plugins list (written only once; user can extend via UI)
  if [ ! -f "${obsidian_dir}/community-plugins.json" ]; then
    cat >"${obsidian_dir}/community-plugins.json" <<'EOF' || warn "Failed to write Obsidian community-plugins.json"
[
  "dataview",
  "templater-obsidian",
  "calendar",
  "periodic-notes",
  "obsidian-tasks-plugin",
  "obsidian-kanban",
  "obsidian-minimal-settings",
  "obsidian-style-settings"
]
EOF
  fi

  # Theme and font appearance
  if [ ! -f "${obsidian_dir}/appearance.json" ]; then
    cat >"${obsidian_dir}/appearance.json" <<'EOF' || warn "Failed to write Obsidian appearance.json"
{
  "baseTheme": "dark",
  "cssTheme": "Minimal",
  "accentColor": "#81A1C1",
  "textFontFamily": "iA Writer Quattro S",
  "interfaceFontFamily": "iA Writer Quattro S",
  "monospaceFontFamily": "iA Writer Mono S",
  "baseFontSize": 16,
  "enabledCssSnippets": ["nord"]
}
EOF
  fi

  # Nord colour palette CSS snippet
  if [ ! -f "${snippets_dir}/nord.css" ]; then
    cat >"${snippets_dir}/nord.css" <<'EOF' || warn "Failed to write Obsidian Nord CSS snippet"
/* Nord colour palette for Obsidian Minimal theme */
.theme-dark {
  --color-base-00: #2e3440;
  --color-base-10: #3b4252;
  --color-base-20: #434c5e;
  --color-base-25: #4c566a;
  --color-base-30: #4c566a;
  --color-base-35: #58647b;
  --color-base-40: #7b88a8;
  --color-base-50: #9eafcc;
  --color-base-60: #b0bad0;
  --color-base-70: #c8d0e0;
  --color-base-100: #eceff4;

  --interactive-accent: #81a1c1;
  --interactive-accent-rgb: 129, 161, 193;
  --interactive-accent-hover: #88c0d0;

  --background-primary: #2e3440;
  --background-primary-alt: #3b4252;
  --background-secondary: #3b4252;
  --background-secondary-alt: #434c5e;
  --background-modifier-border: #4c566a;

  --text-normal: #d8dee9;
  --text-muted: #9eafcc;
  --text-faint: #7b88a8;
  --text-accent: #81a1c1;
  --text-accent-hover: #88c0d0;

  --color-red: #bf616a;
  --color-orange: #d08770;
  --color-yellow: #ebcb8b;
  --color-green: #a3be8c;
  --color-cyan: #88c0d0;
  --color-blue: #81a1c1;
  --color-purple: #b48ead;
}
EOF
  fi

  # Core app settings
  if [ ! -f "${obsidian_dir}/app.json" ]; then
    cat >"${obsidian_dir}/app.json" <<'EOF' || warn "Failed to write Obsidian app.json"
{
  "legacyEditor": false,
  "livePreview": true,
  "defaultViewMode": "source",
  "vimMode": false,
  "showLineNumber": false,
  "readableLineLength": true,
  "strictLineBreaks": false,
  "showFrontmatter": false,
  "spellcheck": true,
  "spellcheckLanguages": ["en"],
  "promptDelete": false,
  "trashOption": "system",
  "attachmentFolderPath": "60 - Resources/Attachments",
  "newLinkFormat": "shortest",
  "useMarkdownLinks": false
}
EOF
  fi

  # Core plugins
  if [ ! -f "${obsidian_dir}/core-plugins.json" ]; then
    cat >"${obsidian_dir}/core-plugins.json" <<'EOF' || warn "Failed to write Obsidian core-plugins.json"
[
  "file-explorer",
  "global-search",
  "switcher",
  "graph",
  "backlink",
  "canvas",
  "outgoing-link",
  "tag-pane",
  "properties",
  "page-preview",
  "daily-notes",
  "templates",
  "note-composer",
  "command-palette",
  "word-count",
  "outline",
  "workspaces"
]
EOF
  fi

  # Daily notes core plugin config
  if [ ! -f "${obsidian_dir}/daily-notes.json" ]; then
    cat >"${obsidian_dir}/daily-notes.json" <<'EOF' || warn "Failed to write Obsidian daily-notes.json"
{
  "folder": "10 - Daily Notes",
  "template": "Templates/Daily Note",
  "autorun": false,
  "format": "YYYY-MM-DD"
}
EOF
  fi

  # Templater plugin config
  if [ ! -f "${plugins_dir}/templater-obsidian/data.json" ]; then
    cat >"${plugins_dir}/templater-obsidian/data.json" <<'EOF' || warn "Failed to write Templater plugin config"
{
  "template_folder": "Templates",
  "auto_jump_to_cursor": true,
  "trigger_on_file_creation": false,
  "enable_system_commands": false
}
EOF
  fi

  # Dashboard note
  if [ ! -f "${vault_dir}/00 - Home/Dashboard.md" ]; then
    cat >"${vault_dir}/00 - Home/Dashboard.md" <<'EOF' || warn "Failed to write Obsidian dashboard note"
# Dashboard

> Director of Engineering · SWTCH Energy

## Quick Navigation

- [[10 - Daily Notes/|Daily Notes]]
- [[20 - Projects/|Projects]]
- [[30 - Teams & People/|Team]]
- [[40 - Meetings/|Meetings]]
- [[50 - Research/|Research]]
- [[60 - Resources/|Resources]]

## Active Projects

```dataview
TABLE status, priority FROM "20 - Projects"
WHERE status != "Complete"
SORT priority ASC
```

## Recent Meetings

```dataview
LIST FROM "40 - Meetings"
SORT file.mtime DESC
LIMIT 5
```

## Open Tasks

```tasks
not done
limit 10
```
EOF
  fi

  # Templates
  if [ ! -f "${templates_dir}/Daily Note.md" ]; then
    cat >"${templates_dir}/Daily Note.md" <<'EOF' || warn "Failed to write Daily Note template"
# <% tp.date.now("YYYY-MM-DD, dddd") %>

## Focus

-

## Meetings

-

## Notes

## Tomorrow

-
EOF
  fi

  if [ ! -f "${templates_dir}/Meeting Note.md" ]; then
    cat >"${templates_dir}/Meeting Note.md" <<'EOF' || warn "Failed to write Meeting Note template"
---
date: <% tp.date.now("YYYY-MM-DD") %>
attendees:
type: meeting
---

# <% tp.file.title %>

**Date:** <% tp.date.now("YYYY-MM-DD") %>
**Attendees:**

## Agenda

-

## Notes

## Actions

- [ ]

## Decisions

EOF
  fi

  if [ ! -f "${templates_dir}/Project Brief.md" ]; then
    cat >"${templates_dir}/Project Brief.md" <<'EOF' || warn "Failed to write Project Brief template"
---
date: <% tp.date.now("YYYY-MM-DD") %>
status: Active
priority: Medium
owner:
---

# <% tp.file.title %>

## Overview

## Goals & Success Criteria

## Scope

### In Scope

### Out of Scope

## Stakeholders

## Timeline

## Risks

## Notes
EOF
  fi

  if [ ! -f "${templates_dir}/1-1 Note.md" ]; then
    cat >"${templates_dir}/1-1 Note.md" <<'EOF' || warn "Failed to write 1-1 Note template"
---
date: <% tp.date.now("YYYY-MM-DD") %>
person:
type: 1-1
---

# 1:1 — <% tp.file.title %>

**Date:** <% tp.date.now("YYYY-MM-DD") %>

## Their Updates

## Blockers & Concerns

## Feedback

## My Updates

## Action Items

- [ ]
EOF
  fi

  if [ ! -f "${templates_dir}/Research Note.md" ]; then
    cat >"${templates_dir}/Research Note.md" <<'EOF' || warn "Failed to write Research Note template"
---
date: <% tp.date.now("YYYY-MM-DD") %>
tags: research
topic:
---

# <% tp.file.title %>

## Summary

## Key Findings

## Source(s)

## Related Notes

## My Take
EOF
  fi
}

configure_iterm2() {
  local guid="0F1F07B1-1D4B-4F1C-8C0F-46A9D81EAA01"
  local profile_dir="${HOME}/Library/Application Support/iTerm2/DynamicProfiles"
  local preset_dir="${HOME}/Library/Application Support/iTerm2/ColorPresets"
  local profile_file="${profile_dir}/Nord.json"
  local preset_file="${preset_dir}/Nord.itermcolors"

  log "Configuring iTerm2 with JetBrains Mono Nerd Font and Nord"

  mkdir -p "$profile_dir" "$preset_dir"

  if ! download_file "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/schemes/Nord.itermcolors" "$preset_file"; then
    warn "Unable to download Nord.itermcolors"
  fi

  # Unquoted heredoc: intentional — expands ${guid}; no other $ references in content
  cat >"$profile_file" <<EOF || warn "Failed to write ${profile_file}"
{
  "Profiles": [
    {
      "Guid": "${guid}",
      "Name": "Nord",
      "Normal Font": "JetBrainsMonoNerdFont-Regular 14",
      "Use Non-ASCII Font": false,
      "Background Color": { "Red Component": 0.18039216101169586, "Green Component": 0.20392157137393951, "Blue Component": 0.25098040699958801, "Alpha Component": 1, "Color Space": "sRGB" },
      "Foreground Color": { "Red Component": 0.84705883264541626, "Green Component": 0.87058824300765991, "Blue Component": 0.91372549533843994, "Alpha Component": 1, "Color Space": "sRGB" },
      "Bold Color": { "Red Component": 0.99999600648880005, "Green Component": 1, "Blue Component": 1, "Alpha Component": 1, "Color Space": "sRGB" },
      "Cursor Color": { "Red Component": 0.92549020051956177, "Green Component": 0.93725490570068359, "Blue Component": 0.95686274766921997, "Alpha Component": 1, "Color Space": "sRGB" },
      "Cursor Text Color": { "Red Component": 0.15686273574829102, "Green Component": 0.15686270594596863, "Blue Component": 0.15686270594596863, "Alpha Component": 1, "Color Space": "sRGB" },
      "Selection Color": { "Red Component": 0.92549020051956177, "Green Component": 0.93725490570068359, "Blue Component": 0.95686274766921997, "Alpha Component": 1, "Color Space": "sRGB" },
      "Selected Text Color": { "Red Component": 0.29803922772407532, "Green Component": 0.33725491166114807, "Blue Component": 0.41568627953529358, "Alpha Component": 1, "Color Space": "sRGB" },
      "Link Color": { "Red Component": 0.99607843160629272, "Green Component": 1, "Blue Component": 1, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 0 Color": { "Red Component": 0.23137255012989044, "Green Component": 0.25882354378700256, "Blue Component": 0.32156863808631897, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 1 Color": { "Red Component": 0.74901962280273438, "Green Component": 0.3803921639919281, "Blue Component": 0.41568627953529358, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 2 Color": { "Red Component": 0.63921570777893066, "Green Component": 0.7450980544090271, "Blue Component": 0.54901963472366333, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 3 Color": { "Red Component": 0.92156863212585449, "Green Component": 0.79607844352722168, "Blue Component": 0.54509806632995605, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 4 Color": { "Red Component": 0.5058823823928833, "Green Component": 0.63137257099151611, "Blue Component": 0.75686275959014893, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 5 Color": { "Red Component": 0.70588237047195435, "Green Component": 0.55686277151107788, "Blue Component": 0.67843139171600342, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 6 Color": { "Red Component": 0.53333336114883423, "Green Component": 0.75294119119644165, "Blue Component": 0.81568628549575806, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 7 Color": { "Red Component": 0.89803922176361084, "Green Component": 0.91372549533843994, "Blue Component": 0.94117647409439087, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 8 Color": { "Red Component": 0.29803922772407532, "Green Component": 0.33725491166114807, "Blue Component": 0.41568627953529358, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 9 Color": { "Red Component": 0.74901962280273438, "Green Component": 0.3803921639919281, "Blue Component": 0.41568627953529358, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 10 Color": { "Red Component": 0.63921570777893066, "Green Component": 0.7450980544090271, "Blue Component": 0.54901963472366333, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 11 Color": { "Red Component": 0.92156863212585449, "Green Component": 0.79607844352722168, "Blue Component": 0.54509806632995605, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 12 Color": { "Red Component": 0.5058823823928833, "Green Component": 0.63137257099151611, "Blue Component": 0.75686275959014893, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 13 Color": { "Red Component": 0.70588237047195435, "Green Component": 0.55686277151107788, "Blue Component": 0.67843139171600342, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 14 Color": { "Red Component": 0.56078433990478516, "Green Component": 0.73725491762161255, "Blue Component": 0.73333334922790527, "Alpha Component": 1, "Color Space": "sRGB" },
      "Ansi 15 Color": { "Red Component": 0.92549020051956177, "Green Component": 0.93725490570068359, "Blue Component": 0.95686274766921997, "Alpha Component": 1, "Color Space": "sRGB" }
    }
  ]
}
EOF

  defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$guid" >/dev/null 2>&1 || warn "Unable to set iTerm2 default bookmark GUID"
  defaults write com.googlecode.iterm2 "NoSyncDefaultBookmarkGuid" -string "$guid" >/dev/null 2>&1 || warn "Unable to set iTerm2 no-sync default bookmark GUID"
}

configure_starship() {
  local config_file="${HOME}/.config/starship.toml"

  log "Configuring starship"

  if [ -f "$config_file" ] && [ ! -f "${config_file}.bak.original" ]; then
    cp "$config_file" "${config_file}.bak.original" || warn "Failed to back up existing starship.toml to ${config_file}.bak.original"
  fi

  mkdir -p "${HOME}/.config"

  cat >"$config_file" <<'EOF' || { warn "Failed to write ${config_file}"; return 0; }
format = """
$directory$git_branch$git_state$git_status$ruby$nodejs$fill$cmd_duration$status$time
$character"""

[fill]
symbol = " "

[directory]
style = "bold cyan"
truncation_length = 3
truncate_to_repo = true

[git_branch]
symbol = " "
style = "bold yellow"
format = "[$symbol$branch(:$remote_branch)]($style) "

[git_state]
format = '[\($state( $progress_current/$progress_total)\)]($style) '
style = "bold yellow"

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
symbol = " "
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

configure_zsh_aliases() {
  local aliases_file="${HOME}/.zsh_aliases"

  log "Writing ${aliases_file}"
  cat >"$aliases_file" <<'EOF' || { warn "Failed to write ${aliases_file}"; return 0; }
# ============================================================================
# ~/.zsh_aliases
# Engineering Director aliases — Ruby/Rails shop
# Managed by setup-macbook.sh — do not edit by hand.
# ============================================================================


# ── Git ──────────────────────────────────────────────────────────────────────

alias g='git'
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -v'
alias gcm='git commit -m'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull --rebase'
alias gl='git log --oneline --graph --decorate -20'
alias gla='git log --oneline --graph --decorate --all'
alias gd='git diff'
alias gds='git diff --staged'
alias grb='git rebase'
alias grbi='git rebase -i'
alias gst='git stash'
alias gstp='git stash pop'
alias gclean='git clean -fd'
alias gbD='git branch -D'

# Delete local branches whose remote tracking branch is gone
alias gprune='git remote prune origin && git branch -vv | grep "gone]" | awk '"'"'{print $1}'"'"' | xargs git branch -D'


# ── Rails ────────────────────────────────────────────────────────────────────

alias r='rails'
alias rs='rails server'
alias rc='rails console'
alias rcs='rails console --sandbox'
alias rg='rails generate'
alias rd='rails destroy'
alias rr='rails routes'
alias rrg='rails routes | grep'
alias rdb='rails db:migrate'
alias rdbs='rails db:migrate:status'
alias rdbr='rails db:rollback'
alias rdbc='rails db:create'
alias rdbp='rails db:seed'
alias rdbrl='rails db:schema:load'
alias rtest='rails test'
alias rspec='bundle exec rspec'
alias rspecf='bundle exec rspec --fail-fast'
alias rspecl='bundle exec rspec --format documentation'


# ── Bundler ───────────────────────────────────────────────────────────────────

alias be='bundle exec'
alias bi='bundle install'
alias bu='bundle update'
alias bui='bundle update && bundle install'


# ── Directory navigation ──────────────────────────────────────────────────────

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'
alias proj='cd ~/projects'


# ── Process and port inspection ───────────────────────────────────────────────

alias psg='ps aux | grep'
alias port='lsof -i'
alias fport='lsof -ti'

# Usage: killport 3000
killport() { lsof -ti ":$1" | xargs kill -9; }


# ── Docker ────────────────────────────────────────────────────────────────────

alias dk='docker'
alias dkc='docker compose'
alias dkcu='docker compose up -d'
alias dkcd='docker compose down'
alias dkcs='docker compose ps'
alias dklog='docker compose logs -f'


# ── General quality of life ───────────────────────────────────────────────────

alias ll='ls -lAh'
alias la='ls -A'
alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
alias grep='grep --color=auto'
alias reload='source ~/.zshrc'
alias zshrc='$EDITOR ~/.zshrc'
alias starshiprc='$EDITOR ~/.config/starship.toml'
alias hosts='sudo $EDITOR /etc/hosts'
alias pubkey='cat ~/.ssh/id_ed25519.pub | pbcopy && echo "Public key copied to clipboard"'

# bat: syntax-highlighted cat (requires: brew install bat)
if command -v bat &>/dev/null; then
  alias cat='bat'
fi


# ── Functions ─────────────────────────────────────────────────────────────────

# Make a directory and cd into it
mkcd() { mkdir -p "$1" && cd "$1"; }

# Tail Rails logs — defaults to development, pass staging/production/test etc.
# Usage: railslog          (development)
#        railslog test
railslog() { tail -f "log/${1:-development}.log"; }

# Open the GitHub page for the current repo in your browser
ghopen() {
  local url
  url=$(git remote get-url origin 2>/dev/null \
    | sed 's/git@github.com:/https:\/\/github.com\//' \
    | sed 's/\.git$//')
  if [[ -z "$url" ]]; then
    echo "No git remote 'origin' found"
    return 1
  fi
  open "$url"
}

# Fuzzy-search local git branches and check out
# Requires: brew install fzf
gfco() {
  if ! command -v fzf &>/dev/null; then
    echo "fzf not found — run: brew install fzf"
    return 1
  fi
  local branch
  branch=$(git branch | fzf --height=20% --reverse | sed 's/^[* ]*//') && git checkout "$branch"
}

# Fuzzy-search git log and show the selected commit
# Requires: brew install fzf
glf() {
  if ! command -v fzf &>/dev/null; then
    echo "fzf not found — run: brew install fzf"
    return 1
  fi
  git log --oneline --graph --decorate | fzf --ansi --height=40% --reverse \
    --preview 'git show --stat --color=always $(echo {} | grep -o "[a-f0-9]\{7,\}" | head -1)'
}

EOF
}

print_summary() {
  local warning

  printf '\n'
  log "Bootstrap complete"
  if [ "${#WARNINGS[@]}" -eq 0 ]; then
    log "No warnings"
  else
    log "Warnings:"
    for warning in "${WARNINGS[@]}"; do
      printf '  - %s\n' "$warning"
    done
  fi

  printf '\n'
  log "You may need to restart zsh, Finder, or the affected apps for every change to take effect."
}

main() {
  ensure_sudo_session
  install_homebrew
  load_homebrew_env

  brew update >/dev/null 2>&1 || warn "brew update failed"

  install_with_fallback "bash-completion" "formula:bash-completion"
  install_with_fallback "zsh-completions" "formula:zsh-completions"

  ensure_zsh_homebrew_config
  ensure_zsh_rbenv_config
  ensure_zsh_plugins_config
  ensure_zsh_starship_config
  install_requested_packages
  install_requested_fonts
  ensure_zsh_fzf_config
  ensure_zsh_zoxide_config
  ensure_zsh_ls_color_config
  ensure_zsh_editor_config
  ensure_zsh_op_completion_config
  ensure_zsh_ssh_config
  ensure_zsh_aliases_config
  install_superpowers_plugins
  configure_rbenv_rubies
  configure_ssh
  configure_git
  configure_zsh_aliases
  configure_sublime_text
  configure_sublime_defaults
  configure_vscode
  configure_cursor
  configure_dock
  configure_obsidian
  configure_iterm2
  configure_starship
  print_summary
}

main "$@"
