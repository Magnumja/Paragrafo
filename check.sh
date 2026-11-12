#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc Sources/Paragrafo/Extraction.swift Checks/main.swift -o .build/checks/verify
.build/checks/verify
