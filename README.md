# Hongguo for Mac

红果短剧的**非官方** macOS 桌面客户端。原生 Swift 壳 + 本地后端，一键安装。

> **⚠️ 免责声明（务必阅读）**
> - 本项目与字节跳动 / 红果短剧官方**无任何关系**。"红果短剧"名称与全部内容版权归原权利方所有。
> - 本项目仅供个人学习研究，请勿用于商业用途，请勿二次分发打包产物。
> - 后端能力来自第三方公开仓库 [zhangbaio/hongguo](https://github.com/zhangbaio/hongguo)（安装时拉取，本仓库**不分发**其文件与字节系二进制）。
> - 接口与内容可用性取决于第三方服务，**随时可能失效**；使用产生的全部风险由使用者自担。如收到权利方投诉，本项目将配合处理。

## 功能

- 发现页：分类筛选、热播榜、真人剧 / 漫剧 / AI 剧上新
- 搜索、详情（评分 / 播放量 / 简介 / 选集）
- 播放：选集、倍速（0.75–2x）、自动连播、续播、进度拖动
- 本机收藏与观看历史（不与任何账号同步，仅存本机）
- 原生 App：独立窗口 + Dock 图标，退出即自动收掉后端服务

## 一键安装

**要求**：macOS 13+（Apple Silicon 或 Intel），**不需要** Homebrew / 开发者工具（构建产物可直接下载；若需本地构建才要 `xcode-select --install`）。

1. 到 [Releases](../../releases) 下载 `setup_mac.command`
2. 右键该文件 → **打开**（首次需此操作绕过 Gatekeeper；或在终端执行 `bash setup_mac.command`）
3. 等待完成（首次约 3–5 分钟：拉取上游后端、下载 JRE、装 Python 依赖），结束后自动打开 App

安装脚本只做组装，不做任何隐藏动作，源码就在 `scripts/` 里，装什么一清二楚：

| 步骤 | 内容 |
|---|---|
| 1 | 拉取本仓库（补丁 / UI / 壳源码） |
| 2 | 克隆上游后端 `zhangbaio/hongguo`（锁定 commit `5f8a58d10f`） |
| 3 | 组装 `~/hongguo-mac/run`（后端 + 签名服务） |
| 4 | 下载 Temurin JRE 17（Adoptium 官方源） |
| 5 | Python venv + 依赖（fastapi / uvicorn / pycryptodome / pillow） |
| 6 | 应用 mac 适配补丁（3 处小改动，见 `scripts/patches/`） |
| 7 | 获取 Hongguo.app（优先 Release 产物，失败则本地 swiftc 构建） |

## 卸载

```bash
rm -rf ~/hongguo-mac ~/Applications/Hongguo.app /Applications/Hongguo.app
rm -rf ~/Library/Caches/local.hongguo.desktop ~/Library/WebKit/local.hongguo.desktop 2>/dev/null
```

## 架构

```
Hongguo.app (SwiftUI + WKWebView, 本仓库)
   │  启动/退出时管理下面两个本地服务
   ▼
FastAPI 后端 :8010 ── /search /rank /latest /episodes /stream …   ← 上游 zhangbaio/hongguo
   │  取签名                                                        (安装时拉取, 锁 commit)
   ▼
unidbg 签名服务 :9099 → 红果 / fqnovel 接口
   ▼
/stream: 视频在本地解密后以标准 mp4 串流 (支持 Range 拖动)
```

本仓库自有代码 = `app/`（Swift 壳）、`web/`（界面）、`scripts/`（安装与补丁）、CI 配置。
上游代码与字节系二进制**不由本仓库分发**，仅安装时从其原始公开位置获取。

## 手动构建壳 App

```bash
xcode-select --install   # 如未装命令行工具
cd app && bash build.sh  # 产物 app/dist/Hongguo.app
```

## License

- 本仓库自有代码：[MIT](LICENSE)
- 上游引用与运行时组件：见 [NOTICE.md](NOTICE.md)
