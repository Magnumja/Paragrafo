#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc -O Sources/Paragrafo/Extraction.swift Checks/Resources/main.swift -o .build/checks/resource-profile
/usr/bin/time -l .build/checks/resource-profile
