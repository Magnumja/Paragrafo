#!/bin/zsh
set -eu
cd "$(dirname "$0")"
swift build -c release
APP="dist/Parágrafo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Brand/paragrafo-logo.png "$APP/Contents/Resources/"
cp Brand/Paragrafo.icns "$APP/Contents/Resources/"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/Paragrafo" "$APP/Contents/MacOS/Paragrafo"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Paragrafo</string>
<key>CFBundleIdentifier</key><string>app.paragrafo.mac</string>
<key>CFBundleIconFile</key><string>Paragrafo.icns</string>
<key>CFBundleName</key><string>Parágrafo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Documento PDF</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
</dict></array>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
VERSION="$(cat VERSION)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP"
print "Aplicativo criado em $APP"
