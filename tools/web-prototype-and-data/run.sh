#!/usr/bin/env bash
# Bucharest Public Transport Interactive App - Launcher Script
set -e

export PORT="${PORT:-8080}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo "🚎 Bucharest Public Transport - Interactive Live App"
echo "=========================================================="
echo "Directory: $DIR"
echo "Target Port: $PORT"
echo ""

cd "$DIR"

# Check Python3 availability
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: python3 is required to run this application."
    exit 1
fi

echo "Starting server (zero external dependencies)..."
exec python3 app.py
