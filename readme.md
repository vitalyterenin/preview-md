# PreviewMD

PreviewMD is a native, read-only macOS viewer for Markdown files. It renders Markdown as a clean document rather than source text.

## Current scope

- Open supported Markdown files from Finder or with **Open…**.
- Register as a viewer for `.md`, `.markdown`, `.mdown`, and `.mkdn` files.
- Show the same renderer in the application and Finder Quick Look.
- Support headings, paragraphs, bold, italic, strikethrough, inline code, fenced code blocks, lists, block quotes, pipe tables, links, and horizontal rules.
- Do not provide editing controls.

## Reading controls

- `Command-Plus` increases the document zoom.
- `Command-Minus` decreases the document zoom.
- `Command-Zero` resets the zoom to its actual size.
- **Edit** in the title bar opens the current file in Visual Studio Code.

Zoom scales the entire document viewport, including typography, code blocks, and layout spacing.

PreviewMD remembers each document's window frame and zoom level. New documents open in a larger `1200 × 900` window when screen space permits.

## Reading width and tables

- Use **Width: 800** in the upper app header for a centered 800 px reading column. Click it to switch to **Width: Window**, which lets the document use the available window width.
- The selected reading width mode is remembered for each document.
- Drag a table's vertical divider to resize its adjacent columns. PreviewMD saves the resulting column proportions in `.previewmd/<document-name>.json` beside the document and restores them in both the app and Finder Quick Look. The sidecar is created only after the first resize, and it travels with the document directory when the directory is copied or synced.

## App icon

The app icon source is `assets/previewmd-icon.png`. The build embeds the generated `resources/previewmd.icns` bundle resource.

## Build

Requirements: an Apple silicon Mac, macOS 13 or later, and the macOS Command Line Tools with the Swift compiler. The current build script targets `arm64` and uses only Apple system frameworks.

Build from a local checkout:

```sh
./scripts/build-app.sh
```

The resulting app bundle is `build/PreviewMD.app`. The script applies an ad hoc signature for local use; it does not produce a Developer ID signed or notarized distribution.

Move the app to `/Applications`, open it once, then choose **PreviewMD** as the default app for Markdown files in Finder.

### Quick Look status

The Quick Look extension is included in the build and shares the Markdown renderer. Finder activation remains unverified with the current ad hoc signing setup; Finder may show its plain-text fallback. A successful build alone does not confirm Quick Look activation.

Open `samples/formatting-demo.md` to check the renderer.
