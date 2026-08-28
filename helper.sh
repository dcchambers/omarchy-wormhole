#!/bin/bash

# Normalizes magic-wormhole output into a flat key=value protocol on stdout,
# so the Quickshell panel only needs a single SplitParser. wormhole prints
# the code line, progress, and status messages on stderr; merging the streams
# here keeps the QML side free of dual-parser juggling.
#
# Output protocol (one record per line):
#   code=<wormhole code>          send mode, once the mailbox is allocated
#   status=<status line>          progression lines from wormhole
#   done=<completion line>        successful completion
#   error=<message>               failure
#   detail=<line>                 anything else worth showing in the log
#
# Usage:
#   helper.sh send [--qr] <path...>
#   helper.sh send-clipboard [--qr]
#   helper.sh receive <code>

set -o pipefail

cleanup_dir=""
protocol_dir=""
command_pid=""
parser_pid=""
cleanup() {
  [[ -n "$cleanup_dir" ]] && rm -rf -- "$cleanup_dir"
  [[ -n "$protocol_dir" ]] && rm -rf -- "$protocol_dir"
}
trap cleanup EXIT

cancel() {
  trap - TERM INT
  if [[ -n "$command_pid" ]]; then
    # Wormhole and any clipboard pipeline run in their own session, so killing
    # the negative PID terminates the whole transfer rather than orphaning the
    # Python process when Quickshell stops this helper.
    kill -TERM -- "-$command_pid" 2>/dev/null || kill -TERM "$command_pid" 2>/dev/null || true
  fi
  [[ -n "$parser_pid" ]] && kill -TERM "$parser_pid" 2>/dev/null || true
  wait "$command_pid" 2>/dev/null || true
  wait "$parser_pid" 2>/dev/null || true
  exit 130
}
trap cancel TERM INT

if ! command -v wormhole >/dev/null 2>&1; then
  echo "error=magic-wormhole is not installed (pacman -S magic-wormhole)"
  exit 127
fi

mode="${1:-}"
if [[ -n "$mode" ]]; then shift; fi

case "$mode" in
  send)
    qr_args=()
    if [[ ${1:-} == "--qr" ]]; then
      qr_args=(--qr)
      shift
    fi
    if (($# == 0)); then
      echo "error=nothing to send"
      exit 2
    fi
    if (($# > 1)); then
      cleanup_dir=$(mktemp -d) || {
        echo "error=could not create temporary archive directory"
        exit 1
      }
      archive="$cleanup_dir/wormhole-files.tar.gz"
      echo "status=Packaging selected files..."

      declare -A seen_names=()
      tar_args=()
      for path in "$@"; do
        name=${path%/}
        name=${name##*/}
        if [[ -n ${seen_names[$name]:-} ]]; then
          echo "error=two selected items have the same name: $name"
          exit 1
        fi
        seen_names[$name]=1
        tar_args+=(--directory "$(dirname -- "$path")" "--add-file=$name")
      done

      if ! archive_error=$(tar --create --gzip --file "$archive" "${tar_args[@]}" 2>&1); then
        echo "error=${archive_error%%$'\n'*}"
        exit 1
      fi
      set -- wormhole send "${qr_args[@]}" "$archive"
    else
      set -- wormhole send "${qr_args[@]}" "$1"
    fi
    ;;
  send-clipboard)
    if ! command -v wl-paste >/dev/null 2>&1; then
      echo "error=wl-clipboard is not installed (pacman -S wl-clipboard)"
      exit 127
    fi
    if [[ ${1:-} == "--qr" ]]; then
      set -- bash -c 'wl-paste | wormhole send --qr --text -'
    else
      set -- bash -c 'wl-paste | wormhole send --text -'
    fi
    ;;
  receive)
    if (($# != 1)); then
      echo "error=usage: helper.sh receive <code>"
      exit 2
    fi
    mkdir -p "$HOME/Downloads"
    set -- wormhole receive --accept-file -o "$HOME/Downloads" "$1"
    ;;
  *)
    echo "error=usage: helper.sh send [--qr] <paths...> | send-clipboard [--qr] | receive <code>"
    exit 2
    ;;
esac

parse_output() {
  while IFS= read -r line; do
    case "$line" in
      *"Wormhole code is:"*)
        echo "code=${line#*Wormhole code is: }"
        ;;
      *"On the other computer"* | "Sending "* | "Sending ("* | "Receiving "* | "Receiving ("*)
        echo "status=$line"
        ;;
      *"Received file written to:"* | *"Transfer complete."* | *"Text message sent."*)
        echo "done=$line"
        ;;
      "")
        ;; # drop blank lines
      *)
        # Progress bars rewrite one line with \r; forward each resulting chunk.
        tr '\r' '\n' <<< "$line" | while IFS= read -r part; do
          [[ -n "$part" ]] && echo "detail=$part"
        done
        ;;
    esac
  done
}

# A FIFO keeps protocol parsing live while giving us the command's PID. setsid
# makes that PID a process-group leader, allowing the TERM trap above to cancel
# wormhole and every descendant in one operation.
protocol_dir=$(mktemp -d) || {
  echo "error=could not create protocol pipe"
  exit 1
}
protocol_fifo="$protocol_dir/output"
mkfifo "$protocol_fifo"
parse_output <"$protocol_fifo" &
parser_pid=$!
WORMHOLE_QR="${WORMHOLE_QR:-0}" setsid stdbuf -oL -eL "$@" >"$protocol_fifo" 2>&1 &
command_pid=$!

wait "$command_pid"
rc=$?
wait "$parser_pid" 2>/dev/null || true
if ((rc != 0)); then
  echo "error=wormhole exited with status $rc"
  exit "$rc"
fi
echo "done=complete"
