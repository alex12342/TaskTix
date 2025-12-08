#!/usr/bin/env bash
set -euo pipefail

PRINTER_NAME="${PRINTER_NAME:-Star}"

# Read all ticket text from stdin
TICKET_TEXT="$(cat)"

if [ -z "$TICKET_TEXT" ]; then
  echo "No ticket text received on stdin" >&2
  exit 1
fi

TMPFILE=$(mktemp /tmp/ticket.XXXXXX.txt)
printf "%s\n" "$TICKET_TEXT" > "$TMPFILE"

lp -d "$PRINTER_NAME" \
   -o media=Custom.72x200mm \
   -o page-left=0 -o page-right=0 -o page-top=0 -o page-bottom=0 \
   "$TMPFILE"

rm "$TMPFILE"

