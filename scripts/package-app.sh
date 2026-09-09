#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product GradingWorkspace
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/build/Grading Workspace.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/GradingWorkspace" "$app_dir/Contents/MacOS/GradingWorkspace"
# PreviewCatalog prefers bundles in the app's Resources directory.
for bundle in "$binary_dir"/*.bundle; do
  [ -d "$bundle" ] || continue
  ditto "$bundle" "$app_dir/Contents/Resources/$(basename "$bundle")"
done
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GradingWorkspace</string>
<key>CFBundleIdentifier</key><string>local.grading.workspace.preview</string>
<key>CFBundleName</key><string>Grading Workspace</string>
<key>CFBundleDisplayName</key><string>Grading Workspace</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Ad hoc signing is local-only; this is not distribution signing or notarization.
codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
