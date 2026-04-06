# Clash Verge Steam Routing Kit

Shared Steam routing for Clash Verge Rev on Windows.

[简体中文](README.zh-CN.md)

## Project Status

This repository is an AI-generated project.

The code, structure, and documentation were produced through AI-assisted generation and iteration. Please review the scripts before using them in your own environment.

It injects three reusable groups into any subscribed profile:

- `SteamCommunity`: Steam community, chat, avatars, and other commonly blocked Steam web content
- `SteamMainland`: Steam store, login, help, and general Steam web traffic that usually works well from mainland China
- `SteamDownload`: Steam CDN, content servers, and download-related traffic

## What This Repo Solves

- Keeps Steam routing logic in one place across multiple PCs
- Applies the same Steam split-routing behavior across different service providers
- Rebinds newly added remote subscriptions to the shared `Script.js`
- Separates community, store/login, and download traffic so they can be tuned independently

## Install on Another Windows PC

1. Install Clash Verge Rev and open it once.
2. Import your subscription(s) normally.
3. Clone this repo or copy the folder to that machine.
4. Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-steam-routing.ps1
```

5. Restart Clash Verge Rev once, or switch subscriptions once.

## Recommended Defaults

- `SteamCommunity`: use `Auto Select` or a Hong Kong/Japan node
- `SteamMainland`: use `DIRECT` first
- `SteamDownload`: use `DIRECT`

If the Steam store shows `-100`, temporarily change `SteamMainland` from `DIRECT` to the same node as `SteamCommunity` and test again.

## Files

- `Script.js`: shared Clash Verge Rev profile script
- `install-steam-routing.ps1`: one-shot installer for a new PC
- `sync-clash-verge-steam-script.ps1`: background watcher that rebinds remote subscriptions to `Script.js`
- `Start ClashVerge Steam Sync.vbs`: startup entry that launches the watcher hidden
- `Merge.yaml`: placeholder to satisfy the global merge card

## Safety Notes

- Do not commit `profiles.yaml`, provider subscription YAML files, or subscription URLs/tokens
- This public repo intentionally contains only the reusable routing framework, not your personal provider configs
- The installer does not copy your provider profiles; it only installs the shared Steam routing framework

## License

MIT. See [LICENSE](LICENSE).
