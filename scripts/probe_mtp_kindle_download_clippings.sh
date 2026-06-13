#!/usr/bin/env bash
set -uo pipefail

KEEP_CLIPPINGS=0
if [[ "${1:-}" == "--keep-clippings" ]]; then
  KEEP_CLIPPINGS=1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
out_dir="${PWD}/mtp-kindle-download-clippings-${timestamp}"
mkdir -p "$out_dir"

log_file="$out_dir/probe.log"

log() {
  printf '%s\n' "$*" | tee -a "$log_file"
}

run_capture() {
  local label="$1"
  local file="$2"
  shift 2

  log ""
  log "== $label =="
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } >"$out_dir/$file" 2>&1
  local status=$?
  log "wrote $file (exit $status)"
  return "$status"
}

find_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi

  for prefix in /opt/homebrew /usr/local; do
    if [[ -x "$prefix/bin/$name" ]]; then
      printf '%s/bin/%s\n' "$prefix" "$name"
      return 0
    fi
  done

  return 1
}

extract_first_clippings_id() {
  awk '
    /^File ID:/ {
      id = $3
    }
    /^[[:space:]]*Filename:[[:space:]]*My Clippings\.txt[[:space:]]*$/ {
      if (id != "") {
        print id
        exit
      }
    }
  ' "$1"
}

write_system_info() {
  {
    echo "date: $(date)"
    echo "sw_vers:"
    sw_vers
    echo "uname: $(uname -a)"
    echo "arch: $(uname -m)"
    echo "shell: ${SHELL:-unknown}"
    echo "pwd: $PWD"
  } >"$out_dir/system.txt" 2>&1
}

write_readme() {
  cat >"$out_dir/README.txt" <<EOF
Kindle MTP clippings download probe

Send this whole folder back:
$out_dir

What this test checks:
- mtp-files runs first on a fresh USB connection.
- The script finds the MTP file ID for My Clippings.txt.
- mtp-getfile downloads only My Clippings.txt.
- The downloaded file is summarized, then deleted by default.

To keep the downloaded My Clippings.txt for manual inspection, rerun with:
./scripts/probe_mtp_kindle_download_clippings.sh --keep-clippings
EOF
}

log "Kindle MTP clippings download probe"
log "Output directory: $out_dir"
log ""
log "Before continuing:"
log "- Close Amazon USB File Manager, OpenMTP, Calibre, Android File Transfer, and any other file-transfer app."
log "- Unplug the Kindle."
log "- Wake or unlock the Kindle if the screen asks."
log "- Plug the Kindle back in with USB."
log "- Wait about 5 seconds after plugging it in."
log ""
log "This probe downloads only My Clippings.txt if it can find it."
log "By default, it deletes the downloaded file after writing size/hash/counts."
log ""
printf 'Press Return after the Kindle has been freshly plugged in... '
read -r _

write_system_info
write_readme

mtp_files="$(find_tool mtp-files || true)"
mtp_getfile="$(find_tool mtp-getfile || true)"

missing_tools=0
if [[ -z "$mtp_files" ]]; then
  log "Missing required tool: mtp-files"
  missing_tools=1
fi
if [[ -z "$mtp_getfile" ]]; then
  log "Missing required tool: mtp-getfile"
  missing_tools=1
fi

if [[ "$missing_tools" -ne 0 ]]; then
  log ""
  log "Result: libmtp command-line tools are missing."
  log "Install them with: brew install libmtp"
  log "Then rerun this script."
  log "Send back this folder if you want me to inspect the setup state: $out_dir"
  exit 2
fi

log ""
log "Using tools:"
log "mtp-files: $mtp_files"
log "mtp-getfile: $mtp_getfile"

run_capture "mtp-files first" "mtp-files-first.txt" "$mtp_files" || true

clippings_id="$(extract_first_clippings_id "$out_dir/mtp-files-first.txt" || true)"
if [[ -z "$clippings_id" ]]; then
  log ""
  log "Result: mtp-files did not list My Clippings.txt."
  log "Send back the probe directory: $out_dir"
  exit 3
fi

log ""
log "Found My Clippings.txt with MTP file ID: $clippings_id"

clippings_file="$out_dir/My Clippings.txt"
run_capture "mtp-getfile My Clippings.txt" "mtp-getfile.txt" "$mtp_getfile" "$clippings_id" "$clippings_file" || {
  log ""
  log "Result: Found My Clippings.txt, but mtp-getfile could not download it."
  log "Send back the probe directory: $out_dir"
  exit 4
}

if [[ ! -s "$clippings_file" ]]; then
  log ""
  log "Result: Found My Clippings.txt, but mtp-getfile did not create a non-empty downloaded file."
  log "Send back the probe directory: $out_dir"
  exit 4
fi

{
  echo "file_id: $clippings_id"
  echo "bytes: $(wc -c <"$clippings_file" | tr -d ' ')"
  echo "sha256: $(shasum -a 256 "$clippings_file" | awk '{print $1}')"
  echo "separator_count: $(grep -c '^==========[[:space:]]*$' "$clippings_file" || true)"
  echo "metadata_line_count: $(grep -Ec '^-[[:space:]]+Your (Highlight|Note|Bookmark)' "$clippings_file" || true)"
} >"$out_dir/clippings-summary.txt"

if [[ "$KEEP_CLIPPINGS" -eq 0 ]]; then
  rm -f "$clippings_file"
  log "Deleted downloaded My Clippings.txt after writing clippings-summary.txt."
else
  log "Kept downloaded My Clippings.txt because --keep-clippings was passed."
fi

log ""
log "Result: SUCCESS. MTP can list and download My Clippings.txt from this Kindle."
log "Send back the probe directory: $out_dir"
