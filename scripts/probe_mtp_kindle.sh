#!/usr/bin/env bash
set -uo pipefail

KEEP_CLIPPINGS=0
if [[ "${1:-}" == "--keep-clippings" ]]; then
  KEEP_CLIPPINGS=1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
out_dir="${PWD}/mtp-kindle-probe-${timestamp}"
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

maybe_install_libmtp() {
  if find_tool mtp-detect >/dev/null && find_tool mtp-files >/dev/null && find_tool mtp-getfile >/dev/null; then
    return 0
  fi

  log "libmtp command-line tools were not found."
  if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew is not installed, so this probe cannot install libmtp automatically."
    log "Install Homebrew from https://brew.sh, then run: brew install libmtp"
    return 1
  fi

  log "This probe can install libmtp with Homebrew."
  log "It will run: brew install libmtp"
  printf 'Install libmtp now? [y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      run_capture "brew install libmtp" "brew-install-libmtp.txt" brew install libmtp
      ;;
    *)
      log "Skipped libmtp install."
      return 1
      ;;
  esac
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

log "Kindle MTP probe"
log "Output directory: $out_dir"
log ""
log "Before continuing:"
log "- Plug in the Kindle with USB."
log "- Unlock it if the screen asks."
log "- Close Amazon USB File Manager, OpenMTP, Calibre, or any other MTP/file-transfer app."
log "- This probe does not upload anything."
log "- By default, it deletes the downloaded My Clippings.txt after recording size/hash/counts."
log ""
printf 'Press Return when the Kindle is connected... '
read -r _

{
  echo "date: $(date)"
  echo "sw_vers:"
  sw_vers
  echo "uname: $(uname -a)"
  echo "arch: $(uname -m)"
  echo "shell: ${SHELL:-unknown}"
  echo "pwd: $PWD"
} >"$out_dir/system.txt" 2>&1

if ! maybe_install_libmtp; then
  log ""
  log "Probe stopped before MTP scan because libmtp tools are unavailable."
  log "Send this directory back if you want me to inspect the setup state: $out_dir"
  exit 2
fi

mtp_detect="$(find_tool mtp-detect)"
mtp_files="$(find_tool mtp-files)"
mtp_folders="$(find_tool mtp-folders || true)"
mtp_getfile="$(find_tool mtp-getfile)"

log ""
log "Using tools:"
log "mtp-detect: $mtp_detect"
log "mtp-files: $mtp_files"
if [[ -n "$mtp_folders" ]]; then
  log "mtp-folders: $mtp_folders"
fi
log "mtp-getfile: $mtp_getfile"

run_capture "mtp-detect" "mtp-detect.txt" "$mtp_detect" || true
if [[ -n "$mtp_folders" ]]; then
  run_capture "mtp-folders" "mtp-folders.txt" "$mtp_folders" || true
fi
run_capture "mtp-files" "mtp-files.txt" "$mtp_files" || true

clippings_id="$(extract_first_clippings_id "$out_dir/mtp-files.txt" || true)"
if [[ -z "$clippings_id" ]]; then
  log ""
  log "Result: MTP scan completed, but My Clippings.txt was not found in mtp-files output."
  log "Send back the probe directory: $out_dir"
  exit 3
fi

log ""
log "Found My Clippings.txt with MTP file ID: $clippings_id"

clippings_file="$out_dir/My Clippings.txt"
run_capture "mtp-getfile My Clippings.txt" "mtp-getfile.txt" "$mtp_getfile" "$clippings_id" "$clippings_file" || {
  log ""
  log "Result: Found a candidate My Clippings.txt file ID, but download failed."
  log "Send back the probe directory: $out_dir"
  exit 4
}

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
log "Result: SUCCESS. MTP can download My Clippings.txt from this Kindle."
log "Send back the probe directory: $out_dir"
