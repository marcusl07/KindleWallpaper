#!/usr/bin/env bash
set -uo pipefail

timestamp="$(date +%Y%m%d-%H%M%S)"
out_dir="${PWD}/mtp-kindle-fresh-listing-${timestamp}"
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
Kindle MTP fresh-listing probe

Send this whole folder back:
$out_dir

What this test checks:
- mtp-files runs first on a fresh USB connection.
- mtp-folders runs second.
- mtp-detect runs last.

The command order matters. The previous probe detected the Kindle first, then
file listing failed. This test checks whether detection itself disturbed the
MTP session.
EOF
}

log "Kindle MTP fresh-listing probe"
log "Output directory: $out_dir"
log ""
log "Before continuing:"
log "- Close Amazon USB File Manager, OpenMTP, Calibre, Android File Transfer, and any other file-transfer app."
log "- Unplug the Kindle."
log "- Wake or unlock the Kindle if the screen asks."
log "- Plug the Kindle back in with USB."
log "- Wait about 5 seconds after plugging it in."
log ""
log "This probe does not download or upload anything. It only records command output."
log ""
printf 'Press Return after the Kindle has been freshly plugged in... '
read -r _

write_system_info
write_readme

mtp_files="$(find_tool mtp-files || true)"
mtp_folders="$(find_tool mtp-folders || true)"
mtp_detect="$(find_tool mtp-detect || true)"

missing_tools=0
if [[ -z "$mtp_files" ]]; then
  log "Missing required tool: mtp-files"
  missing_tools=1
fi
if [[ -z "$mtp_folders" ]]; then
  log "Missing required tool: mtp-folders"
  missing_tools=1
fi
if [[ -z "$mtp_detect" ]]; then
  log "Missing required tool: mtp-detect"
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
log "mtp-folders: $mtp_folders"
log "mtp-detect: $mtp_detect"

run_capture "mtp-files first" "mtp-files-first.txt" "$mtp_files" || true
run_capture "mtp-folders second" "mtp-folders-second.txt" "$mtp_folders" || true
run_capture "mtp-detect last" "mtp-detect-last.txt" "$mtp_detect" || true

if grep -qi "My Clippings\.txt" "$out_dir/mtp-files-first.txt"; then
  log ""
  log "Result: SUCCESS. mtp-files listed My Clippings.txt when run first."
elif grep -qi "No Devices have been found\|no devices found" "$out_dir/mtp-files-first.txt"; then
  log ""
  log "Result: mtp-files still could not see the Kindle when run first."
  log "This suggests the issue is not just mtp-detect running before file listing."
else
  log ""
  log "Result: mtp-files produced output. Send the folder back so we can inspect whether the Kindle files are listed."
fi

log "Send back the probe directory: $out_dir"
