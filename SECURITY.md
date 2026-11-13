# Security policy

## Supported version

The latest `0.3.x` release receives security fixes. This is an early, locally signed macOS app, **not notarized or independently audited**. Do not interpret this review as a guarantee that every PDF is safe to open.

Report vulnerabilities using this repository's **Security → Report a vulnerability**. Do not include private PDFs, tokens, local paths or personal information in public issues. Include the affected version, a synthetic reproduction, expected impact and macOS version.

## Data and trust boundaries

- PDF parsing: Apple PDFKit; OCR: Vision; translation: Apple's Translation framework. Keep macOS updated. Password-protected PDFs must be unlocked before import.
- No third-party Swift packages. No account, telemetry or analytics in the application.
- Questions and excerpts go to an Ollama server over numeric loopback HTTP only. HTTP redirects and system proxies are disabled for this client. Listed cloud-backed models and names containing `cloud` are excluded/rejected. The app cannot inspect arbitrary custom model implementations: keep Ollama updated and configure local-only mode (`OLLAMA_NO_CLOUD=1`) for stronger assurance. Never expose its port to an untrusted network.
- Downloads of language packs and Ollama models need internet. Translation/assistant operations after installation use the native engine and local server respectively.
- Document excerpts and model responses are untrusted text. The app gives the model no tools, filesystem-write or shell capability. Generated external links are blocked; internal source/page links are validated. Prompt injection can still distort an answer or citation; verify the actual source.
- Saved translations, summaries, source snippets, vectors and recent file paths live in `~/Library/Application Support/Paragrafo/`. They are **not application-encrypted**. Newly created library directories use owner-only permissions; written files use `0600`. FileVault protects data at rest when configured by the user. Backups and system sync may retain copies according to user settings.
- Storage keys accept a bounded filename alphabet and reject targets resolving outside the library. Vector shapes have bounds and are checked before allocation/arithmetic. Only the application's cache is removed when a document is forgotten; original PDFs are not deleted.
- Chat history is held in memory, not restored between sessions. Summaries and their source snippets are saved with the document until it is forgotten.

## Release integrity

Release downloads include SHA-256 checksums. The `.app` is ad hoc signed; verify checksums before opening. No Developer ID identity or Apple notarization is claimed. Release builds contain code and branding only, without PDFs, models or the library. Tests use isolated temporary libraries.

See [the release review](docs/RELEASE-REVIEW.md) for the exact checks, findings and remaining limitations.
