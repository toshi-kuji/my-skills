---
name: ocr
description: Use when Codex needs to OCR PDFs or image files on macOS, especially converting .pdf, .jpg, .jpeg, or .png files to UTF-8 .txt files with Japanese and English text recognition using Apple's Vision framework.
---

# OCR

## Overview

Use this skill to convert PDFs and images to UTF-8 `.txt` files on macOS. The bundled Swift tool uses PDFKit, Vision, and ImageIO, and is designed for Japanese and English OCR.

## Workflow

1. Put target files in one folder, or identify the folder the user wants processed.
2. Run the bundled runner:

```sh
/Users/toshi/.codex/skills/ocr/scripts/run-ocr.sh /path/to/folder
```

If no folder is supplied, the runner processes `$PWD/tmp`.

Useful options:

```sh
# Process a folder recursively.
/Users/toshi/.codex/skills/ocr/scripts/run-ocr.sh --recursive /path/to/folder

# Process one file.
/Users/toshi/.codex/skills/ocr/scripts/run-ocr.sh /path/to/file.pdf

# Resume a large run without overwriting existing non-empty .txt outputs.
/Users/toshi/.codex/skills/ocr/scripts/run-ocr.sh --recursive --skip-existing /path/to/folder

# Write a machine-readable TSV report.
/Users/toshi/.codex/skills/ocr/scripts/run-ocr.sh --recursive --report /path/to/ocr-report.tsv /path/to/folder
```

## Behavior

- Supported inputs: `.pdf`, `.jpg`, `.jpeg`, `.png`.
- Processing scope: direct children of target folders by default; use `--recursive` to include nested folders.
- Targets: one or more files and/or folders may be supplied.
- Output: same folder and same basename as the input, with `.txt` extension.
- Existing `.txt` outputs are overwritten by default; use `--skip-existing` to keep existing non-empty outputs.
- If a file fails, the tool logs `[FAIL]` and continues with the remaining files.
- `--report PATH` writes a TSV report with input, output, status, method, page count, and error columns.
- Exit code `0` means all target files succeeded, or no target files were found.
- Exit code `1` means at least one file failed.
- Exit code `2` means invalid invocation or target folder error before processing.

## Do Not Use Swift JIT

Do not run this tool with:

```sh
swift /Users/toshi/.codex/skills/ocr/scripts/main.swift /path/to/folder
```

The Swift interpreter/JIT can fail when resolving Vision and PDFKit Objective-C symbols. Always use `scripts/run-ocr.sh`; it compiles with `swiftc`, sets module cache paths under `/private/tmp`, and then runs the compiled binary.

## Implementation Notes

- PDFs are rendered page-by-page to RGB bitmap images before OCR.
- If Vision OCR fails for a PDF page, the tool falls back to `PDFPage.string` for that page when embedded text is available.
- If PDFKit/Vision extraction fails for a PDF and `pdftotext` is available on `PATH`, the tool uses `pdftotext -layout` as a file-level fallback.
- Embedded PDF text may contain broken line wrapping, but it is preferable to failing the whole file when Vision is unavailable.
- Images are normalized to RGB bitmap images before OCR.
- Vision OCR uses accurate recognition and prefers Japanese/English when supported by the host.
- If errors mention `CVPixelBuffer`, `NSOSStatusErrorDomain(-6662)`, or `Foundation._GenericObjCError(0)`, Vision may be blocked by the current sandbox. Retry the same runner outside the sandbox before treating the input file as corrupt.
