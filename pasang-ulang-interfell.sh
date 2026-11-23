#!/bin/bash
# Interfell: pasang ulang app desktop. Data tetap, dibackup DULU sebelum apa pun dipindah.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/pasang-ulang-interfell.sh)"
#
#   --periksa   cuma pemeriksaan kesehatan (pengganti `aihub doctor`), nggak mengubah apa pun
#   --lengkap   backup ikut uploads chat dan riwayat run workflow (bisa besar sekali)
#
# Ini juga SATU BARIS PEMULIHAN resmi (skill rilis-ke-tim bagian 5): jalan di versi Interfell mana pun yang
# terpasang, karena nggak bergantung pada app lama sama sekali.
#
# Keputusan Daniel 21 Nov 2026: jalur tim cuma app desktop. Instalasi terminal lama (~/aihub, ~/.local/bin/aihub,
# baris PATH di ~/.zshrc) dicabut, KECUALI ~/aihub punya kerja lokal (perubahan, commit belum di-push, stash): itu
# Mac pengembang, dan bagian terminal dibiarkan utuh. Yang nggak pernah disentuh: ~/.claude, ~/.codex, ~/.kimi-code,
# Keychain. ~/.aihub nggak dihapus. Nggak ada yang di-rm: semua yang dicabut dipindah ke satu folder di Trash.
#
# Akar kepercayaan: HTTPS ke GitHub (manifest dan unduhan dari awalan rilis aihub-install yang dikunci di sini) plus
# sha256 wajib dari manifest. Tanda tangan Ed25519 NGGAK diperiksa di sini: LibreSSL bawaan macOS nggak bisa Ed25519
# dan Mac tim belum tentu punya node atau python. Penegakan tanda tangan diserahkan ke updater di dalam app.
#
# Variabel INTERFELL_* di bawah cuma buat uji (HOME palsu, folder Applications palsu). Orang biasa nggak perlu.
set -uo pipefail

PERINTAH='bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/pasang-ulang-interfell.sh)"'
MANIFEST_URL="https://raw.githubusercontent.com/danielsandhika/aihub-install/main/desktop-latest.json"
AWALAN_UNDUH="https://github.com/danielsandhika/aihub-install/releases/download/"
BUNDLE_ID="com.danielsandhika.aihub"
APPS="${INTERFELL_APPS:-/Applications}"
APP="$APPS/AI Hub.app"
DATA="$HOME/.aihub"
REPO="$HOME/aihub"
BINLINK="$HOME/.local/bin/aihub"
ZSHRC="$HOME/.zshrc"
BARIS_PATH='export PATH="$HOME/.local/bin:$PATH"'
TUNGGU="${INTERFELL_TUNGGU:-90}"
STAMP="$(date +%Y-%m-%d-%H%M%S)"
TRASH_DIR=""
KERJA=""
BACKUP=""
# Ctrl+C atau berhenti di tengah: folder unduhan sementara dan zip setengah jadi dibersihkan.
trap '[ -n "$KERJA" ] && rm -rf "$KERJA"; [ -n "$BACKUP" ] && rm -f "$BACKUP.part"' EXIT

MODE="pasang"
LENGKAP=0
# `bash -c "$(curl ...)" --periksa` menaruh opsi pertama di $0, bukan $1. Tanpa ini opsinya hilang diam-diam
# (dan --periksa malah menjalankan pemasangan penuh). Dua bentuk sama-sama jalan: dengan atau tanpa `--`.
case "$0" in --periksa|--lengkap) set -- "$0" "$@" ;; esac
for a in "$@"; do
  case "$a" in
    --periksa) MODE="periksa" ;;
    --lengkap) LENGKAP=1 ;;
    -h|--help) sed -n 2,8p "$0" 2>/dev/null; exit 0 ;;
    *) printf '\n  Unknown option: %s\n  Options: --periksa (check only), --lengkap (bigger backup)\n\n' "$a"; exit 1 ;;
  esac
done

judul()   { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()      { printf '  ok     %s\n' "$1"; }
info()    { printf '  info   %s\n' "$1"; }
peringat(){ printf '  !      %s\n' "$1"; }
pemulihan() { printf '\n  If anything goes wrong later, run this one line in Terminal:\n  %s\n\n' "$PERINTAH"; }

# Berhenti dengan LANGKAH (skill rilis-ke-tim bagian 4): apa yang salah, apa yang harus dilakukan, lalu ulangi
# perintah yang sama. Baris terakhir selalu perintah pemulihan.
berhenti() {
  printf '\n  STOPPED: %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf '  Next step: %s\n' "$2" >&2
  [ -n "$KERJA" ] && rm -rf "$KERJA"
  printf '\n  Then run the same line again:\n  %s\n\n' "$PERINTAH" >&2
  exit 1
}

tanya_ya() {
  # $1 = pertanyaan. Cuma "yes" (atau "y") yang dianggap setuju.
  local jawab=""
  printf '\n  %s Type yes to continue: ' "$1"
  IFS= read -r jawab || jawab=""
  case "$(printf '%s' "$jawab" | tr '[:upper:]' '[:lower:]')" in yes|y) return 0 ;; *) return 1 ;; esac
}

# Satu folder Trash per jalan. Kalau Trash nggak bisa ditulis (izin macOS), jatuh ke folder di home.
siapkan_trash() {
  [ -n "$TRASH_DIR" ] && return 0
  TRASH_DIR="$HOME/.Trash/Interfell reinstall $STAMP"
  if ! mkdir -p "$TRASH_DIR" 2>/dev/null; then
    TRASH_DIR="$HOME/Interfell removed $STAMP"
    mkdir -p "$TRASH_DIR" || berhenti "Could not make a folder for removed files." "Check that your home folder has free space."
    peringat "The Trash is not writable from Terminal, so removed files go to: $TRASH_DIR"
  fi
}
ke_trash() {
  # $1 = sumber, $2 = nama di folder Trash
  siapkan_trash
  mv "$1" "$TRASH_DIR/$2"
}

# ---------- penemu ----------
# App GUI yang terdaftar di macOS. Bukan pgrep "AI Hub": jadwal yang lagi jalan memakai binary yang sama
# (ELECTRON_RUN_AS_NODE) dan bakal dikira app yang nggak mau ditutup.
app_jalan() { [ -n "$(lsappinfo find bundleid="$BUNDLE_ID" 2>/dev/null)" ]; }

# Server Interfell yang menjawab di 127.0.0.1:4173 sampai 4183. Keluaran: "port dariApp(1/0)".
# Port itu milik seluruh Mac, bukan per akun: Interfell milik akun macOS LAIN (Mac bersama, atau gladi resik di akun
# kedua) bisa menjawab duluan. Server yang pid-nya milik user lain dilewati.
cari_server() {
  local p isi pid pemilik aku
  aku="$(id -un)"
  for p in 4173 4174 4175 4176 4177 4178 4179 4180 4181 4182 4183; do
    isi="$(curl -fsS -m 1 "http://127.0.0.1:$p/api/health" 2>/dev/null)" || continue
    case "$isi" in *'"ok":true'*) ;; *) continue ;; esac
    pid="$(printf '%s' "$isi" | sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p')"
    if [ -n "$pid" ]; then
      pemilik="$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')"
      [ "$pemilik" = "$aku" ] || continue
    fi
    case "$isi" in *'"dariApp":true'*) printf '%s 1\n' "$p" ;; *) printf '%s 0\n' "$p" ;; esac
    return 0
  done
  return 1
}

# Server terminal lama (`aihub`): pid di lockfile ~/.aihub/server.json, atau proses dist/server/index.js di 4173.
pid_server_terminal() {
  local pid=""
  if [ -f "$DATA/server.json" ]; then
    pid="$(sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$DATA/server.json" | head -1)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then printf '%s\n' "$pid"; return 0; fi
  fi
  for pid in $(lsof -nP -t -iTCP:4173 -sTCP:LISTEN 2>/dev/null); do
    case "$(ps -o command= -p "$pid" 2>/dev/null)" in
      *.app/Contents/*) ;;
      *dist/server/index.js*|*bin/aihub.js*) printf '%s\n' "$pid"; return 0 ;;
    esac
  done
  return 1
}

versi_app() { plutil -extract CFBundleShortVersionString raw -o - "$1/Contents/Info.plist" 2>/dev/null; }
id_app()    { plutil -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist" 2>/dev/null; }

# ---------- kesehatan (pengganti `aihub doctor`) ----------
GAGAL_CEK=0
JUMLAH_CEK=0
LANGKAH_CEK=""
lulus() { JUMLAH_CEK=$((JUMLAH_CEK + 1)); printf '  PASS   %s\n' "$1"; }
jatuh() {
  JUMLAH_CEK=$((JUMLAH_CEK + 1)); GAGAL_CEK=$((GAGAL_CEK + 1))
  printf '  FAIL   %s\n' "$1"
  [ -n "${2:-}" ] && LANGKAH_CEK="$LANGKAH_CEK
  - $2"
}

# Plist com.aihub.* yang pasti gagal waktu launchd memanggilnya. Keluaran: satu baris per plist rusak.
plist_rusak() {
  local f a0 a1 env_ran
  for f in "$HOME/Library/LaunchAgents"/com.aihub.*.plist; do
    [ -f "$f" ] || continue
    a0="$(plutil -extract ProgramArguments.0 raw -o - "$f" 2>/dev/null)"
    a1="$(plutil -extract ProgramArguments.1 raw -o - "$f" 2>/dev/null)"
    env_ran="$(plutil -extract EnvironmentVariables.ELECTRON_RUN_AS_NODE raw -o - "$f" 2>/dev/null)"
    case "$a0 $a1" in
      *"$REPO/"*) [ -f "$REPO/bin/aihub.js" ] || { printf '%s (points to ~/aihub, which is gone)\n' "$(basename "$f" .plist)"; continue; } ;;
    esac
    if [ -z "$a0" ] || { case "$a0" in /*) [ ! -e "$a0" ] ;; *) false ;; esac; }; then
      printf '%s (program missing)\n' "$(basename "$f" .plist)"; continue
    fi
    case "$a1" in /*.js|/*.ts|/*.cjs|/*.mjs) [ -e "$a1" ] || { printf '%s (script missing)\n' "$(basename "$f" .plist)"; continue; } ;; esac
    case "$a0" in *.app/Contents/MacOS/*) [ "$env_ran" = "1" ] || { printf '%s (opens the app instead of running)\n' "$(basename "$f" .plist)"; continue; } ;; esac
  done
}

cari_cli() {
  # $1 = nama CLI. PATH dari zsh login (non interaktif, jadi nggak ada prompt) plus folder lazim.
  local c="$1" d
  for d in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin "$HOME/.claude/local" "$HOME/.npm-global/bin" "$HOME/.bun/bin" "$HOME/.cargo/bin"; do
    [ -x "$d/$c" ] && { printf '%s\n' "$d/$c"; return 0; }
  done
  if [ -x /bin/zsh ]; then
    d="$(/bin/zsh -lc "command -v $c" </dev/null 2>/dev/null | tail -1)"
    case "$d" in /*) printf '%s\n' "$d"; return 0 ;; esac
  fi
  return 1
}

periksa_semua() {
  judul "Health check"
  GAGAL_CEK=0; JUMLAH_CEK=0; LANGKAH_CEK=""
  local v rusak srv clis c

  if [ -d "$APP" ]; then
    v="$(versi_app "$APP")"
    if [ "$(id_app "$APP")" = "$BUNDLE_ID" ]; then lulus "Interfell app ${v:-?} is installed in $APPS"
    else jatuh "$APP is not the Interfell app (bundle id $(id_app "$APP"))" "Run the reinstall line below."; fi
    if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then lulus "App signature is intact"
    else jatuh "App signature is broken (macOS may say the app is damaged)" "Run the reinstall line below."; fi
    if [ -n "${VERSI_TERBARU:-}" ] && [ -n "$v" ] && [ "$v" != "$VERSI_TERBARU" ]; then
      info "Newest version is $VERSI_TERBARU. The app updates itself at start, or run the reinstall line."
    fi
    # Mesin jadwal tanpa node: binary app sebagai Node, cuma membaca daftar tugas.
    if ELECTRON_RUN_AS_NODE=1 "$APP/Contents/MacOS/AI Hub" "$APP/Contents/Resources/app/bin/aihub.js" schedule list >/dev/null 2>&1; then
      lulus "The app can run schedules by itself (no Node needed)"
    else jatuh "Schedule engine inside the app does not start" "Run the reinstall line below."; fi
  else
    jatuh "Interfell app is not installed in $APPS" "Run the reinstall line below."
  fi

  clis=""
  for c in claude codex kimi; do cari_cli "$c" >/dev/null && clis="$clis $c"; done
  if [ -n "$clis" ]; then lulus "AI tools found:$clis"
  else jatuh "No AI tool found (claude, codex, or kimi)" "Install Claude Code: bash -c \"\$(curl -fsSL https://claude.ai/install.sh)\", then log in once by running: claude"; fi

  if [ ! -e "$DATA" ]; then lulus "Data folder ~/.aihub is not there yet (Interfell makes it on first start)"
  elif : > "$DATA/.tulis-uji" 2>/dev/null; then rm -f "$DATA/.tulis-uji"; lulus "Data folder ~/.aihub is writable"
  else jatuh "Data folder ~/.aihub is not writable" "Run: sudo chown -R \$(id -un) ~/.aihub"; fi

  rusak="$(plist_rusak)"
  if [ -z "$rusak" ]; then lulus "All schedules point to files that exist"
  else
    jatuh "$(printf '%s\n' "$rusak" | grep -c .) schedule(s) point to missing files: $(printf '%s' "$rusak" | tr '\n' ';' | sed 's/;$//; s/;/; /g')" "Open Interfell once: it repairs broken schedules when it starts."
  fi

  srv="$(cari_server)"
  if [ -n "$srv" ]; then
    case "$srv" in
      *" 1") lulus "Interfell is running and answering (port ${srv% *})" ;;
      *) info "A terminal Interfell server answers on port ${srv% *}"; lulus "Interfell server answers (port ${srv% *})" ;;
    esac
  else jatuh "Interfell is not answering" "Open Interfell from the Applications folder, wait 10 seconds, then run: $PERINTAH --periksa"; fi

  if [ -d "$REPO" ]; then info "Terminal copy at ~/aihub is still here (kept on purpose if it has local work)"
  else lulus "No leftover terminal copy (~/aihub)"; fi
  if [ -L "$BINLINK" ] && [ ! -e "$BINLINK" ]; then jatuh "~/.local/bin/aihub is a broken link" "Remove it: rm ~/.local/bin/aihub"
  elif [ -L "$BINLINK" ]; then info "~/.local/bin/aihub still points to $(readlink "$BINLINK")"; fi
  if [ -f "$ZSHRC" ] && grep -qxF "$BARIS_PATH" "$ZSHRC"; then info "PATH line for ~/.local/bin is in ~/.zshrc (harmless; other tools may use it)"
  else info "No Interfell PATH line in ~/.zshrc"; fi

  printf '\n'
  if [ "$GAGAL_CEK" -eq 0 ]; then printf '  All %s checks passed.\n' "$JUMLAH_CEK"
  else
    printf '  %s of %s checks failed. Next steps:%s\n' "$GAGAL_CEK" "$JUMLAH_CEK" "$LANGKAH_CEK"
  fi
  [ "$GAGAL_CEK" -eq 0 ]
}

# ---------- 0. Bentuk perintah ----------
if [ "$MODE" = "periksa" ]; then
  [ "$(uname -s)" = "Darwin" ] || { printf '\n  Interfell only runs on macOS.\n\n'; exit 1; }
  VERSI_TERBARU="$(curl -fsSL -m 10 "$MANIFEST_URL" 2>/dev/null | plutil -extract version raw -o - - 2>/dev/null || true)"
  periksa_semua; rc=$?
  pemulihan
  exit "$rc"
fi

# `curl ... | bash` memakai stdin buat isi skrip, jadi pertanyaan di bawah nggak bisa dijawab.
if [ ! -t 0 ]; then
  cat <<EOF

  Run it in this form so Terminal can answer the questions:

    $PERINTAH

EOF
  exit 1
fi

judul "Interfell · reinstall (your data stays)"

# ---------- 1. Periksa awal (diam) ----------
judul "1/5 Checking this Mac"
[ "$(uname -s)" = "Darwin" ] || berhenti "Interfell only runs on macOS." "Use a Mac."
[ "$(uname -m)" = "arm64" ] || berhenti "This Mac has an Intel chip. Interfell is built for Apple silicon (M1 or newer) only." "Tell Daniel which Mac you have."
ok "macOS on Apple silicon ($(sw_vers -productVersion 2>/dev/null))"

# Perkiraan ukuran backup: ~/.aihub dikurangi yang nggak ikut.
DIBUANG="preview-cache desktop-tools desktop-build backup-app uji-workflow aihub-install"
[ "$LENGKAP" -eq 1 ] || DIBUANG="$DIBUANG uploads workflow/run"
PERLU_K=$((2 * 1024 * 1024)) # unduhan + bongkar + salin app, kira-kira 2 GB
if [ -d "$DATA" ]; then
  total_k="$(du -sk "$DATA" 2>/dev/null | awk '{print $1}')"
  for d in $DIBUANG; do
    [ -e "$DATA/$d" ] && total_k=$((total_k - $(du -sk "$DATA/$d" 2>/dev/null | awk '{print $1}')))
  done
  [ "${total_k:-0}" -gt 0 ] || total_k=0
  PERLU_K=$((PERLU_K + total_k))
fi
BEBAS_K="$(df -k "$HOME" | awk 'NR==2 {print $4}')"
if [ "${BEBAS_K:-0}" -lt "$PERLU_K" ]; then
  berhenti "Not enough free disk space. Need about $((PERLU_K / 1024)) MB, free is $((BEBAS_K / 1024)) MB." "Free up some space (empty the Trash, delete big downloads)."
fi
ok "Free disk space: $((BEBAS_K / 1024)) MB (need about $((PERLU_K / 1024)) MB)"
# Akun macOS standar (bukan admin) nggak bisa menulis ke /Applications. Ketahuan di sini, bukan sesudah app lama dicabut.
[ -d "$APPS" ] && [ -w "$APPS" ] || berhenti "This Mac account cannot write to $APPS. Nothing was changed." "Log in with an admin account on this Mac, or ask Daniel."
ok "Can write to $APPS"

# Versi terbaru dibaca DI SINI, sebelum apa pun diubah: offline atau manifest aneh = berhenti dengan Mac utuh.
KERJA="$(mktemp -d /tmp/interfell-pasang.XXXXXX)" || berhenti "Could not make a temporary folder." "Restart the Mac and try again."
curl -fsSL -m 30 --retry 2 -o "$KERJA/manifest.json" "$MANIFEST_URL" \
  || berhenti "Could not reach GitHub to find the newest version. Nothing was changed." "Check the internet connection."
VERSI="$(plutil -extract version raw -o - "$KERJA/manifest.json" 2>/dev/null)"
URL="$(plutil -extract url raw -o - "$KERJA/manifest.json" 2>/dev/null)"
SHA="$(plutil -extract sha256 raw -o - "$KERJA/manifest.json" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
printf '%s' "$VERSI" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || berhenti "The version list on GitHub looks wrong (version '$VERSI'). Nothing was changed." "Tell Daniel."
case "$URL" in "$AWALAN_UNDUH"*) ;; *) berhenti "The download address is not the official Interfell release ($URL). Nothing was changed." "Tell Daniel." ;; esac
printf '%s' "$SHA" | grep -qE '^[0-9a-f]{64}$' || berhenti "The version list has no valid fingerprint (sha256). Nothing was changed." "Tell Daniel."
ok "Newest published version: $VERSI"

# App terpasang lebih baru dari yang terbit (build lokal pengembang): jangan diturunkan tanpa ditanya.
if [ -d "$APP" ]; then
  V_PASANG="$(versi_app "$APP")"
  if [ -n "$V_PASANG" ] && [ "$V_PASANG" != "$VERSI" ] && [ "$(printf '%s\n%s\n' "$V_PASANG" "$VERSI" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$V_PASANG" ]; then
    if ! tanya_ya "The installed app ($V_PASANG) is NEWER than the published one ($VERSI). Replace it with $VERSI?"; then
      printf '\n  Nothing was changed. Keep using Interfell %s.\n' "$V_PASANG"
      pemulihan
      exit 0
    fi
  fi
fi

# App yang lagi jalan: minta izin, tutup lewat AppleScript (bukan kill), tunggu.
if app_jalan; then
  if tanya_ya "Interfell is open. It needs to close now (running chats stop)."; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
    for _ in $(seq 1 30); do app_jalan || break; sleep 1; done
    app_jalan && berhenti "Interfell did not close." "Quit Interfell from its menu (Interfell > Quit), or save your work and restart the Mac."
    ok "Interfell closed"
  else
    berhenti "Interfell is still open." "Quit Interfell when you are ready."
  fi
else
  ok "Interfell is not running"
fi

PID_TERMINAL="$(pid_server_terminal)"
if [ -n "$PID_TERMINAL" ]; then
  if tanya_ya "An old terminal Interfell server is running (process $PID_TERMINAL). It needs to stop now."; then
    kill "$PID_TERMINAL" 2>/dev/null
    for _ in $(seq 1 20); do kill -0 "$PID_TERMINAL" 2>/dev/null || break; sleep 0.5; done
    kill -0 "$PID_TERMINAL" 2>/dev/null && berhenti "The terminal server did not stop." "Run in Terminal: aihub stop"
    ok "Terminal server stopped"
  else
    berhenti "The terminal server is still running." "Run in Terminal: aihub stop"
  fi
fi

# ---------- 2. Backup DULU ----------
judul "2/5 Backing up your Interfell data"
if [ ! -d "$DATA" ]; then
  ok "No Interfell data yet (~/.aihub), nothing to back up"
else
  mkdir -p "$HOME/Downloads" || berhenti "Could not open your Downloads folder. Nothing was removed." "Check that ~/Downloads exists. If macOS asks whether Terminal may use Downloads, click Allow."
  BACKUP="$HOME/Downloads/Interfell-before-reinstall-$STAMP.zip"
  set -- -x '.aihub/preview-cache/*' '.aihub/search.db' '.aihub/search.db-*' '.aihub/desktop-tools/*' '.aihub/desktop-build/*' \
    '.aihub/backup-app/*' '.aihub/uji-workflow/*' '.aihub/aihub-install/*' '*.log' '*.DS_Store'
  [ "$LENGKAP" -eq 1 ] || set -- "$@" '.aihub/uploads/*' '.aihub/workflow/run/*'
  info "This can take a few minutes for big data folders."
  ( cd "$HOME" && zip -r -q -y "$BACKUP.part" .aihub "$@" ); rc=$?
  # zip keluar 12 = "nggak ada yang perlu dizip" (folder kosong): itu bukan galat, tapi zip-nya nggak ada.
  if [ "$rc" -ne 0 ] || [ ! -s "$BACKUP.part" ]; then
    rm -f "$BACKUP.part"
    berhenti "The backup could not be made (zip exit $rc). Nothing was removed." "Check free space. If macOS asked whether Terminal may use Downloads, click Allow (or turn it on in System Settings > Privacy & Security > Files and Folders > Terminal)."
  fi
  unzip -tq "$BACKUP.part" >/dev/null 2>&1 || { rm -f "$BACKUP.part"; berhenti "The backup failed its integrity test. Nothing was removed." "Check free space, then try again."; }
  DAFTAR="$(zipinfo -1 "$BACKUP.part" 2>/dev/null)"
  JUMLAH="$(grep -c . <<<"$DAFTAR")"
  [ "$JUMLAH" -gt 0 ] || { rm -f "$BACKUP.part"; berhenti "The backup is empty. Nothing was removed." "Tell Daniel."; }
  for kunci in schedules.json desktop.json session-prefs.json titles.json akun-tim.json rahasia.json mcp-koneksi.json workflow/wf proyek notes; do
    [ -e "$DATA/$kunci" ] || continue
    grep -qxF ".aihub/$kunci" <<<"$DAFTAR" || grep -qxF ".aihub/$kunci/" <<<"$DAFTAR" \
      || { rm -f "$BACKUP.part"; berhenti "The backup is missing $kunci. Nothing was removed." "Tell Daniel, and send this screen."; }
  done
  mv "$BACKUP.part" "$BACKUP" && chmod 600 "$BACKUP"
  ok "Backup checked: $JUMLAH entries, $(du -h "$BACKUP" | awk '{print $1}')"
  printf '       %s\n' "$BACKUP"
  info "It holds your logins, so keep it to yourself. To restore later: quit Interfell, then run"
  printf '       ditto -x -k "%s" ~\n' "$BACKUP"
  [ "$LENGKAP" -eq 1 ] || info "Chat uploads and workflow run history are not in it (they stay in ~/.aihub). Add --lengkap to include them."
fi

# ---------- 3. Cabut instalasi terminal lama ----------
judul "3/5 Old terminal install"
SIMPAN_REPO=0
if [ ! -e "$REPO" ]; then
  ok "No terminal copy at ~/aihub"
elif [ ! -d "$REPO/.git" ]; then
  SIMPAN_REPO=1
  peringat "~/aihub is not a git copy of Interfell, so it is left alone."
elif ! xcode-select -p >/dev/null 2>&1; then
  SIMPAN_REPO=1
  peringat "Developer tools are missing, so ~/aihub cannot be checked for local work. It is left alone."
else
  export GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0
  alasan=""
  if ! STATUS="$(git -C "$REPO" status --porcelain 2>/dev/null)"; then
    alasan="git could not read it"
  else
    # Lockfile dan .DS_Store = sisa npm/Finder, bukan kerja orang (sama dengan pengaman update di app).
    KOTOR="$(printf '%s\n' "$STATUS" | grep -v -E '^.. (package-lock\.json|(.*/)?\.DS_Store)$' | grep -c .)"
    [ "$KOTOR" -gt 0 ] && alasan="$KOTOR changed file(s)"
    if UP="$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
      DEPAN="$(git -C "$REPO" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 1)"
      [ "${DEPAN:-0}" -gt 0 ] && alasan="${alasan:+$alasan, }$DEPAN commit(s) not pushed to $UP"
    else
      alasan="${alasan:+$alasan, }a branch with no upstream (commits may exist only here)"
    fi
    STASH="$(git -C "$REPO" stash list 2>/dev/null | grep -c .)"
    [ "$STASH" -gt 0 ] && alasan="${alasan:+$alasan, }$STASH stash(es)"
  fi
  if [ -n "$alasan" ]; then
    SIMPAN_REPO=1
    peringat "This looks like a developer Mac: ~/aihub has $alasan."
    peringat "The terminal setup (~/aihub, the aihub command, the PATH line) is left exactly as it is."
  else
    ke_trash "$REPO" "aihub" || berhenti "Could not move ~/aihub to the Trash." "Close any Terminal or editor window open in ~/aihub."
    ok "Moved ~/aihub to the Trash ($TRASH_DIR)"
  fi
fi

if [ "$SIMPAN_REPO" -eq 0 ]; then
  if [ -L "$BINLINK" ]; then
    case "$(readlink "$BINLINK")" in
      "$REPO"/*) ke_trash "$BINLINK" "aihub-command-link" && ok "Removed the old aihub command (~/.local/bin/aihub)" ;;
      *) info "~/.local/bin/aihub points somewhere else, left alone" ;;
    esac
  fi
  if [ -f "$ZSHRC" ] && grep -qxF "$BARIS_PATH" "$ZSHRC"; then
    LAIN="$(ls -A "$HOME/.local/bin" 2>/dev/null | grep -v -x 'aihub' | head -5 | tr '\n' ' ')"
    if [ -n "$LAIN" ]; then
      info "The PATH line in ~/.zshrc stays: other tools live in ~/.local/bin ($LAIN)"
    else
      printf '\n  The old installer added this line to ~/.zshrc:\n\n'
      grep -nxF "$BARIS_PATH" "$ZSHRC" | sed 's/^/    line /'
      if tanya_ya "Remove it? A copy of ~/.zshrc is saved first."; then
        SALINAN_RC="$HOME/.zshrc.before-interfell-$STAMP"
        cp -p "$ZSHRC" "$SALINAN_RC" || berhenti "Could not copy ~/.zshrc." "Check free space."
        grep -vxF "$BARIS_PATH" "$SALINAN_RC" > "$ZSHRC.interfell-baru"
        # cat > menulis lewat symlink (dotfiles) dan mempertahankan izin berkas.
        cat "$ZSHRC.interfell-baru" > "$ZSHRC" && rm -f "$ZSHRC.interfell-baru"
        if grep -qxF "$BARIS_PATH" "$ZSHRC"; then berhenti "The line is still in ~/.zshrc." "Your copy is at $SALINAN_RC."; fi
        ok "Removed. Copy of the old file: $SALINAN_RC"
      else
        info "Kept the PATH line (harmless)"
      fi
    fi
  fi
fi

# ---------- 4. Pasang app ----------
judul "4/5 Installing the newest Interfell"

info "Downloading..."
curl -fL --retry 2 --progress-bar -o "$KERJA/app.zip" "$URL" || berhenti "The download failed. Your current app is untouched." "Check the internet connection."
SHA_UNDUH="$(shasum -a 256 "$KERJA/app.zip" | awk '{print $1}')"
if [ -z "$SHA_UNDUH" ] || [ "$SHA_UNDUH" != "$SHA" ]; then
  berhenti "The download's fingerprint does not match (got ${SHA_UNDUH:-nothing}). Your current app is untouched." "Try again in a few minutes. If it keeps happening, tell Daniel."
fi
ok "Fingerprint matches"

mkdir "$KERJA/isi" && ditto -x -k "$KERJA/app.zip" "$KERJA/isi" || berhenti "Could not unpack the download. Your current app is untouched." "Check free space."
DAFTAR_APP="$(find "$KERJA/isi" -maxdepth 2 -type d -name '*.app' ! -path '*/__MACOSX/*')"
[ "$(printf '%s\n' "$DAFTAR_APP" | grep -c .)" -eq 1 ] || berhenti "The download does not hold exactly one app. Your current app is untouched." "Tell Daniel."
BARU="$DAFTAR_APP"
[ "$(id_app "$BARU")" = "$BUNDLE_ID" ] || berhenti "The download is not the Interfell app ($(id_app "$BARU")). Your current app is untouched." "Tell Daniel."
[ "$(versi_app "$BARU")" = "$VERSI" ] || berhenti "The download is version $(versi_app "$BARU"), expected $VERSI. Your current app is untouched." "Try again in a few minutes."
codesign --verify --deep --strict "$BARU" >/dev/null 2>&1 || berhenti "The downloaded app's signature is broken. Your current app is untouched." "Tell Daniel."
ok "Download checked (Interfell $VERSI, signature intact)"

LAMA_DI_TRASH=""
if [ -e "$APP" ]; then
  ke_trash "$APP" "AI Hub.app" || berhenti "Could not move the old app out of the way." "Quit Interfell and try again."
  LAMA_DI_TRASH="$TRASH_DIR/AI Hub.app"
fi
if ! ditto "$BARU" "$APP"; then
  rm -rf "$APP"
  [ -n "$LAMA_DI_TRASH" ] && mv "$LAMA_DI_TRASH" "$APP"
  berhenti "Could not copy the new app into $APPS. The old app was put back." "Check free space."
fi
if ! codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  rm -rf "$APP"
  [ -n "$LAMA_DI_TRASH" ] && mv "$LAMA_DI_TRASH" "$APP"
  berhenti "The installed copy failed its signature check. The old app was put back." "Tell Daniel."
fi
# curl nggak memasang karantina, jadi ini mestinya kosong. Kalau ada, bersihkan dari app INI saja.
if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then xattr -dr com.apple.quarantine "$APP" 2>/dev/null; fi
rm -rf "$KERJA"; KERJA=""
ok "Installed $APP"
[ -n "$LAMA_DI_TRASH" ] && info "The previous app is in the Trash: $LAMA_DI_TRASH"

# ---------- 5. Buka dan periksa ----------
judul "5/5 Opening Interfell"
open "$APP" || berhenti "macOS would not open the app." "Open Interfell from the Applications folder by double clicking it."
SRV=""
for _ in $(seq 1 "$TUNGGU"); do
  SRV="$(cari_server)" && case "$SRV" in *" 1") break ;; esac
  SRV=""; sleep 1
done
[ -n "$SRV" ] || berhenti "Interfell was installed but did not answer within $TUNGGU seconds." "Open Interfell from Applications. If a dialog says it cannot be opened, send a screenshot to Daniel."
ok "Interfell is running (port ${SRV% *})"

# Jadwal lama dipulihkan app waktu menyala; beri waktu sebentar sebelum menilai.
for _ in $(seq 1 20); do [ -z "$(plist_rusak)" ] && break; sleep 1; done

VERSI_TERBARU="$VERSI"
periksa_semua; rc=$?
judul "Done"
[ -n "$BACKUP" ] && printf '  Backup:  %s\n' "$BACKUP"
[ -n "$TRASH_DIR" ] && printf '  Removed items are in: %s\n' "$TRASH_DIR"
printf '  Sessions in ~/.claude, ~/.codex, and ~/.kimi-code were not touched.\n'
pemulihan
exit "$rc"
