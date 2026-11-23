#!/bin/bash
# Interfell: copot app desktop dari Mac ini.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/uninstall-interfell.sh)"
#
#   --hapus-data   ikut pindahkan data Interfell (~/.aihub) ke Trash, SESUDAH backup yang diverifikasi
#
# Yang dipindah ke SATU folder Trash "Interfell uninstalled <waktu>": app, jadwal launchd com.aihub.* (dicabut dari
# launchd dulu), ~/Library/Application Support/AI Hub, log aihub-*.log, preferensi dan cache app. Nggak ada yang
# di-rm, jadi semuanya bisa dikembalikan. Yang NGGAK PERNAH disentuh: ~/.claude, ~/.codex, ~/.kimi-code, Keychain,
# dan ~/aihub (salinan terminal milik pengembang). ~/.aihub tetap ada kecuali --hapus-data.
#
# Variabel INTERFELL_* cuma buat uji (HOME palsu, folder Applications palsu).
set -uo pipefail

PERINTAH='bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/uninstall-interfell.sh)"'
PASANG='bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/pasang-ulang-interfell.sh)"'
BUNDLE_ID="com.danielsandhika.aihub"
APPS="${INTERFELL_APPS:-/Applications}"
APP="$APPS/AI Hub.app"
DATA="$HOME/.aihub"
STAMP="$(date +%Y-%m-%d-%H%M%S)"
BACKUP=""
trap '[ -n "$BACKUP" ] && rm -f "$BACKUP.part"' EXIT

HAPUS_DATA=0
# `bash -c "$(curl ...)" --hapus-data` menaruh opsi pertama di $0, bukan $1. Tanpa ini opsinya hilang diam-diam
# (data dikira tetap disimpan). Dua bentuk sama-sama jalan: dengan atau tanpa `--`.
case "$0" in --hapus-data) set -- "$0" "$@" ;; esac
for a in "$@"; do
  case "$a" in
    --hapus-data) HAPUS_DATA=1 ;;
    -h|--help) sed -n 2,7p "$0" 2>/dev/null; exit 0 ;;
    *) printf '\n  Unknown option: %s\n  Option: --hapus-data (also move ~/.aihub to the Trash, after a backup)\n\n' "$a"; exit 1 ;;
  esac
done

judul()   { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()      { printf '  ok     %s\n' "$1"; }
info()    { printf '  info   %s\n' "$1"; }
berhenti() {
  printf '\n  STOPPED: %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf '  Next step: %s\n' "$2" >&2
  printf '\n  Then run the same line again:\n  %s\n\n' "$PERINTAH" >&2
  exit 1
}
tanya_ya() {
  local jawab=""
  printf '\n  %s Type yes to continue: ' "$1"
  IFS= read -r jawab || jawab=""
  case "$(printf '%s' "$jawab" | tr '[:upper:]' '[:lower:]')" in yes|y) return 0 ;; *) return 1 ;; esac
}
# App GUI yang terdaftar di macOS. Bukan pgrep "AI Hub": jadwal yang lagi jalan memakai binary yang sama
# (ELECTRON_RUN_AS_NODE) dan bakal dikira app yang nggak mau ditutup.
app_jalan() { [ -n "$(lsappinfo find bundleid="$BUNDLE_ID" 2>/dev/null)" ]; }

if [ ! -t 0 ]; then
  cat <<EOF

  Run it in this form so Terminal can answer the questions:

    $PERINTAH

EOF
  exit 1
fi
[ "$(uname -s)" = "Darwin" ] || { printf '\n  This is for macOS only.\n\n'; exit 1; }

judul "Interfell · uninstall"
printf '\n  This removes the Interfell app, its schedules, and its app files from this Mac.\n'
if [ "$HAPUS_DATA" -eq 1 ]; then
  printf '  Your Interfell data (~/.aihub) is backed up to Downloads first, then moved to the Trash too.\n'
else
  printf '  Your Interfell data (~/.aihub: workflows, projects, schedules, logins, settings) is KEPT.\n'
fi
printf '  Sessions in ~/.claude, ~/.codex, ~/.kimi-code and your Keychain are not touched.\n'
printf '  Everything removed goes to one folder in the Trash, so it can be put back.\n'
tanya_ya "Uninstall Interfell?" || { printf '\n  Nothing was changed.\n\n'; exit 0; }

# ---------- tutup app ----------
if app_jalan; then
  if tanya_ya "Interfell is open. It needs to close now (running chats stop)."; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
    for _ in $(seq 1 30); do app_jalan || break; sleep 1; done
    app_jalan && berhenti "Interfell did not close." "Quit Interfell from its menu (Interfell > Quit)."
    ok "Interfell closed"
  else
    berhenti "Interfell is still open. Nothing was changed." "Quit Interfell when you are ready."
  fi
fi

# ---------- backup dulu (cuma --hapus-data) ----------
if [ "$HAPUS_DATA" -eq 1 ] && [ -d "$DATA" ]; then
  judul "Backing up your Interfell data first"
  mkdir -p "$HOME/Downloads" || berhenti "Could not open your Downloads folder. Nothing was changed." "Check that ~/Downloads exists."
  BACKUP="$HOME/Downloads/Interfell-before-uninstall-$STAMP.zip"
  ( cd "$HOME" && zip -r -q -y "$BACKUP.part" .aihub -x '.aihub/preview-cache/*' '.aihub/search.db' '.aihub/search.db-*' \
      '.aihub/desktop-tools/*' '.aihub/desktop-build/*' '.aihub/backup-app/*' '.aihub/uji-workflow/*' '.aihub/aihub-install/*' '*.log' '*.DS_Store' ); rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$BACKUP.part" ]; then berhenti "The backup could not be made (zip exit $rc). Nothing was changed." "Check free space. If macOS asked whether Terminal may use Downloads, click Allow."; fi
  unzip -tq "$BACKUP.part" >/dev/null 2>&1 || berhenti "The backup failed its integrity test. Nothing was changed." "Check free space, then try again."
  DAFTAR="$(zipinfo -1 "$BACKUP.part" 2>/dev/null)"
  JUMLAH="$(grep -c . <<<"$DAFTAR")"
  [ "$JUMLAH" -gt 0 ] || berhenti "The backup is empty. Nothing was changed." "Tell Daniel."
  for kunci in schedules.json desktop.json session-prefs.json titles.json akun-tim.json rahasia.json mcp-koneksi.json workflow/wf proyek notes; do
    [ -e "$DATA/$kunci" ] || continue
    grep -qxF ".aihub/$kunci" <<<"$DAFTAR" || grep -qxF ".aihub/$kunci/" <<<"$DAFTAR" \
      || berhenti "The backup is missing $kunci. Nothing was changed." "Tell Daniel, and send this screen."
  done
  mv "$BACKUP.part" "$BACKUP" && chmod 600 "$BACKUP"
  ok "Backup checked: $JUMLAH entries, $(du -h "$BACKUP" | awk '{print $1}')"
  printf '       %s\n' "$BACKUP"
  info "It holds your logins, so keep it to yourself. Uploads and run history are included."
fi

# ---------- pindah ke satu folder Trash ----------
judul "Removing"
TRASH_DIR="$HOME/.Trash/Interfell uninstalled $STAMP"
if ! mkdir -p "$TRASH_DIR" 2>/dev/null; then
  TRASH_DIR="$HOME/Interfell uninstalled $STAMP"
  mkdir -p "$TRASH_DIR" || berhenti "Could not make a folder for removed files." "Check free space."
  info "The Trash is not writable from Terminal, so removed files go to: $TRASH_DIR"
fi
DIPINDAH=0
pindah() {
  # $1 = sumber, $2 = subfolder di Trash
  [ -e "$1" ] || [ -L "$1" ] || return 0
  mkdir -p "$TRASH_DIR/$2" && mv "$1" "$TRASH_DIR/$2/" && { DIPINDAH=$((DIPINDAH + 1)); ok "Moved $(printf '%s' "$1" | sed "s|^$HOME|~|")"; } \
    || info "Could not move $1 (left in place)"
}

shopt -s nullglob
UIDKU="$(id -u)"
for f in "$HOME/Library/LaunchAgents"/com.aihub.*.plist; do
  label="$(basename "$f" .plist)"
  launchctl bootout "gui/$UIDKU/$label" >/dev/null 2>&1 || true
  pindah "$f" "LaunchAgents"
done
pindah "$APP" "Applications"
pindah "$APP.lama" "Applications"
pindah "$HOME/Library/Application Support/AI Hub" "Application Support"
for f in "$HOME/Library/Logs"/aihub-*.log; do pindah "$f" "Logs"; done
pindah "$HOME/Library/Preferences/$BUNDLE_ID.plist" "Preferences"
for f in "$HOME/Library/Caches/$BUNDLE_ID" "$HOME/Library/Caches/$BUNDLE_ID".* "$HOME/Library/HTTPStorages/$BUNDLE_ID" "$HOME/Library/HTTPStorages/$BUNDLE_ID".*; do pindah "$f" "Caches"; done
pindah "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" "Saved Application State"
shopt -u nullglob

if [ "$HAPUS_DATA" -eq 1 ] && [ -d "$DATA" ]; then
  mkdir -p "$TRASH_DIR/Interfell data" && mv "$DATA" "$TRASH_DIR/Interfell data/.aihub" \
    && { DIPINDAH=$((DIPINDAH + 1)); ok "Moved ~/.aihub (your data; the backup is in Downloads)"; } \
    || berhenti "Could not move ~/.aihub. The app is already removed; your data is still in ~/.aihub." "Close any window using ~/.aihub."
fi

judul "Done"
if [ "$DIPINDAH" -eq 0 ]; then
  rmdir "$TRASH_DIR" 2>/dev/null
  printf '  Interfell was not installed here. Nothing was changed.\n'
else
  printf '  Removed items are in: %s\n' "$TRASH_DIR"
fi
[ "$HAPUS_DATA" -eq 1 ] || { [ -d "$DATA" ] && printf '  Your Interfell data is still in ~/.aihub. Installing again picks it up.\n'; }
[ -d "$HOME/aihub" ] && printf '  A terminal copy is still at ~/aihub. It was not touched.\n'
printf '\n  To install Interfell again, run:\n  %s\n\n' "$PASANG"
