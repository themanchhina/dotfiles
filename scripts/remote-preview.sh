#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || "$1" == -h || "$1" == --help ]]; then
  echo "Usage: $0 HOST [LOCAL_PORT]"
  echo "Run on your Mac, then use <Space>cp in remote Neovim. Ctrl-C closes the bridge."
  [[ $# -eq 1 && ( "$1" == -h || "$1" == --help ) ]] && exit 0
  exit 2
fi
host=$1
port=${2:-8765}
if [[ -z "$host" || "$host" == -* || "$host" == *[[:space:]]* || "$host" == *:* ]]; then
  echo "Error: Supply an SSH host alias or user@hostname." >&2
  exit 1
fi
if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
  echo "Error: Local port must be between 1 and 65535." >&2
  exit 1
fi
port=$((10#$port))
command -v open >/dev/null 2>&1 || { echo "Error: Run this command on your Mac." >&2; exit 1; }

echo "Preview bridge: ${host}:8765 -> 127.0.0.1:${port}. Press Ctrl-C to stop."
ssh -T -o ExitOnForwardFailure=yes \
  -L "127.0.0.1:${port}:127.0.0.1:8765" "$host" '
    mkdir -p "$HOME/.cache/dotfiles"
    touch "$HOME/.cache/dotfiles/markdown-preview.url"
    tail -n 1 -F "$HOME/.cache/dotfiles/markdown-preview.url"
  ' | while IFS= read -r url; do
    # Only preview URLs may ask the local machine to open a browser.
    if [[ "$url" =~ ^http://(localhost|127\.0\.0\.1):8765/page/[0-9]+$ ]]; then
      open "http://127.0.0.1:${port}/page/${url##*/}"
    fi
  done
