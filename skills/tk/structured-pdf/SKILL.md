---
name: tk-structured-pdf
description: Use when creating PDFs that should be structured, tagged, and have embedded font subsets. The user controls paper size, margins, page numbering, typography, content, and document structure; this skill supplies the technical Pandoc + WeasyPrint workflow and verification checks.
---

# Structured PDF

Create PDFs from Markdown or HTML with:

- meaningful heading/list/paragraph structure
- tagged PDF output (`Tagged: yes`)
- PDF/UA-oriented output settings (`--pdf-variant=pdf/ua-1`)
- embedded font subsets (`emb yes / sub yes / uni yes`)
- compact output when the content and fonts allow it

The user decides page size, margins, page numbers, typography, content, and document structure. Do not impose a legal-document layout unless requested.

## Preferred Toolchain

Use Pandoc to preserve semantic Markdown structure and WeasyPrint to render tagged PDF/UA-oriented output:

```bash
pandoc input.md \
  --from markdown+fenced_divs-smart \
  --template skills/tk-structured-pdf/templates/no-title.html \
  --standalone \
  --css generated-or-user.css \
  --metadata title="Document Title" \
  --metadata lang=en-US \
  --pdf-engine=weasyprint \
  --pdf-engine-opt=--pdf-tags \
  --pdf-engine-opt=--pdf-variant=pdf/ua-1 \
  -o output.pdf
```

Use the bundled helper script for repeatable output:

```bash
skills/tk-structured-pdf/scripts/render_pdf_ua.sh input.md output.pdf "Document Title" \
  --paper Letter \
  --margins "0.66in 0.72in 0.62in 0.72in" \
  --page-numbers none
```

Common options:

- `--paper Letter`, `--paper A4`, `--paper Legal`, or any CSS page size such as `8.5in 11in`
- `--margins "top right bottom left"` using CSS units
- `--page-numbers none|bottom-center|bottom-right`
- `--font "Times New Roman"` and `--font-size 9.35pt`
- `--line-height 1.17`
- `--content-width none` or a CSS length such as `7.05in`
- `--css path/to/extra.css` for user-specific styling
- `--lang en-US`

## Input Guidance

Use semantic Markdown:

- `#` for main sections
- `##` for subsections
- `-` or `1.` for lists
- `>` for quotes
- fenced divs for title blocks or special styling:

```markdown
::: {.caption}
SEC TCR Supplement - Cover Narrative
:::
```

Avoid manually spacing with blank lines, tabs, or ASCII art. Let CSS handle layout.

When converting from an existing prose draft, preserve the user's intended hierarchy. Do not invent headings, page numbers, captions, or filing labels unless the user asks.

## Verification

After generating, run:

```bash
pdfinfo output.pdf | rg "Title|Producer|Tagged|Metadata Stream|Pages|Encrypted|Page size|File size|PDF version"
pdffonts output.pdf
pdftotext -layout output.pdf - | sed -n '1,80p'
```

Expected:

- `Producer: WeasyPrint ...`
- `Tagged: yes`
- `Metadata Stream: yes`
- `Encrypted: no`
- requested page size
- `pdffonts`: every font row should show `emb yes`, `sub yes`, `uni yes`

If the user cares about viewer outline/bookmarks, open the PDF and confirm headings appear in the viewer's outline/sidebar. Chrome-generated tagged PDFs may show `Tagged: yes` but still lack useful outline/bookmark structure.

## When To Use Chrome Instead

Use Chrome headless only when the user prioritizes browser CSS fidelity over PDF structure. Chrome can create tagged PDFs, but it may not preserve useful outline/bookmark navigation from headings.

For structured filing PDFs, default to Pandoc + WeasyPrint with `--pdf-tags` and `--pdf-variant=pdf/ua-1`.
