#!/usr/bin/env bash
# Safe launcher for restoring a Raspberry Pi from raspi-private-backup.
# This script does not install packages, enable/start services, or overwrite existing files.
set -Eeuo pipefail
umask 077

say() { printf '\n%s\n' "$*"; }
die() { printf 'RALAT: %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -ne 0 ]] || die "Jalankan sebagai pengguna biasa, bukan root."
command -v tar >/dev/null 2>&1 || die "tar tiada. Pasang dahulu: sudo apt install tar"
command -v git >/dev/null 2>&1 || die "git tiada. Pasang dahulu: sudo apt install git"

BACKUP_TARBALL="${1:-}"
if [[ -z "$BACKUP_TARBALL" ]]; then
  printf 'Lokasi fail backup .tar.gz: '
  IFS= read -r BACKUP_TARBALL
fi
[[ -f "$BACKUP_TARBALL" ]] || die "Fail backup tidak ditemui: $BACKUP_TARBALL"
[[ "$BACKUP_TARBALL" == *.tar.gz ]] || die "Fail mesti berakhir dengan .tar.gz"

REPO_DIR="$HOME/recovery-repo"
RESTORE_SCRIPT="$REPO_DIR/restore-from-backup.sh"
WORK_DIR="$HOME/raspi-restore-source"

say "=== Pemulihan Raspberry Pi (mod selamat) ==="
say "Backup: $BACKUP_TARBALL"
say "Skrip tidak akan menimpa fail sedia ada, enable/start servis, atau memadam backup."

if [[ ! -f "$RESTORE_SCRIPT" ]]; then
  if [[ -e "$REPO_DIR" ]]; then
    die "$REPO_DIR wujud tetapi restore-from-backup.sh tiada. Semak folder itu dahulu."
  fi
  say "Muat turun skrip pemulihan dari GitHub..."
  git clone --branch recovery-system --depth 1 https://github.com/zus599470/speedtest-bot.git "$REPO_DIR"
fi
[[ -f "$RESTORE_SCRIPT" ]] || die "Skrip pemulihan tidak ditemui: $RESTORE_SCRIPT"
bash -n "$RESTORE_SCRIPT" || die "Sintaks restore-from-backup.sh tidak sah."

if [[ -e "$WORK_DIR" ]]; then
  printf 'Folder %s sudah wujud. Guna folder ini dan jangan ekstrak semula? [y/N] ' "$WORK_DIR"
  IFS= read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || die "Dihentikan tanpa perubahan."
else
  mkdir -p "$WORK_DIR"
  say "Menyemak arkib sebelum ekstrak..."
  tar -tzf "$BACKUP_TARBALL" >/dev/null || die "Arkib rosak atau tidak sah."
  tar -xzf "$BACKUP_TARBALL" -C "$WORK_DIR"
fi

BACKUP_DIR="$(find "$WORK_DIR" -mindepth 1 -maxdepth 1 -type d -name 'raspi-private-backup-*' -print -quit)"
[[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || die "Folder raspi-private-backup-* tidak ditemui selepas ekstrak."
[[ -f "$BACKUP_DIR/system/inventory/architecture.txt" ]] || die "Inventori backup tidak lengkap."

say "Backup berjaya diekstrak dan inventori ditemui."
say "Skrip restore akan dibuka. Pilih 6 untuk urutan pemulihan selamat."
say "Semak setiap prompt sebelum jawab ya. Servis tidak akan dihidupkan secara automatik."
exec bash "$RESTORE_SCRIPT" "$BACKUP_DIR"
