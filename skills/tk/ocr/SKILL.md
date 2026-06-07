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

## Behavior

- Supported inputs: `.pdf`, `.jpg`, `.jpeg`, `.png`.
- Processing scope: direct children of the target folder only; no recursive traversal.
- Output: same folder and same basename as the input, with `.txt` extension.
- Existing `.txt` outputs are overwritten.
- If a file fails, the tool logs `[FAIL]` and continues with the remaining files.
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
- Embedded PDF text may contain broken line wrapping, but it is preferable to failing the whole file when Vision is unavailable.
- Vision OCR uses accurate recognition and prefers Japanese/English when supported by the host.
