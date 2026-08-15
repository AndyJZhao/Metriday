#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dir="$project_dir/.build/smoke-tests"

mkdir -p "$output_dir"
swiftc \
  "$project_dir/Sources/MetridayApp/Models.swift" \
  "$project_dir/Sources/MetridayApp/MarkdownCodec.swift" \
  "$project_dir/Sources/MetridayApp/MarkdownStore.swift" \
  "$project_dir/SmokeTests/main.swift" \
  -o "$output_dir/MetridaySmokeTests"
"$output_dir/MetridaySmokeTests"
