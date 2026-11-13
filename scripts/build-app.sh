#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
build_root="${PREVIEWMD_OUTPUT_DIR:-$project_root/build}"
mkdir -p "$build_root"
staging="$(mktemp -d "$build_root/.preview-md-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app_bundle="$staging/PreviewMD.app"
quick_look_bundle="$app_bundle/Contents/PlugIns/PreviewMDQuickLook.appex"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
target="arm64-apple-macosx13.0"
tools="$(bash scripts/sparkle-tools.sh)"
markdown_tools="$(python3 scripts/markdown-tools.py)"
yaml_tools="$(python3 scripts/yaml-tools.py)"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" "$app_bundle/Contents/Frameworks" "$quick_look_bundle/Contents/MacOS"
python3 scripts/release.py plist "$app_bundle/Contents/Info.plist"
cp resources/previewmd.icns "$app_bundle/Contents/Resources/previewmd.icns"
python3 - "$quick_look_bundle/Contents/Info.plist" <<'PLIST'
import json, pathlib, plistlib, sys
config=json.loads(pathlib.Path('release.json').read_text())
info=plistlib.loads(pathlib.Path('resources/quick-look-info.plist').read_bytes())
info.update(CFBundleShortVersionString=config['version'], CFBundleVersion=config['build'])
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PLIST
ditto "$tools/Sparkle.framework" "$app_bundle/Contents/Frameworks/Sparkle.framework"
sparkle="$app_bundle/Contents/Frameworks/Sparkle.framework"
# The host is not sandboxed; optional Sparkle XPC services are unused.
rm -rf "$sparkle/Versions/B/XPCServices"
for executable in "$sparkle/Versions/B/Sparkle" "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app/Contents/MacOS/Updater"; do
    if [[ "$(lipo -archs "$executable")" != arm64 ]]; then
        lipo "$executable" -thin arm64 -output "$executable.arm64"
        mv "$executable.arm64" "$executable"
    fi
done
swiftc -sdk "$sdk_path" -target "$target" -module-name PreviewMD \
  -I "$markdown_tools/include" "$markdown_tools/libcmark.a" \
  -I "$yaml_tools/modules" -I "$yaml_tools/include" "$yaml_tools/libYams.a" \
  -framework AppKit -framework WebKit -F "$tools" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  sources/shared/document-state.swift sources/shared/markdown-html.swift sources/shared/markdown-profile.swift sources/shared/vault-resolver.swift sources/shared/obsidian-markdown.swift sources/shared/markdown-properties.swift \
  sources/shared/markdown-preview-view-controller.swift sources/app/markdown-document.swift \
  sources/app/update-settings.swift sources/app/app-delegate.swift \
  -o "$app_bundle/Contents/MacOS/PreviewMD"
swiftc -sdk "$sdk_path" -target "$target" -module-name PreviewMDQuickLook \
  -I "$markdown_tools/include" "$markdown_tools/libcmark.a" \
  -I "$yaml_tools/modules" -I "$yaml_tools/include" "$yaml_tools/libYams.a" \
  -framework QuickLookUI sources/shared/document-state.swift sources/shared/markdown-html.swift sources/shared/markdown-profile.swift sources/shared/vault-resolver.swift sources/shared/obsidian-markdown.swift sources/shared/markdown-properties.swift \
  sources/quick-look/preview-view-controller.swift sources/quick-look/extension-main.swift \
  -o "$quick_look_bundle/Contents/MacOS/PreviewMDQuickLook"
python3 scripts/licenses.py install --app "$app_bundle" --sparkle-license "$tools/LICENSE"
plutil -lint "$app_bundle/Contents/Info.plist" "$quick_look_bundle/Contents/Info.plist"
xattr -dr com.apple.FinderInfo "$app_bundle" 2>/dev/null || true
python3 scripts/signing.py sign --app "$app_bundle"
# Replace only this script's generated output.
if [[ -e "$build_root/PreviewMD.app" ]]; then rm -rf "$build_root/PreviewMD.app"; fi
mv "$app_bundle" "$build_root/PreviewMD.app"
printf 'Built %s\n' "$build_root/PreviewMD.app"
