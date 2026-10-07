#!/bin/zsh
# 构建 红果短剧.app (自用, ad-hoc 签名, 免开发者账号)
# 产物: dist/Hongguo.app
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
APP=dist/Hongguo.app

rm -rf dist icon.iconset icon_1024.png
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 1) 图标: swift 画 1024px → sips 缩出 iconset → iconutil 打 icns
swift make_icon.swift icon_1024.png
mkdir -p icon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s icon_1024.png --out icon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) icon_1024.png --out icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# 2) 二进制
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/Hongguo" HongguoApp.swift

# 3) Info.plist
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>Hongguo</string>
  <key>CFBundleIdentifier</key><string>local.hongguo.desktop</string>
  <key>CFBundleName</key><string>红果短剧</string>
  <key>CFBundleDisplayName</key><string>红果短剧</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.0.3</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
</dict>
</plist>
PLIST

# 4) ad-hoc 签名(本机运行足够)
codesign --force -s - "$APP"

rm -rf icon.iconset icon_1024.png
echo "构建完成: $DIR/dist/Hongguo.app"
