#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -m) == arm64 ]] || { echo 'Dieser Prototyp bündelt die Excel-Erweiterung für Apple Silicon.' >&2; exit 1; }
mkdir -p Vendor
if [[ ! -f Vendor/libduckdb.zip ]]; then
  curl -fL --retry 2 https://github.com/duckdb/duckdb/releases/download/v1.4.3/libduckdb-osx-universal.zip -o Vendor/libduckdb.zip
fi
if [[ ! -f Vendor/excel.duckdb_extension.gz ]]; then
  curl -fL --retry 2 https://extensions.duckdb.org/v1.4.3/osx_arm64/excel.duckdb_extension.gz -o Vendor/excel.duckdb_extension.gz
fi
# Pinned official release artifacts, hashed when first acquired for this project.
shasum -a 256 -c <<'SUMS'
efd0c2424589f0d5743ffdc0de22ce84b99bf307c330752f44277cffa3406e43  Vendor/libduckdb.zip
5938cb579eaa1770c4deaaca2c48318dc1b83d9084f43b8e33c49c70e4b42a86  Vendor/excel.duckdb_extension.gz
SUMS
unzip -o Vendor/libduckdb.zip -d Vendor
gzip -dc Vendor/excel.duckdb_extension.gz > Vendor/excel.duckdb_extension
python3 scripts/fixtures.py
