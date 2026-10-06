# NOTICE — 第三方组件与引用说明

本仓库（hongguo-mac）自有代码仅指 `app/`、`web/`、`scripts/`、`.github/` 下的内容（MIT，见 LICENSE）。
运行时引用或安装期获取的第三方组件如下，均保留其原有许可，本仓库不对其再分发或重新授权。

## 安装期从其原始公开位置获取（不由本仓库分发）

| 组件 | 来源 | 许可 | 说明 |
|---|---|---|---|
| 上游后端（server.py、hongguo.py、解密链等） | [zhangbaio/hongguo](https://github.com/zhangbaio/hongguo) @ commit `5f8a58d10f` | 该仓库未声明许可，版权归其作者 | 仅安装脚本按其公开状态引用；本仓库对其做的修改见 `scripts/patches/` |
| unidbg-sign.jar（签名服务） | 同上仓库内 `windows-package-src/sign/` | 见上游仓库声明 | 运行时加载 |
| capture/fq_oversea/（签名资源） | 同上仓库内 | 版权归原权利方 | 运行时加载 |

## 安装脚本自动下载的运行时

| 组件 | 来源 | 许可 |
|---|---|---|
| Temurin JRE 17 | [Adoptium](https://adoptium.net) | GPLv2 with Classpath Exception |
| Python 包：fastapi / uvicorn / requests / pycryptodome / pillow / pillow-heif | PyPI | MIT / BSD / Apache-2.0 等各自许可 |
| unidbg / Unicorn2（含于上述 jar 内） | [zhkl0228/unidbg](https://github.com/zhkl0228/unidbg) | Apache-2.0（Unicorn 部分遵循其上游许可） |

## 其他说明

- `config.json` 中的游客态设备参数取自上游公开源码（unidbg-sign 的 FqTrace 测试参数），非本仓库原创，亦不含任何账号凭证。
- 本项目名称与界面中的"红果短剧"字样及自绘图标均为描述性使用，用于说明适配对象；本项目为个人自研的第三方适配版本，与"红果短剧"官方无关联。
- 本项目仅供学习研究；如权利方认为任何内容侵权，请提出，将配合移除。
