---
название: Synthetic profile demonstration
готово: true
число: 7
дата: 2026-11-13
aliases: [Profile demo, Reading home]
связи:
  - "[[obsidian-note|Related note]]"
описание: |
  This property is literal text, including **these asterisks**.
---
# Obsidian profile demo

This is a synthetic example, not an export of a personal vault. Auto detects its
Obsidian syntax. Choose CommonMark or GitHub in the profile menu to compare how
that same source is interpreted; the file itself stays unchanged.

Follow [[obsidian-note|the related note]], jump to
[[obsidian-note#Reading section|a heading]], or follow
[[obsidian-note#^reading-block|a named block]]. Use Back to return here.

## Embedded content

![[markdown-sample-illustration.svg|320]]

![[obsidian-note#Reading section]]

![[obsidian-note#^reading-block]]

## Reading annotations

> [!tip]+ A foldable callout
> Click the title to hide or show this content.
>
> > [!note] Nested callout
> > Note content supports **Markdown** and [[obsidian-note|links]].

This sentence contains ==highlighted **text**== and a footnote.[^example]
%% This comment is intentionally hidden in Obsidian mode. %%

- [x] Read the rendered note
- [ ] Follow its links and return

[^example]: Footnotes are read-only, like the rest of the document.

Code examples are literal, and do not select Obsidian automatically by themselves:

```md
[[literal link]] ==literal highlight== %%literal comment%%
```
