#!/usr/bin/env bash
# Safe, interactive restore helper for the user's Raspberry Pi backup.
# Does not overwrite existing project folders or start services automatically.
set -Eeuo pipefail
umask 077

BACKUP_DIR="${1:-$HOME/raspi-private-backup-20261014-234757}"
STAGE="$HOME/raspi-restore-staging-$(date +%Y%m%d-%H%M%S)"

die() { printf 'RALAT: %s\n' "$*" >&2; exit 1; }
say() { printf '\n===== %s =====\n' "$*"; }
confirm() {
  local answer
  read -r -p "$1 [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

[[ -d "$BACKUP_DIR" ]] || die "Folder backup tidak dijumpai: $BACKUP_DIR"
[[ -f "$BACKUP_DIR/system/inventory/architecture.txt" ]] || die "Inventori backup tiada; pastikan arkib diekstrak dengan betul."

say "Pengesahan platform"
printf 'OS: '; . /etc/os-release; printf '%s\n' "$PRETTY_NAME"
printf 'Architecture sekarang: '; dpkg --print-architecture
printf 'Architecture backup: '; cat "$BACKUP_DIR/system/inventory/architecture.txt"
if [[ "$(dpkg --print-architecture)" != "$(cat "$BACKUP_DIR/system/inventory/architecture.txt")" ]]; then
  printf 'AMARAN: seni bina berbeza; jangan pasang binari lama secara terus.\n'
fi

say "Semak arkib"
archives=(
  "$BACKUP_DIR/speedtest-bot.tar.gz"
  "$BACKUP_DIR/raspberry-dashboard.tar.gz"
  "$BACKUP_DIR/pencarimovie-server.tar.gz"
  "$BACKUP_DIR/pencarimovie-bot.tar.gz"
  "$BACKUP_DIR/hermes-pi-bot.tar.gz"
  "$BACKUP_DIR/telegram-api/telegram-bot-api-full.tar.gz"
  "$BACKUP_DIR/pihole/pihole-config.tar.gz"
)
for archive in "${archives[@]}"; do
  if [[ -f "$archive" ]] && tar -tzf "$archive" >/dev/null 2>&1; then
    printf 'OK: %s\n' "${archive#"$BACKUP_DIR"/}"
  else
    printf 'TIDAK SAH / TIADA: %s\n' "${archive#"$BACKUP_DIR"/}"
  fi
done

say "Menu pemulihan"
cat <<'MENU'
1. Pulihkan projek yang foldernya BELUM wujud (mod selamat)
2. Salin konfigurasi peribadi yang belum wujud
3. Pasang pakej manual dari inventori (semakan dahulu)
4. Pasang unit systemd (tidak akan enable/start servis)
5. Paparkan panduan Pi-hole dan Cloudflare
0. Keluar
MENU
read -r -p "Pilih [0-5]: " choice

case "$choice" in
  1)
    mkdir -p "$STAGE"
    projects=(speedtest-bot raspberry-dashboard pencarimovie-server pencarimovie-bot hermes-pi-bot)
    for project in "${projects[@]}"; do
      archive="$BACKUP_DIR/$project.tar.gz"
      [[ -f "$archive" ]] || { printf 'SKIP: arkib tiada: %s\n' "$project"; continue; }
      target="$HOME/$project"
      if [[ -e "$target" ]]; then
        printf 'SKIP: folder sudah wujud, tidak ditimpa: %s\n' "$target"
        continue
      fi
      mkdir -p "$STAGE/$project"
      tar -xzf "$archive" -C "$STAGE/$project"
      extracted="$STAGE/$project/$project"
      [[ -d "$extracted" ]] || die "Struktur arkib tidak dijangka untuk $project"
      if confirm "Salin $project ke $target?"; then
        cp -a "$extracted" "$target"
        printf 'OK: dipulihkan ke %s\n' "$target"
      else
        printf 'Dibatalkan: %s\n' "$project"
      fi
    done
    archive="$BACKUP_DIR/telegram-api/telegram-bot-api-full.tar.gz"
    target="$HOME/telegram-bot-api"
    if [[ -f "$archive" && ! -e "$target" ]]; then
      mkdir -p "$STAGE/telegram-api"
      tar -xzf "$archive" -C "$STAGE/telegram-api"
      if [[ -d "$STAGE/telegram-api/telegram-bot-api" ]] && confirm "Salin source Telegram Bot API ke $target?"; then
        cp -a "$STAGE/telegram-api/telegram-bot-api" "$target"
        printf 'OK: source Telegram Bot API disalin. Binari/build masih perlu disahkan atau dibina semula.\n'
      fi
    else
      printf 'SKIP: Telegram Bot API sudah ada atau arkib tiada.\n'
    fi
    printf '\nStaging sementara: %s\n' "$STAGE"
    ;;
  2)
    echo "Fail rahsia tidak akan dicetak. Sasaran hanya dibuat jika fail sasaran belum wujud."
    while IFS= read -r -d '' src; do
      rel="${src#"$BACKUP_DIR/private/"}"
      case "$rel" in
        home/azam/*) target="/${rel#home/azam/}" ;;
        cloudflared/token) target="/etc/cloudflared/token" ;;
        *) printf 'SKIP: laluan tidak dikenali: %s\n' "$rel"; continue ;;
      esac
      if [[ -e "$target" ]]; then
        printf 'SKIP: sasaran sudah wujud: %s\n' "$target"
        continue
      fi
      if confirm "Pulihkan fail rahsia ke $target?"; then
        if [[ "$target" == /etc/cloudflared/token ]]; then
          sudo install -d -o root -g root -m 700 /etc/cloudflared
          sudo install -o root -g root -m 600 "$src" "$target"
        else
          sudo install -D -o "$USER" -g "$(id -gn)" -m 600 "$src" "$target"
        fi
        printf 'OK: konfigurasi disalin (kandungan tidak dipaparkan).\n'
      fi
    done < <(find "$BACKUP_DIR/private" -type f -print0)
    ;;
  3)
    pkgfile="$BACKUP_DIR/system/inventory/manual-packages.txt"
    [[ -s "$pkgfile" ]] || die "Senarai pakej manual tiada."
    echo "Senarai pakej manual boleh mengandungi pakej lama/tidak tersedia."
    echo "Tiada pemasangan dibuat oleh pilihan ini."
    printf 'Bilangan entri: '; wc -l < "$pkgfile"
    if confirm "Papar senarai pakej untuk semakan?"; then cat "$pkgfile"; fi
    echo "Selepas semakan, pasang pakej terpilih menggunakan apt secara berasingan."
    ;;
  4)
    units="$BACKUP_DIR/system/units"
    [[ -d "$units" ]] || die "Folder unit systemd tiada."
    echo "Unit akan disalin sahaja. Enable/start tidak dijalankan."
    for src in "$units"/*.service; do
      [[ -f "$src" ]] || continue
      name="$(basename "$src")"
      target="/etc/systemd/system/$name"
      if [[ -e "$target" ]]; then
        printf 'SKIP: unit sudah wujud: %s\n' "$name"
      elif confirm "Pasang unit $name ke /etc/systemd/system/?"; then
        sudo install -o root -g root -m 644 "$src" "$target"
        printf 'OK: unit disalin: %s\n' "$name"
      fi
    done
    if confirm "Jalankan systemctl daemon-reload sekarang?"; then sudo systemctl daemon-reload; fi
    echo "Semak setiap EnvironmentFile, executable dan laluan sebelum enable/start servis."
    ;;
  5)
    cat <<'GUIDE'
PI-HOLE:
- Backup config sahaja tidak menjamin pemulihan merentas versi Pi-hole.
- Pasang versi Pi-hole yang serasi dan semak dokumentasi rasmi sebelum restore.
- Jangan extract pihole-config.tar.gz terus ke /etc tanpa semakan.
- Selepas pulih, semak DNS, lists, custom settings dan status pihole-FTL.

CLOUDFLARE:
- Token disimpan dalam private/cloudflared/token.
- Pulihkan token dengan hak root dan permission 600 sahaja.
- Semak tunnel, hostname dan DNS di Cloudflare sebelum enable/start cloudflared.

TELEGRAM BOT API:
- Arkib source bukan jaminan binari ARM64 atau build dependencies tersedia.
- Pasang build tools/dependencies mengikut dokumentasi upstream, kemudian bina dan uji dahulu.

KESELAMATAN:
- Jangan muat naik folder backup/private atau arkib penuh ke repo GitHub awam.
- Jangan jalankan skrip jauh melalui curl | bash tanpa semakan kandungan.
GUIDE
    ;;
  0) echo "Keluar tanpa perubahan."; exit 0 ;;
  *) die "Pilihan tidak sah." ;;
esac

say "Selesai"
echo "Tiada servis di-enable atau dimulakan secara automatik."
