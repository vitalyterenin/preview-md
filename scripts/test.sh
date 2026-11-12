#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/release.py validate
python3 -m unittest discover -s tests -p 'test_*.py'
zsh -n scripts/build-app.sh
bash -n scripts/sparkle-tools.sh
