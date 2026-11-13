#!/usr/bin/env python3
# SPDX-License-Identifier: MIT; adapted from Vitaly Terenin’s release tooling.
"""Install and verify the approved project and dependency notices before signing."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil

ROOT = Path(__file__).resolve().parent.parent
FILES = ('LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md')
# The owner approved Apache-2.0 for PreviewMD; changes need a new approval.
CMARK_REVISION = '27d942c8b0a62d192f616e5bf3578f4b6a89e180'
CMARK_COPYING_SHA256 = 'c22e885f33b821bddb24cf007145e5540655b6c0f403e49e6c76a93c28e6d9a9'
APACHE_SHA256 = 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30'


def source_files():
    data = json.loads((ROOT / 'release.json').read_text())
    if data.get('license') != 'Apache-2.0':
        raise ValueError('PreviewMD requires its owner-approved Apache-2.0 license')
    files = {name: (ROOT / name).read_bytes() for name in FILES}
    if hashlib.sha256(files['LICENSE']).hexdigest() != APACHE_SHA256:
        raise ValueError('Apache-2.0 terms are incomplete or changed')
    if b'Copyright 2026 Vitaly Terenin' not in files['NOTICE']:
        raise ValueError('The project copyright notice is missing')
    sparkle = data['sparkleVersion']
    if f'## Sparkle {sparkle}\n'.encode() not in files['THIRD_PARTY_NOTICES.md']:
        raise ValueError('Third-party notices do not match the pinned Sparkle version')
    notices = files['THIRD_PARTY_NOTICES.md'].decode()
    marker = '## cmark-gfm ' + CMARK_REVISION + '\n'
    if marker not in notices:
        raise ValueError('Missing pinned cmark-gfm notice')
    try:
        copying = notices.split(marker, 1)[1].split('```text\n', 1)[1].split('```', 1)[0]
    except IndexError:
        raise ValueError('Missing complete cmark-gfm COPYING')
    if hashlib.sha256(copying.encode()).hexdigest() != CMARK_COPYING_SHA256:
        raise ValueError('Changed or incomplete cmark-gfm COPYING')
    return files, sparkle


def verify_bundle(app):
    app = Path(app)
    files, sparkle = source_files()
    for name, expected in files.items():
        if (app / 'Contents/Resources/Licenses' / name).read_bytes() != expected:
            raise ValueError(f'Installed app is missing the exact {name}')
    plist = app / 'Contents/Frameworks/Sparkle.framework/Resources/Info.plist'
    if plistlib.loads(plist.read_bytes()).get('CFBundleShortVersionString') != sparkle:
        raise ValueError('Bundled Sparkle differs from the reviewed third-party notices')


def install(app, dependency_license):
    files, _ = source_files()
    upstream = Path(dependency_license).read_bytes()
    if not upstream.strip() or upstream not in files['THIRD_PARTY_NOTICES.md']:
        raise ValueError('Complete upstream Sparkle license and external notices must be preserved')
    destination = Path(app) / 'Contents/Resources/Licenses'
    destination.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        (destination / name).write_bytes(content)
    verify_bundle(app)


def stage_distribution(app, directory):
    verify_bundle(app)
    for name in FILES:
        shutil.copyfile(ROOT / name, Path(directory) / name)


def verify_distribution(directory, app_name):
    directory = Path(directory)
    verify_bundle(directory / app_name)
    for name, expected in source_files()[0].items():
        if (directory / name).read_bytes() != expected:
            raise ValueError(f'Disk image is missing the exact {name}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['install', 'verify'])
    parser.add_argument('--app', required=True)
    parser.add_argument('--sparkle-license')
    args = parser.parse_args()
    if args.command == 'install':
        if not args.sparkle_license: parser.error('--sparkle-license is required for install')
        install(args.app, args.sparkle_license)
    else:
        verify_bundle(args.app)
    print('Verified project license and complete third-party notices in the app bundle')
