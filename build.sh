#!/bin/zsh
# 编译并打包成 GamepadMouse.app
set -e
cd "$(dirname "$0")"
APP=build/GamepadMouse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macos13 Sources/*.swift \
  -framework Cocoa -framework GameController \
  -o "$APP/Contents/MacOS/GamepadMouse"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.gamepadmouse</string>
  <key>CFBundleName</key><string>GamepadMouse</string>
  <key>CFBundleExecutable</key><string>GamepadMouse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier local.gamepadmouse "$APP"
echo "OK: $APP"

# ./build.sh --install：装到 ~/Applications 并重启
if [[ "$1" == "--install" ]]; then
  pkill -f GamepadMouse.app/Contents/MacOS/GamepadMouse || true
  rm -rf ~/Applications/GamepadMouse.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/GamepadMouse.app
  echo "已安装并启动 ~/Applications/GamepadMouse.app"
fi
