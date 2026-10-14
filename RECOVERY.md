# Raspberry Pi recovery (safe mode)

This public repository contains recovery scripts and documentation only. Never commit the private backup archive, environment files, tokens, passwords, Pi-hole secrets, or runtime user state.

## Before reinstalling Ubuntu
1. Keep a copy of the private archive on a separate PC or external drive.
2. Verify its SHA-256 against the value recorded when it was created.
3. Do not rely on the backup remaining only on the Raspberry Pi SD card.
4. Store the archive securely and do not upload it to this public repository.

## Restore workflow
Transfer the private backup archive to the reinstalled Pi. Check it and extract it:

```bash
tar -tzf "$HOME/raspi-private-backup-20261014-234757.tar.gz" >/dev/null
mkdir -p "$HOME"
tar -xzf "$HOME/raspi-private-backup-20261014-234757.tar.gz" -C "$HOME"
```

Clone the recovery branch and run the helper against the extracted backup folder:

```bash
git clone -b recovery-system https://github.com/zus599470/speedtest-bot.git ~/recovery-repo
bash ~/recovery-repo/restore-from-backup.sh "$HOME/raspi-private-backup-20261014-234757"
```

Choose menu option 6 for the guided safe sequence, or use options 1, 2 and 4 separately. Run the helper as a normal user (for example, azam); it uses sudo only for protected configuration and systemd operations.

The helper checks archives and architecture, restores project folders or merges only files that do not already exist, restores private config files only when the destination is absent, and copies systemd units only after confirmation. It does not enable or start services, install packages automatically, restore Pi-hole configuration, or run remote installer scripts.

## Important limitations
- This is a guided recovery helper, not fully automatic one-command recovery. Review prompts carefully and test every service.
- Python virtual environments are not restored; recreate them for the installed Python version and install verified requirements.
- Review systemd units, environment-file paths, executable paths and permissions before enabling services.
- Pi-hole configuration restoration is version-sensitive; use the supported backup/restore workflow for the installed version.
- Cloudflare tunnel settings, DNS/hostname, credentials and permissions must be checked.
- Telegram Bot API source may need dependencies and a fresh ARM64 build.
- Local changes made after the backup date are not included.
