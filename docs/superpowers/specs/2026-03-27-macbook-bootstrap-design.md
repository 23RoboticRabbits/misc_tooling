# MacBook Bootstrap Script Design

## Goal

Create a single standalone bash script that can be hosted on GitHub and executed via `curl` to bootstrap a new MacBook for Mike Roth.

## Scope

The script must:

- Install Homebrew if missing.
- Configure zsh to initialize Homebrew and Homebrew shell completions.
- Install requested CLI tools and desktop apps via Homebrew, continuing with warnings when a package is unavailable or incompatible.
- Configure Git global name, email, and global ignore rules.
- Install the latest stable Ruby `3.x` and `4.x` through `rbenv`, set global Ruby to the `4.x` version when available, and install Ruby editor gems inside that `rbenv` Ruby.
- Set Sublime Text as the default app for common text, Markdown, YAML, Ruby, and Python file extensions.
- Bootstrap Sublime Text with Package Control, Ruby/Rails/editor packages, Nord theme, and user/LSP settings.
- Configure iTerm2 to use Fira Code and a Nord-themed profile as automatically as is practical from a script.
- Include top-of-file comments showing both direct pipe and download-then-run `curl` install patterns.

## Constraints

- The script must be idempotent and safe to rerun.
- The requested package list includes items whose Homebrew token or availability may change over time; the script should use fallback candidates where useful and otherwise warn.
- The script should target macOS and work with the system `bash`, which is commonly Bash 3.2 on new Macs.
- GUI preference changes may require the app to be installed, launched once, or restarted before they fully apply.

## Architecture

The bootstrap script is a single file with small shell functions grouped by responsibility:

1. Logging and warning collection
2. Homebrew installation and shell environment initialization
3. Safe, idempotent file updates for shell config
4. Formula and cask installation helpers with fallback support
5. Git configuration
6. Sublime default-app registration using `duti`
7. iTerm2 theme/profile installation
8. Final summary output

## Package Strategy

- Install formulae for CLI tools and build dependencies where possible.
- Install casks for GUI apps.
- Treat `npm` as satisfied by the `node` install rather than forcing a separate package.
- Resolve `codex` by trying the formula first and then the cask if needed.
- Resolve font requests by matching available Homebrew casks beginning with `font-fira` and `font-ia`, with explicit fallback tokens if search results are empty.
- Use Homebrew for `rbenv` and Ruby build prerequisites, but install actual Ruby runtimes through `rbenv`, not Homebrew Ruby formulae.

## zsh Configuration

Append managed blocks to:

- `~/.zprofile` for Homebrew `shellenv`
- `~/.zshrc` for `FPATH`, `compinit`, and `rbenv` initialization

The managed blocks are marker-delimited so the script can avoid duplicate entries on reruns.

## Sublime Defaults

Install `duti` through Homebrew, then register `com.sublimetext.4` for:

- Plain text
- Markdown
- YAML
- Ruby
- Python

using common file extensions plus plain-text UTIs where practical.

## Sublime Package Bootstrap

Seed Sublime Text configuration under `~/Library/Application Support/Sublime Text` to install:

- `LSP`
- `LSP-ruby-lsp`
- `Ruby Syntax`
- `Rails`
- `ERB Snippets`
- `SublimeLinter`
- `SublimeLinter-rubocop`
- `RubyFormat`
- `Terminus`
- `GitSavvy`
- `GitGutter`
- `A File Icon`
- `AdvancedNewFile`
- `SideBarEnhancements`
- `RSpec`
- `BracketHighlighter`
- `TrailingSpaces`
- `AutoFileName`
- `Nord`

Also write the requested user preferences and LSP settings, plus supporting SublimeLinter path settings so GUI-launched Sublime can find `rbenv` shims more reliably.

## Ruby Setup

Install `ruby-build` and common native build dependencies via Homebrew, then:

- discover the newest stable `3.x` and `4.x` releases from `rbenv install -l`
- install both if available
- set `rbenv global` to the `4.x` version
- install editor-support gems into that `4.x` Ruby, including `ruby-lsp`, `rubocop`, `rubocop-rails`, `rubocop-rspec`, and `rubocop-shopify`

## iTerm2 Configuration

Create a dynamic iTerm2 profile named `Nord` with:

- Fira Code as the normal font
- Nord color values

Also download the upstream `Nord.itermcolors` file for reference/import and set the new profile GUID as the default bookmark GUID in iTerm2 preferences.

## Error Handling

- Homebrew installation is mandatory and should fail the script if it cannot be installed.
- Package installs, file association updates, and GUI preference updates should warn and continue.
- Ruby installation, gem installation, and Sublime package bootstrap should also warn and continue when a non-critical step fails.
- The final script output should summarize all warnings and point out likely manual follow-up if needed.
