# Interfell: pasang, perbaiki, uninstall

Interfell sekarang cuma app desktop (macOS, Apple silicon). Semua lewat **Terminal** (Cmd+Space, ketik "terminal").

## Pasang, pasang ulang, atau perbaiki

Satu baris yang sama buat pasang pertama kali, pasang ulang, atau memperbaiki app yang nggak mau kebuka atau nggak mau update:

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/pasang-ulang-interfell.sh)"
```

Data kamu (sesi, workflow, project, jadwal, login) tetap. Skripnya bikin backup dulu di Downloads.

Cuma mau cek kesehatan tanpa mengubah apa pun: tambahkan ` --periksa` di ujung baris itu.

## Uninstall

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsandhika/aihub-install/main/uninstall-interfell.sh)"
```

Yang dihapus masuk satu folder di Trash, jadi bisa dikembalikan. Folder data `~/.aihub` sengaja disimpan.

## Panduan lengkap

[Interfell-Panduan-Tim.pdf](Interfell-Panduan-Tim.pdf)

## Update

Sesudah terpasang, update datang sendiri waktu app dibuka, dan cuma update yang lolos pemeriksaan tanda tangan yang dipasang. Kalau app bilang **Update blocked**, kabari Daniel dulu dan jangan pasang Interfell dari tempat lain.

## Isi repo ini

- `pasang-ulang-interfell.sh`, `uninstall-interfell.sh`: skrip di atas.
- `get-aihub.sh`: perintah pasang terminal yang lama, sekarang cuma menunjuk ke baris pasang di atas.
- `desktop-latest.json`: kanal update app (ditandatangani; jangan diedit tangan).
- Rilis (Releases): zip app tiap versi.
