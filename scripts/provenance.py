#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Frozen repository/tool identities shared by validation and measurement."""
from pathlib import Path
import hashlib, os, re, subprocess, sys
ROOT = Path(__file__).resolve().parents[1]
def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def source():
    paths = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT).split(b'\0')
    files = {}
    for raw in sorted(set(paths) - {b''}):
        path = ROOT / os.fsdecode(raw)
        data = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes() if path.exists() else b'<deleted>'
        files[os.fsdecode(raw)] = {'sha256': hashlib.sha256(data).hexdigest(),
                                 'mode': path.lstat().st_mode if path.exists() or path.is_symlink() else 0}
    return {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'status': subprocess.check_output(['git', 'status', '--short', '--untracked-files=all'], cwd=ROOT, text=True),
            'files': files}
def tool(path):
    path = Path(path).resolve(strict=True)
    return {'path': str(path), 'sha256': sha256(path),
            'version': subprocess.check_output([str(path), '--version'], text=True).strip()}
def inputs(goose, compiler):
    result = {'source': source(), 'goose_revision': (ROOT / 'GOOSE_REVISION').read_text().strip(),
              'tools': {'goose': tool(goose), 'cc': tool(compiler), 'python': {
                  'path': str(Path(sys.executable).resolve()), 'sha256': sha256(sys.executable), 'version': sys.version}}}
    advertised = re.search(r'\bgoose ([0-9a-f]{7,40})\b', result['tools']['goose']['version'])
    if advertised is None or not result['goose_revision'].startswith(advertised.group(1)):
        raise RuntimeError('Goose executable does not advertise the pinned source revision')
    return result
