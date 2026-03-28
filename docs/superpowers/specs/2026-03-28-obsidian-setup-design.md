# Obsidian Setup Design

## Goal

Extend `setup-macbook.sh` to create a pre-configured Obsidian vault tailored for an engineering leadership role.

## Scope

The script must:

- create a default vault at `~/Documents/Obsidian`
- scaffold a folder structure suited to an engineering leadership role using a lifecycle-based taxonomy
- download and install the Minimal theme
- download and install a curated set of community plugins including Obsidian Git
- write Obsidian config files (`appearance.json`, `app.json`, `core-plugins.json`, `community-plugins.json`, `daily-notes.json`)
- apply Nord colours via a CSS snippet
- configure fonts to use iA Writer Quattro S (text/UI) and iA Writer Mono S (code)
- create starter templates (Daily Note, Meeting Note, Project Brief, 1:1 Note, Research Note)
- create a Dashboard note with Dataview queries for active projects, recent meetings, and open tasks
- pre-configure the Templater plugin with the Templates folder
- register the vault as the currently selected vault in Obsidian's global config (`~/Library/Application Support/obsidian/obsidian.json`)

## Constraints

- All operations must be idempotent — existing files are never overwritten; config files are written only when absent.
- Plugin and theme downloads use `curl -fsSL` via the existing `download_file()` helper; failures warn and continue.
- The vault directory structure is created with `mkdir -p`; no failure is fatal.
- Compatible with macOS system Bash 3.2.

## Vault Folder Structure

The vault uses a lifecycle-based taxonomy as its primary organisational axis. Content flows through `active/` → `evergreen/` or `archive/` as it matures or completes.

- **`active/`** — browsable work-in-progress, organised by content type
- **`evergreen/`** — flat; permanent knowledge notes and long-lived reference (people, concepts). Queried rather than browsed.
- **`archive/`** — flat; completed projects, past meetings, concluded research. Queried rather than browsed.

Daily notes and templates sit outside the lifecycle taxonomy as they are temporal or structural.

```
~/Documents/Obsidian/
├── .obsidian/
│   ├── app.json
│   ├── appearance.json
│   ├── community-plugins.json
│   ├── core-plugins.json
│   ├── daily-notes.json
│   ├── plugins/
│   │   ├── dataview/
│   │   ├── templater-obsidian/
│   │   ├── calendar/
│   │   ├── periodic-notes/
│   │   ├── obsidian-tasks-plugin/
│   │   ├── obsidian-kanban/
│   │   ├── obsidian-minimal-settings/
│   │   ├── obsidian-style-settings/
│   │   └── obsidian-git/
│   ├── snippets/
│   │   └── nord.css
│   └── themes/
│       └── Minimal/
│           ├── manifest.json
│           └── theme.css
├── 00 - Home/
│   └── Dashboard.md
├── 10 - Daily Notes/
├── active/
│   ├── projects/
│   ├── meetings/
│   └── research/
├── evergreen/          (flat)
├── archive/            (flat)
├── assets/             (attachments)
└── Templates/
    ├── Daily Note.md
    ├── Meeting Note.md
    ├── Project Brief.md
    ├── 1-1 Note.md
    └── Research Note.md
```

### Lifecycle flow

| Content | Created in | Moves to |
|---|---|---|
| Projects | `active/projects/` | `archive/` when complete |
| Meetings | `active/meetings/` | `archive/` after the meeting |
| Research | `active/research/` | `evergreen/` when refined, or `archive/` if abandoned |
| People / team notes | `evergreen/` directly | rarely archived |
| Permanent concepts / ideas | `evergreen/` directly | — |

## Community Plugins

All plugins are sourced from GitHub releases (`/releases/latest/download/{main.js,manifest.json,styles.css}`).

| Plugin ID | GitHub Repo | Purpose |
|---|---|---|
| `dataview` | blacksmithgu/obsidian-dataview | Query notes as a database; powers Dashboard |
| `templater-obsidian` | SilentVoid13/Templater | Template engine for notes and folders |
| `calendar` | liamcain/obsidian-calendar-plugin | Calendar sidebar for daily note navigation |
| `periodic-notes` | liamcain/obsidian-periodic-notes | Daily/weekly/monthly note management |
| `obsidian-tasks-plugin` | obsidian-tasks-group/obsidian-tasks | Cross-vault task tracking |
| `obsidian-kanban` | mgmeyers/obsidian-kanban | Kanban boards for project management |
| `obsidian-minimal-settings` | kepano/obsidian-minimal-settings | GUI configuration for the Minimal theme |
| `obsidian-style-settings` | mgmeyers/obsidian-style-settings | CSS variable customisation UI (required by Minimal Settings) |
| `obsidian-git` | denolehov/obsidian-git | Git integration for vault version control and sync |

## Theme: Minimal + Nord

- **Theme:** Minimal (`kepano/obsidian-minimal`) — downloaded to `.obsidian/themes/Minimal/`
- **Colour scheme:** Nord dark palette applied via `.obsidian/snippets/nord.css`, enabled in `appearance.json` under `enabledCssSnippets`
- **Base theme:** dark (`"baseTheme": "dark"`)
- **Accent colour:** `#81A1C1` (Nord frost blue)

## Fonts

Set in `appearance.json`:

- `textFontFamily`: `"iA Writer Quattro S"` — body text and UI
- `interfaceFontFamily`: `"iA Writer Quattro S"` — panels and sidebar
- `monospaceFontFamily`: `"iA Writer Mono S"` — code blocks and inline code

The iA Writer fonts are installed via Homebrew casks (`font-ia-writer-duo`, `font-ia-writer-mono`, `font-ia-writer-quattro`) by the existing `install_requested_fonts()` function.

## Approach

Add three functions to `setup-macbook.sh`:

1. `install_obsidian_plugin(plugin_id, github_owner, github_repo, plugins_dir)` — downloads manifest.json, main.js, and optionally styles.css into the named plugin directory; skips if main.js already exists.

2. `register_obsidian_vault(vault_path)` — writes or updates `~/Library/Application Support/obsidian/obsidian.json` using inline Ruby, adding the vault with `"open": true` so Obsidian opens it on first launch. Uses an MD5-derived 8-character hex string as the vault ID for stability across runs.

3. `configure_obsidian()` — orchestrates vault creation, theme download, plugin installs, config/template file writes, and vault registration. Called from `main()` after `configure_dock()`.

## Error Handling

- warn if any plugin download fails; continue with remaining plugins
- warn if theme download fails
- warn if any config file write fails
- never call `die()` — Obsidian setup is non-critical
