# PreviewMD icon

The selected direction is an editorial lowercase `m` in dark navy on a warm ivory paper tile. The source is `previewmd-icon.png`; the application embeds `../resources/previewmd.icns`.

The artwork was generated and refined using the built-in imagegen tool. The owner selected concept 06 (Editorial M). The original exploration remains in the local, ignored `build/icon-concepts` directory.

## Final refinement prompt

Use case: precise-object-edit. Input image is the selected PreviewMD icon. Preserve the EXACT lowercase dark navy serif m letter, its typography, shape, size, position, proportions and near-black ink color. Preserve the warm ivory subtle paper texture, softly rounded square tile and delicate bottom-edge bevel. This is final production asset cleanup, not a redesign. Remove every stray speck, fleck, noise patch and irregularity outside the tile. Make the tile contour perfectly smooth and precise. Everything outside this rounded-square tile is genuine perfectly clean fully transparent alpha, no shadow, no stray pixels, no halo or glow. Keep approximately 8% transparent padding around the tile, square canvas. The entire tile interior must be solid opaque. Single icon only, no checkerboard painted into the image, no added objects, no extra letters or watermark.

## Export

Run `scripts/build-icons.sh` from any directory to regenerate the standard macOS iconset and ICNS from the 1024-pixel PNG master. Image resizing uses macOS `sips`; ICNS packaging uses `iconutil`. Transparent padding is already included in the master.
