#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/checks
export PARAGRAFO_LIBRARY="$(mktemp -d)"
trap 'rm -rf "$PARAGRAFO_LIBRARY"' EXIT
swiftc Sources/Paragrafo/Extraction.swift Sources/Paragrafo/DocumentState.swift Sources/Paragrafo/TranslationInput.swift Sources/Paragrafo/Library.swift Sources/Paragrafo/Exporter.swift Sources/Paragrafo/AnswerFormatter.swift Checks/main.swift -o .build/checks/verify
.build/checks/verify
