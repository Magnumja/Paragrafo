#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc -O Sources/Paragrafo/Extraction.swift Sources/Paragrafo/DocumentState.swift Checks/Performance/main.swift -o .build/checks/benchmark
.build/checks/benchmark
