# PreviewMD code audit

Audit completed on 2026-11-13. Evidence was last reconciled at
2026-11-13T11:11:03Z. This is an audit and proposed remediation plan, not an
implementation or release approval.

**Follow-up:** local implementation was subsequently authorized. R1–R4 are now
addressed; see [Implementation outcome](#implementation-outcome). The original
audit evidence and historical line references below describe the initial
revision, not the corrected state. Publication and installation were on hold at
the implementation handoff. Current release procedures are maintained in
[the release guide](releases.md).

## Scope and result

The inspected revision is `5e6d22d5b39911908802f00b80f446cf165760cb`, on
`feature/obsidian-profiles`. The working tree was clean at the start. This is the
local 0.1.4/build 5 candidate; the installed stable application remains 0.1.3/build
4. No application source, permanent tests, release configuration, Git refs,
installed application, or user documents were changed. The only durable project
changes are this report and its README link. Experiments and an additional
development build are isolated under `build/code-audit-2026-11-13/`.

Three confirmed issues merit changes: multi-second synchronous vault rendering,
fragment selection that disagrees with Obsidian rendering, and a manual CI run
that can cross the documented publication boundary. Existing tests all pass;
these issues occur outside their current scenario coverage. A separate Swift
dependency-cache concern is conditional, not a reproduced compiler failure.

The complete skill was delegated using the current host catalog's analytical
frontier selection, explicit `gpt-6-astra` and `reasoning_effort="high"`, with a
fresh-context `deep_refactor` executor. The bounded delivery review used the same
explicit selection. Accepted launch configuration is the available evidence;
independent runtime model metadata was unavailable. No rerouting was reported.

## Audited system and coverage

Finder/open-panel events enter `AppDelegate`, which owns `ReaderWindow` instances.
`MarkdownSnapshot` reads the file; a reader captures its old position and uses a
generation counter to reject superseded callbacks. The preview controller owns
the WebKit view, per-file controls and a token-checked script bridge. Rendering
currently runs synchronously inside that controller.

`MarkdownHTML` combines cmark-gfm, profile selection, Obsidian preprocessing,
bounded vault resolution, YAML properties and resource embedding. It produces
HTML and table identities. A nonce-based CSP permits only the application script;
raw note HTML is omitted. Quick Look produces the same HTML through a data-based
provider, with different filesystem permissions and no main-app override state.

Reading preferences live in per-path UserDefaults keys. Table widths live in a
versioned adjacent JSON sidecar. Saves preserve unknown fields and previous table
identities, reject damaged formats, and write atomically. Source Markdown is not
written. Sparkle handles updates; pinned local tooling builds arm64 app/extension
binaries, installs notices, signs artifacts and publishes through GitHub Actions.

| Path or boundary | Inspection and executed evidence | Remaining limits |
| --- | --- | --- |
| Open, reload, Back, multiple windows, failed reads | Deep read of app/controller/state code; existing real AppKit/WebKit smoke tests passed for navigation, scroll, independent preferences and stale-file recovery | No exhaustive reordered-callback or OS termination test |
| CommonMark/GitHub parsing, links, images, script bridge | Deep read of shared renderer; existing native semantics, local SVG, CSP-safe markup, Find and table-bridge tests passed | Remote image/network failure timing and every supported macOS version were not exercised |
| Obsidian profiles, YAML, resolution and embeds | Deep read of all five relevant shared components; existing suite plus isolated section/block and scale probes | Real private vaults deliberately excluded; only synthetic fixtures |
| Sidecar preservation and migration | Deep read of `document-state.swift`; reordering, duplicates, old identities, malformed sidecars and failed saves covered by existing checks | External simultaneous writers and every legacy frame shape were not simulated |
| Finder Quick Look | Provider, entitlements and shared-core inspection; fresh extension compilation, signature check and standalone WebKit HTML tests | Not a real Finder-hosted sandbox/selection test; installed provider was not replaced |
| Build, updater, signing, notices, publication | Delivery scripts, workflow, Python tests, package validation and real isolated Sparkle preference lifecycle | No production update, DMG installation, CI launch, remote permission/secret audit or publication |

The product exclusions remain intentional: plugin execution, Dataview, Templater,
math, Mermaid, unsupported media, global alias lookup and editing are not missing
implementation work in this audit. Auto remains a heuristic with a manual
override. No broad framework or dependency replacement is justified.

## Confirmed findings

### R1 — Vault lookup blocks the main thread for seconds

**Priority:** P1 for reading responsiveness within the advertised vault-size
boundary. **Confidence:** high. **Change:** performance work plus a small
rendering/UI boundary refactor; moderate effort and concurrency regression risk.

Locations: [`vault-resolver.swift:32`](../sources/shared/vault-resolver.swift#L32)
enumerates the vault; line 68 scans the complete array for every short-name link.
[`markdown-preview-view-controller.swift:100`](../sources/shared/markdown-preview-view-controller.swift#L100)
calls the renderer synchronously on the UI path.
[`app-delegate.swift:63`](../sources/app/app-delegate.swift#L63) rerenders Obsidian
documents on activation even if the host source has not changed, to refresh embeds.

**Trigger and observation.** A synthetic note contains 100 distinct short-name
wikilinks. The directory contains 100, 2,000 or 10,000 tiny Markdown files and an
empty `.obsidian` directory. Each render creates its normal per-render resolver.
The exact current renderer was compiled with the production script's unoptimized
Swift mode and arm64/macOS 13 target, using the same cached cmark/Yams libraries.

| Indexed files | Render seconds, three consecutive trials |
| --- | --- |
| 100 | 0.0590 / 0.0578 / 0.0578 |
| 2,000 | 0.9713 / 0.9907 / 0.9771 |
| 10,000 | 4.8007 / 4.8298 / 4.9112 |

Environment: Apple M3 Pro, 12 CPU cores, 36 GB RAM, macOS 26.7.2, Apple Swift
6.4.2. Files were created immediately before measurement, so these are local,
warm-filesystem observations, not controlled cold-cache measurements. Every
output was 16,880 UTF-8 bytes. Timing includes rendering and name lookup, excludes
fixture creation and WebKit layout, and is not a measured end-to-end UI latency.
The inspected synchronous call path makes that work UI-blocking. No speedup has
been implemented or measured.

**Impact.** Opening or revisiting an ordinary link-rich note can stop interaction
with every application window. Several visible Obsidian windows add sequential
work on app activation. The 20,000-entry cap bounds enumeration size but does not
provide an interactive latency guarantee.

**Proposed correction.** Keep the bounded per-render resolver, but construct a
case-insensitive basename lookup once instead of filtering the whole file array
for each link. Move file reads/indexing/render preparation off the UI thread and
apply the finished HTML on the main thread only for the current generation.
Bound queued work and discard superseded requests. Preserve explicit-path
resolution, duplicate detection, incomplete-index warnings, symlink checks,
render budgets and refresh of changed embedded notes.

**Acceptance.** Repeat the same 100/2,000/10,000-file inputs and flags, with output
equivalence checked, before claiming improvement. Add a real reader check that
another window continues to handle events during a large render; target no
render-attributable main-thread stall over 100 ms on this reference machine.
Exercise close, new navigation, profile change and reload while work is pending;
only the latest result may update the document or persisted state.

### R2 — Fragment selection and visible rendering use different syntax rules

**Priority:** P2, incorrect locally displayed content. **Confidence:** high.
**Change:** correctness fix followed by a narrow shared parsing boundary;
moderate effort and regression risk.

Locations: [`obsidian-markdown.swift:97`](../sources/shared/obsidian-markdown.swift#L97)
selects sections from raw source using a separate plain cmark tree, before YAML
extraction and comment processing. Lines 105–106 flatten code/text distinctions
when matching block IDs; lines 116–123 stop only at sibling headings and otherwise
default to the end of the entire file. Rendering uses `prepare` and
`decorateBlockID` instead; the latter also loses escape provenance at lines
156–169.

**Reproduced through full `MarkdownHTML.render` embeds:**

| Target note and request | Actual output | Required outcome |
| --- | --- | --- |
| `%%` comment containing `# Hidden Heading`; `![[note#Hidden Heading]]` | The hidden heading and comment text become visible; a dangling closing `%%` is also shown | Hidden prose must not become an addressable visible section; return the missing-section notice |
| YAML multiline scalar containing `# Fake Heading`; corresponding heading embed | Property text becomes rendered body headings | YAML values remain property values, not selectable body sections |
| `> # Quoted Heading` followed by top-level `# Unrelated`; embed the quoted heading | The unrelated heading and its body are included | Stop at the selected section/container boundary before the next unrelated peer section |
| Paragraph ending with inline code `` `^literal` ``; `#^literal` embed | The paragraph is selected even though its normal rendering contains no block anchor | Literal code is not a block ID |
| Paragraph ending in escaped `\^literal` | The escape is lost and the visible caret/text are replaced by a block anchor | Escaped source remains literal, consistently with the preprocessing escape policy |

The comment case is a local rendering defect. No external disclosure or network
transmission was demonstrated. The original Markdown files are unchanged.

**Proposed correction.** Make fragment selection and rendering consume the same
semantic decisions about frontmatter, comments, escapes and code boundaries.
Reuse cmark source positions and a small common preprocessing/selection helper;
do not create a second parser or introduce a Markdown-engine replacement.
Keep enough source-range provenance to select only the intended body nodes.
Bound nested section ranges by their enclosing structure and subsequent heading
boundary. Preserve current valid heading/list/quote/table block embeds,
ambiguity warnings, recursive budgets and deterministic embedded-ID prefixes.

**Acceptance.** Add the five cases above as behavioral regressions, including a
paired whole-note render and fragment render. The hidden/YAML/code targets must
fail visibly rather than becoming content; escaped carets must remain visible;
the nested heading must exclude the unrelated marker. Existing valid section,
standalone list-block, recursive embed, footnote and table-identity checks must
remain green. This is a deliberate bug fix, not merely a mechanical extraction.

### R3 — Manual workflow dispatch on a tag can publish

**Priority:** P2, a delivery authorization-boundary mismatch. **Confidence:**
high. **Change:** small condition correction; low effort and low regression risk.

Locations: [`.github/workflows/release.yml:70`](../.github/workflows/release.yml#L70)
gates publication only on `github.ref_type == 'tag'`, while
[`docs/releases.md:6`](releases.md) promises that manual runs build/check without
publication. `scripts/publish.py:92` validates the tag/version but does not reject
the workflow-dispatch event.

**Trigger.** Dispatch the workflow manually against a matching, still-unpublished
tag, for example after its original tag-push run stopped. GitHub supports
dispatching against either a branch or tag. If build and environment requirements
succeed, the current condition enables the release/feed publication job.
[GitHub event documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch).

**Evidence.** The bounded delivery audit exercised `publish.publish` in memory
with `GITHUB_EVENT_NAME=workflow_dispatch`, a matching tag ref, substituted network
and filesystem methods. It recorded release creation, asset upload and release
publication requests. No real CI, network write or release operation occurred.
Effective remote environment approval rules were not checked; they may add a
further gate, but do not correct the workflow's event predicate.

**Proposed correction.** Require the intended event explicitly:
`github.event_name == 'push' && github.ref_type == 'tag'`. Consider the same
fail-closed event check at the publisher entry point if CI is its only authorized
caller; first characterize local recovery commands so that a guard does not
silently remove an established operator workflow.

**Acceptance.** A local event/ref matrix must deny publication for PR,
manual-branch and manual-tag events and allow the matching tag-push event.
Keep all existing immutable-release, signature, hash and readback tests. A real
workflow launch/publication remains a separately authorized operation.

## Conditional maintenance risk

**R4 — Yams cache identity omits the Swift toolchain.**
[`yaml-tools.py:23`](../scripts/yaml-tools.py#L23) fingerprints only its script and
accepts a warm cache when `libYams.a` exists. The current cache ships a binary
`.swiftmodule` without a `.swiftinterface`. A read-only in-memory probe confirmed
that the warm path performs zero compiler queries and zero build commands.
Swift documents that binary modules depend on compiler versions;
[module stability explanation](https://www.swift.org/blog/abi-stability-and-more/).

This is P3 and conditional: no actual compiler-upgrade failure was reproduced.
Include the selected toolchain/target in cache identity or let SwiftPM evaluate
its existing build graph, and validate the module/include outputs. Preserve
pinned checksums and reviewed notices. Validate with two distinct cache/toolchain
identities without switching the user's active developer tools. No new package
is needed.

## Remediation order and architectural choice

1. Correct R3's event gate as a small isolated change before another release
   workflow is used. Verify the event matrix entirely locally.
2. Fix R2's fragment semantics with targeted regressions, then extract only the
   semantic boundary that selection and rendering actually share.
3. Address R1 in separately verifiable stages: per-render lookup structure first,
   then asynchronous preparation and latest-result ownership. Preserve recovery,
   position capture, sidecars and embed-refresh contracts across both stages.
4. Repair R4 when touching dependency-build reproducibility; it does not block
   ordinary reading on the toolchain that passed this audit.

For R1, leaving the synchronous architecture unchanged retains the measured
stalls. A per-render lookup table is the smallest first improvement, but does not
remove blocking filesystem reads. Apple's existing Swift concurrency or
Dispatch/OperationQueue facilities provide the background-work mechanism; a
bounded serial worker is a reasonable initial fit for the current synchronous
renderer. The existing generation counter can continue to own final UI results.
A persistent vault database, filesystem watcher service or third-party job
framework would add freshness/migration obligations without current evidence of
need. Apple's [responsiveness guidance](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
supports moving non-UI work off the main thread and avoiding merely wrapping
synchronous work in a task that still runs on the main actor.

For R2, retain the already integrated, source-position-aware
[cmark-gfm API](https://github.com/github/cmark-gfm) and pinned Yams dependency.
The defects are in the adapter's inconsistent selection rules. An engine swap
would expand the regression surface across GFM, HTML safety, tables and embeds;
no observed defect requires that cost. No dependencies were added or upgraded.

## Verification and retained evidence

Executed successfully against the unchanged application source:

- `bash scripts/test.sh`: release identity validation, **42 Python tests**, shell
  syntax checks and both native reading/Obsidian smoke suites. Their publication
  messages came from fake-client tests, not actual remote publication.
- `bash build/code-audit-2026-11-13/run-probe.sh`: isolated AppKit/WebKit cases.
  The suspected folded-callout table-resize failure was **rejected**: measured
  columns started at 50/50, became 52/48 after keyboard resize and saved a sidecar.
  Nested duplicate YAML keys also correctly fell back to readable source.
- `bash build/code-audit-2026-11-13/run-render-probe.sh`: initial section and
  performance experiments. `render-probe.log` preserves the three-trial timings.
  The harness was then extended with full embeds;
  `bash build/code-audit-2026-11-13/run-render-probe.sh --sections-only` produced
  `sections.log`. These are temporary audit artifacts, not permanent tests.
- `PREVIEWMD_OUTPUT_DIR="$PWD/build/code-audit-2026-11-13/package" zsh scripts/build-app.sh`:
  fresh main-app/Quick Look compilation, metadata and ad hoc signing succeeded.
- `python3 scripts/check-app.py build/code-audit-2026-11-13/package/PreviewMD.app`:
  arm64 components, strict signatures, included notices and isolated real Sparkle
  preferences passed across fresh/relaunch/resume stages.

Local evidence:
probe source (`build/code-audit-2026-11-13/probe.swift`),
native probe results (`build/code-audit-2026-11-13/probe.log`),
render probe source (`build/code-audit-2026-11-13/render-probe.swift`),
render measurements (`build/code-audit-2026-11-13/render-probe.log`),
full-embed results (`build/code-audit-2026-11-13/sections.log`),
mock-only publication reproducer (`build/code-audit-2026-11-13/publisher-probe.py`),
build log (`build/code-audit-2026-11-13/build.log`),
package-check log (`build/code-audit-2026-11-13/check-app.log`).
These ignored local paths are evidence attachments, not release assets, and will
not accompany a normal clone. Reproduction uses synthetic fixtures only.
The retained runners now allocate a fresh fixture directory per invocation so
repeating them cannot reuse previously saved widths or the largest performance
corpus. This isolation-only adjustment passed shell syntax checks; the recorded
results above are from the original, initially empty fixture directories.

Plugin registration was sampled before the build, after it and after validation;
only the existing 0.1.3 provider remained listed. The installed app's plist still
reports 0.1.3/build 4. No provider removal was necessary. A live scoped search of
the personal Notion Tracker found no PreviewMD ticket; no ticket was created or
changed. No PR, push, tag, release, installed-app or user-data mutation occurred.

At the original audit handoff, implementation awaited authorization. The local
candidate remains unpublished, and the Finder sandbox and real updater transition
remain future explicitly authorized release checks.

## Implementation outcome

Local implementation was authorized after the audit and completed on 2026-11-13.
The candidate remains version 0.1.4/build 5; its icon, product scope, persisted
reading/sidecar formats and dependency versions are unchanged.

### Completed changes

- **R3:** the publication job requires both a `push` event and a tag ref. A test
  evaluates the actual workflow predicate for PR, manual branch, manual tag,
  branch push and tag push contexts. The publisher's existing operator/recovery
  entry point was preserved; no workflow was launched.
- **R2:** rendering and fragment selection share syntax preparation and the
  cmark dialect. Selection performs no linked-note reads and spends no unrelated
  embed budget. YAML/comments are excluded from addressable body sections;
  source-aware block IDs preserve escaped, entity and code literals; nested
  sections stop at their container. Valid list, quote, table and paragraph IDs,
  Unicode source positions, wiki labels and embedded table/footnote identities
  remain covered.
- **R1:** each render builds one case-insensitive basename lookup. File reads,
  indexing, parsing, sidecar restoration and complete HTML preparation run on a
  serial Dispatch worker. Each reader retains at most one active request and one
  replaceable pending request. Existing generation ownership rejects superseded
  results and late position callbacks; closing removes pending work. An active
  synchronous preparation is allowed to finish, but its discarded result cannot
  reopen or update the window. Back removes history only after successful loading.
- **R1, state consistency:** position capture validates the DOM's document token;
  late WebKit navigation completions are ignored. A successful table resize bumps
  a revision. If the same document's widths changed after preparation, its latest
  action is prepared again before commit, retaining the bounded queue. Resizing
  the old page does not cancel navigation to a different file. Zoom/width choices
  are read at commit, with width reapplied after the matching navigation finishes.
- **R4:** the Yams cache fingerprint includes the script, selected Swift command
  and version, SDK path/version and target. Cache hits also require a nonempty
  library, module and C headers. SwiftPM uses that selected command/SDK; a failed
  or incomplete rebuild does not record a successful new fingerprint.

The retained Swift/Dispatch design uses the system worker pool and the existing
generation owner. No third-party concurrency dependency, persistent vault index,
filesystem watcher, storage migration or parser replacement was introduced.
An independent executor at the same selected model/effort reviewed the async
ownership and found the stale-width race above; it was corrected before final
verification. No further blocking finding was identified in that bounded review.

### Before/after behavior and performance

New fragment regressions first failed with six assertions across the five audited
scenarios; they pass after the correction. New delivery/cache regressions first
produced nine expected subtest failures and now pass. A deliberately altered,
isolated copy without the table revision guard timed out on the new-DOM width
assertion; this demonstrates that the concurrent-resize regression detects the
race. The production source was not altered for that sensitivity check.

The old and corrected rendering sources were compiled separately using the same
Swift toolchain, arm64/macOS 13 target, unoptimized Swift flags and pinned native
libraries. Both read the exact same synthetic directories, with three trials for
each scale and 100 wikilinks per note. Every corresponding HTML size and SHA-256
matched. These are warm local-filesystem worker measurements; the earlier audit
timings used a separate run and are not the comparison denominator.

| Files | Baseline range | Corrected range | Median speedup |
| --- | --- | --- | --- |
| 100 | 39.9–46.6 ms | 10.8–15.4 ms | 3.7× |
| 2,000 | 664–680 ms | 56.9–64.0 ms | 11.0× |
| 10,000 | 3.30–3.78 s | 265–276 ms | 12.6× |

The integrated native suite also opened a real `ReaderWindow` over a separate
10,000-file/100-link synthetic vault. It reached the rendered WebKit document in
306 ms; a 5 ms main-thread heartbeat delivered 56 events with a maximum observed
gap of **32.4 ms**, below the 100 ms acceptance target. Another window's reading
width control worked while preparation was in progress. This is a single
reference-machine UI observation, not a guarantee for all hardware, cloud-only
files or arbitrary document sizes.

The deterministic native checks additionally pause real preparation both before
I/O and after HTML/sidecar capture. They exercise 40 superseded requests, profile
changes during reload, navigation during reload, failed Back and successful retry,
position retention, successful resize during a pending reload and window close.
These integration checks exercise actual ReaderWindow/WebKit/UserDefaults and
synthetic filesystem storage; the pure-render comparison alone would not prove
those ownership contracts.

### Final verification and evidence

The final `bash scripts/test.sh` passed **46 Python tests**, both prior native
smoke suites, the new fragment suite and asynchronous reader/responsiveness
scenarios. Existing source-preservation, corrupt-sidecar, vault-boundary,
cycle/budget, image, Find, navigation and embedded-refresh checks remain green.
No tests were skipped or relaxed to obtain this result.

Evidence retained locally:

- Final integrated test log (`build/code-audit-2026-11-13/final-tests.log`).
- Fragment failures before correction (`build/code-audit-2026-11-13/fragment-before.log`)
  and focused corrected results (`build/code-audit-2026-11-13/fragment-after.log`).
- Concurrent-width test sensitivity (`build/code-audit-2026-11-13/width-guard-sensitivity.log`).
- Comparable benchmark runner and exact flags (`build/code-audit-2026-11-13/comparison/run.sh`),
  baseline timings/hashes (`build/code-audit-2026-11-13/comparison/baseline.csv`)
  and corrected timings/hashes (`build/code-audit-2026-11-13/comparison/current.csv`).

The benchmark runner uses the retained original Swift sources in its `baseline`
subdirectory and current project sources for the corrected executable. Repeated
runs reuse the same scale-specific synthetic directories, preserving equivalent
inputs and paths. It never reads a real user vault.

Final package verification completed at 2026-11-13T11:32:08Z:

```sh
PREVIEWMD_OUTPUT_DIR="$PWD/build/code-audit-2026-11-13/final-package" zsh scripts/build-app.sh
python3 scripts/check-app.py build/code-audit-2026-11-13/final-package/PreviewMD.app
```

Both commands passed: main app/Quick Look compilation, arm64 binaries, strict
ad hoc signatures, bundled notices and isolated Sparkle fresh/relaunch/resume
preferences. See the final build log (`build/code-audit-2026-11-13/final-build.log`)
and final package-check log (`build/code-audit-2026-11-13/final-check-app.log`).
The development package is separate from the earlier audit package and installed
stable application. The installed plist still reports 0.1.3/build 4; plugin
registration is byte-for-byte unchanged from the audit snapshot. Icon/assets,
resources and release version are byte-for-byte unchanged from the starting Git
revision. Documentation links and `git diff --check` passed.

No remote CI, push, PR, tag, publication, installation or real user-vault action
was performed. The remaining operational checks are the previously stated
Finder-hosted sandbox preview and real updater transition, when separately
authorized. No unresolved R1–R4 implementation work remains in this local scope.
