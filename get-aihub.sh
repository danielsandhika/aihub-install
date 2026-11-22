#!/bin/bash
# get-aihub.sh lama: dulu meng-clone repo ke ~/aihub dan memasang perintah `aihub` di terminal.
#
# Sejak 21 Nov 2026 (keputusan Daniel) jalur tim cuma app desktop. Skrip ini sengaja nggak memasang apa pun lagi:
# dia cuma menunjuk ke perintah pasang ulang, supaya perintah lama yang masih nyangkut di chat dan dokumen nggak
# diam-diam menghidupkan jalur terminal lagi (skill rilis-ke-tim bagian 10).

cat <<'EOF'

  The terminal install of Interfell is retired. Interfell is now the desktop app only.

  To install it (or repair it), run this one line in Terminal. Your sessions,
  workflows, projects, and settings stay:

    bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/pasang-ulang-interfell.sh)"

  It backs up your Interfell data first, removes the old ~/aihub terminal copy
  (unless it has your own changes), and installs the newest app.

EOF
exit 1
