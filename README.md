# Clash Verge Steam Routing Kit

面向 Windows 上 Clash Verge Rev 的共享分流工具包，专门处理 Steam 与 Unity Hub，并提供更强硬的 Unity 中国绕行方案。

[![简体中文](https://img.shields.io/badge/简体中文-当前-2ea44f?style=for-the-badge)](README.md)
[![English](https://img.shields.io/badge/English-Read-0366d6?style=for-the-badge)](README.en.md)

## 项目状态

这是一个 AI 生成项目。

本仓库的代码、结构和文档通过 AI 辅助生成与迭代完成。请在自己的环境中使用前先自行审阅脚本。

它会向任意 Clash Verge Rev 订阅注入 6 个可复用分组：

- `UnityHub`：Unity 全球控制面，负责登录、许可、版本清单、配置与服务网关
- `UnityDownload`：Unity 全球下载面，负责 Editor、模块与包下载链路
- `UnityChina`：Unity 中国链路隔离组，负责 `unity.cn`、`unitychina.cn`、`u3d.cn` 等中国专用域名
- `SteamCommunity`：Steam 社区、聊天、头像，以及其他常见被拦截的 Steam Web 内容
- `SteamMainland`：Steam 商店、登录、帮助，以及通常在中国大陆可正常访问的 Steam Web 流量
- `SteamDownload`：Steam CDN、内容服务器，以及下载相关流量

## 这个仓库解决什么问题

- 在多台电脑之间复用同一套 Steam 与 Unity Hub 分流逻辑
- 在不同服务商之间复用同一套规则，而不是反复手改订阅
- 自动把新接入的远程订阅重新绑定到共享 `Script.js`
- 把 Steam 社区、商店/登录、下载流量拆开分别调控
- 把 Unity 全球控制面、全球下载面、Unity 中国链路拆开分别调控

## 为什么要单独拆 UnityChina

Unity 官方面向全球的 Hub 与下载链路主要在 `unity.com`、`unity3d.com`、`public-cdn.cloud.unity3d.com`、`download.unity3d.com` 一侧，而 Unity 中国官方文档又明确存在单独的中国账号和中国包下载链路，例如 `upm-cdn-china.unitychina.cn`。

这意味着如果你的目标是“从地区识别到 CDN 分配都尽量避开 Unity 中国”，只把 `download.unitychina.cn` 代理掉还不够，必须把整类中国专用域名单独剥出来。当前版本的默认策略就是：

- `UnityHub`：走代理，负责把地区识别和服务上下文留在全球链路
- `UnityDownload`：走代理，负责把 Editor 和模块下载留在全球链路
- `UnityChina`：默认 `REJECT`，直接拦掉 Unity 中国专用域名，避免 Hub 回落到中国链路

## 在另一台 Windows 电脑上安装

1. 安装 Clash Verge Rev，并至少打开一次。
2. 正常导入你的订阅。
3. 克隆本仓库，或把整个目录复制到目标电脑。
4. 运行：

```bat
install-steam-routing.bat
```

5. 重启一次 Clash Verge Rev，或者切换一次订阅。

## 通过 Release 快速安装

1. 从 Releases 页面下载最新版本 zip。
2. 解压到任意目录。
3. 双击 `install-steam-routing.bat`。
4. 重启一次 Clash Verge Rev，或者切换一次订阅。

你只需要下载一次。之后继续运行同一个 `install-steam-routing.bat`，它会先检查 GitHub 上是否有新的 Release；如果有，就会自动下载并切换到新版本后再执行安装。若 GitHub 检查超时，会在控制台提示你是只执行一次本地脚本，还是直接退出。

## 推荐默认设置

- `UnityHub`：`自动选择`，或手动指定一个稳定的海外节点
- `UnityDownload`：和 `UnityHub` 使用同一个稳定海外节点，避免 Editor/模块下载又被分回中国链路
- `UnityChina`：`REJECT`
- `SteamCommunity`：`自动选择`，或手动指定香港/日本节点
- `SteamMainland`：`DIRECT`
- `SteamDownload`：`DIRECT`

如果 Unity Hub 仍然出现 `Validation Failed`：

- 先确认 `UnityHub` 与 `UnityDownload` 不是 `DIRECT`
- 尽量让 `UnityHub` 与 `UnityDownload` 使用同一个稳定海外节点
- 如果某个节点对 `public-cdn.cloud.unity3d.com` 或 `download.unity3d.com` 返回空响应，优先换日本、美国或新加坡节点

如果 Steam 商店出现 `-100` 错误，可以临时把 `SteamMainland` 从 `DIRECT` 改成和 `SteamCommunity` 相同的节点再测试。

## 文件说明

- `bootstrap-install.ps1`：自动更新启动器，负责检查 GitHub Release、下载新版本并切换执行
- `AGENTS.md`：面向 Codex 或其他 agent 的项目操作约定
- `install-steam-routing.bat`：面向 Release 用户的一键安装入口，每次运行都会先检查更新
- `Script.js`：共享的 Clash Verge Rev 配置脚本
- `install-steam-routing.ps1`：新电脑的一键安装脚本
- `sync-clash-verge-steam-script.ps1`：后台监听脚本，会把远程订阅重新绑定到 `Script.js`
- `Start ClashVerge Steam Sync.vbs`：开机启动入口，用于隐藏启动监听脚本
- `VERSION`：当前本地包版本号，供自动更新逻辑比较使用
- `Merge.yaml`：用于兼容全局 Merge 卡片的占位文件

## 安全说明

- 不要提交 `profiles.yaml`、服务商订阅 YAML，或者带 token 的订阅链接
- 这个公开仓库只包含可复用的分流框架，不包含你的个人服务商配置
- 安装脚本不会复制你的服务商订阅文件，它只安装共享分流层

## 许可证

MIT，详见 [LICENSE](LICENSE)。
