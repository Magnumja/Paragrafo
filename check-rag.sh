#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc -swift-version 6 Sources/Paragrafo/Extraction.swift Sources/Paragrafo/Ollama.swift Sources/Paragrafo/RAG.swift Checks/RAG/main.swift -o .build/checks/rag-verify
.build/checks/rag-verify
