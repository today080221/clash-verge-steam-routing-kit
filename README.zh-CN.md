# Clash Verge Steam Routing Kit

适用于 Windows 上 Clash Verge Rev 的共享 Steam 分流工具包。

[English](README.md)

## 项目状态

这是一个 AI 生成项目。

本仓库的代码、结构和文档均通过 AI 辅助生成与迭代完成。在你自己的环境中使用前，建议先自行审阅相关脚本。

它会向任意订阅配置中注入 3 个可复用的分组：

- `SteamCommunity`：Steam 社区、聊天、头像，以及其他常见会被拦截的 Steam Web 内容
- `SteamMainland`：Steam 商店、登录、帮助，以及通常在中国大陆可正常访问的 Steam Web 流量
- `SteamDownload`：Steam CDN、内容服务器，以及下载相关流量

## 这个仓库解决什么问题

- 在多台电脑之间复用同一套 Steam 分流逻辑
- 在不同服务商之间应用同样的 Steam 分流策略
- 自动把新接入的远程订阅重新绑定到共享 `Script.js`
- 将社区、商店/登录、下载流量拆开，方便分别调控

## 在另一台 Windows 电脑上安装

1. 安装 Clash Verge Rev，并至少打开一次。
2. 正常导入你的订阅。
3. 克隆本仓库，或把整个目录复制到目标机器。
4. 运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-steam-routing.ps1
```

5. 重启一次 Clash Verge Rev，或者切换一次订阅。

## 通过 Release 快速安装

1. 从 Releases 页面下载最新版本 zip。
2. 解压到任意目录。
3. 双击 `install-steam-routing.bat`。
4. 重启一次 Clash Verge Rev，或者切换一次订阅。

## 推荐默认设置

- `SteamCommunity`：使用 `自动选择`，或手动指定香港/日本节点
- `SteamMainland`：优先使用 `DIRECT`
- `SteamDownload`：使用 `DIRECT`

如果 Steam 商店出现 `-100` 错误，可以临时把 `SteamMainland` 从 `DIRECT` 改成和 `SteamCommunity` 相同的节点，再重新测试。

## 文件说明

- `install-steam-routing.bat`：面向 Release 用户的一键安装入口
- `Script.js`：共享的 Clash Verge Rev 配置脚本
- `install-steam-routing.ps1`：新电脑的一键安装脚本
- `sync-clash-verge-steam-script.ps1`：后台监控脚本，会把远程订阅重新绑定到 `Script.js`
- `Start ClashVerge Steam Sync.vbs`：开机启动入口，用于隐藏启动监控脚本
- `Merge.yaml`：用于兼容全局 Merge 卡片的占位文件

## 安全说明

- 不要把 `profiles.yaml`、服务商订阅 YAML，或者带 token 的订阅链接提交到仓库
- 这个公开仓库只包含可复用的分流框架，不包含你的个人服务商配置
- 安装脚本不会复制你的服务商订阅文件，它只安装共享的 Steam 分流框架

## 许可证

MIT，详见 [LICENSE](LICENSE)。
