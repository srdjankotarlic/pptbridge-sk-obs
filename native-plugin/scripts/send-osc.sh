#!/bin/bash

set -euo pipefail

HOST="${PPTBRIDGE_OSC_HOST:-127.0.0.1}"
PORT="${PPTBRIDGE_OSC_PORT:-57130}"

usage() {
  cat <<'USAGE'
Usage: send-osc.sh /pptbridge/next

Environment:
  PPTBRIDGE_OSC_HOST  Default: 127.0.0.1
  PPTBRIDGE_OSC_PORT  Default: 57130

Examples:
  send-osc.sh /pptbridge/next
  send-osc.sh /pptbridge/previous
  send-osc.sh /pptbridge/reload
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 1
fi

ADDRESS="$1"
if [[ "$ADDRESS" != /* ]]; then
  echo "OSC address must start with /" >&2
  exit 1
fi

length_with_null=$((${#ADDRESS} + 1))
padding=$(((4 - (length_with_null % 4)) % 4))

{
  printf '%s\0' "$ADDRESS"
  for ((i = 0; i < padding; i++)); do
    printf '\0'
  done
} | nc -u -w 1 "$HOST" "$PORT"
