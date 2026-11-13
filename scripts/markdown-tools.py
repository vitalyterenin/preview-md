#!/usr/bin/env python3
"""Build the pinned cmark-gfm sources with Apple's C toolchain (no runtime dependency)."""
import concurrent.futures
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request
import licenses

REVISION = '27d942c8b0a62d192f616e5bf3578f4b6a89e180'
ARCHIVE_SHA256 = 'f8710b90b90a503240c920c6922367e700bb9895bb02018d6448d2f812fc7968'
ROOT = Path(__file__).resolve().parent.parent


def build():
    if REVISION != licenses.CMARK_REVISION:
        raise ValueError('cmark-gfm revision differs from reviewed notices')
    licenses.source_files()
    cache = Path(os.environ.get('PREVIEWMD_MARKDOWN_TOOLS_DIR', ROOT / 'build' / 'tools' / ('cmark-' + REVISION)))
    cache.mkdir(parents=True, exist_ok=True)
    fingerprint = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    stamp = cache / 'build-stamp'
    if stamp.exists() and stamp.read_text() == fingerprint and (cache / 'libcmark.a').exists():
        return cache
    archive = cache / 'source.tar.gz'
    if not archive.exists():
        data = urllib.request.urlopen('https://codeload.github.com/github/cmark-gfm/tar.gz/' + REVISION, timeout=60).read()
        if hashlib.sha256(data).hexdigest() != ARCHIVE_SHA256:
            raise ValueError('cmark-gfm archive checksum mismatch')
        archive.write_bytes(data)
    data = archive.read_bytes()
    if hashlib.sha256(data).hexdigest() != ARCHIVE_SHA256:
        raise ValueError('Cached cmark-gfm archive checksum mismatch')
    source = cache / ('cmark-gfm-' + REVISION)
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for entry in tar.getmembers():
            # This pinned source has only regular files/directories. Reject links and traversal.
            if entry.issym() or entry.islnk() or not (entry.isfile() or entry.isdir()):
                raise ValueError('Unexpected source archive entry')
            if Path(entry.name).is_absolute() or '..' in Path(entry.name).parts:
                raise ValueError('Unsafe source archive path')
        tar.extractall(cache)
    if hashlib.sha256((source / 'COPYING').read_bytes()).hexdigest() != licenses.CMARK_COPYING_SHA256:
        raise ValueError('cmark-gfm upstream COPYING differs from reviewed notices')
    include = cache / 'include'
    include.mkdir(exist_ok=True)
    for directory in ('src', 'extensions'):
        for header in (source / directory).glob('*.h'):
            shutil.copyfile(header, include / header.name)
    # The only CMake feature tests needed by this macOS-only static build are
    # supported by Apple Clang. Source lists and version come from upstream CMake.
    config = (source / 'src/config.h.in').read_text()
    (include / 'config.h').write_text(config.replace('#cmakedefine ', '#define '))
    (include / 'cmark-gfm_export.h').write_text('#define CMARK_GFM_EXPORT\n#define CMARK_GFM_NO_EXPORT\n#define CMARK_GFM_DEPRECATED __attribute__((deprecated))\n')
    version = (source / 'src/cmark-gfm_version.h.in').read_text()
    for key, value in [('MAJOR', '0'), ('MINOR', '29'), ('PATCH', '0'), ('GFM', '13')]:
        version = version.replace('@PROJECT_VERSION_' + key + '@', value)
    (include / 'cmark-gfm_version.h').write_text(version)
    (include / 'module.modulemap').write_text('module CMark {\n header "cmark-gfm.h"\n header "cmark-gfm-extension_api.h"\n header "cmark-gfm-core-extensions.h"\n export *\n}\n')
    objects = cache / 'objects'
    objects.mkdir(exist_ok=True)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    sources = [p for d in ('src', 'extensions') for p in (source / d).glob('*.c') if p.name != 'main.c']
    def compile_file(path):
        output = objects / (path.parent.name + '-' + path.stem + '.o')
        subprocess.run(['xcrun', 'clang', '-target', 'arm64-apple-macosx13.0', '-isysroot', sdk,
                        '-O2', '-fvisibility=hidden', '-DCMARK_GFM_STATIC_DEFINE', '-I', str(include),
                        '-I', str(source / 'src'), '-I', str(source / 'extensions'),
                        '-c', str(path), '-o', str(output)], check=True)
        return output
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        outputs = list(pool.map(compile_file, sources))
    subprocess.run(['xcrun', 'libtool', '-static', '-o', str(cache / 'libcmark.a'), *map(str, outputs)], check=True)
    shutil.copyfile(source / 'COPYING', cache / 'COPYING')
    stamp.write_text(fingerprint)
    return cache


if __name__ == '__main__':
    print(build())
