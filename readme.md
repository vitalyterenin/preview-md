# PreviewMD

PreviewMD is a native, read-only Markdown viewer for macOS. Open a Markdown file
from Finder or **File → Open…** to read the rendered document, with adjustable
zoom, reading width and table columns.

## Install

Requires an Apple silicon Mac and macOS 13 or later.

1. Download [PreviewMD.dmg](https://github.com/vitalyterenin/preview-md/releases/latest/download/PreviewMD.dmg)
   from the latest GitHub release.
2. Open the image, drag **PreviewMD** to **Applications**, eject the image, and
   launch the installed app.
3. For Markdown files, choose **PreviewMD** in Finder's **Get Info → Open with**;
   use **Change All…** if you want it as the default viewer.

The app uses its own persistent self-signed certificate. It is not Developer ID
signed or notarized, so first launch may need **System Settings → Privacy &
Security → Open Anyway**. No certificate installation is required.

## Read Markdown

Supported extensions are `.md`, `.markdown`, `.mdown` and `.mkdn`.
The renderer supports headings, paragraphs, bold, italic, strikethrough, inline
code, fenced code blocks, lists, block quotes, pipe tables, images, links and
horizontal rules. PreviewMD provides no text editing controls.

| Control | Action |
| --- | --- |
| `Command-Plus` / `Command-Minus` | Increase / decrease document zoom |
| `Command-Zero` | Reset zoom to actual size |
| **Width: 800** / **Width: Window** | Switch between a centered reading column and available window width |
| Table column divider | Drag to resize the adjacent columns |
| **Edit** | Open the current file in Visual Studio Code, when installed |
| `Command-W` / `Command-Q` | Close the window / quit PreviewMD |

Zoom scales the full document, including typography, code blocks and spacing.
Window position, zoom and reading width are remembered for each document.
New document windows use a `1200 × 900` content size when screen space permits;
the minimum window size is `900 × 650`.

After a table resize, column proportions are saved in
`.previewmd/<document-name>.json` beside the Markdown file. The sidecar travels
with the directory when copied or synced; the original Markdown is not edited.
Writing that preference requires a writable document directory.

## Software updates

Open **PreviewMD → Settings → Software Updates…**:

1. **Check for Updates…** starts a manual check when the updater is ready.
2. **Automatically Check for Updates** enables background checks while running.
3. **Automatically Install Updates** controls automatic downloading/installation.
   It is disabled while checks are off; the saved choice is retained.
4. **Version** shows the running app version.

Both preferences are enabled by default. Checks run every four hours while the
app is running. Changes persist across launches and stay in sync with Sparkle's
own dialogs. Automatic installation may wait for the app to quit or for macOS
authorization. Updates and their feed are signed with PreviewMD's own update key.
An older locally built copy has no updater and needs one manual installation.

## Data and limitations

PreviewMD reads local files and stores reading preferences locally. It does not
add telemetry or request Accessibility, Input Monitoring or Screen Recording.
Update checks contact GitHub Releases/Pages; Sparkle system profiling is disabled.
Images and links in a document may contact their referenced servers through WebKit.

The embedded Finder Quick Look extension shares the renderer and packaged table
preferences. Finder activation remains unverified; Finder may use its plain-text
fallback. Building or signing the extension alone does not prove activation.

Task lists, footnotes, GitHub alerts, collapsible details, math and Mermaid are
not rendered as those extended features. See the
[render gallery](samples/markdown-render-gallery.md) for examples and the
[formatting demo](samples/formatting-demo.md) for a short sample.

Report problems through [GitHub Issues](https://github.com/vitalyterenin/preview-md/issues).

## Build and release

With the macOS Command Line Tools and Python 3 installed, run from the repository root:

```sh
bash scripts/test.sh
./scripts/build-app.sh
python3 scripts/check-app.py build/PreviewMD.app
```

The build downloads a pinned, checksum-verified Sparkle release and uses Apple's
AppKit, WebKit and QuickLookUI frameworks. It produces `build/PreviewMD.app` with
an ad hoc development signature. Keep development output separate from the
installed stable app. The icon source is `assets/previewmd-icon.png`; the embedded
resource is `resources/previewmd.icns`.

[Release operations](docs/releases.md) describe GitHub Actions builds, persistent
signing, the stable DMG/feed, verification and recovery. Release artifacts are
built in GitHub Actions.

## License

Maintained by Vitaly Terenin. PreviewMD's original code and assets are licensed
under [Apache-2.0](LICENSE); see [NOTICE](NOTICE). Sparkle and adapted release
tooling retain their own terms in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
All three documents are included in the app and DMG.
