
# PDF Cleaner

A Bash utility that sanitizes PDF files by removing metadata, rebuilding the document structure, and generating a forensic report before and after the cleaning process.

The script is intended for users who want to inspect a PDF for potentially suspicious content and reduce unnecessary metadata before sharing or archiving the document.

## Features

- Generates a forensic report before and after cleaning.
- Removes document metadata.
- Rebuilds the PDF using Ghostscript.
- Linearizes the PDF with QPDF.
- Cleans the internal object structure using MuPDF.
- Checks for:
  - Metadata
  - Digital signatures
  - Embedded attachments
  - JavaScript
  - Suspicious PDF objects

## Requirements

The following tools must be installed:

- bash
- ghostscript
- qpdf
- mupdf-tools
- exiftool
- poppler-utils

On Debian/Ubuntu:

```bash
sudo ./install_dependencies.sh
