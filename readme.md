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
pipe tables, strikethrough, tasks, footnotes and automatic links in the GitHub
and Obsidian profiles. PreviewMD provides no text editing controls. Opening several files creates independent document windows.

| Control | Action |
| --- | --- |
| **Markdown profile** | Auto, CommonMark, GitHub or Obsidian; remembers the choice for this file |
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
Other windows remain usable while a document loads. A newer file or profile
choice takes precedence over a load that is still in progress.

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

## Markdown profiles and Obsidian

**Auto** uses the nearest ancestor `.obsidian` directory to recognize a vault.
Outside a vault it looks for distinctive syntax in prose, excluding code blocks,
inline code and raw HTML. Plain documents fall back to **CommonMark**; GitHub
syntax selects **GitHub**. The profile row shows the resolved mode and reason.
Choose a mode explicitly when the source is ambiguous. The choice is saved per
file path on this Mac and survives reopening; switching keeps zoom, width and
scroll position. It never changes the source or Obsidian settings.

| Profile | Interpretation |
| --- | --- |
| CommonMark | CommonMark structure; no pipe tables, task checkboxes, footnotes, strikethrough or Obsidian syntax |
| GitHub | CommonMark plus pipe tables, task checkboxes, footnotes, strikethrough and autolinks |
| Obsidian | GitHub foundation plus YAML properties, wikilinks, note/image embeds, callouts, highlights, comments and named blocks |

Obsidian properties use a real YAML parser. Text, numbers, true/false checkboxes,
dates, lists, aliases and quoted wikilinks are displayed as read-only properties.
Text properties stay literal; nested mappings are shown structurally. Invalid,
duplicate-key, oversized or excessively nested YAML, and YAML aliases/anchors
that require expansion, retain a readable source fallback. Custom vault-wide
property type settings and CSS classes are not imported.

`[[Note]]`, `[[Note|Label]]`, `[[Note#Heading]]` and `[[Note#^block-id]]` resolve
inside the vault. Paths with folders start at the vault root; `./` and `../`
are relative to the current note and must stay inside that root. Without a vault,
the document's folder is the lookup boundary. Short names search that boundary;
duplicate basenames display an ambiguity notice and require an explicit path.
Aliases are displayed as properties and link labels; they are not a second
vault-wide filename index. Missing links are visible, not newly created notes.

`![[Note]]`, heading/block embeds and `![[image.svg|320x180]]` use the same
resolver. A standalone `^block-id` after a list, quote or table names that block;
paragraph and list-item IDs can appear at the end of their text. Cycles, missing
sections, ambiguous headings and unsupported media produce readable notices.
Embed traversal is capped at five levels, 64 embeds, 2 MiB per note and 8 MiB of
note text per render. The filename index is capped at 20,000 entries; an incomplete
index asks for an explicit path. Hidden files/directories and symlink traversal
are not indexed. PDF/audio/video/canvas embeds are not rendered.

Callouts support nested content and `+`/`-` folding. `==Highlights==`, `%%comments%%`,
read-only tasks and footnotes preserve code examples as literal text. Obsidian
notes refresh on return to the app even when only an embedded note changed.
**Reload** retries resolution after file or folder changes. The
[synthetic Obsidian demo](samples/obsidian-demo.md) exercises these features.

This is core reading compatibility, not the Obsidian application or plugin runtime.
It does not execute Dataview, Templater, note scripts, HTML or vault CSS, and does
not implement math, Mermaid, canvas, graph/search queries, multi-heading search,
plugin-defined syntax, backlinks or editing. Auto is a heuristic, not a claim that
all Markdown dialects can be inferred perfectly.

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
Quick Look uses the same profile detection/rendering core in Auto mode. Its sandbox
may prevent vault discovery or access to sibling notes/attachments; notices then
explain unresolved content. The main app's per-file override is not shared with
the extension. Use the main app for navigation, overrides and saved resizing.

GitHub alerts, arbitrary HTML details, math and Mermaid are not rendered as
those extended features. Obsidian callouts use their own supported folding syntax. See the
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

The build downloads pinned, checksum-verified Sparkle binaries, cmark-gfm and Yams
sources, and uses Apple's AppKit, WebKit and QuickLookUI frameworks. It produces `build/PreviewMD.app` with
an ad hoc development signature. Keep development output separate from the
installed stable app. The icon source is `assets/previewmd-icon.png`; the embedded
resource is `resources/previewmd.icns`. Run `scripts/build-icons.sh` after changing
the PNG master to regenerate all icon sizes and the embedded resource.

[Release operations](docs/releases.md) describe GitHub Actions builds, persistent
signing, the stable DMG/feed, verification and recovery. Release artifacts are
built in GitHub Actions.

The historical [code audit](docs/refactoring-review.md) records the 0.1.4
implementation findings, corrections and local verification results.

## License

Maintained by Vitaly Terenin. PreviewMD's original code and assets are licensed
under [Apache-2.0](LICENSE); see [NOTICE](NOTICE). Sparkle, cmark-gfm, Yams,
libyaml and adapted release tooling retain their own terms in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
All three documents are included in the app and DMG.
