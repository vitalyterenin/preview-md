#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
markdown_tools="$(python3 scripts/markdown-tools.py)"
yaml_tools="$(python3 scripts/yaml-tools.py)"
sparkle_tools="$(bash scripts/sparkle-tools.sh)"
root="$(mktemp -d "$PWD/build/reading-test.XXXXXX")"
domain="com.vitalyterenin.preview-md.reading-test.$(uuidgen)"
trap 'defaults delete "$domain" >/dev/null 2>&1 || true; rm -rf "$root"' EXIT
app="$root/ReadingTests.app"
mkdir -p "$app/Contents/MacOS"
python3 - "$app" "$domain" <<'PY'
import pathlib,plistlib,sys
pathlib.Path(sys.argv[1],'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':sys.argv[2], 'CFBundleExecutable':'ReadingTests','CFBundlePackageType':'APPL'}))
PY
swiftc -D PREVIEWMD_TESTING -I "$markdown_tools/include" "$markdown_tools/libcmark.a" \
  -I "$yaml_tools/modules" -I "$yaml_tools/include" "$yaml_tools/libYams.a" \
  -framework AppKit -framework WebKit -F "$sparkle_tools" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$sparkle_tools" \
  sources/shared/*.swift sources/app/*.swift tests/reading-smoke.swift tests/obsidian-smoke.swift \
  -o "$app/Contents/MacOS/ReadingTests"
"$app/Contents/MacOS/ReadingTests" "$root"
