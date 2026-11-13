#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/checks
export PARAGRAFO_LIBRARY="$(mktemp -d)"
trap 'rm -rf "$PARAGRAFO_LIBRARY"' EXIT
swiftc -swift-version 6 Sources/Paragrafo/Extraction.swift Sources/Paragrafo/DocumentState.swift Sources/Paragrafo/Library.swift Sources/Paragrafo/Exporter.swift Sources/Paragrafo/AnswerFormatter.swift Sources/Paragrafo/Ollama.swift Sources/Paragrafo/RAG.swift Sources/Paragrafo/Assistant.swift Checks/Assistant/main.swift -o .build/checks/assistant-verify
.build/checks/assistant-verify "$@"
