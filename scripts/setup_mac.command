#!/bin/bash
# =====================================================================
# Hongguo for Mac — 一键安装脚本
# 用法: 双击本文件(首次需右键→打开以绕过 Gatekeeper), 或在终端执行。
# 功能: 自动完成全部安装 —— 拉取上游后端、下载 JRE、装 Python 依赖、
#       构建本壳 App, 装完直接打开。
# 安装位置: $HONGGUO_HOME (默认 ~/hongguo-mac)
# 说明: 本脚本只组装公开组件; 上游后端来自 github.com/zhangbaio/hongguo
#       (锁定 commit, 见 UPSTREAM_SHA), 本仓库不再分发其文件。
# =====================================================================
set -u

UPSTREAM_REPO="zhangbaio/hongguo"
UPSTREAM_FALLBACK="zerozhh/hongguo"   # 本人公开 fork, 作为上游备份源
UPSTREAM_SHA="5f8a58d10f"
ORIGIN_REPO="${HONGGUO_REPO:-zerozhh/hongguo-mac}"
ROOT="${HONGGUO_HOME:-$HOME/hongguo-mac}"

say()  { printf '\033[1;35m[安装]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[跳过/警告]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[失败]\033[0m %s\n' "$*" >&2; exit 1; }

ARCH=$(uname -m)   # arm64 或 x86_64
say "Hongguo for Mac 安装开始 (架构: $ARCH)"
say "安装目录: $ROOT"

# ---------- 0. 基础命令检查 ----------
for c in git python3 curl patch tar; do
  command -v "$c" >/dev/null 2>&1 || die "缺少命令 $c 。请先在终端执行: xcode-select --install 安装命令行工具后重试。"
done

# ---------- 1. 定位本仓库文件(补丁/UI/壳源码) ----------
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
if [ -f "$SCRIPT_DIR/../web/app.html" ]; then
  REPO_DIR="$SCRIPT_DIR/.."
  say "使用脚本所在仓库: $REPO_DIR"
else
  REPO_DIR="$ROOT/repo"
  if [ ! -f "$REPO_DIR/web/app.html" ]; then
    say "下载本仓库 ($ORIGIN_REPO) ..."
    mkdir -p "$ROOT"
    curl -fsSL "https://github.com/$ORIGIN_REPO/archive/refs/heads/main.tar.gz" | tar xz -C "$ROOT" || die "仓库下载失败, 检查网络"
    rm -rf "$REPO_DIR"; mv "$ROOT/hongguo-mac-main" "$REPO_DIR"
  fi
  say "仓库文件: $REPO_DIR"
fi

# ---------- 2. 拉取上游后端(锁定 commit; 多源回退) ----------
UP="$ROOT/upstream"
if [ -f "$UP/hongguo.py" ]; then
  say "上游后端已存在: $UP (如需重拉请删除该目录)"
else
  ok=""
  for src in "https://github.com/$UPSTREAM_REPO.git" "https://github.com/$UPSTREAM_FALLBACK.git"; do
    say "克隆上游后端: $src (约 250MB, 一次性) ..."
    if git clone --depth 1 -q "$src" "$UP"; then ok=1; break; fi
    warn "该源克隆失败, 尝试备用源 ..."
    rm -rf "$UP"
  done
  [ -n "$ok" ] || die "所有上游源均克隆失败, 请检查网络后重试"
fi
CUR_SHA="$(git -C "$UP" rev-parse --short=10 HEAD 2>/dev/null || echo '?')"
if [ "$CUR_SHA" != "$UPSTREAM_SHA" ]; then
  warn "上游 HEAD ($CUR_SHA) 与锁定版本不同, 尝试切到 $UPSTREAM_SHA"
  git -C "$UP" fetch --depth 1 -q origin "$UPSTREAM_SHA" && git -C "$UP" checkout -q "$UPSTREAM_SHA" \
    && say "已锁定上游 commit $UPSTREAM_SHA" || warn "锁定失败, 继续用 HEAD($CUR_SHA), 补丁可能不匹配"
fi

# ---------- 3. 组装运行目录 ----------
RUN="$ROOT/run"
say "组装运行目录 ..."
mkdir -p "$RUN/sign" "$RUN/capture" "$RUN/app/web" "$RUN/app/downloads"
cp "$UP/windows-package-src/sign/unidbg-sign.jar" "$RUN/sign/" || die "签名 jar 复制失败"
rm -rf "$RUN/capture/fq_oversea"
cp -R "$UP/windows-package-src/capture/fq_oversea" "$RUN/capture/" || die "签名资源复制失败"
for f in server.py hongguo.py offline_dl.py apikeys.py safeguards.py downloader.py devicepool.py; do
  cp "$UP/$f" "$RUN/app/" || die "缺少上游文件 $f"
done
rm -rf "$RUN/app/frida"; cp -R "$UP/frida" "$RUN/app/frida"
cp "$UP/web/index.html" "$RUN/app/web/index.html" 2>/dev/null || true
cp "$REPO_DIR/web/app.html" "$RUN/app/web/app.html" || die "UI 复制失败"

say "应用 mac 适配补丁 ..."
say "应用 mac 适配补丁 ..."
for p in server-mac hongguo-mac; do
  ( cd "$RUN/app" && patch -p1 -s < "$REPO_DIR/scripts/patches/$p.patch" ) \
    && say "$p 补丁应用成功" || warn "$p 补丁未能完全应用(上游可能已更新), 功能可能受影响"
done

# ---------- 4. JRE 17 (Temurin, 免 Homebrew) ----------
# Adoptium API 架构命名: aarch64/x64 (macOS uname 是 arm64/x86_64, 需映射)
case "$ARCH" in
  arm64)  API_ARCH="aarch64" ;;
  x86_64) API_ARCH="x64" ;;
  *) die "不支持的架构: $ARCH" ;;
esac
if [ -x "$ROOT/jre/Contents/Home/bin/java" ]; then
  say "JRE 已存在: $ROOT/jre"
else
  say "下载 Temurin JRE 17 ($API_ARCH) ..."
  mkdir -p "$ROOT/jre"
  curl -fsSL "https://api.adoptium.net/v3/binary/latest/17/ga/mac/$API_ARCH/jre/hotspot/normal/eclipse" \
    -o "$ROOT/jre.tar.gz" || die "JRE 下载失败"
  tar xzf "$ROOT/jre.tar.gz" -C "$ROOT/jre" --strip-components=1 && rm -f "$ROOT/jre.tar.gz" \
    || die "JRE 解压失败"
  say "JRE 就绪: $("$ROOT/jre/Contents/Home/bin/java" -version 2>&1 | head -1)"
fi

# ---------- 5. Python 依赖 ----------
if [ -x "$RUN/venv/bin/python" ] && "$RUN/venv/bin/python" -c "import fastapi, uvicorn, Crypto, PIL" 2>/dev/null; then
  say "Python 依赖已就绪"
else
  say "创建虚拟环境并安装依赖 (fastapi/uvicorn/pycryptodome/pillow) ..."
  python3 -m venv "$RUN/venv" || die "venv 创建失败"
  "$RUN/venv/bin/pip" install -q --upgrade pip
  "$RUN/venv/bin/pip" install -q requests fastapi "uvicorn[standard]" pycryptodome pillow pillow-heif \
    || die "依赖安装失败"
fi

# ---------- 6. 生成 config.json (游客态设备参数) ----------
if [ ! -f "$RUN/app/config.json" ]; then
  say "生成 config.json (游客态参数, 与上游公开源码中的测试参数一致)"
  cat > "$RUN/app/config.json" <<'CFG'
{
  "_说明": "游客态设备参数, 取自上游公开源码(unidbg-sign FqTrace)中的测试设备; 若日后被风控, 请用自己的安卓设备抓包替换(extract_config.py)",
  "api_host": "api5-normal-sinfonlinea.fqnovel.com",
  "base_query": {
    "iid": "4223674528611611",
    "device_id": "4223674528607515",
    "aid": "8662",
    "app_name": "novelread",
    "version_code": "72232",
    "version_name": "7.2.2.32",
    "channel": "google_market",
    "device_platform": "android",
    "device_type": "Pixel 5",
    "device_brand": "Google",
    "os_version": "12",
    "os_api": "31",
    "update_version_code": "72232",
    "manifest_version_code": "72232",
    "resolution": "1080*2340",
    "dpi": "440",
    "language": "zh",
    "rom_version": "12",
    "cdid": "8f7c33a2-1f4b-4c6a-9d2e-5b8a7c1e3f90",
    "klink_egdi": "0"
  },
  "session_headers": {
    "user-agent": "com.phoenix.read/72232 (Linux; U; Android 12; zh_CN; Pixel 5; Build/SQ3A.220705.004; tt-ok/3.12.13.20)",
    "x-tt-store-region": "cn-sh",
    "x-tt-store-region-src": "uid",
    "passport-sdk-version": "5051452",
    "sdk-version": "2"
  }
}
CFG
fi

# ---------- 7. 壳 App: 优先下载 Release 产物, 失败则本地构建 ----------
if [ ! -d "$ROOT/Hongguo.app" ]; then
  say "下载已构建的 Hongguo.app ..."
  if curl -fsSL "https://github.com/$ORIGIN_REPO/releases/latest/download/Hongguo.app.zip" -o "$ROOT/app.zip" 2>/dev/null; then
    unzip -q "$ROOT/app.zip" -d "$ROOT" && rm -f "$ROOT/app.zip" || true
  fi
  if [ ! -d "$ROOT/Hongguo.app" ]; then
    if command -v swiftc >/dev/null 2>&1; then
      say "没有可用产物, 改为本地构建 (需要几秒) ..."
      ( cd "$REPO_DIR/app" && bash build.sh ) || die "本地构建失败"
      cp -R "$REPO_DIR/app/dist/Hongguo.app" "$ROOT/" || die "产物复制失败"
    else
      die "无法获取 Hongguo.app (下载失败且未安装 swiftc)。请安装 Xcode 命令行工具: xcode-select --install 后重跑。"
    fi
  fi
else
  say "Hongguo.app 已存在: $ROOT/Hongguo.app"
fi
# ad-hoc 签名产物无公证, 主动清掉隔离属性, 免去"右键打开"
xattr -dr com.apple.quarantine "$ROOT/Hongguo.app" 2>/dev/null || true

# ---------- 8. 完成 ----------
say "✅ 安装完成: $ROOT"
say "打开 App ..."
open "$ROOT/Hongguo.app"
say "提示: App 会自动拉起后端并打开主界面; 退出 App 即同时退出后端服务。"
