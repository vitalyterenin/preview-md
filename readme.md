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
The shared cmark-gfm renderer supports CommonMark text structure, including nested
lists, ordered-list starting numbers, reference links and hard line breaks, plus
pipe tables, strikethrough and automatic links. PreviewMD provides no text editing
controls. Opening several files creates independent document windows.

| Control | Action |
| --- | --- |
| **Open…** / `Command-O` | Open one or more files; also available on an empty launch |
| `Command-F`, `Command-G`, `Shift-Command-G` | Find text, next match, previous match |
| Heading or neighboring Markdown link | Jump to a section or open the linked document in the same window |
| **Back** / `Command-[` | Return to the previous linked document and reading position |
| **Reload** / `Command-R` | Read the file again without resetting the reading position |
| `Command-Plus` / `Command-Minus` | Increase / decrease document zoom |
| `Command-Zero` | Reset zoom to actual size |
| **Width: 800** / **Width: Window** | Switch between a centered reading column and available window width |
| Table column divider | Drag to resize; focus a divider and use arrow keys for keyboard resizing |
| **Open in Editor…** | Use VS Code if installed, or choose an installed text editor |
| **File → Choose Editor…** | Change the chosen editor |
| `Command-W` / `Command-Q` | Close the window / quit PreviewMD |

Save in your editor and return to PreviewMD: visible documents refresh on app
activation when their source bytes changed. Use **Reload** for changes made while
PreviewMD remains active, or to refresh a changed image. If a file disappears or
becomes unreadable, the last readable version stays visible with an error and a
retry instruction. Local non-Markdown links are left for Finder; web and email
links open in their external apps. Missing heading targets display a notice.

Zoom scales the full document, including typography, code blocks and spacing.
Window position, zoom, reading width and scroll position are remembered per file
path on this Mac. New windows use a `1200 × 900` content size when screen space
permits; the minimum window size is `900 × 650`. A large content change can move
the text at the saved scroll position. Renaming a file gives it a new local state.

After a table resize, column proportions are saved in
`.previewmd/<document-name>.json` beside the Markdown file. The sidecar travels
with the directory when copied or synced; the original Markdown is not edited.
Writing requires a writable document directory. A failed save displays a notice
that the change applies only to the current session. Damaged or unsupported
sidecars are reported and preserved instead of overwritten.

New table preferences follow unchanged table content when tables are reordered.
Editing a table's content starts that table with default widths; prior saved
entries remain in the sidecar. Identical tables are ambiguous and use defaults.
Older positional sidecars remain readable and acquire content identities on the
next successful resize. Window and reading preferences are local, not portable.

Local PNG, JPEG, GIF, WebP and SVG images up to 20 MiB each are embedded in the
preview. Unreadable, missing or unsupported images display **Image unavailable**.

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
Remote images may contact their referenced HTTP(S) servers through WebKit;
activated web links open externally. Local embedded images are not uploaded.
Raw HTML is omitted, document scripts are not executed, and unsupported URL
schemes are blocked.

The embedded Finder Quick Look extension shares the renderer and reads saved
table preferences. Press Space on a selected Markdown file in Finder. Activation
of the installed 0.1.3 extension was observed on macOS 26.7.2; this is not a test
of every supported OS. The 0.1.4 image rendering path is covered in a standalone
WebKit context; its sandboxed Finder preview must also be checked after installing
the signed release. Finder may choose another provider or a plain-text fallback.
Quick Look is a reading preview; use the main app for navigation and saved resizing.

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

The build downloads pinned, checksum-verified Sparkle binaries and cmark-gfm
sources, and uses Apple's
AppKit, WebKit and QuickLookUI frameworks. It produces `build/PreviewMD.app` with
an ad hoc development signature. Keep development output separate from the
installed stable app. The icon source is `assets/previewmd-icon.png`; the embedded
resource is `resources/previewmd.icns`.

[Release operations](docs/releases.md) describe GitHub Actions builds, persistent
signing, the stable DMG/feed, verification and recovery. Release artifacts are
built in GitHub Actions.

## License

Maintained by Vitaly Terenin. PreviewMD's original code and assets are licensed
under [Apache-2.0](LICENSE); see [NOTICE](NOTICE). Sparkle, cmark-gfm and adapted
release tooling retain their own terms in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
All three documents are included in the app and DMG.
