#!/usr/bin/env bash

set -e

sudo apt update

sudo apt install -y \
    ghostscript \
    qpdf \
    mupdf-tools \
    exiftool \
    poppler-utils
