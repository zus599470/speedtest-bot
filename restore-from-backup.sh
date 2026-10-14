#!/usr/bin/env bash
# Safe, interactive Raspberry Pi restore helper.
# Never overwrites existing files and never enables/starts services automatically.
set -Eeuo pipefail
umask 077

BACKUP_DIR="${1:-$HOME/raspi-private-backup-20261014-234757}"
STAGE="$HOME/raspi-restore-staging-$(date +%Y%m%d-%H%M%S)"
RESTORE_USER="${SUDO_USER:-$USER}"
RESTORE_GROUP="$(id -gn "$RESTORE_USER" 2>/dev/null || id -gn)"

die() { printf 'RALAT: %s\n' "$*" >&2; exit 1; }
say() { printf '\n===== %s =====\n' "$*"; }
confirm() {
  local answer
  read -r -p "$1 [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

[[ "$EUID" -ne 0 ]] || die "Jalankan sebagai pengguna biasa (contoh: azam), bukan menggunakan sudo di hadapan skrip."
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

restore_projects() {
  mkdir -p "$STAGE"
  local project archive target extracted
  local projects=(speedtest-bot raspberry-dashboard pencarimovie-server pencarimovie-bot hermes-pi-bot)
  for project in "${projects[@]}"; do
    archive="$BACKUP_DIR/$project.tar.gz"
    [[ -f "$archive" ]] || { printf 'SKIP: arkib tiada: %s\n' "$project"; continue; }
    target="$HOME/$project"
    mkdir -p "$STAGE/$project"
    tar -xzf "$archive" -C "$STAGE/$project"
    extracted="$STAGE/$project/$project"
    [[ -d "$extracted" ]] || die "Struktur arkib tidak dijangka untuk $project"
    if [[ -e "$target" ]]; then
      printf 'Folder sudah wujud: %s\n' "$target"
      if confirm "Gabungkan fail yang BELUM wujud sahaja untuk $project?"; then
        cp -an "$extracted/." "$target/"
        printf 'OK: fail sedia ada dikekalkan; fail hilang ditambah ke %s\n' "$target"
      else
        printf 'SKIP: %s\n' "$target"
      fi
    elif confirm "Pulihkan $project ke $target?"; then
      cp -a "$extracted" "$target"
      printf 'OK: dipulihkan ke %s\n' "$target"
    else
      printf 'Dibatalkan: %s\n' "$project"
    fi
  done

  archive="$BACKUP_DIR/telegram-api/telegram-bot-api-full.tar.gz"
  target="$HOME/telegram-bot-api"
  if [[ -f "$archive" ]]; then
    mkdir -p "$STAGE/telegram-api"
    tar -xzf "$archive" -C "$STAGE/telegram-api"
    if [[ -d "$STAGE/telegram-api/telegram-bot-api" ]]; then
      if [[ -e "$target" ]]; then
        if confirm "Telegram Bot API sudah wujud. Gabungkan fail yang belum wujud sahaja?"; then
          cp -an "$STAGE/telegram-api/telegram-bot-api/." "$target/"
        fi
      elif confirm "Salin source Telegram Bot API ke $target?"; then
        cp -a "$STAGE/telegram-api/telegram-bot-api" "$target"
      fi
      printf 'Nota: source sahaja; build/binari dan dependencies mesti disahkan atau dibina semula.\n'
    else
      printf 'SKIP: struktur dalaman Telegram Bot API tidak dikenali; tiada fail disalin.\n'
    fi
  fi
  printf '\nStaging sementara: %s\n' "$STAGE"
}

restore_private() {
  echo "Fail rahsia tidak akan dicetak. Fail sedia ada tidak akan ditimpa."
  while IFS= read -r -d '' src; do
    local rel target
    rel="${src#"$BACKUP_DIR/private/"}"
    case "$rel" in
      home/azam/*) target="/home/azam/${rel#home/azam/}" ;;
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
        sudo install -D -o "$RESTORE_USER" -g "$RESTORE_GROUP" -m 600 "$src" "$target"
      fi
      printf 'OK: konfigurasi disalin (kandungan tidak dipaparkan).\n'
    fi
  done < <(find "$BACKUP_DIR/private" -type f -print0)
}

review_packages() {
  local pkgfile="$BACKUP_DIR/system/inventory/manual-packages.txt"
  [[ -s "$pkgfile" ]] || die "Senarai pakej manual tiada."
  echo "Senarai pakej manual boleh mengandungi pakej lama/tidak tersedia."
  echo "Tiada pemasangan dibuat oleh pilihan ini."
  printf 'Bilangan entri: '; wc -l < "$pkgfile"
  if confirm "Papar senarai pakej untuk semakan?"; then cat "$pkgfile"; fi
  echo "Selepas semakan, pasang pakej terpilih menggunakan apt secara berasingan."
}

restore_units() {
  local units="$BACKUP_DIR/system/units" src name target
  [[ -d "$units" ]] || die "Folder unit systemd tiada."
  echo "Unit disalin sahaja. Enable/start tidak dijalankan."
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
  echo "Semak EnvironmentFile, executable dan laluan sebelum enable/start servis."
}

show_guide() {
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
}

say "Menu pemulihan"
cat <<'MENU'
1. Pulihkan projek (tambah fail hilang sahaja; tidak menimpa fail sedia ada)
2. Salin konfigurasi peribadi yang belum wujud
3. Semak senarai pakej manual (tiada pemasangan automatik)
4. Pasang unit systemd yang belum wujud (tidak enable/start servis)
5. Paparkan panduan Pi-hole dan Cloudflare
6. Jalankan pemulihan selamat: projek, konfigurasi peribadi, unit systemd
0. Keluar
MENU
read -r -p "Pilih [0-6]: " choice

case "$choice" in
  1) restore_projects ;;
  2) restore_private ;;
  3) review_packages ;;
  4) restore_units ;;
  5) show_guide ;;
  6)
    say "Langkah 1/3: projek"
    restore_projects
    say "Langkah 2/3: konfigurasi peribadi"
    restore_private
    say "Langkah 3/3: unit systemd"
    restore_units
    ;;
  0) echo "Keluar tanpa perubahan."; exit 0 ;;
  *) die "Pilihan tidak sah." ;;
esac

say "Selesai"
echo "Tiada servis di-enable atau dimulakan secara automatik."
