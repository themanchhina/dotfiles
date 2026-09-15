#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 put HOST REMOTE_DIR [LOCAL_PATH...] | get HOST REMOTE_PATH [LOCAL_DIR]" >&2
  exit "${1:-2}"
}

die() { echo "remote-files: $*" >&2; exit 1; }

if [[ $# -eq 1 && ( "$1" == -h || "$1" == --help ) ]]; then usage 0; fi
[[ $# -ge 3 ]] || usage
action=$1 host=$2
shift 2

[[ -n "$host" && "$host" != -* && "$host" != *:* && "$host" != *[[:space:]]* ]] || die "invalid host (use an SSH alias or user@hostname)"

case "$action" in
  put)
    remote_dir=$1
    shift
    [[ -n "$remote_dir" && "$remote_dir" != -* && "$remote_dir" != *$'\n'* && "$remote_dir" != *$'\r'* ]] || die "invalid remote directory"

    paths=("$@")
    absolute_paths=()
    if [[ ${#paths[@]} -eq 0 ]]; then
      command -v osascript >/dev/null 2>&1 || die "osascript is required when no local paths are supplied"
      command -v jq >/dev/null 2>&1 || die "jq is required when no local paths are supplied"
      clipboard_json=$(osascript -l JavaScript <<'JXA'
ObjC.import('AppKit');
const pasteboard = $.NSPasteboard.generalPasteboard;
const classes = $.NSArray.arrayWithObject($.NSURL);
const urls = pasteboard.readObjectsForClassesOptions(classes, $.NSDictionary.dictionary);
const paths = [];
for (let i = 0; urls && i < urls.count; i++) {
  const url = urls.objectAtIndex(i);
  if (url && url.isFileURL) {
    const path = ObjC.unwrap(url.path);
    if (path) paths.push(path);
  }
}
JSON.stringify(paths);
JXA
) || die "could not read Finder clipboard"
      jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null <<<"$clipboard_json" || die "Finder clipboard did not contain file paths"
      while IFS= read -r -d '' path; do paths+=("$path"); done < <(jq -j '.[] + "\u0000"' <<<"$clipboard_json")
    fi

    [[ ${#paths[@]} -gt 0 ]] || die "no local files or Finder clipboard paths"
    for path in "${paths[@]}"; do
      [[ -e "$path" ]] || die "local path does not exist: $path"
      [[ "$path" == /* ]] || path="$PWD/$path"
      absolute_paths+=("$path")
    done
    scp -r -- "${absolute_paths[@]}" "${host}:${remote_dir}"
    ;;
  get)
    [[ $# -le 2 ]] || usage
    remote_path=$1
    local_dir=${2:-.}
    [[ -n "$remote_path" && "$remote_path" != -* && "$remote_path" != *$'\n'* && "$remote_path" != *$'\r'* ]] || die "invalid remote path"
    [[ -d "$local_dir" ]] || die "local directory does not exist: $local_dir"
    [[ "$local_dir" == /* ]] || local_dir="$PWD/$local_dir"
    scp -r -- "${host}:${remote_path}" "$local_dir"
    ;;
  *) usage ;;
esac
