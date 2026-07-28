#!/bin/bash
# Bootstrap AI Hub: satu perintah, dari nol sampai jalan.
#
#   curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/get-aihub.sh | bash
#
# Skrip ini TIDAK memuat rahasia apa pun. Dia cuma nuntun prasyarat lalu clone repo
# private pakai kredensial GitHub milik user sendiri, jadi aman ditaruh di tempat publik.
set -uo pipefail

REPO="danielsandhika/AI-Hub"
TARGET="${AIHUB_HOME:-$HOME/aihub}"

say()   { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()    { printf '  ok   %s\n' "$1"; }
warn()  { printf '  !    %s\n' "$1"; }
die()   { printf '\n  BERHENTI: %s\n\n' "$1" >&2; exit 1; }
langkah() { printf '\n  ── %s\n' "$1"; }

say "AI Hub · pemasangan"

# ---------- 1. Prasyarat ----------
[ "$(uname)" = "Darwin" ] || die "AI Hub baru jalan di macOS."

if ! xcode-select -p >/dev/null 2>&1; then
  warn "Xcode Command Line Tools belum ada, dibutuhkan buat compile modul terminal."
  langkah "Jendela instalasi bakal muncul. Selesaikan dulu, lalu jalankan perintah ini lagi."
  xcode-select --install || true
  exit 1
fi
ok "Xcode Command Line Tools"

if ! command -v node >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    warn "Node belum ada, dipasang lewat Homebrew..."
    brew install node || die "Gagal pasang Node. Coba 'brew install node' manual."
  else
    die "Node.js dan Homebrew dua-duanya belum ada. Pasang Homebrew dulu dari https://brew.sh lalu ulangi."
  fi
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
[ "$NODE_MAJOR" -ge 20 ] || die "Node kamu v$(node -v 2>/dev/null), minimal v20. Jalankan 'brew upgrade node' lalu ulangi."
ok "Node $(node -v)"

# ---------- 2. Akses repo ----------
punya_akses() { git ls-remote "$1" >/dev/null 2>&1; }

CLONE_URL=""
# Buat yang pakai alias SSH sendiri (contoh: host github-personal di ~/.ssh/config),
# alamat git@github.com nggak akan kebaca. Sediakan jalan pintas eksplisit.
if [ -n "${AIHUB_CLONE_URL:-}" ] && punya_akses "$AIHUB_CLONE_URL"; then
  CLONE_URL="$AIHUB_CLONE_URL"; ok "akses repo lewat AIHUB_CLONE_URL"
elif punya_akses "git@github.com:$REPO.git"; then
  CLONE_URL="git@github.com:$REPO.git"; ok "akses repo lewat SSH"
elif punya_akses "https://github.com/$REPO.git"; then
  CLONE_URL="https://github.com/$REPO.git"; ok "akses repo lewat HTTPS"
else
  warn "Belum bisa mengakses repo $REPO."
  echo
  echo "  Dua hal yang perlu beres:"
  echo "    1. Undangan collaborator dari Daniel sudah kamu TERIMA"
  echo "       (cek email, atau buka https://github.com/notifications)"
  echo "    2. Terminal ini sudah login GitHub"
  echo
  if command -v gh >/dev/null 2>&1; then
    langkah "GitHub CLI terdeteksi. Menjalankan login..."
    gh auth login || true
    gh auth setup-git >/dev/null 2>&1 || true
  else
    if command -v brew >/dev/null 2>&1; then
      langkah "Memasang GitHub CLI biar login-nya dituntun lewat browser..."
      brew install gh && gh auth login && gh auth setup-git >/dev/null 2>&1 || true
    else
      die "Login GitHub belum ada. Pasang GitHub CLI (brew install gh), jalankan 'gh auth login', lalu ulangi perintah ini."
    fi
  fi

  if punya_akses "https://github.com/$REPO.git"; then
    CLONE_URL="https://github.com/$REPO.git"; ok "akses repo lewat HTTPS"
  elif punya_akses "git@github.com:$REPO.git"; then
    CLONE_URL="git@github.com:$REPO.git"; ok "akses repo lewat SSH"
  else
    echo
    echo "  Kalau kamu pakai alias SSH sendiri di ~/.ssh/config, jalankan begini:"
    echo "    AIHUB_CLONE_URL=alias-kamu:$REPO.git bash -c \"\$(curl -fsSL <url-skrip-ini>)\""
    echo
    die "Masih belum bisa akses repo. Pastikan undangan collaborator sudah diterima, lalu ulangi perintah ini."
  fi
fi

# ---------- 3. Ambil kode ----------
if [ -d "$TARGET/.git" ]; then
  say "Folder $TARGET sudah ada, diperbarui saja"
  git -C "$TARGET" checkout -- package-lock.json 2>/dev/null || true
  git -C "$TARGET" pull --ff-only || die "Gagal memperbarui. Kalau ada file yang kamu ubah di $TARGET, kembalikan dulu."
elif [ -e "$TARGET" ]; then
  die "$TARGET sudah ada tapi bukan hasil clone git. Pindahkan atau hapus dulu, lalu ulangi."
else
  say "Mengambil kode ke $TARGET"
  git clone --depth 50 "$CLONE_URL" "$TARGET" || die "Gagal clone."
fi
ok "kode siap"

# ---------- 4. Pasang ----------
say "Memasang (2 sampai 5 menit, ada modul yang dikompilasi)"
cd "$TARGET"
bash install.sh || die "Pemasangan gagal. Kirim 10 baris terakhir error di atas ke Daniel, atau jalankan 'aihub doctor'."

say "Selesai"
cat <<EOF

  Jalankan:            aihub
  Kalau ada update:    tombol hijau di dashboard, atau 'aihub update'
  Kalau ada masalah:   aihub doctor

  Panduan pakai ada di $TARGET/docs/PANDUAN.md (versi PDF: docs/AI-Hub-Panduan-Tim.pdf)

EOF
