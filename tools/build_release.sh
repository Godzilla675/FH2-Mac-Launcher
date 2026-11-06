#!/bin/bash
# Packages the native macOS SwiftUI installer and launcher app ("Forza Horizon 2.app")
# inside a clean drag-to-install DMG ("Forza-Horizon-2-Mac-Installer.dmg" / "Forza-Horizon-2-Setup.dmg")
# and ZIP ("Forza-Horizon-2-Mac-App.zip").
#
# Usage: tools/build_release.sh [version]
set -euo pipefail

VERSION="${1:-1.1.0}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
APP_NAME="Forza Horizon 2.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
MIN_MACOS="14.0"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

echo "==> [1/7] Compiling d3d12.dll, fh2pad.dll, and noop.exe with mingw-w64..."
make -C "$REPO_ROOT" clean
make -C "$REPO_ROOT" all

for bin in d3d12.dll fh2pad.dll noop.exe; do
    if [ ! -f "$REPO_ROOT/build/$bin" ]; then
        echo "ERROR: $REPO_ROOT/build/$bin was not built!" >&2
        exit 1
    fi
done

echo "==> [2/7] Preparing Forza Horizon 2.app bundle structure & bundling macOS static 7zz..."
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/bin"
mkdir -p "$APP_BUNDLE/Contents/Resources/payload/layer"
mkdir -p "$APP_BUNDLE/Contents/Resources/payload/azimuth"
mkdir -p "$APP_BUNDLE/Contents/Resources/payload/azimuth-0.9.10"
mkdir -p "$APP_BUNDLE/Contents/Resources/payload/azimuth-1.0.1"
mkdir -p "$APP_BUNDLE/Contents/Resources/payload/extra_options"

SEVENZIP_TAR="$SCRATCH/7z-mac.tar.xz"
if curl -fsSL --retry 3 "https://github.com/ip7z/7zip/releases/download/26.05/7z2605-mac.tar.xz" -o "$SEVENZIP_TAR" || \
   curl -fsSL --retry 3 "https://www.7-zip.org/a/7z2605-mac.tar.xz" -o "$SEVENZIP_TAR"; then
    mkdir -p "$SCRATCH/7z_mac"
    tar -xJf "$SEVENZIP_TAR" -C "$SCRATCH/7z_mac"
    cp "$SCRATCH/7z_mac/7zz" "$APP_BUNDLE/Contents/Resources/bin/7zz"
else
    cp "$(command -v 7zz)" "$APP_BUNDLE/Contents/Resources/bin/7zz"
fi
chmod +x "$APP_BUNDLE/Contents/Resources/bin/7zz"

cp "$REPO_ROOT/manifest.json" "$APP_BUNDLE/Contents/Resources/manifest.json"

echo "==> [3/7] Compiling native SwiftUI macOS executable (FH2Launcher)..."
swiftc -O \
    -parse-as-library \
    -target "arm64-apple-macos$MIN_MACOS" \
    -framework SwiftUI \
    -framework AppKit \
    -framework GameController \
    -framework Combine \
    -o "$APP_BUNDLE/Contents/MacOS/FH2Launcher" \
    "$REPO_ROOT/app/FH2Launcher.swift"

echo "==> [4/7] Extracting Microsoft d3dcompiler_47.dll & ExtraOptions..."
FF_EXE="$SCRATCH/FirefoxSetup62.exe"
curl -fsSL --retry 3 \
    "https://ftp.mozilla.org/pub/firefox/releases/62.0/win64/en-US/Firefox%20Setup%2062.0.exe" \
    -o "$FF_EXE"
7z e -y "$FF_EXE" "core/d3dcompiler_47.dll" -o"$APP_BUNDLE/Contents/Resources/payload/layer" >/dev/null

cp "$REPO_ROOT/build/d3d12.dll" "$REPO_ROOT/build/fh2pad.dll" "$REPO_ROOT/build/noop.exe" "$APP_BUNDLE/Contents/Resources/payload/layer/"

# Bundle Azimuth 0.9.10 (default) and 1.0.1
cp -R "$REPO_ROOT/payload/azimuth-0.9.10/"* "$APP_BUNDLE/Contents/Resources/payload/azimuth-0.9.10/"
cp -R "$REPO_ROOT/payload/azimuth-0.9.10/"* "$APP_BUNDLE/Contents/Resources/payload/azimuth/"
cp -R "$REPO_ROOT/payload/azimuth-1.0.1/"* "$APP_BUNDLE/Contents/Resources/payload/azimuth-1.0.1/"

# Bundle ExtraOptions (already staged in repo payload/extra_options, or refreshed from latest GitHub release)
if [ -d "$REPO_ROOT/payload/extra_options" ] && [ -f "$REPO_ROOT/payload/extra_options/winmm.dll" ]; then
    cp -R "$REPO_ROOT/payload/extra_options/"* "$APP_BUNDLE/Contents/Resources/payload/extra_options/"
else
    EO_ZIP="$SCRATCH/extra_options.zip"
    EO_URL=$(curl -fsSL https://api.github.com/repos/RokkuDayo/ForzaHorizon2_ExtraOptions/releases/latest | grep -Eo 'https://[^"]+azimuth\.zip' | head -n 1)
    curl -fsSL "$EO_URL" -o "$EO_ZIP"
    unzip -q "$EO_ZIP" -d "$SCRATCH/eo"
    cp -R "$SCRATCH/eo/Azimuth/"* "$APP_BUNDLE/Contents/Resources/payload/extra_options/"
fi

# Also pre-place d3d12.dll, fh2pad.dll, and d3dcompiler_47.dll inside both bundled azimuth folders for convenience
for az_dir in azimuth azimuth-0.9.10 azimuth-1.0.1; do
    cp "$APP_BUNDLE/Contents/Resources/payload/layer/"*.dll "$APP_BUNDLE/Contents/Resources/payload/$az_dir/"
done

echo "==> [5/7] Generating custom macOS squircle AppIcon.icns..."
swift "$REPO_ROOT/tools/make_icon.swift" "$SCRATCH/icon.png"
ICONSET="$SCRATCH/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$SCRATCH/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$SCRATCH/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Forza Horizon 2</string>
    <key>CFBundleDisplayName</key><string>Forza Horizon 2</string>
    <key>CFBundleIdentifier</key><string>io.github.fh2port.macos.launcher</string>
    <key>CFBundleExecutable</key><string>FH2Launcher</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.racing-games</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Open-source Apple Silicon compatibility launcher. Not affiliated with Microsoft or Playground Games.</string>
</dict>
</plist>
EOF

echo "==> [6/7] Ad-hoc signing Forza Horizon 2.app..."
codesign --force --deep -s - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> [7/7] Creating clean DMG and ZIP archives..."
STAGE_DMG="$SCRATCH/dmg"
mkdir -p "$STAGE_DMG"
cp -R "$APP_BUNDLE" "$STAGE_DMG/"
ln -s /Applications "$STAGE_DMG/Applications"

DMG_INSTALLER="$DIST_DIR/Forza-Horizon-2-Mac-Installer.dmg"
DMG_SETUP="$DIST_DIR/Forza-Horizon-2-Setup.dmg"
ZIP_APP="$DIST_DIR/Forza-Horizon-2-Mac-App.zip"

hdiutil create \
    -volname "Forza Horizon 2" \
    -srcfolder "$STAGE_DMG" \
    -fs HFS+ \
    -format UDZO \
    "$DMG_INSTALLER" >/dev/null

cp "$DMG_INSTALLER" "$DMG_SETUP"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_APP"

echo "==> Build complete!"
ls -lh "$DIST_DIR"
shasum -a 256 "$DMG_INSTALLER" "$DMG_SETUP" "$ZIP_APP"
