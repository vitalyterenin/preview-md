#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
build_root="$project_root/build"
app_bundle="$build_root/PreviewMD.app"
quick_look_bundle="$app_bundle/Contents/PlugIns/PreviewMDQuickLook.appex"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
target="arm64-apple-macosx13.0"

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" "$quick_look_bundle/Contents/MacOS"

cp "$project_root/resources/app-info.plist" "$app_bundle/Contents/Info.plist"
cp "$project_root/resources/previewmd.icns" "$app_bundle/Contents/Resources/previewmd.icns"
cp "$project_root/resources/quick-look-info.plist" "$quick_look_bundle/Contents/Info.plist"

swiftc \
  -sdk "$sdk_path" \
  -target "$target" \
  -module-name PreviewMD \
  -framework AppKit \
  -framework WebKit \
  "$project_root/sources/shared/document-state.swift" \
  "$project_root/sources/shared/markdown-html.swift" \
  "$project_root/sources/shared/markdown-preview-view-controller.swift" \
  "$project_root/sources/app/markdown-document.swift" \
  "$project_root/sources/app/app-delegate.swift" \
  -o "$app_bundle/Contents/MacOS/PreviewMD"

swiftc \
  -sdk "$sdk_path" \
  -target "$target" \
  -module-name PreviewMDQuickLook \
  -framework QuickLookUI \
  "$project_root/sources/shared/document-state.swift" \
  "$project_root/sources/shared/markdown-html.swift" \
  "$project_root/sources/quick-look/preview-view-controller.swift" \
  "$project_root/sources/quick-look/extension-main.swift" \
  -o "$quick_look_bundle/Contents/MacOS/PreviewMDQuickLook"

plutil -lint "$app_bundle/Contents/Info.plist" "$quick_look_bundle/Contents/Info.plist"
codesign --force --sign - --timestamp=none \
  --entitlements "$project_root/resources/quick-look-entitlements.plist" \
  "$quick_look_bundle"
codesign --force --sign - --timestamp=none "$app_bundle"

echo "Built $app_bundle"
