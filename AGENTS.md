# AGENTS.md

This file captures project-specific guidance for agents working in this repository.

## Purpose

This repository is a reusable Steam, Unity, and NVIDIA routing kit for Clash Verge Rev on Windows, with an explicit Unity China isolation layer.

It provides a shared routing layer that:

- splits Unity traffic into `UnityGlobal`, `UnityWeb`, `UnityHub`, `UnityEditor`, `UnityDownload`, and `UnityChina`
- splits NVIDIA traffic into `NvidiaServices` and `NvidiaDownload`
- splits Steam traffic into `SteamCommunity`, `SteamMainland`, and `SteamDownload`
- optionally splits Bilibili web-player CDN traffic into `BilibiliVideo`
- keeps the same routing logic reusable across different providers
- supports multi-PC installation through local scripts and release assets

## Stable Behavior

Treat the following group names as stable public interface unless the user explicitly asks to rename them:

- `UnityGlobal`
- `UnityWeb`
- `UnityHub`
- `UnityEditor`
- `UnityDownload`
- `UnityChina`
- `NvidiaServices`
- `NvidiaDownload`
- `SteamCommunity`
- `SteamMainland`
- `SteamDownload`
- `BilibiliVideo`

The intended defaults are:

- `UnityGlobal`: proxy or auto-select
- `UnityWeb`: point to `UnityGlobal` by default
- `UnityHub`: point to `UnityGlobal` by default
- `UnityEditor`: point to `UnityGlobal` by default
- `UnityDownload`: point to `UnityGlobal` by default
- `UnityChina`: `REJECT`
- `NvidiaServices`: `DIRECT` first, with proxy choices available for service-path troubleshooting
- `NvidiaDownload`: `DIRECT` first, with proxy choices available for download-path troubleshooting
- `SteamCommunity`: proxy or auto-select
- `SteamMainland`: `DIRECT` first
- `SteamDownload`: `DIRECT`
- `BilibiliVideo`: `DIRECT` first, with proxy choices available for 6003/CDN troubleshooting

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
- `test-unity-routing.bat`
- `test-unity-routing.ps1`
- `Script.js`
- `Merge.yaml`
- `README.md`
- `README.en.md`
- `VERSION`
- `LICENSE`
- `compose-routing-script.ps1`
- `claude-privacy.bat`
- `claude-privacy.ps1`
- `enable-claude-privacy.bat`
- `enable-claude-privacy.ps1`
- `scripts/RoutingKit.psm1`
- `scripts/ClaudePrivacy.Core.psm1`
- `scripts/ClaudePrivacy.Windows.psm1`
- `scripts/ClaudePrivacy.Maintenance.psm1`
- `scripts/ClaudePrivacy.Host.cs`
- `scripts/ClaudePrivacy.Enablement.psm1`
- `config/claude-privacy-domains.json`
- `docs/claude-privacy-handoff.md`
- `CHANGELOG.md`
- `release-files.txt`
- `build-release.ps1`
- `tests/` (all fixture and test files listed explicitly in `release-files.txt`)

`release-files.txt` is the executable packaging allowlist. Build local assets with `build-release.ps1`; never zip AppData or arbitrary working folders. Do not publish or bump `VERSION` unless release work is authorized.

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

The installer owns only `profiles/SteamRoutingKit.js` with a hash manifest. It must never overwrite generic `Script.js`, `Merge.yaml`, `profiles.yaml`, or automatically bind subscriptions. Users explicitly create/update script cards and select subscriptions. The old sync entrypoint is now a one-shot managed-file updater, and the VBS is only a compatibility notice. Never restore automatic rebinding or automatic Clash restart.

Legacy migration is explicit (`-MigrateLegacy`) and supports `-WhatIf`. Only recognized legacy scripts/startup content and exact process `-File` paths may be disabled, with backups. Unknown/customized installations require review. Compose public routing and private owner enhancements explicitly with separate function scopes, public first and owner second.

Do not duplicate complex update or install logic into the batch file.

## Diagnostic Conventions

For Unity download troubleshooting, the preferred entrypoint is:

- `test-unity-routing.bat`

That batch file should stay simple and call:

- `test-unity-routing.ps1`

The diagnostic script is responsible for:

- comparing direct Unity download results against the current Clash-proxied results
- showing current Clash mode, TUN state, system proxy state, and Unity group selections

## Security And Privacy

Claude privacy protection is optional and independent from installation. Its default action is read-only status. Keep Chrome URL policy scoped to the three documented page domains; the six network suffixes in `config/claude-privacy-domains.json` are a separate public interface. That JSON is the authoritative source for downstream vendoring.

Firewall protection uses verified exact Claude executable paths, never global UDP blocking or unverified MSIX package identity assumptions. Preserve ownership journals, reject user edits/collisions, support preview/apply/refresh/rollback, and add new paths before pruning stale ones. Never claim registry/firewall configuration proves browser ICE or process-level UDP enforcement. Test with isolated adapters and fixtures; real machine enablement requires task authorization.

Keep protection scope explicit: new/legacy state defaults to `Desktop`; `DesktopAndCli` opts in to the official native Windows CLI, with the choice persisted for subsequent refreshes. Independently verify signatures and exact product/company metadata for Desktop and NativeCli. A verified same-name CLI outside Desktop scope is reported and excluded, while unknown identities still fail discovery. Combined scope must discover the current user's `.local/bin/claude.exe` even when it is not running. Never execute Claude during discovery, expand scope through automatic refresh, or target generic Node/WSL/VM hosts. Rollback disables both owned rule kinds but preserves the selected scope for later explicit enablement.

Automatic privacy maintenance is separately enabled and must use the same user's InteractiveToken/HighestAvailable task with no saved password, protected deployed code, administrator-owned task ACLs, and verified file/definition fingerprints. Never run privileged maintenance from a user-writable checkout. Keep the two-minute/logon triggers bounded; report delays and failures without claiming gap-free protection. Rollback must persist the disabled gate and remove only the owned task before removing protection. A queued refresh must never re-enable after rollback. The one-time enablement entry requests one same-user UAC elevation, validates real task execution and rollback coordination, and restores the requested enabled final state; its receipt must distinguish configuration checks from unproven network enforcement.

Scheduled maintenance must start through the protected GUI-subsystem host and create its PowerShell child with CreateNoWindow and UseShellExecute=false. Do not treat WindowStyle or the scheduler Hidden field as proof that no console appears. Compile the reviewed C# source with the verified system compiler, pin the generated executable and build record, and keep existing-runtime upgrades ownership-aware. MaintenanceOnly upgrades must retain enabled protection, scope, rules and Chrome policy. Preserve fresh discovery/signature/fingerprint checks while removing redundant no-op work; do not silently change the two-minute frequency. Validate quiet operation on natural task cycles using actual visible-window observation attributed to the host and its descendants, and distinguish wall time from CPU time.

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

- preserve the Unity global parent group plus Web/Hub/Editor/Download/China split unless explicitly asked to redesign it
- prefer additive, targeted rule fixes over broad changes
- keep NVIDIA download-specific rules ahead of the broader NVIDIA service rules so driver and app payloads remain independently selectable
- keep both `download.nvidia.com` and redirected `download.nvidia.cn` hosts in `NvidiaDownload`; NVIDIA driver delivery may redirect from the global hostname to the China CDN
- keep `NvidiaServices` on `DIRECT` by default, but preserve proxy choices for networks where sign-in or service traffic needs an alternate path
- keep `NvidiaDownload` on `DIRECT` by default, but preserve proxy choices for networks where the direct CDN path is unhealthy
- remember that Unity global parent routing, Unity browser/account traffic, Unity global control traffic, Unity Editor API/package traffic, Unity global download traffic, Unity China traffic, NVIDIA service traffic, NVIDIA download traffic, Steam community traffic, mainland web traffic, and download traffic may need different routing behavior
- keep `UnityChina` isolated from the global Unity path unless the user explicitly asks otherwise
- keep installation and release docs aligned with actual script behavior
- test complete subscriptions that already include all business groups, including UnityWeb pointing to UnityGlobal; validate every group reference for cycles, repeated application, and public/owner composition
- distinguish migration of the legacy watcher from the user's active global script/card; installing SteamRoutingKit.js does not disable an old global script or prove the current subscription uses the new file

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
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run-tests.ps1` passes without machine configuration writes
- release allowlist includes all runtime modules and domain data
- fixed-hash files named in `.gitattributes` retain exact reviewed bytes in Git blobs and clean exports; do not normalize their line endings without updating deployment/downstream provenance

## Git Hygiene

Use small, descriptive commits.

If a change affects documentation, release packaging, or public behavior, mention that clearly in the commit message.
