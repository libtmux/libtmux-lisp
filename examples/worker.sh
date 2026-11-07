#!/bin/sh
# An example application: acknowledge initialization and one consumed request.
set -eu
program=$1
socket=$2
ready=$3
consumed=$4
receipt=$5
"$program" -S "$socket" wait-for -S "$ready"
IFS= read -r message
printf '%s' "$message" > "$receipt"
printf 'processed: %s\n' "$message"
"$program" -S "$socket" wait-for -S "$consumed"
exec /bin/cat
