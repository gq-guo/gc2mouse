#!/bin/zsh
# 编译并打包成 gc2mouse.app
# ./build.sh --install：装到 ~/Applications 并重启
set -e
cd "$(dirname "$0")"
APP=build/gc2mouse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos13 Sources/*.swift \
  -framework Cocoa -framework GameController \
  -o "$APP/Contents/MacOS/gc2mouse"
[[ -f Resources/AppIcon.icns ]] || ./Icon/make_icns.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.gc2mouse</string>
  <key>CFBundleName</key><string>gc2mouse</string>
  <key>CFBundleDisplayName</key><string>gc2mouse</string>
  <key>CFBundleExecutable</key><string>gc2mouse</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier local.gc2mouse "$APP"
echo "OK: $APP"

if [[ "$1" == "--install" ]]; then
  pkill -f "gc2mouse.app/Contents/MacOS/gc2mouse" || true
  # 旧版本名为 GamepadMouse，一并停掉并移除
  pkill -f "GamepadMouse.app/Contents/MacOS/GamepadMouse" || true
  rm -rf ~/Applications/GamepadMouse.app ~/Applications/gc2mouse.app
  cp -R "$APP" ~/Applications/
  touch ~/Applications/gc2mouse.app   # 让访达刷新图标
  open ~/Applications/gc2mouse.app
  echo "已安装并启动 ~/Applications/gc2mouse.app"
fi
