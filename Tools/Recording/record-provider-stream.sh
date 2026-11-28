#!/bin/sh
# Records one real provider response stream for AC-M2-24 (T-19; plan "Real provider recordings"; L2a). P-3.
#
# Run it from the repo root as a script, never pasted line by line, so the comments here are comments and nothing
# enters the interactive shell history:
#     zsh Tools/Recording/record-provider-stream.sh openai
#     bash Tools/Recording/record-provider-stream.sh anthropic
# It sends the committed golden request (Fixtures/M2/payload/golden/g1-outcome-empty-<provider>.head.txt and
# .body.json) with the key typed at a hidden prompt. The key is never echoed, never written to a file, never in any
# process's arguments (curl reads the auth header from its standard input; the key is only ever passed to shell
# builtins: read, printf, [ and case) and is cleared when the script ends.
# Only the response stream is kept, as <out-dir>/<provider>.sse (default ~/tend-rec-out); no response headers are
# saved. The HTTP status code is printed. If the stream contains the typed key, the file is deleted.
#
# TEND_REC_BASE (optional, tests only) replaces "https://<host>" with another base URL, such as a local test server.
# Variable names avoid zsh's special parameters (`path` is tied to PATH, `status` is read-only).

set -u

provider=${1:-}
out=${2:-"$HOME/tend-rec-out"}

case "$provider" in
    openai) auth_name='Authorization'; auth_prefix='Bearer '; label='OpenAI' ;;
    anthropic) auth_name='x-api-key'; auth_prefix=''; label='Anthropic' ;;
    gemini) auth_name='x-goog-api-key'; auth_prefix=''; label='Gemini' ;;
    *)
        echo "usage: zsh|bash Tools/Recording/record-provider-stream.sh <openai|anthropic|gemini> [out-dir]" >&2
        exit 64
        ;;
esac

head_file="Fixtures/M2/payload/golden/g1-outcome-empty-$provider.head.txt"
body_file="Fixtures/M2/payload/golden/g1-outcome-empty-$provider.body.json"
if [ ! -f "$head_file" ] || [ ! -f "$body_file" ]; then
    echo "run this from the repo root (no $head_file or $body_file here)" >&2
    exit 66
fi

# The request line: "POST <host> <path[?query]>".
read -r method host req_path < "$head_file"
if [ "$method" != "POST" ] || [ -z "$host" ] || [ -z "$req_path" ]; then
    echo "unexpected request line in $head_file" >&2
    exit 65
fi
url="${TEND_REC_BASE:-https://$host}$req_path"

# Every other header of the golden request, except the auth header (that one is built from the typed key).
set --
while IFS= read -r line; do
    case "$line" in
        "$auth_name: "*|'') ;;
        *) set -- "$@" -H "$line" ;;
    esac
done <<HEADERS
$(tail -n +2 "$head_file")
HEADERS

echo "Sending the golden request for $label to $url"

restore_echo() { [ -t 0 ] && stty echo 2>/dev/null; }
trap 'restore_echo; key=; exit 130' INT TERM HUP

key=
printf '%s key (hidden), then Return: ' "$label" >&2
if [ -t 0 ]; then
    stty -echo || { echo "cannot hide the input here; nothing was sent" >&2; exit 1; }
    IFS= read -r key
    restore_echo
    echo >&2
else
    IFS= read -r key
    echo >&2
fi
if [ -z "$key" ]; then
    echo "no key read; nothing was sent" >&2
    exit 1
fi

mkdir -p "$out"
stream="$out/$provider.sse"
http_status=$(printf '%s: %s%s\n' "$auth_name" "$auth_prefix" "$key" |
    curl -sS -N -X POST -H @- "$@" --data-binary "@$body_file" -o "$stream" -w '%{http_code}' -- "$url")
code=$?

# The leak check runs in the shell itself (builtins only), so the key is never in any process's arguments (review
# R50-F5). The key is quoted inside the pattern, so glob characters in it match only themselves.
leak=no
if [ -f "$stream" ]; then
    content=$(cat -- "$stream")
    case $content in
        *"$key"*) leak=yes ;;
    esac
    content=
fi
key=
trap - INT TERM HUP

if [ "$leak" = yes ]; then
    rm -f -- "$stream"
    echo "the response contained the key, so $stream was deleted" >&2
    exit 1
fi
echo "HTTP status: ${http_status:-none} (curl exit $code)"
if [ "$code" -ne 0 ]; then
    exit "$code"
fi
if grep -l -i -E 'sk-|x-api-key|x-goog-api-key|authorization|AIza|bearer' -- "$stream" >/dev/null; then
    echo "check $stream by hand: it contains a key-shaped or header-shaped word" >&2
    exit 1
fi
echo "Saved only the response stream: $stream"
