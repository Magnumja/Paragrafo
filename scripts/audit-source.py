#!/usr/bin/env python3
"""Small offline release hygiene gate; not a substitute for a security audit."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
patterns = [re.compile(p.encode()) for p in (
    r'gh[pousr]_[A-Za-z0-9]{30,}', r'github_pat_[A-Za-z0-9_]{40,}',
    r'sk-[A-Za-z0-9_-]{30,}', r'AKIA[0-9A-Z]{16}', r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
)]
failed = []
for name in subprocess.check_output(['git', 'ls-files'], cwd=root, text=True).splitlines():
    path = root / name
    if not path.is_file():
        continue
    data = path.read_bytes()
    if any(p.search(data) for p in patterns):
        failed.append(name)
    if path.suffix.lower() in {'.pdf', '.gguf', '.p12', '.pem', '.vec'} or name.startswith(('.build/', 'dist/')):
        failed.append(name)
if failed:
    raise SystemExit('Review tracked files: ' + ', '.join(sorted(set(failed))))
print('PASS: tracked files contain no matching credentials, PDFs, model weights or build output')
