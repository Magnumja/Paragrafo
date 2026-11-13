#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/checks
export PARAGRAFO_LIBRARY="$(mktemp -d)"
trap 'rm -rf "$PARAGRAFO_LIBRARY"' EXIT
swiftc -swift-version 6 Sources/Paragrafo/Extraction.swift Sources/Paragrafo/DocumentState.swift Sources/Paragrafo/TranslationInput.swift Sources/Paragrafo/ReaderModel.swift Sources/Paragrafo/Library.swift Sources/Paragrafo/Exporter.swift Checks/Model/main.swift -o .build/checks/model-verify
.build/checks/model-verify
