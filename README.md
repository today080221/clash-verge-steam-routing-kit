# Clash Verge Steam Routing Kit

面向 Windows 上 Clash Verge Rev 的共享分流工具包，处理 Steam、Unity、NVIDIA 与可选的 B 站视频 CDN，并提供更强硬的 Unity 中国绕行方案。

[![简体中文](https://img.shields.io/badge/简体中文-当前-2ea44f?style=for-the-badge)](README.md)
[![English](https://img.shields.io/badge/English-Read-0366d6?style=for-the-badge)](README.en.md)

## 项目状态

这是一个 AI 生成项目。

本仓库的代码、结构和文档通过 AI 辅助生成与迭代完成。请在自己的环境中使用前先自行审阅脚本。

它会向任意 Clash Verge Rev 订阅注入 12 个可复用分组：

- `UnityGlobal`：Unity 全球主分组，用来收敛 `UnityHub`、`UnityEditor`、`UnityDownload` 的默认出口
- `UnityWeb`：Unity 网页与账号分组，负责浏览器里的 Unity ID、Asset Store 和相关 Web API
- `UnityHub`：Unity 全球控制面，负责登录、许可、版本清单、配置与服务网关
- `UnityEditor`：Unity Editor 相关 API、包管理、分析与辅助云服务
- `UnityDownload`：Unity 全球下载面，负责 Editor、模块与包下载链路
- `UnityChina`：Unity 中国链路隔离组，负责 `unity.cn`、`unitychina.cn`、`u3d.cn` 等中国专用域名
- `NvidiaServices`：NVIDIA 网页、登录、控制面与其他官方服务流量
- `NvidiaDownload`：NVIDIA 驱动、NVIDIA App 与 OTA 包体下载流量，默认直连
- `SteamCommunity`：Steam 社区、聊天、头像，以及其他常见被拦截的 Steam Web 内容
- `SteamMainland`：Steam 商店、登录、帮助，以及通常在中国大陆可正常访问的 Steam Web 流量
- `SteamDownload`：Steam CDN、内容服务器，以及下载相关流量
- `BilibiliVideo`：可选的 B 站视频 CDN 分组，用来在网页播放器 6003、CDN/DNS 异常时单独切换视频链路

## 这个仓库解决什么问题

- 在多台电脑之间复用同一套 Steam、Unity 与 NVIDIA 分流逻辑
- 在不同服务商之间复用同一套规则，而不是反复手改订阅
- 自动把新接入的远程订阅重新绑定到共享 `Script.js`
- 把 Steam 社区、商店/登录、下载流量拆开分别调控
- 把 B 站网页播放器相关 CDN 从通用中国直连规则里单独剥出来，必要时只切视频链路
- 把 NVIDIA 服务流量与驱动/App 下载流量拆开，避免大文件下载被迫跟随登录或网页出口
- 把 Unity 全球控制面、全球下载面、Unity 中国链路拆开分别调控
- 让所有 Unity 全球相关分组都可以默认指向同一个 `UnityGlobal`，需要时再单独覆盖
- 把浏览器里的 Unity ID、Asset Store 和 Unity Hub / Editor 链路拆开分别调控

## 为什么要单独拆 UnityChina

Unity 官方面向全球的 Hub 与下载链路主要在 `unity.com`、`unity3d.com`、`public-cdn.cloud.unity3d.com`、`download.unity3d.com` 一侧，而 Unity 中国官方文档又明确存在单独的中国账号和中国包下载链路，例如 `upm-cdn-china.unitychina.cn`。

这意味着如果你的目标是“从地区识别到 CDN 分配都尽量避开 Unity 中国”，只把 `download.unitychina.cn` 代理掉还不够，必须把整类中国专用域名单独剥出来。当前版本的默认策略就是：

- `UnityGlobal`：走代理，作为 Unity 全球链路的统一上游组
- `UnityWeb`：默认指向 `UnityGlobal`，负责浏览器里的 Unity ID、Asset Store 与相关 Web API
- `UnityHub`：默认指向 `UnityGlobal`，负责把地区识别和服务上下文留在全球链路
- `UnityEditor`：默认指向 `UnityGlobal`，负责 Unity Editor 相关 API、包管理、分析与辅助云服务
- `UnityDownload`：默认指向 `UnityGlobal`，负责把 Editor 和模块下载留在全球链路
- `UnityChina`：默认 `REJECT`，直接拦掉 Unity 中国专用域名，避免 Hub 回落到中国链路

## 为什么要单独拆 NvidiaDownload

NVIDIA 驱动和 NVIDIA App 包体通常体积很大，而且 NVIDIA App 可能使用并发分段传输。NVIDIA 官方支持文档明确说明，代理或下载管理器可能影响文件传输并造成下载损坏；NVIDIA App 的官方安装入口也直接使用 `us.download.nvidia.com` 这类下载主机。

当前规则因此采用“服务与下载分离”的保守边界：

- `NvidiaServices`：接管更宽的 `nvidia.com` 与 `nvidia.cn` 官方服务域名，默认使用自动选择/代理，同时保留 `DIRECT`
- `NvidiaDownload`：以更高优先级接管 `*.download.nvidia.com` 与 `ota-downloads.nvidia.com`，默认 `DIRECT`，同时保留代理选项用于直连 CDN 异常时切换
- 不自动接管 GeForce NOW 等独立域名生态，避免把低延迟流媒体服务和驱动下载混为一组

参考：[NVIDIA 关于代理影响下载完整性的说明](https://nvidia.custhelp.com/app/answers/detail/a_id/21)；[NVIDIA App 官方下载页](https://www.nvidia.com/en-us/software/nvidia-app/)。

注意：Clash 规则只能控制已经进入 Clash 的连接。如果 Proxifier 又把 NVIDIA 进程单独送到另一个上游代理，仍可能形成双层代理；这时应让 NVIDIA 进程直接进入 Clash，或在 Proxifier 中对下载流量设为直连。

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
- `UnityWeb`：默认指向 `UnityGlobal`
- `UnityHub`：默认指向 `UnityGlobal`
- `UnityEditor`：默认指向 `UnityGlobal`
- `UnityDownload`：默认指向 `UnityGlobal`
- `UnityChina`：`REJECT`
- `NvidiaServices`：`自动选择`，或手动指定一个稳定节点；需要时可单独切 `DIRECT`
- `NvidiaDownload`：`DIRECT`；只有直连 CDN 异常时再切到稳定节点
- `SteamCommunity`：`自动选择`，或手动指定香港/日本节点
- `SteamMainland`：`DIRECT`
- `SteamDownload`：`DIRECT`
- `BilibiliVideo`：默认 `DIRECT`；如果网页播放器出现 6003、但开启系统代理/全局代理后恢复，就临时切到一个稳定节点

如果 Unity Hub 仍然出现 `Validation Failed`：

- 先确认 `UnityGlobal`、`UnityHub`、`UnityEditor`、`UnityDownload` 都不是 `DIRECT`
- 默认先把 `UnityHub`、`UnityEditor`、`UnityDownload` 都指向 `UnityGlobal`
- 如果需要单独覆盖，再只调整某一个 Unity 细分组
- 先运行 `test-unity-routing.bat` 做对照验证
- 如果脚本显示“直连链路是 `302 -> download.unitychina.cn -> 404`，但 Clash 代理链路是 `200`”，说明 Unity 请求没有稳定进 Clash，优先改成 `规则模式 + 开启 TUN`
- 如果脚本显示“Clash 代理链路本身仍然是 `302` 或 `404`”，说明当前节点虽然在海外，但 Unity 还是被分配到了中国镜像，直接换 `UnityHub`/`UnityDownload` 节点并重测
- 如果某个节点能通过 `200/206` 检查，但大文件中途 `ECONNRESET`，继续用脚本对比其他节点；不要只看地区名，先看真实 Unity 链路结果
- 如果你在活动连接里看到 `unity-connect-prd.storage.googleapis.com`、`config.uca.cloud.unity3d.com`、`api.hub-proxy.unity3d.com`、`unity-assetstorev2-prd.storage.googleapis.com` 之类的请求，它们现在会分别落到 `UnityEditor`、`UnityHub` 或 `UnityWeb`，不再被泛化的 `google` 规则抢走
- 如果 Unity Package Manager 能看到包列表，但下载 `.tgz` 包体经常卡住，先确认 `UnityEditor` 没有单独绑到别的节点，优先和 `UnityHub`、`UnityDownload` 一起指向 `UnityGlobal`
- 给 Unity 做代理时，最好额外用 Proxifier 之类的工具把 `Unity Hub.exe`、`Unity.exe` 和 `UnityPackageManager.exe` 强制 reroute 到 Clash Verge Rev 的本地代理，例如 `127.0.0.1:7897`
- 当前规则额外覆盖了 `storage.googleapis.com` 与兼容旧版 `upm-cdn.unity.com`，用来接住 Unity 官方文档里提到的 UPM 签名包文件与旧 CDN 域名
- 浏览器里的 `assetstore.unity.com`、`kharma.unity3d.com`、`unity-assetstorev2-prd.storage.googleapis.com`、`id.unity.com`、`login.unity.com` 和 `accounts.unity3d.com` 现在会单独走 `UnityWeb`
- 如果 UPM 仍然偶发不走 Clash，可按 Unity 官方代理文档给启动 Unity Hub / Editor 的进程注入 `HTTP_PROXY` 和 `HTTPS_PROXY`

如果 Steam 商店出现 `-100` 错误，可以临时把 `SteamMainland` 从 `DIRECT` 改成和 `SteamCommunity` 相同的节点再测试。

如果 NVIDIA App 驱动下载失败：

- 先确认 `NvidiaDownload` 仍为 `DIRECT`，再重新开始下载任务；`international-gfe.download.nvidia.com`、`us.download.nvidia.com` 等下载主机会优先命中这个组
- `NvidiaServices` 与下载组互不绑定，登录、版本信息或网页访问需要代理时，不必让大驱动包也经过同一个节点
- 如果同时使用系统代理和 Proxifier，避免再把 NVIDIA 进程送往第二个远端代理；让连接只经过一次 Clash 决策
- 如果运营商直连 CDN 本身很慢或失败，再把 `NvidiaDownload` 临时切到一个稳定节点，不需要改动整个 NVIDIA 服务出口

如果 B 站网页视频播放页出现错误码 `6003`：

- 先把 `BilibiliVideo` 从 `DIRECT` 改成一个已经验证可用的节点或自动选择组
- 这只会接管 `bilivideo.com` 与 `hdslb.com` 这类视频/静态 CDN，不会把所有 `bilibili.com` API 一起改走代理
- 如果切换后立刻恢复，问题通常在本地直连 DNS/CDN 分配或运营商链路，而不是浏览器硬件解码
- 如果仍然报错，再清一次页面缓存或打开无痕窗口测试，避免旧播放器请求继续复用失败连接

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
- `test-unity-routing.ps1`：Unity 诊断脚本，可对比直连/代理结果，并额外测试 Package Manager tarball 链路
- `VERSION`：当前本地包版本号，供自动更新逻辑比较使用
- `Merge.yaml`：用于兼容全局 Merge 卡片的占位文件

## 安全说明

- 不要提交 `profiles.yaml`、服务商订阅 YAML，或者带 token 的订阅链接
- 这个公开仓库只包含可复用的分流框架，不包含你的个人服务商配置
- 安装脚本不会复制你的服务商订阅文件，它只安装共享分流层

## 许可证

MIT，详见 [LICENSE](LICENSE)。
