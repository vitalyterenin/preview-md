#!/usr/bin/env python3
"""Build reviewed Yams + its bundled libyaml with their dependency-free Swift package."""
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import licenses

VERSION = '6.2.2'
ARCHIVE_SHA256 = 'c18b63003173ff886eb781e0cbb2cba612fb5c68485b0cd4e66ad06b686091e8'
ROOT = Path(__file__).resolve().parent.parent


def build():
    licenses.source_files()
    cache = Path(os.environ.get('PREVIEWMD_YAML_TOOLS_DIR', ROOT / 'build/tools' / ('yams-' + VERSION)))
    cache.mkdir(parents=True, exist_ok=True)
    fingerprint = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    stamp = cache / 'build-stamp'
    if stamp.exists() and stamp.read_text() == fingerprint and (cache / 'libYams.a').exists():
        return cache
    archive = cache / 'source.tar.gz'
    if not archive.exists():
        data = urllib.request.urlopen('https://codeload.github.com/jpsim/Yams/tar.gz/refs/tags/' + VERSION, timeout=60).read()
        if hashlib.sha256(data).hexdigest() != ARCHIVE_SHA256:
            raise ValueError('Yams archive checksum mismatch')
        archive.write_bytes(data)
    data = archive.read_bytes()
    if hashlib.sha256(data).hexdigest() != ARCHIVE_SHA256:
        raise ValueError('Cached Yams archive checksum mismatch')
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for entry in tar.getmembers():
            parts = Path(entry.name).parts
            if not (entry.isfile() or entry.isdir()) or Path(entry.name).is_absolute() or '..' in parts:
                raise ValueError('Unsafe Yams archive entry')
            if Path(entry.name).name.lower() in ('agents.md', 'agents.override.md', 'agent-rules.md'):
                raise ValueError('Unexpected agent instruction in dependency')
        tar.extractall(cache)
    source = cache / ('Yams-' + VERSION)
    if hashlib.sha256((source / 'LICENSE').read_bytes()).hexdigest() != licenses.YAMS_LICENSE_SHA256:
        raise ValueError('Yams license differs from reviewed notice')
    subprocess.run(['swift', 'build', '--package-path', str(source), '-c', 'release',
                    '--triple', 'arm64-apple-macosx13.0'], check=True, stdout=sys.stderr)
    output = Path(subprocess.check_output(['swift', 'build', '--package-path', str(source), '-c', 'release',
                                           '--triple', 'arm64-apple-macosx13.0', '--show-bin-path'], text=True).strip())
    modules = cache / 'modules'
    modules.mkdir(exist_ok=True)
    if (output / 'libYams.a').exists():
        shutil.copyfile(output / 'libYams.a', cache / 'libYams.a')
        shutil.copytree(output / 'Yams.swiftmodule', modules / 'Yams.swiftmodule', dirs_exist_ok=True)
    else:
        # Older SwiftPM emits objects for automatic library products.
        objects = list((output / 'Yams.build').glob('*.o')) + list((output / 'CYaml.build').rglob('*.o'))
        if not objects:
            raise ValueError('SwiftPM did not emit Yams/CYaml objects')
        subprocess.run(['xcrun', 'libtool', '-static', '-o', str(cache / 'libYams.a'), *map(str, objects)], check=True)
        shutil.copytree(output / 'Modules', modules, dirs_exist_ok=True)
    shutil.copytree(source / 'Sources/CYaml/include', cache / 'include', dirs_exist_ok=True)
    stamp.write_text(fingerprint)
    return cache


if __name__ == '__main__':
    print(build())
