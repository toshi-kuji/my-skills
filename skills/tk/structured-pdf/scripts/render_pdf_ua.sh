#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  cat >&2 <<'USAGE'
Usage:
  render_pdf_ua.sh input.md output.pdf "Document Title" [options]

Options:
  --lang LANG                         Default: en-US
  --paper SIZE                        Letter, A4, Legal, or CSS size. Default: Letter
  --margins "TOP RIGHT BOTTOM LEFT"   Default: 0.66in 0.72in 0.62in 0.72in
  --page-numbers none|bottom-center|bottom-right
                                      Default: none
  --font "FONT FAMILY"                Default: Times New Roman
  --font-size SIZE                    Default: 9.35pt
  --line-height VALUE                 Default: 1.17
  --content-width VALUE               Default: none
  --css FILE                          Extra user CSS loaded after generated base CSS
USAGE
  exit 2
fi

input="$1"
output="$2"
title="$3"
shift 3

lang="en-US"
paper="Letter"
margins="0.66in 0.72in 0.62in 0.72in"
page_numbers="none"
font="Times New Roman"
font_size="9.35pt"
line_height="1.17"
content_width="none"
extra_css=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --lang)
      lang="$2"; shift 2 ;;
    --paper)
      paper="$2"; shift 2 ;;
    --margins)
      margins="$2"; shift 2 ;;
    --page-numbers)
      page_numbers="$2"; shift 2 ;;
    --font)
      font="$2"; shift 2 ;;
    --font-size)
      font_size="$2"; shift 2 ;;
    --line-height)
      line_height="$2"; shift 2 ;;
    --content-width)
      content_width="$2"; shift 2 ;;
    --css)
      extra_css="$2"; shift 2 ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2 ;;
  esac
done

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
template="$skill_dir/templates/no-title.html"

command -v pandoc >/dev/null 2>&1 || {
  echo "pandoc is required" >&2
  exit 127
}

command -v weasyprint >/dev/null 2>&1 || {
  echo "weasyprint is required" >&2
  exit 127
}

case "$page_numbers" in
  none)
    page_rule=""
    ;;
  bottom-center)
    page_rule='@bottom-center { content: counter(page); font-family: "'"$font"'", serif; font-size: 9pt; }'
    ;;
  bottom-right)
    page_rule='@bottom-right { content: "Page " counter(page) " of " counter(pages); font-family: "'"$font"'", serif; font-size: 9pt; }'
    ;;
  *)
    echo "--page-numbers must be none, bottom-center, or bottom-right" >&2
    exit 2
    ;;
esac

if [ "$content_width" = "auto" ]; then
  content_width="none"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/structured-pdf.XXXXXX")"
tmp_css="$tmp_dir/style.css"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_css" <<CSS
@page {
  size: $paper;
  margin: $margins;
  $page_rule
}

html,
body {
  margin: 0;
  padding: 0;
  color: #111;
  background: #fff;
  font-family: "$font", serif;
  font-size: $font_size;
  line-height: $line_height;
}

body {
  max-width: $content_width;
  margin: 0 auto;
}

.caption {
  text-align: center;
  font-size: 12pt;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.02em;
  margin: 0 0 4pt 0;
}

.subtitle,
.date {
  text-align: center;
  font-size: 9.6pt;
  margin: 0 0 1pt 0;
}

.date {
  margin-bottom: 8pt;
}

.re {
  border-top: 0.75pt solid #222;
  padding-top: 5pt;
  margin: 0 0 9pt 0;
  font-weight: 700;
}

h1 {
  font-size: 10.2pt;
  line-height: 1.12;
  margin: 7pt 0 3pt 0;
  font-weight: 700;
  page-break-after: avoid;
}

h2 {
  font-size: 9.65pt;
  line-height: 1.12;
  margin: 5.4pt 0 2pt 0;
  font-weight: 700;
  page-break-after: avoid;
}

p {
  margin: 0 0 4.1pt 0;
}

blockquote {
  margin: 4pt 0 5pt 0.28in;
  padding-left: 0.13in;
  border-left: 1.2pt solid #777;
  font-size: 9.15pt;
}

ul,
ol {
  margin: 2pt 0 5pt 0.23in;
  padding-left: 0.17in;
}

li {
  margin: 0 0 2.1pt 0;
  padding-left: 0.02in;
}

.signature {
  margin-top: 9pt;
}
CSS

css_args=(--css "$tmp_css")
if [ -n "$extra_css" ]; then
  css_args+=(--css "$extra_css")
fi

pandoc "$input" \
  --from markdown+fenced_divs-smart \
  --template "$template" \
  --standalone \
  "${css_args[@]}" \
  --metadata title="$title" \
  --metadata lang="$lang" \
  --pdf-engine=weasyprint \
  --pdf-engine-opt=--pdf-tags \
  --pdf-engine-opt=--pdf-variant=pdf/ua-1 \
  -o "$output"

echo "Wrote $output"

if command -v pdfinfo >/dev/null 2>&1; then
  pdfinfo "$output" | rg "Title|Producer|Tagged|Metadata Stream|Pages|Encrypted|Page size|File size|PDF version" || true
fi

if command -v pdffonts >/dev/null 2>&1; then
  pdffonts "$output"
fi
