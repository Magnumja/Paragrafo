# Contributing

Use a short branch and a focused PR. Describe the trigger, expected behavior and the checks run. UI text is Brazilian Portuguese; documentation is available in English and Portuguese.

```sh
./check.sh
./check-model.sh
./check-rag.sh
./check-assistant.sh
./build-app.sh
```

The last two suites exercise local inference only when Ollama is available. They never download models automatically in CI. Use synthetic documents, never private PDFs. Keep dependencies optional, respect Reduce Transparency, and measure memory/CPU before claiming a performance gain. Do not commit `.build`, `dist`, model weights, saved libraries or credentials.

Security issues belong in private vulnerability reports, not public issues. See [SECURITY.md](SECURITY.md).
