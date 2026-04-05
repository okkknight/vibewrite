#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$repo_root/.derivedData-dmg"
stage_root="$repo_root/.build/dmg-stage"
dist_dir="$repo_root/dist"

rm -rf "$stage_root"
mkdir -p "$stage_root" "$dist_dir"

echo "Building Release app..."
xcodebuild \
  -project "$repo_root/VibeWrite.xcodeproj" \
  -scheme VibeWrite \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  ENABLE_DEBUG_DYLIB=NO \
  build

app_path="$derived_data/Build/Products/Release/VibeWrite.app"
if [[ ! -d "$app_path" ]]; then
  echo "Missing built app: $app_path" >&2
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app_path/Contents/Info.plist")
dmg_name="VibeWrite-${version}-${build_number}.dmg"
dmg_path="$dist_dir/$dmg_name"

echo "Preparing DMG staging folder..."
cp -R "$app_path" "$stage_root/"
ln -s /Applications "$stage_root/Applications"

echo "Creating DMG: $dmg_path"
hdiutil create \
  -volname "VibeWrite" \
  -srcfolder "$stage_root" \
  -ov \
  -format UDZO \
  "$dmg_path"

echo "Done: $dmg_path"
