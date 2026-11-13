# Release review — 0.3.0 — 2026-11-13

This is a scoped engineering review, not an independent penetration test or a guarantee of safety. The release is an early Apple Silicon build, ad hoc signed and not notarized. macOS 15 is the minimum deployment target; testing here used an Apple M5 with 16 GB RAM. CI also builds/checks on macOS 15.

## Security findings addressed

| Finding | Change | Evidence |
|---|---|---|
| A tampered storage key could form a path outside the library | Bounded filename alphabet, resolved-parent checks, owner-only permissions for new storage | Traversal and escaping-symlink regression checks |
| Malformed vector dimensions could overflow size arithmetic | Dimension/count/128 MiB bounds before multiplication and load | `Int.max` regression check |
| Loopback requests could follow a redirect or use a system proxy | Numeric loopback HTTP allowlist, no redirects, no proxies | Endpoint policy tests and source review |
| A cloud-backed Ollama model could contradict local-first claims | Filter `remote_model`/`remote_host` metadata and reject cloud names | Model policy check; local inference checks |
| Model-authored Markdown could open an arbitrary URL | Only validated in-app source/page links are handled | Negative-citation test and UI handler review |

No third-party Swift packages exist in Package.swift. Tracked files and Git history were scanned locally for common credential patterns; no matches were found. Such pattern scanning does not detect every possible secret. No original/user PDFs, local saved library, model weights or build output are published. Screenshots use a synthetic Northwind document.

## Resource findings addressed

- The app previously asked Ollama to keep both models loaded for **30 minutes** after a request. It now requests **2 minutes**, a 93% shorter retention interval. This changes the idle residency policy; it is not a measured 93% reduction in memory. Other clients of the shared Ollama server can extend residency.
- Generation is limited to **1,024 output tokens** and chat context to **8,192 tokens**. These bounds contain runaway generation; long answers can reach the limit. The models remain optional and are never bundled or silently downloaded.
- Per-page autorelease pools now release temporary PDFKit/Vision objects during extraction. A 200-page text fixture was measured before and after, optimized builds, three fresh processes each:

| | Before | After |
|---|---:|---:|
| Peak process RSS, median | 76.81 MiB | 74.41 MiB |
| Extraction time, median | 0.219 s | 0.219 s |

The memory benefit is modest (~2.4 MiB), stable across these three runs. There is no extraction-speed improvement on this fixture. Generation of the fixture is included in peak RSS, not in reported extraction time. This does not predict performance for complex scans or every PDF.

- The release `.app` is approximately **4.1 MiB on disk**, before ZIP compression. The development build cache is over 1 GB and is excluded from Git and releases.
- The local Ollama server reported about **0.69 GB** for the embedding model and **3.12 GB** for the chat model with 8K context in the existing running setup. These are separate model allocations, not the app binary; model/hardware choices change them. No claim that the full AI workflow is lightweight on every Mac is made.
- Rendering remains paginated and lazy, generation is refreshed at most ~15 times/second, embedding batches are bounded, and indexing runs only when requested. No background polling of the server occurs while the assistant is inactive.

## Verification

Local commands completed:

- `./check.sh`: real text PDF and image-only OCR, paragraph boundaries, saved work, export, storage isolation and security regressions.
- `./check-model.sh`: reuse/invalidation of a translation language pair and pause before session startup.
- `./check-rag.sh`: chunk coverage, vector search, multilingual retrieval, local endpoint/model policy, actual local embeddings and generation, missing models, cancellation.
- `./check-assistant.sh`: synthetic six-section PDF → index → questions/citations → summary → cancellation → saved-index restoration with real `bge-m3` and `llama3.2:3b`.
- Release build and `codesign --verify --strict`.
- GitHub Actions independently runs checks/build; real inference explicitly skips when Ollama is unavailable. Native translation with installed language packs is a manual validation from the app's development history, not exercised by headless CI.

## Remaining limits and rollout

- The app is not sandboxed and can read selected files with the user's filesystem permissions. PDFKit/Vision and the locally installed Ollama server are trusted dependencies; keep them updated.
- Saved work is plaintext in Application Support. The app does not manage full-disk encryption, backups or external sync settings. New files are owner-readable/writable; existing directory permissions are preserved.
- Model inference can hallucinate or cite the wrong passage. Documents can contain prompt injection. The model has no tools or shell/file authority, but textual correctness is not guaranteed.
- No stress test of thousands of scanned pages or every model was performed. Memory/CPU depends on document and model; pausing cancels the app's work but does not stop another Ollama client's work.
- No universal Intel binary, Developer ID signing, notarization, automatic updates or crash telemetry is included.
- Rollback: keep the previous app bundle and replace it if needed; the app's saved library is not automatically deleted or migrated destructively. The first public release has no earlier public release to roll back to.

Reproduce the current extraction profile with `./benchmark-resources.sh` (synthetic PDF, removed on exit). Run several times on the same machine. `./benchmark.sh` measures only the historical metadata lookup paths, not complete frame rendering.
