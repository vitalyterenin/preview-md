#!/bin/zsh
set -eu

project_root="${0:A:h:h}"
cd "$project_root"

source_icon="assets/previewmd-icon.png"
iconset="assets/previewmd.iconset"
mkdir -p "$iconset"

for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$source_icon" \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -s format png -z "$retina_size" "$retina_size" "$source_icon" \
    --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns "$iconset" --output resources/previewmd.icns
