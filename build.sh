#!/bin/bash
set -e
cd "$(dirname "$0")"
APP=FontReview

swiftc -parse-as-library -O $APP.swift -o $APP

rm -rf $APP.app
mkdir -p $APP.app/Contents/MacOS $APP.app/Contents/Resources
mv $APP $APP.app/Contents/MacOS/

ICON_XML=""

# Icon Composer icon (light/dark/clear/tinted, macOS 26): FontReview.icon
if [ -d $APP.icon ]; then
  rm -rf icon_build && mkdir icon_build
  xcrun actool $APP.icon --compile icon_build \
    --output-format human-readable-text --notices --warnings --errors \
    --output-partial-info-plist icon_build/partial.plist \
    --app-icon $APP --include-all-app-icons \
    --target-device mac --minimum-deployment-target 26.0 --platform macosx
  cp icon_build/Assets.car $APP.app/Contents/Resources/
  ICON_XML="<key>CFBundleIconName</key><string>$APP</string>"
  rm -rf icon_build
fi

# Fallback / older macOS: plain icon.png (square, 1024x1024)
if [ -f icon.png ]; then
  rm -rf AppIcon.iconset && mkdir AppIcon.iconset
  for s in 16 32 128 256 512; do
    sips -z $s $s icon.png --out AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) icon.png --out AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns AppIcon.iconset -o $APP.app/Contents/Resources/AppIcon.icns
  rm -rf AppIcon.iconset
fi

cat > $APP.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP</string>
<key>CFBundleIdentifier</key><string>dev.nelio.$APP</string>
<key>CFBundleName</key><string>$APP</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
$ICON_XML
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

codesign --force --deep --sign - $APP.app

rm -rf dmg $APP.dmg && mkdir dmg
cp -R $APP.app dmg/
ln -s /Applications dmg/Applications
hdiutil create -volname $APP -srcfolder dmg -ov -format UDZO $APP.dmg
rm -rf dmg
echo "Done: $APP.dmg"
