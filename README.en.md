# Clash Verge Steam Routing Kit

A shared routing toolkit for Clash Verge Rev on Windows, focused on Steam and Unity Hub, with a stricter Unity China bypass strategy.

[![简体中文](https://img.shields.io/badge/简体中文-Read-0366d6?style=for-the-badge)](README.md)
[![English](https://img.shields.io/badge/English-Current-2ea44f?style=for-the-badge)](README.en.md)

## Project Status

This repository is an AI-generated project.

The code, structure, and documentation were produced through AI-assisted generation and iteration. Please review the scripts before using them in your own environment.

It injects six reusable groups into any Clash Verge Rev subscription:

- `UnityHub`: Unity global control-plane traffic for sign-in, licensing, release metadata, config, and service gateways
- `UnityDownload`: Unity global download-plane traffic for editor, modules, and package delivery
- `UnityChina`: an isolation group for China-specific Unity domains such as `unity.cn`, `unitychina.cn`, and `u3d.cn`
- `SteamCommunity`: Steam community, chat, avatars, and other commonly blocked Steam web content
- `SteamMainland`: Steam store, login, help, and general Steam web traffic that usually works from mainland China
- `SteamDownload`: Steam CDN, content servers, and download-related traffic

## What This Repo Solves

- Reuses the same Steam and Unity Hub routing logic across multiple PCs
- Applies the same split-routing behavior across different providers
- Rebinds newly added remote subscriptions to the shared `Script.js`
- Separates Steam community, store/login, and download traffic so they can be tuned independently
- Separates Unity global control, Unity global download, and Unity China traffic so they can be tuned independently

## Why `UnityChina` Exists

Unity's global Hub flow mostly lives on `unity.com`, `unity3d.com`, `public-cdn.cloud.unity3d.com`, and `download.unity3d.com`, while Unity China documentation also exposes separate China-specific account and package-delivery endpoints such as `upm-cdn-china.unitychina.cn`.

That means "proxy `download.unitychina.cn`" alone is not enough if your goal is to stay off the Unity China path from geo/context detection through CDN assignment. The current default model is:

- `UnityHub`: proxy, to keep region/context and service metadata on the global path
- `UnityDownload`: proxy, to keep editor and module downloads on the global path
- `UnityChina`: `REJECT` by default, to block dedicated Unity China domains instead of silently falling back to them

## Install on Another Windows PC

1. Install Clash Verge Rev and open it once.
2. Import your subscription(s) normally.
3. Clone this repo or copy the folder to that machine.
4. Run:

```bat
install-steam-routing.bat
```

5. Restart Clash Verge Rev once, or switch subscriptions once.

## Quick Install from a Release

1. Download the latest release zip from the Releases page.
2. Extract it to any folder.
3. Double-click `install-steam-routing.bat`.
4. Restart Clash Verge Rev once, or switch subscriptions once.

You only need to download the package once. After that, keep using the same `install-steam-routing.bat`: it checks GitHub for newer releases before running the installer, downloads updates automatically when available, and falls back to a console prompt if the GitHub check times out.

## Recommended Defaults

- `UnityHub`: `Auto Select`, or a stable overseas node
- `UnityDownload`: use the same stable overseas node as `UnityHub`
- `UnityChina`: `REJECT`
- `SteamCommunity`: `Auto Select`, or a Hong Kong/Japan node
- `SteamMainland`: `DIRECT`
- `SteamDownload`: `DIRECT`

If Unity Hub still shows `Validation Failed`:

- make sure `UnityHub` and `UnityDownload` are not `DIRECT`
- prefer using the same stable overseas node for both
- run `test-unity-routing.bat` first
- if the script shows `302 -> download.unitychina.cn -> 404` on the direct path but `200` on the Clash proxy path, Unity is not entering Clash reliably enough; prefer `Rule mode + TUN enabled`
- if the Clash proxy path itself still returns `302` or `404`, that node is still being sent to the Unity China mirror even though it is an overseas node; switch `UnityHub` and `UnityDownload` together and test again
- if a node passes the `200/206` checks but large downloads still hit `ECONNRESET`, compare more nodes with the script instead of trusting the region label alone

If the Steam store shows `-100`, temporarily change `SteamMainland` from `DIRECT` to the same node as `SteamCommunity` and test again.

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
- `install-steam-routing.ps1`: one-shot installer for a new PC
- `sync-clash-verge-steam-script.ps1`: background watcher that rebinds remote subscriptions to `Script.js`
- `Start ClashVerge Steam Sync.vbs`: startup entry that launches the watcher hidden
- `test-unity-routing.bat`: one-click entrypoint for Unity 404/302/reset diagnosis
- `test-unity-routing.ps1`: Unity diagnostic script that compares direct vs proxied requests
- `VERSION`: local package version used by the auto-update comparison
- `Merge.yaml`: placeholder to satisfy the global merge card

## Safety Notes

- Do not commit `profiles.yaml`, provider subscription YAML files, or subscription URLs/tokens
- This public repo intentionally contains only the reusable routing framework, not your personal provider configs
- The installer does not copy your provider profiles; it only installs the shared routing layer

## License

MIT. See [LICENSE](LICENSE).
