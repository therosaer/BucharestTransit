#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v inotifywait >/dev/null 2>&1; then
    echo "inotifywait is required to watch source changes." >&2
    exit 1
fi

install_app() {
    echo "Building and installing on the USB-connected iPhone..."
    if xtool dev run --usb; then
        echo "Install complete. Watching for app changes..."
    else
        echo "Install failed. Fix the issue or reconnect the iPhone; the next change will retry." >&2
    fi
}

install_app

while true; do
    inotifywait --quiet --recursive \
        --event close_write,create,delete,move \
        --format '%w%f' \
        Sources Package.swift Info.plist xtool.yml |
    while IFS= read -r changed; do
        echo "Change detected: $changed"
        while IFS= read -r -t 1 next_change; do
            echo "Change detected: $next_change"
        done
        install_app
    done
done
