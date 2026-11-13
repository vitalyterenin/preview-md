# PreviewMD releases

PreviewMD uses GitHub Actions for arm64 builds, GitHub Releases for `PreviewMD.dmg`,
and GitHub Pages for its signed Sparkle feed. Only a push of a matching `v<version>` tag publishes;
pull requests run checks without signing secrets or publication permissions.
A manual workflow run builds and checks a package without publishing a release.

## Release identity

`release.json` owns the version, increasing build, first-release build, repository,
permanent URLs, Apache-2.0 license, Sparkle version and public signing pins.
The host bundle ID is `com.vitalyterenin.preview-md`; Quick Look uses
`com.vitalyterenin.preview-md.quick-look`. Keep both IDs, the Sparkle public key
and the exact persistent certificate stable for future updates.

- Download: https://github.com/vitalyterenin/preview-md/releases/latest/download/PreviewMD.dmg
- Feed: https://vitalyterenin.github.io/preview-md/appcast.xml
- Distribution: Apple silicon, macOS 13 or later.

The dedicated self-signed **PreviewMD Release** certificate is pinned by SHA-256
in `release.json`; its public DER is `resources/release-signing.cer`.
The independent Ed25519 identity authenticates both feed and archive. Private keys
are stored in encrypted repository Secrets with owner-only backups in the owner's
central Secrets store. Never generate replacement identities during routine builds.

Repository secrets are `PREVIEWMD_SIGNING_P12` (base64 PKCS#12),
`PREVIEWMD_SIGNING_PASSWORD`, and `SPARKLE_PRIVATE_KEY` (Sparkle's base64 seed).
The workflow imports the identity into an isolated temporary keychain, restores
its search list and removes it on failure or success. A native private-key
preflight runs before the build; every app, Quick Look extension and updater
component must use the pinned certificate and a certificate-bound requirement.
Ad hoc signing is allowed only for development and pull-request checks.

GitHub Pages uses the Actions publishing source. The `github-pages` environment
permits `v*` tags. Only the publish job receives contents, Pages and OIDC write
permissions. Keep official actions pinned and keep release immutability off:
older DMG assets are removed after a new public download/feed is verified.

## Publish an update

1. Refresh and follow the owner's app-release skill. Read the complete current
   app documentation and check its claims against source and observed behavior.
2. Change the app and increase `version` and positive `build` in `release.json`.
   Keep `firstReleaseBuild` fixed at `3`. Run the checks below.
3. Obtain the owner's approval for the exact branch, PR, merge and release tag,
   as required by the owner's global repository rules. Push the branch, open a PR,
   wait for its checks, and merge the checked revision.
4. Push a fresh `v<version>` tag for that exact merged revision. Never move an
   existing published tag or reuse a published version/build with new bytes.
5. Wait for both Actions jobs. Download the public DMG and signed feed and verify
   their exact bytes, version/build, signatures, architecture and embedded notices.
   A source push, successful upload or green build job alone is not publication.

The macOS job builds all release artifacts. It validates metadata, arm64 executables,
licenses and pinned signatures, then creates an APFS DMG with the app, Applications
shortcut, LICENSE, NOTICE and THIRD_PARTY_NOTICES.md. It verifies the previous feed
and increasing build, signs the archive and single-entry feed, and uploads a
14-day internal artifact with hashes and the previous feed snapshot.

The Linux publisher checks repository/tag/commit identity, artifact hashes and
prior feed state. It uploads a draft release, publishes it, reads the public DMG
back, and only then stages the signed feed for Pages. Final public verification
precedes deletion of older `PreviewMD.dmg` assets; release records, tags and
unrelated assets are preserved. Publication is serialized rather than cancelled.

The first build can bootstrap only when the configured feed and latest GitHub
release are both absent. A missing feed on a later build stops publication.
A cached old feed may briefly disagree with the new permanent download;
Sparkle rejects the mismatch. Never bypass verification to resolve caching.
If publication fails, retry its job with the same verified artifact. Changes to
already published app/DMG bytes require a new version and build.

## Local checks

From the repository root on an Apple silicon Mac with Command Line Tools,
Swift, Python 3 and network access for the pinned Sparkle, cmark-gfm and Yams downloads:

```sh
bash scripts/test.sh
./scripts/build-app.sh
python3 scripts/check-app.py build/PreviewMD.app
```

The build downloads pinned official Sparkle, cmark-gfm and Yams archives after
SHA-256 verification, embeds only arm64 executables, and validates complete
dependency notices. The cmark-gfm static library is compiled with Apple Clang;
Yams and bundled libyaml are built through SwiftPM. Their complete upstream
licenses are pinned and checked against the bundled notices. All notices remain
in `Contents/Resources/Licenses` after installation.
Packaging checks the finished image as well. Adapted release tooling retains its
MIT terms in THIRD_PARTY_NOTICES.md; PreviewMD's original code is Apache-2.0.

Python tests use fake GitHub/network clients. They cover artifact tampering,
repository/tag mismatch, downgrade/reused-build rejection, first-release bounds,
publication retries, deadlines, notice preservation and pinned signing rules.
`check-app.py` checks emitted metadata and signatures, then uses a unique disposable
app bundle and preference domain to exercise the actual Sparkle settings over
three processes. It preserves the installed app and its preferences.

The native Software Updates controls use Sparkle's current state and persisted
preferences. Defaults enable checks and automatic installation, with four-hour
checks while running. Disabling checks disables the installation control while
preserving the saved installation choice. Manual checking follows updater
readiness independently of the automatic-check preference. Feed signatures are
required, failure fallback, system profiling and delta archives are disabled.

Build overrides: `PREVIEWMD_OUTPUT_DIR`, `PREVIEWMD_TOOLS_DIR`,
`PREVIEWMD_MARKDOWN_TOOLS_DIR`, `PREVIEWMD_YAML_TOOLS_DIR`,
`PREVIEWMD_SIGN_KEYCHAIN`, and `PREVIEWMD_REQUIRE_RELEASE_SIGNING`.
Do not install a development build over the stable copy. Local builds support
verification; public release artifacts must be built in GitHub Actions.

## Limits

Self-signing is not Developer ID signing or notarization. First downloaded launch
may need **System Settings → Privacy & Security → Open Anyway**. Users do not
install a trusted root or reduce system security protections. PreviewMD does not
request Accessibility, Input Monitoring or Screen Recording access.

The pre-GitHub app used ad hoc signatures and had no updater. Its first upgrade
requires a manual installation. Subsequent versions preserve the new identities.
The installed 0.1.3 Quick Look extension was exercised in Finder on macOS 26.7.2,
with its running provider traced to the installed app. The real background Sparkle
update from 0.1.2 (build 3) to 0.1.3 (build 4) downloaded the public CI bytes and
replaced/relaunched the app on quit. The original preference domain was empty,
so that test does not establish migration of populated per-document preferences.
Neither observation proves behavior across all supported macOS releases.

## Markdown dependency

[cmark-gfm](https://github.com/github/cmark-gfm) is pinned to
[27d942c8b0a62d192f616e5bf3578f4b6a89e180](https://github.com/github/cmark-gfm/commit/27d942c8b0a62d192f616e5bf3578f4b6a89e180),
including the upstream autolink overflow fix newer than tag 0.29.0.gfm.13.
The archive SHA-256 and complete COPYING are checked by the build. The shared
static parser replaces the old regular-expression grammar; app-specific table
layout, safe URLs, image handling and navigation remain in Swift/WebKit.
[Swift Markdown](https://github.com/swiftlang/swift-markdown) and its swift-cmark
backend were considered. The direct C parser avoids an unnecessary Swift AST
wrapper, newer package toolchain requirement and additional build dependencies
for this HTML viewer. Upstream CMake source/configuration was inspected; this
macOS-only build compiles that same C source with Apple's toolchain directly.

## Reading workflow validation for 0.1.4

`test.sh` includes an isolated native AppKit/WebKit test application on macOS.
It exercises nested lists, ordered starts, references, hard breaks, heading IDs,
safe HTML/URL handling, local SVG decoding, live script messages, table identity
and corrupt/unwritable-sidecar recovery. It also checks actual link clicks, Back,
native Find, atomic external saves, scroll restoration, independent document
settings, missing-file recovery and Markdown source preservation. The test owns
its temporary fixtures and unique preference domain; it does not use user files.

The 0.1.4 local candidate was also exercised through native UI in a disposable
bundle with a separate ID: empty launch/Open, SVG and list rendering, Find,
heading/neighbor navigation, choosing TextEdit when VS Code is absent, saving a
synthetic document there and returning to a refreshed preview at the prior scroll
position. Software Updates showed 0.1.4 and both defaults enabled. The installed
stable application was not replaced. This UI copy omitted the extension to avoid
competing with the stable Quick Look provider.

Before calling the new release verified, check the published signed app in Finder
with a local SVG, identify the actual extension process, and exercise the real
0.1.3-to-0.1.4 updater. Standalone WebKit HTML image decoding cannot establish
sandboxed Quick Look file access. Compare saved preferences and sidecars across
that update. Do not infer migration from a fresh empty preference domain.

Before every tag, review this guide, the README, all four Markdown samples,
referenced illustration and icon assets, icon provenance, the historical code
audit, LICENSE, NOTICE, complete third-party notices, and the GitHub About
description. Record actual checks and corrections in the release PR. The
historical product audit remains local; it is not maintained release guidance.

## Markdown profiles and Obsidian validation

The shared renderer offers Auto/CommonMark/GitHub/Obsidian profiles. The native
regression harness adds a synthetic vault with Russian typed properties, short and
path links, heading/block transclusion, images, nested folding callouts, comments,
highlights, tasks and footnotes. It verifies actual WebKit navigation, Back, Find,
per-file overrides/reopening, unchanged source bytes, and refresh of changed embeds.
Failure cases include ambiguous names, missing sections, unsafe paths/symlinks,
embed cycles, invalid YAML and bounded YAML alias/depth handling. UI automation
was unavailable for this task; the native test harness is not a manual walkthrough.
Quick Look uses Auto and shares the rendering code, but signed sandboxed vault
access still requires a future installed-release test.

YAML uses [Yams 6.2.2](https://github.com/jpsim/Yams/tree/6.2.2), its bundled libyaml,
and their complete MIT notices. `scripts/yaml-tools.py` pins the upstream archive
SHA-256, checks the reviewed license, and builds the dependency-free upstream
Swift package. Its static product is linked into both host and extension. Older
SwiftPM object output and the newer static-library output are supported. No YAML
objects or note code are evaluated; event limits run before node composition.
The optional cache override is `PREVIEWMD_YAML_TOOLS_DIR`. Cache identity includes
the selected Swift command/version, SDK path/version, target and build script;
missing libraries, modules or headers trigger a rebuild.

[Quartz's OFM adapter](https://github.com/jackyzha0/quartz/blob/v4/quartz/plugins/transformers/ofm.ts)
and [remark-wiki-link](https://github.com/flowershow/remark-wiki-link) were reviewed.
They rely on JavaScript/site-generation runtimes; the latter does not provide full
note transclusion. No code was copied from either. PreviewMD instead extends its
existing cmark syntax tree and filename resolver for native read-only rendering.
Obsidian's MarkdownRenderer requires the Obsidian App/Component lifecycle and is
not used as a standalone library. There is no embedded Obsidian/plugin runtime.

## Reader responsiveness and fragment regressions

`test.sh` also covers bounded background preparation: one active request and one
replaceable pending request per reader. It exercises rapid requests, profile and
document changes during loading, close, failed Back/retry, position retention and
concurrent table resizing. A large synthetic vault check measures main-thread
responsiveness while another window remains interactive. Timings depend on the
machine and filesystem; they are not a supported maximum latency.

Fragment checks pair full-note rendering with section/block embeds. Hidden
comments, frontmatter and literal code are not selectable sections or block IDs;
nested sections stop at their containing structure. Escaped carets remain text.
See the historical [code audit](refactoring-review.md#implementation-outcome) for
the original reproduction and local before/after measurements.
