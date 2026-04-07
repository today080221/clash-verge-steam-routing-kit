# Clash Verge Steam Routing Kit

Shared Steam routing for Clash Verge Rev on Windows, with an additional dedicated Unity Hub bypass group.

[![简体中文](https://img.shields.io/badge/简体中文-阅读-0366d6?style=for-the-badge)](README.md)
[![English](https://img.shields.io/badge/English-Current-2ea44f?style=for-the-badge)](README.en.md)

## Project Status

This repository is an AI-generated project.

The code, structure, and documentation were produced through AI-assisted generation and iteration. Please review the scripts before using them in your own environment.

It injects four reusable groups into any subscribed profile:

- `UnityHub`: Unity Hub, Unity sign-in and licensing, Package Manager, Asset Store, and related official Unity domains
- `SteamCommunity`: Steam community, chat, avatars, and other commonly blocked Steam web content
- `SteamMainland`: Steam store, login, help, and general Steam web traffic that usually works well from mainland China
- `SteamDownload`: Steam CDN, content servers, and download-related traffic

## What This Repo Solves

- Keeps Steam and Unity Hub routing logic in one place across multiple PCs
- Applies the same Steam and Unity Hub split-routing behavior across different service providers
- Rebinds newly added remote subscriptions to the shared `Script.js`
- Separates Steam community, store/login, and download traffic, plus a dedicated `UnityHub` group, so they can be tuned independently

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

- `UnityHub`: use `Auto Select` or a stable overseas node to fully bypass Unity China paths
- `SteamCommunity`: use `Auto Select` or a Hong Kong/Japan node
- `SteamMainland`: use `DIRECT` first
- `SteamDownload`: use `DIRECT`

If the Steam store shows `-100`, temporarily change `SteamMainland` from `DIRECT` to the same node as `SteamCommunity` and test again.

The current `UnityHub` group intentionally focuses on Unity-owned domains from Unity's official proxy exception guidance, including `unity.com`, `unity3d.com`, `plasticscm.com`, and `unitychina.cn`. This keeps Unity Hub sign-in, licensing, Package Manager, Asset Store, and Unity Version Control traffic together without broadly hijacking unrelated Google or Microsoft domains.

## Files

- `bootstrap-install.ps1`: auto-update bootstrap that checks GitHub releases, downloads newer packages, and hands off execution
- `AGENTS.md`: project-specific operating guidance for Codex and other agents
- `install-steam-routing.bat`: one-click installer entrypoint that checks for updates before each run
- `Script.js`: shared Clash Verge Rev profile script
- `install-steam-routing.ps1`: one-shot installer for a new PC
- `sync-clash-verge-steam-script.ps1`: background watcher that rebinds remote subscriptions to `Script.js`
- `Start ClashVerge Steam Sync.vbs`: startup entry that launches the watcher hidden
- `VERSION`: local package version used by the auto-update comparison
- `Merge.yaml`: placeholder to satisfy the global merge card

## Safety Notes

- Do not commit `profiles.yaml`, provider subscription YAML files, or subscription URLs/tokens
- This public repo intentionally contains only the reusable routing framework, not your personal provider configs
- The installer does not copy your provider profiles; it only installs the shared Steam routing framework

## License

MIT. See [LICENSE](LICENSE).
