#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc -swift-version 6 Sources/Paragrafo/Extraction.swift Sources/Paragrafo/DocumentState.swift Sources/Paragrafo/TranslationInput.swift Sources/Paragrafo/ReaderModel.swift Checks/Model/main.swift -o .build/checks/model-verify
.build/checks/model-verify
