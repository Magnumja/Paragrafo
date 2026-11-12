#!/bin/zsh
set -eu
cd "$(dirname "$0")"
swift build -c release
APP="dist/Parágrafo.app"
mkdir -p "$APP/Contents/MacOS"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/Paragrafo" "$APP/Contents/MacOS/Paragrafo"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Paragrafo</string>
<key>CFBundleIdentifier</key><string>app.paragrafo.mac</string>
<key>CFBundleName</key><string>Parágrafo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
print "Aplicativo criado em $APP"
