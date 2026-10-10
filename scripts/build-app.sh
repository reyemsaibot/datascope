#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/datascope-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/datascope-swift"
BUILD_DIR="${SWIFT_BUILD_DIR:-.build}"
swift build -c release --scratch-path "$BUILD_DIR" --disable-sandbox
assetOutput="$(mktemp -d "${TMPDIR:-/tmp}/datascope-assets.XXXXXX")"
trap 'rm -rf "$assetOutput"' EXIT
xcrun actool --compile "$assetOutput" --platform macosx --minimum-deployment-target 14.0 \
  --app-icon AppIcon --output-partial-info-plist "$assetOutput/partial-info.plist" Assets >/dev/null
for size in 16 32 64 128 256 512 1024; do
  sips -s format tiff -Z "$size" Assets/AppIconSource.png --out "$assetOutput/icon-$size.tiff" >/dev/null
done
tiffutil -cat "$assetOutput/icon-16.tiff" "$assetOutput/icon-32.tiff" "$assetOutput/icon-64.tiff" \
  "$assetOutput/icon-128.tiff" "$assetOutput/icon-256.tiff" "$assetOutput/icon-512.tiff" \
  "$assetOutput/icon-1024.tiff" -out "$assetOutput/icon-pages.tiff" >/dev/null
APP="$PWD/output/DataScope.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BUILD_DIR/release/DataScope" "$APP/Contents/MacOS/"
cp Vendor/libduckdb.dylib "$APP/Contents/Frameworks/"
cp Vendor/excel.duckdb_extension "$APP/Contents/Resources/"
cp docs/DUCKDB-LICENSE.txt "$APP/Contents/Resources/"
cp "$assetOutput/Assets.car" "$APP/Contents/Resources/"
tiff2icns "$assetOutput/icon-pages.tiff" "$APP/Contents/Resources/AppIcon.icns" >/dev/null
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/DataScope"
install_name_tool -delete_rpath "$PWD/Vendor" "$APP/Contents/MacOS/DataScope"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DataScope</string>
<key>CFBundleIdentifier</key><string>local.datascope.prototype</string>
<key>CFBundleName</key><string>DataScope</string>
<key>CFBundleDisplayName</key><string>DataScope</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Leave DuckDB extension bytes unchanged: its signature is checked by DuckDB.
codesign --force --sign - "$APP/Contents/Frameworks/libduckdb.dylib"
codesign --force --sign - "$APP"
echo "App erstellt: $APP"
