# AGENTS.md

This file captures project-specific guidance for agents working in this repository.

## Purpose

This repository is a reusable Steam routing kit for Clash Verge Rev on Windows.

It provides a shared routing layer that:

- splits Steam traffic into `SteamCommunity`, `SteamMainland`, and `SteamDownload`
- keeps the same routing logic reusable across different providers
- supports multi-PC installation through local scripts and release assets

## Stable Behavior

Treat the following group names as stable public interface unless the user explicitly asks to rename them:

- `SteamCommunity`
- `SteamMainland`
- `SteamDownload`

The intended defaults are:

- `SteamCommunity`: proxy or auto-select
- `SteamMainland`: `DIRECT` first
- `SteamDownload`: `DIRECT`

If a change affects these group names or their purpose, update the documentation and release notes together.

## Documentation Conventions

This repository is Chinese-first.

- `README.md` is the primary Simplified Chinese README shown on the repository homepage.
- `README.en.md` is the English companion README.
- Keep language switch badges at the top of both README files.
- When changing user-facing documentation, update both README files in the same change unless the user asks otherwise.
- Keep the note that this is an AI-generated project in the README files.

Preferred README structure:

1. Project title and short description
2. Language switch badges
3. AI-generated project note
4. What the repo solves
5. Install instructions
6. Release quick-install instructions
7. Recommended defaults
8. File overview
9. Safety notes
10. License

## Release Conventions

Use Chinese as the primary language in releases, with a short English summary appended below a separator.

Preferred release title format:

- `vX.Y.Z - 中文标题 / English subtitle`

Preferred release body structure:

1. `## 亮点`
2. `## 快速开始`
3. `## 说明`
4. `---`
5. `## English Summary`

Release assets should be built from the current repository state, not from stale local folders.

Preferred release asset filename:

- `clash-verge-steam-routing-kit-vX.Y.Z.zip`

The release zip should include:

- `AGENTS.md`
- `bootstrap-install.ps1`
- `install-steam-routing.bat`
- `install-steam-routing.ps1`
- `sync-clash-verge-steam-script.ps1`
- `Start ClashVerge Steam Sync.vbs`
- `Script.js`
- `Merge.yaml`
- `README.md`
- `README.en.md`
- `VERSION`
- `LICENSE`

If documentation language layout changes, publish a new release so downloaded assets match the repository homepage.

## Installer Conventions

For end users, the preferred entrypoint is:

- `install-steam-routing.bat`

That batch file should stay simple and call the PowerShell bootstrap:

- `bootstrap-install.ps1`

The bootstrap is responsible for:

- checking the latest GitHub release
- downloading and caching a newer release package when available
- falling back to a timeout prompt so the user can run the local installer once or exit

The actual installer logic should remain in:

- `install-steam-routing.ps1`

Do not duplicate complex update or install logic into the batch file.

## Security And Privacy

Never commit personal or provider-specific runtime data.

Do not commit:

- `profiles.yaml`
- provider subscription YAML files
- subscription URLs or tokens
- AppData runtime state
- logs or local databases

This public repository should contain only the reusable framework.

## Editing Guidance

When changing routing behavior:

- preserve the three-group split unless explicitly asked to redesign it
- prefer additive, targeted rule fixes over broad changes
- remember that Steam community traffic, mainland web traffic, and download traffic may need different routing behavior
- keep installation and release docs aligned with actual script behavior

When changing public-facing text:

- keep Chinese primary and English secondary
- keep wording concise and practical
- prefer instructions that non-technical Windows users can follow directly

## Validation

Before finishing a change, check at least:

- `README.md` and `README.en.md` stay in sync structurally
- install entrypoints still exist and use the expected filenames
- `VERSION` matches the intended release version when cutting a release
- release-facing filenames referenced in docs match the repository files
- `AGENTS.md` stays aligned with the actual documentation and release workflow
- no sensitive local files are staged

## Git Hygiene

Use small, descriptive commits.

If a change affects documentation, release packaging, or public behavior, mention that clearly in the commit message.
