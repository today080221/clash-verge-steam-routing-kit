# Clash Verge Steam Routing Kit

A shared routing toolkit for Clash Verge Rev on Windows covering Steam, Unity, NVIDIA, and optional Bilibili video CDN routing, with a stricter Unity China bypass strategy.

[![简体中文](https://img.shields.io/badge/简体中文-Read-0366d6?style=for-the-badge)](README.md)
[![English](https://img.shields.io/badge/English-Current-2ea44f?style=for-the-badge)](README.en.md)

## Project Status

This repository is an AI-generated project.

The code, structure, and documentation were produced through AI-assisted generation and iteration. Please review the scripts before using them in your own environment.

When explicitly attached to a Clash Verge Rev subscription, the public or composed script injects twelve reusable groups:

- `UnityGlobal`: Unity global parent selector that lets `UnityHub`, `UnityEditor`, and `UnityDownload` converge on the same upstream node
- `UnityWeb`: Unity web and account traffic for browser-side Unity ID, Asset Store, and related web APIs
- `UnityHub`: Unity global control-plane traffic for sign-in, licensing, release metadata, config, and service gateways
- `UnityEditor`: Unity Editor APIs, package-manager traffic, analytics, and auxiliary cloud services
- `UnityDownload`: Unity global download-plane traffic for editor, modules, and package delivery
- `UnityChina`: an isolation group for China-specific Unity domains such as `unity.cn`, `unitychina.cn`, and `u3d.cn`
- `NvidiaServices`: NVIDIA web, sign-in, control-plane, and other official service traffic, with direct routing as the default
- `NvidiaDownload`: NVIDIA driver, NVIDIA App, and OTA payload downloads, with direct routing as the default
- `SteamCommunity`: Steam community, chat, avatars, and other commonly blocked Steam web content
- `SteamMainland`: Steam store, login, help, and general Steam web traffic that usually works from mainland China
- `SteamDownload`: Steam CDN, content servers, and download-related traffic
- `BilibiliVideo`: an optional Bilibili video-CDN selector for web player 6003 errors or CDN/DNS path issues

## What This Repo Solves

- Reuses the same Steam, Unity, and NVIDIA routing logic across multiple PCs
- Applies the same split-routing behavior across different providers
- Preserves each subscription's existing custom script binding; reuse the public or composed script through an explicit choice
- Separates Steam community, store/login, and download traffic so they can be tuned independently
- Separates Bilibili web-player CDN traffic from generic China-direct rules so only the video path needs to be switched when needed
- Separates NVIDIA service traffic from driver and app payloads so large downloads do not have to follow the sign-in or web route
- Separates Unity global control, Unity global download, and Unity China traffic so they can be tuned independently
- Lets all global Unity groups point to the same `UnityGlobal` selector by default while still allowing per-group overrides
- Separates browser-side Unity ID and Asset Store traffic from Unity Hub and Unity Editor traffic

## Why `UnityChina` Exists

Unity's global Hub flow mostly lives on `unity.com`, `unity3d.com`, `public-cdn.cloud.unity3d.com`, and `download.unity3d.com`, while Unity China documentation also exposes separate China-specific account and package-delivery endpoints such as `upm-cdn-china.unitychina.cn`.

That means "proxy `download.unitychina.cn`" alone is not enough if your goal is to stay off the Unity China path from geo/context detection through CDN assignment. The current default model is:

- `UnityGlobal`: proxy, as the shared upstream selector for the global Unity path
- `UnityWeb`: defaults to `UnityGlobal`, for browser-side Unity ID, Asset Store, and related web APIs
- `UnityHub`: defaults to `UnityGlobal`, to keep region/context and service metadata on the global path
- `UnityEditor`: defaults to `UnityGlobal`, for Unity Editor APIs, package-manager traffic, analytics, and auxiliary cloud services
- `UnityDownload`: defaults to `UnityGlobal`, to keep editor and module downloads on the global path
- `UnityChina`: `REJECT` by default, to block dedicated Unity China domains instead of silently falling back to them

## Why `NvidiaDownload` Exists

NVIDIA driver and NVIDIA App payloads are usually large, and NVIDIA App may transfer them in concurrent segments. NVIDIA Support explicitly notes that proxies or download managers can interfere with file transfer and corrupt downloads; the official NVIDIA App entrypoint also serves its installer from download hosts such as `us.download.nvidia.com`.

The rules therefore use a conservative service/download boundary. NVIDIA provides official mainland-China NVIDIA App and account entrypoints; v1.7.1 also verified direct DNS, TLS, and HTTP reachability against service hosts observed in NVIDIA App logs. Both NVIDIA groups consequently put `DIRECT` first while retaining proxy fallbacks. Based on a real driver-download response, v1.7.2 also keeps the second hop from the `.com` host to the redirected `.cn` host in the download group:

- `NvidiaServices` captures the broader official `nvidia.com` and `nvidia.cn` service domains, defaults to `DIRECT`, and can be switched independently when sign-in or service traffic needs a proxy
- `NvidiaDownload` takes higher-priority ownership of `*.download.nvidia.com`, `*.download.nvidia.cn`, and `ota-downloads.nvidia.com`, defaults to `DIRECT`, and keeps proxy choices available when the direct CDN path is unhealthy
- independent ecosystems such as GeForce NOW are not captured automatically, so low-latency game streaming is not mixed with driver delivery

References: [official NVIDIA China App page](https://www.nvidia.cn/software/nvidia-app/); [NVIDIA China account FAQ](https://www.nvidia.cn/account/faq/); [NVIDIA on proxies affecting download integrity](https://nvidia.custhelp.com/app/answers/detail/a_id/21).

Clash rules can only control connections that actually enter Clash. If Proxifier separately sends NVIDIA processes to another upstream proxy, the result may still be a double-proxy path; send NVIDIA directly into Clash or bypass the download traffic in Proxifier instead.

## Install on Another Windows PC

1. Install Clash Verge Rev and open it once.
2. Import your subscription(s) normally.
3. Clone this repo or copy the folder to that machine.
4. Run:

```bat
install-steam-routing.bat
```

5. Create a script enhancement card in Clash Verge Rev, copy the contents of `%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\profiles\SteamRoutingKit.js` into it, and select that card only for the intended subscriptions. Reload those subscriptions.

The installer maintains only the dedicated `SteamRoutingKit.js` file and its hash record. It does not edit `profiles.yaml`, existing `Script.js`, `Merge.yaml`, or subscription bindings. Clash owns the card; after future updates, copy the updated file into the same card. Edited managed files cause a conflict instead of being overwritten. Ordinary installation creates no autostart, restarts no Clash process, and enables no Claude protection.

### Safe migration from older versions

The old watcher repeatedly rebinds subscriptions. Updating the repository does not stop an already-running copy. Close Clash, then preview and run from the new package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-steam-routing.ps1 -MigrateLegacy -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-steam-routing.ps1 -MigrateLegacy
```

Migration stops only legacy processes whose `-File` argument exactly matches this installation. Recognized legacy scripts and startup entries are renamed to uniquely named `.disabled` backups. Unknown or customized versions require manual review before proceeding. All subscription bindings are preserved. Previously lost script contents cannot be reconstructed; restore them from your own backups. Do not re-enable the old watcher.

### Compose public routing with an owner enhancement

Keep the custom source separate. Generate a new file, place it in a separate enhancement card, and explicitly select the intended subscriptions:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\compose-routing-script.ps1 -OwnerScriptPath C:\Private\Owner.js -OutputPath C:\Private\Owner.combined.js
```

Each script retains its own `main` and helper scope. The public `main(config)` runs first, then the owner's `main(config, profileName)`. The owner must synchronously return a configuration object. Do not attach the public layer twice. The builder does not execute owner code, overwrite existing output, or bind subscriptions. Regenerate and review after public-script updates. Never commit compositions containing private configuration.

## Quick Install from a Release

1. Download the latest release zip from the Releases page.
2. Extract it to any folder.
3. Double-click `install-steam-routing.bat`.
4. Create/update the enhancement card and explicitly select subscriptions as described above. Migrate older installations first.

You only need to download the package once. After that, keep using the same `install-steam-routing.bat`: it checks GitHub for newer releases before running the installer, downloads updates automatically when available, and falls back to a console prompt if the GitHub check times out.

## Optional Claude Privacy Protection

The independent `claude-privacy.bat` entrypoint defaults to status inspection. Ordinary routing installation never invokes it. It requires Windows PowerShell 5.1, Windows Firewall components, and verifiable Claude executables in the selected scope; Chrome URL policy requires Chrome 133 or newer. A new installation defaults to the current user's Claude desktop app. The recommended entry enables protection and automatic maintenance together:

```powershell
.\claude-privacy.bat status
.\enable-claude-privacy.bat -WhatIf
.\enable-claude-privacy.bat
```

To also protect an installed official Windows native Claude Code executable, explicitly select the combined scope:

```powershell
.\enable-claude-privacy.bat -ProtectionScope DesktopAndCli -WhatIf
.\enable-claude-privacy.bat -ProtectionScope DesktopAndCli
```

The selection is saved in state. Omitting `-ProtectionScope` later preserves it; older state without this field remains `Desktop`. To return to desktop-only coverage, run `enable-claude-privacy.bat -ProtectionScope Desktop`; it removes the owned CLI rule after ownership checks and updates maintenance. Selecting a scope does not install, start, or log in to Claude, or make model requests.

The last command requests one Windows PowerShell UAC elevation as the SAME Windows user; no task password is entered or stored. A hidden setup process applies rules, deploys protected code, runs the real task, verifies that an old refresh cannot undo rollback, then restores protection and maintenance. Its receipt is `%ProgramData%\ClashVergeSteamRoutingKit-ClaudePrivacy\<user SID>\enablement-result.json`. Only `Completed` with `success: true` confirms these configuration checks; the launcher's return is not completion. Alternatively, run `claude-privacy.bat apply` from an elevated PowerShell as the same user to apply protection without creating a maintenance task.

It merges the current user's Chrome `WebRtcIPHandlingUrl` policy, setting `disable_non_proxied_udp` only for `https://[*.]claude.ai`, `https://[*.]claude.com`, and `https://[*.]anthropic.com`. Other domains are preserved; conflicts stop the operation with a report. Identical preexisting entries are not claimed or removed on rollback. Chrome uses the first matching entry, so earlier policy entries may require manual precedence review. Verify actual loading in `chrome://policy` and ICE behavior in the target page.

Desktop protection discovers the current user's registered Claude MSIX, older still-running versions, and optional explicit `-ClaudePath` candidates on manual commands. It verifies the Anthropic signature and product metadata before blocking outbound UDP for each exact `Claude.exe` path across all firewall profiles. `DesktopAndCli` also checks `.local\bin\claude.exe` under the current user's home directory, retaining its rule even when the CLI is not running. Desktop and CLI product/company metadata are checked separately; the process name alone never establishes trust. `Desktop` records and skips a verified CLI. Unknown signatures, unverifiable same-name processes, or a missing selected CLI still stop refresh and pruning. It never blocks UDP machine-wide or assumes package identity filtering works for full-trust MSIX processes. Multiple versions can coexist. To refresh immediately, use an elevated PowerShell as the same user:

```powershell
.\claude-privacy.bat refresh -WhatIf
.\claude-privacy.bat refresh
.\claude-privacy.bat status
```

Automatic maintenance triggers at user logon and every two minutes while logged on. It reads the saved scope and adds new version rules before removing paths no longer discovered. The task uses that user's highest available privileges, never SYSTEM, and runs only protected deployed code; inspecting CLI signatures and metadata never executes the CLI. Only Administrators/SYSTEM can modify that code and the task definition; every run verifies ownership and file hashes. Shutdown, sleep, scheduling delays, or failures can extend the protection gap after an update; zero-gap coverage is not guaranteed. `status` reports the last result, task health, and success older than six minutes. Explicit standalone `-ClaudePath` arguments are not saved by the task; continue supplying them during manual refresh.

Maintenance follows executable-path changes after Claude updates and checks for rule drift; it is not a resident process required for connectivity. A protected GUI host creates the PowerShell worker without a console window. `-WindowStyle Hidden` or the task's Hidden setting alone does not establish quiet operation. The host is compiled locally using the system .NET Framework compiler and pinned by hash, without Python; deployment stops if the compiler is missing or unverifiable. Unchanged runs still verify signatures, policy, and rule fingerprints, but skip redundant final per-rule reads and writes of unchanged state. The last result records wall time and worker CPU time separately.

To upgrade maintenance for existing protection while retaining its scope, rules, and Chrome settings, use the following entry. It stops if the existing protection needs repair:

```powershell
.\enable-claude-privacy.bat -MaintenanceOnly -WhatIf
.\enable-claude-privacy.bat -MaintenanceOnly
```

This mode still requests one same-user UAC elevation and updates the existing owned task. Its receipt includes `maintenanceOnly: true`; it never applies or rolls back protection. The interval remains two minutes. Quiet-operation acceptance requires observing visible windows of actual natural task runs and their children, not just checking arguments or exit codes.

To stop maintenance while retaining current protection, run `claude-privacy.bat maintenance-disable`; use `maintenance-enable` to enable it again. Both support `-WhatIf` and require same-user elevation. To undo protection:

```powershell
.\claude-privacy.bat rollback -WhatIf
.\claude-privacy.bat rollback
```

Rollback first persists a disabled refresh gate and removes the owned task, then undoes recorded configuration that has not been externally modified. Combined-scope desktop and CLI rules are removed together; later edits are preserved and reported as conflicts. An old queued refresh cannot re-enable protection; explicit `apply` is required. Rollback retains the selected scope, so explicit re-enablement without a scope argument reuses it. Keep `state.json`, `maintenance.json`, and `maintenance-last-run.json` in the same protected directory for reliable rollback and inspection. Deployed code remains for audit and does not run automatically after rollback. Exit code `0` means command completion, `1` means failure, and `2` means incomplete audit, unhealthy maintenance, or unresolved conflicts. Configuration presence does not establish actual network enforcement.

State and result receipts are committed by replacing them with complete staged files while retaining destination permissions. Failed replacement preserves the previous file and staged evidence; do not delete these records to suppress errors. Real file-replacement regressions cover both Windows PowerShell 5.1 and PowerShell 7.

This limits non-proxied WebRTC UDP in the selected pages and outbound UDP from confirmed `Claude.exe` paths in the selected scope. It does not force every TCP connection through a proxy or prove DNS, child processes, Node-hosted CLI installations, WSL/VM, resource pages, or every fingerprint are covered. Chrome policy does not configure Electron. Native CLI coverage requires explicit opt-in and an exact executable rule; it never targets a shared `node.exe` host. Mihomo/Hysteria2 continues to use UDP through its own process. A Python STUN probe cannot replace tests in the target Chrome page and protected Claude process.

The shared network suffix interface is [`config/claude-privacy-domains.json`](config/claude-privacy-domains.json). Its six entries include resource/preview hosts and are distinct from the Chrome page-policy scope. See [handoff and live acceptance](docs/claude-privacy-handoff.md). Sources: [Claude network requirements](https://code.claude.com/docs/en/desktop#network-access-requirements), [Chrome policy definition](https://raw.githubusercontent.com/chromium/chromium/main/components/policy/resources/templates/policy_definitions/WebRtc/WebRtcIPHandlingUrl.yaml), [Windows program firewall rules](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule).

## Recommended Defaults

- `UnityGlobal`: `Auto Select`, or a stable overseas node
- `UnityWeb`: point it to `UnityGlobal`
- `UnityHub`: point it to `UnityGlobal`
- `UnityEditor`: point it to `UnityGlobal`
- `UnityDownload`: point it to `UnityGlobal`
- `UnityChina`: `REJECT`
- `NvidiaServices`: `DIRECT`; switch only this group to a stable node if sign-in, release metadata, or web services fail on the direct path
- `NvidiaDownload`: `DIRECT`; switch to a stable node only when the direct CDN path is unhealthy
- `SteamCommunity`: `Auto Select`, or a Hong Kong/Japan node
- `SteamMainland`: `DIRECT`
- `SteamDownload`: `DIRECT`
- `BilibiliVideo`: `DIRECT` by default; if the web player shows 6003 but works when system/global proxy is enabled, temporarily switch it to a stable node

If Unity Hub still shows `Validation Failed`:

- make sure `UnityGlobal`, `UnityHub`, `UnityEditor`, and `UnityDownload` are not `DIRECT`
- point `UnityHub`, `UnityEditor`, and `UnityDownload` to `UnityGlobal` first
- only override a specific Unity sub-group when you have a confirmed reason
- run `test-unity-routing.bat` first
- if the script shows `302 -> download.unitychina.cn -> 404` on the direct path but `200` on the Clash proxy path, Unity is not entering Clash reliably enough; prefer `Rule mode + TUN enabled`
- if the Clash proxy path itself still returns `302` or `404`, that node is still being sent to the Unity China mirror even though it is an overseas node; switch `UnityHub` and `UnityDownload` together and test again
- if a node passes the `200/206` checks but large downloads still hit `ECONNRESET`, compare more nodes with the script instead of trusting the region label alone
- if you see requests such as `unity-connect-prd.storage.googleapis.com`, `config.uca.cloud.unity3d.com`, `api.hub-proxy.unity3d.com`, or `unity-assetstorev2-prd.storage.googleapis.com` in Clash activity, they now land on `UnityEditor`, `UnityHub`, or `UnityWeb` instead of a generic `google` rule
- if Unity Package Manager can list packages but stalls on `.tgz` downloads, make sure `UnityEditor` is not pinned to a different node and point it back to `UnityGlobal` with `UnityHub` and `UnityDownload`
- when proxying Unity, it is usually best to also use Proxifier or a similar tool to reroute `Unity Hub.exe`, `Unity.exe`, and `UnityPackageManager.exe` into the local Clash Verge Rev proxy, for example `127.0.0.1:7897`
- the rules now also cover `storage.googleapis.com` and the legacy `upm-cdn.unity.com` host so Unity package tarballs and older CDN paths stay inside the Unity-specific route
- browser-side `assetstore.unity.com`, `kharma.unity3d.com`, `unity-assetstorev2-prd.storage.googleapis.com`, `id.unity.com`, `login.unity.com`, and `accounts.unity3d.com` now go through `UnityWeb`
- if UPM still bypasses Clash intermittently, follow Unity's proxy guidance and launch Unity Hub or the Editor with `HTTP_PROXY` and `HTTPS_PROXY`

If the Steam store shows `-100`, temporarily change `SteamMainland` from `DIRECT` to the same node as `SteamCommunity` and test again.

If an NVIDIA App driver download fails:

- first make sure `NvidiaDownload` is still set to `DIRECT`, then restart the download; hosts such as `international-gfe.download.nvidia.com`, redirected `international-gfe.download.nvidia.cn`, and `us.download.nvidia.com` stay on the higher-priority download route
- `NvidiaServices` is independent from the download group; it also defaults to `DIRECT`, but sign-in, release metadata, or web access can use a proxy without sending the large driver payload through the same node
- when both the Windows system proxy and Proxifier are enabled, avoid sending NVIDIA through a second remote proxy; let the connection receive one Clash routing decision
- if the ISP's direct CDN path itself is slow or broken, temporarily switch only `NvidiaDownload` to a stable node instead of changing the entire NVIDIA service route

If the Bilibili web player shows error code `6003`:

- switch `BilibiliVideo` from `DIRECT` to a known-good node or auto-select group
- this only captures video/static CDN domains such as `bilivideo.com` and `hdslb.com`; it does not force all `bilibili.com` API traffic through a proxy
- if playback recovers immediately, the likely cause is the direct DNS/CDN assignment or ISP path, not browser hardware decoding
- if it still fails, clear the page cache or retry in a private window so the player does not reuse a failed connection

Recommended commands for Unity 404/302/reset troubleshooting:

```bat
test-unity-routing.bat
```

It compares the current direct path and the current Clash proxy path. After switching `UnityHub` and `UnityDownload` to another node in Clash Verge Rev, run the script again to compare the next candidate.

## Files

- `bootstrap-install.ps1`: auto-update bootstrap that checks GitHub releases, downloads newer packages, and hands off execution
- `AGENTS.md`: project-specific operating guidance for Codex and other agents
- `install-steam-routing.bat`: one-click installer entrypoint that checks for updates before each run
- `Script.js`: shared Clash Verge Rev profile script
- `install-steam-routing.ps1`: installs the dedicated public script and supports explicit legacy migration
- `sync-clash-verge-steam-script.ps1`: compatibility entrypoint for a single managed-file update; `-Audit` checks its hash, without rebinding subscriptions
- `Start ClashVerge Steam Sync.vbs`: retained compatibility notice; no background process is started
- `compose-routing-script.ps1`: explicitly composes the public layer with an owner enhancement
- `claude-privacy.bat` / `claude-privacy.ps1`: independent optional status, apply, refresh, maintenance controls, and rollback entrypoints
- `enable-claude-privacy.bat` / `enable-claude-privacy.ps1`: one elevation for enablement, real-task and rollback coordination checks, leaving protection enabled
- `scripts/`: required routing ownership, privacy planning, Windows adapter, maintenance, and acceptance modules, plus the GUI host C# source
- `config/claude-privacy-domains.json`: shared network-domain interface for downstream vendoring
- `docs/claude-privacy-handoff.md`: interfaces, limitations, validation results, and live acceptance steps
- `tests/`: isolated tests without machine configuration writes; JavaScript checks require Node.js
- `release-files.txt` / `build-release.ps1`: explicit package manifest and local packaging entrypoint
- `CHANGELOG.md`: unreleased changes and release notes
- `test-unity-routing.bat`: one-click entrypoint for Unity 404/302/reset diagnosis
- `test-unity-routing.ps1`: Unity diagnostic script that compares direct vs proxied requests and also checks a Package Manager tarball path
- `VERSION`: local package version used by the auto-update comparison
- `Merge.yaml`: placeholder to satisfy the global merge card

## Safety Notes

- Do not commit `profiles.yaml`, provider subscription YAML files, or subscription URLs/tokens
- This public repo intentionally contains only the reusable routing framework, not your personal provider configs
- The installer does not copy your provider profiles; it only installs the shared routing layer

## License

MIT. See [LICENSE](LICENSE).
