#!/bin/bash
# Bootstrap AI Hub: satu perintah, dari nol sampai jalan.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/get-aihub.sh)"
#
# Skrip ini TIDAK memuat rahasia apa pun. Dia cuma nuntun prasyarat lalu clone repo
# private pakai kredensial GitHub milik user sendiri, jadi aman ditaruh di tempat publik.
set -uo pipefail

REPO="danielsandhika/AI-Hub"
INSTALLER_URL="https://raw.githubusercontent.com/danielsandhika/aihub-install/main/get-aihub.sh"
TARGET="${AIHUB_HOME:-$HOME/aihub}"

say()   { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()    { printf '  ok   %s\n' "$1"; }
warn()  { printf '  !    %s\n' "$1"; }
die()   { printf '\n  BERHENTI: %s\n\n' "$1" >&2; exit 1; }
langkah() { printf '\n  ── %s\n' "$1"; }

# `curl ... | bash` bikin stdin dipakai buat isi skrip, jadi prompt apa pun
# (host key SSH, login GitHub, sudo) nggak bisa dijawab dan pemasangan mentok.
# Bentuk bash -c "$(curl ...)" nyimpen terminal tetap bisa dipakai.
if [ ! -t 0 ]; then
  cat <<'EOF'

  Jalankan dengan bentuk ini supaya terminalnya tetap bisa menjawab pertanyaan:

    bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/get-aihub.sh)"

EOF
  exit 1
fi

# Homebrew sering nggak kebaca di shell non-interaktif, apalagi di Apple Silicon
# yang menaruhnya di /opt/homebrew. Cari di tempat-tempat yang lazim, bukan cuma PATH.
cari_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/homebrew/bin/brew"; do
    [ -x "$b" ] && { eval "$("$b" shellenv)"; return 0; }
  done
  return 1
}

# Node lewat nvm juga nggak otomatis kebaca di shell baru.
muat_nvm() { [ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true; }

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

command -v node >/dev/null 2>&1 || muat_nvm
if ! command -v node >/dev/null 2>&1; then
  if cari_brew; then
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
# Pengecekan akses harus diam: BatchMode bikin SSH gagal cepat daripada nanya,
# accept-new nerima host key GitHub tanpa tanya, dan GIT_TERMINAL_PROMPT=0 bikin
# HTTPS gagal cepat daripada minta username dan password (yang lagipula sudah
# nggak dipakai GitHub sejak 2021).
punya_akses() {
  GIT_TERMINAL_PROMPT=0 \
  GIT_ASKPASS=/usr/bin/true \
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8" \
    git ls-remote "$1" >/dev/null 2>&1
}

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
  if ! command -v gh >/dev/null 2>&1 && cari_brew; then
    langkah "Memasang GitHub CLI dulu (sekali saja)"
    brew install gh || true
  fi

  # GITHUB_TOKEN / GH_TOKEN di environment bikin `gh auth login` NOLAK jalan
  # ("first clear the value from the environment"), jadi installer-nya berhenti
  # padahal user nggak salah apa-apa. Coba dulu tokennya beneran punya akses;
  # kalau nggak, minggirin token itu buat sisa skrip ini saja.
  if [ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
    if gh repo view "$REPO" >/dev/null 2>&1; then
      langkah "Pakai GITHUB_TOKEN yang sudah ada di terminal kamu"
      gh auth setup-git >/dev/null 2>&1 || true
      if punya_akses "https://github.com/$REPO.git"; then
        CLONE_URL="https://github.com/$REPO.git"; ok "akses repo lewat token yang sudah ada"
      fi
    else
      warn "GITHUB_TOKEN di terminal kamu nggak punya akses ke repo ini, jadi diabaikan."
      unset GITHUB_TOKEN GH_TOKEN
    fi
  fi

  if [ -n "$CLONE_URL" ]; then
    : # sudah dapat akses lewat token, nggak perlu login lagi
  elif command -v gh >/dev/null 2>&1; then
    # Jalur termudah: login lewat browser.
    if ! gh auth status >/dev/null 2>&1; then
      langkah "Login GitHub lewat browser. Pilih HTTPS waktu ditanya protokol."
      gh auth login || die "Login GitHub dibatalkan. Ulangi perintah ini kapan pun kamu siap. Kalau tadi muncul pesan soal GITHUB_TOKEN, jalankan ulang begini: env -u GITHUB_TOKEN -u GH_TOKEN bash -c \"\$(curl -fsSL $INSTALLER_URL)\""
    fi
    gh auth setup-git >/dev/null 2>&1 || true
    ok "login GitHub siap"
  else
    # Tanpa Homebrew dan tanpa GitHub CLI: pakai kunci SSH, cuma butuh bawaan macOS.
    KEY="$HOME/.ssh/id_ed25519"
    if [ ! -f "$KEY" ]; then
      langkah "Membuat kunci SSH baru (sekali seumur hidup)"
      mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
      ssh-keygen -t ed25519 -N "" -f "$KEY" -C "aihub-$(whoami)@$(hostname -s)" >/dev/null || die "Gagal membuat kunci SSH."
    fi
    echo
    echo "  Salin baris di bawah ini, lalu tempel di https://github.com/settings/ssh/new"
    echo "  (Title boleh diisi apa saja, contoh: MacBook saya)"
    echo
    echo "  ────────────────────────────────────────────────────────────"
    cat "$KEY.pub"
    echo "  ────────────────────────────────────────────────────────────"
    echo
    command -v pbcopy >/dev/null 2>&1 && pbcopy < "$KEY.pub" && echo "  (sudah otomatis tersalin ke clipboard kamu)"
    echo
    printf '  Tekan Enter kalau kuncinya sudah ditambahkan di GitHub... '
    read -r _ </dev/tty
    ssh-add "$KEY" >/dev/null 2>&1 || true
  fi

  if punya_akses "https://github.com/$REPO.git"; then
    CLONE_URL="https://github.com/$REPO.git"; ok "akses repo lewat HTTPS"
  elif punya_akses "git@github.com:$REPO.git"; then
    CLONE_URL="git@github.com:$REPO.git"; ok "akses repo lewat SSH"
  else
    echo
    echo "  Kalau kamu pakai alias SSH sendiri di ~/.ssh/config, jalankan begini:"
    echo "    AIHUB_CLONE_URL=alias-kamu:$REPO.git bash -c \"\$(curl -fsSL $INSTALLER_URL)\""
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
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
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
