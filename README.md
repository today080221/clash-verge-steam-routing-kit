# Clash Verge Steam Routing Kit

面向 Windows 上 Clash Verge Rev 的共享分流工具包，专门处理 Steam 与 Unity Hub，并提供更强硬的 Unity 中国绕行方案。

[![简体中文](https://img.shields.io/badge/简体中文-当前-2ea44f?style=for-the-badge)](README.md)
[![English](https://img.shields.io/badge/English-Read-0366d6?style=for-the-badge)](README.en.md)

## 项目状态

这是一个 AI 生成项目。

本仓库的代码、结构和文档通过 AI 辅助生成与迭代完成。请在自己的环境中使用前先自行审阅脚本。

它会向任意 Clash Verge Rev 订阅注入 8 个可复用分组：

- `UnityGlobal`：Unity 全球主分组，用来收敛 `UnityHub`、`UnityEditor`、`UnityDownload` 的默认出口
- `UnityHub`：Unity 全球控制面，负责登录、许可、版本清单、配置与服务网关
- `UnityEditor`：Unity Editor 相关 API、包管理、Asset Store、分析与辅助云服务
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
- 让所有 Unity 全球相关分组都可以默认指向同一个 `UnityGlobal`，需要时再单独覆盖

## 为什么要单独拆 UnityChina

Unity 官方面向全球的 Hub 与下载链路主要在 `unity.com`、`unity3d.com`、`public-cdn.cloud.unity3d.com`、`download.unity3d.com` 一侧，而 Unity 中国官方文档又明确存在单独的中国账号和中国包下载链路，例如 `upm-cdn-china.unitychina.cn`。

这意味着如果你的目标是“从地区识别到 CDN 分配都尽量避开 Unity 中国”，只把 `download.unitychina.cn` 代理掉还不够，必须把整类中国专用域名单独剥出来。当前版本的默认策略就是：

- `UnityGlobal`：走代理，作为 Unity 全球链路的统一上游组
- `UnityHub`：默认指向 `UnityGlobal`，负责把地区识别和服务上下文留在全球链路
- `UnityEditor`：默认指向 `UnityGlobal`，负责 Unity Editor 相关 API、包管理、Asset Store、分析与辅助云服务
- `UnityDownload`：默认指向 `UnityGlobal`，负责把 Editor 和模块下载留在全球链路
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

- `UnityGlobal`：`自动选择`，或手动指定一个稳定的海外节点
- `UnityHub`：默认指向 `UnityGlobal`
- `UnityEditor`：默认指向 `UnityGlobal`
- `UnityDownload`：默认指向 `UnityGlobal`
- `UnityChina`：`REJECT`
- `SteamCommunity`：`自动选择`，或手动指定香港/日本节点
- `SteamMainland`：`DIRECT`
- `SteamDownload`：`DIRECT`

如果 Unity Hub 仍然出现 `Validation Failed`：

- 先确认 `UnityGlobal`、`UnityHub`、`UnityEditor`、`UnityDownload` 都不是 `DIRECT`
- 默认先把 `UnityHub`、`UnityEditor`、`UnityDownload` 都指向 `UnityGlobal`
- 如果需要单独覆盖，再只调整某一个 Unity 细分组
- 先运行 `test-unity-routing.bat` 做对照验证
- 如果脚本显示“直连链路是 `302 -> download.unitychina.cn -> 404`，但 Clash 代理链路是 `200`”，说明 Unity 请求没有稳定进 Clash，优先改成 `规则模式 + 开启 TUN`
- 如果脚本显示“Clash 代理链路本身仍然是 `302` 或 `404`”，说明当前节点虽然在海外，但 Unity 还是被分配到了中国镜像，直接换 `UnityHub`/`UnityDownload` 节点并重测
- 如果某个节点能通过 `200/206` 检查，但大文件中途 `ECONNRESET`，继续用脚本对比其他节点；不要只看地区名，先看真实 Unity 链路结果
- 如果你在活动连接里看到 `unity-connect-prd.storage.googleapis.com`、`config.uca.cloud.unity3d.com`、`api.hub-proxy.unity3d.com` 之类的请求，它们现在会分别落到 `UnityEditor` 或 `UnityHub`，不再被泛化的 `google` 规则抢走

如果 Steam 商店出现 `-100` 错误，可以临时把 `SteamMainland` 从 `DIRECT` 改成和 `SteamCommunity` 相同的节点再测试。

用于 Unity 404/302/掉线排查的推荐命令：

```bat
test-unity-routing.bat
```

它会直接对照当前配置下的“直连”和“Clash 代理”结果。切到别的 `UnityHub`/`UnityDownload` 节点后，再重新运行一次，就能继续做人工对照。

## 文件说明

- `bootstrap-install.ps1`：自动更新启动器，负责检查 GitHub Release、下载新版本并切换执行
- `AGENTS.md`：面向 Codex 或其他 agent 的项目操作约定
- `install-steam-routing.bat`：面向 Release 用户的一键安装入口，每次运行都会先检查更新
- `Script.js`：共享的 Clash Verge Rev 配置脚本
- `install-steam-routing.ps1`：新电脑的一键安装脚本
- `sync-clash-verge-steam-script.ps1`：后台监听脚本，会把远程订阅重新绑定到 `Script.js`
- `Start ClashVerge Steam Sync.vbs`：开机启动入口，用于隐藏启动监听脚本
- `test-unity-routing.bat`：Unity 下载 404/302/掉线的一键排查入口
- `test-unity-routing.ps1`：Unity 诊断脚本，可对比直连/代理结果
- `VERSION`：当前本地包版本号，供自动更新逻辑比较使用
- `Merge.yaml`：用于兼容全局 Merge 卡片的占位文件

## 安全说明

- 不要提交 `profiles.yaml`、服务商订阅 YAML，或者带 token 的订阅链接
- 这个公开仓库只包含可复用的分流框架，不包含你的个人服务商配置
- 安装脚本不会复制你的服务商订阅文件，它只安装共享分流层

## 许可证

MIT，详见 [LICENSE](LICENSE)。
