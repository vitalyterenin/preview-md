# PreviewMD releases

PreviewMD uses GitHub Actions for arm64 builds, GitHub Releases for `PreviewMD.dmg`,
and GitHub Pages for its signed Sparkle feed. Only matching `v<version>` tags publish;
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
Swift, Python 3 and network access for the pinned Sparkle download:

```sh
bash scripts/test.sh
./scripts/build-app.sh
python3 scripts/check-app.py build/PreviewMD.app
```

The build downloads the pinned official Sparkle archive after SHA-256 verification,
embeds only arm64 executables, and validates notices against its complete upstream
license. All notices remain in `Contents/Resources/Licenses` after installation.
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
The embedded Quick Look extension is signed and packaged, but Finder activation
is not established by successful code signing or a bundle build. Retain that
limitation until a real Finder test confirms it. Verify the actual updater with
two published builds: successful signing, packaging and isolated preference tests
do not alone establish download, replacement and relaunch of the installed app.
