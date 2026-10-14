# Raspberry Pi recovery (safe mode)

This repository is public. It contains scripts and documentation only. **Never commit the private backup archive, `.env`/`config.env`, tokens, passwords, Pi-hole secrets, or runtime user state.**

## Before reinstalling Ubuntu
1. Keep a copy of the private archive on a separate PC or external drive.
2. Verify its SHA-256 against the value recorded when it was created.
3. Do not rely on the backup remaining only on the Raspberry Pi SD card.
4. The archive contains secrets; store it securely and do not upload it here.

## Restore workflow
The private archive created for this system is named `raspi-private-backup-20261014-234757.tar.gz`. Transfer it to the reinstalled Pi using a trusted local method. Then extract it into the home directory:

```bash
mkdir -p "$HOME"
tar -tzf "$HOME/raspi-private-backup-20261014-234757.tar.gz" >/dev/null
tar -xzf "$HOME/raspi-private-backup-20261014-234757.tar.gz" -C "$HOME"
```

Clone this repository and run the interactive helper, pointing it to the extracted backup directory:

```bash
git clone https://github.com/zus599470/speedtest-bot.git
cd speedtest-bot
bash restore-from-backup.sh "$HOME/raspi-private-backup-20261014-234757"
```

The helper has conservative behavior:
- validates available tar archives;
- restores project folders only when the destination does not already exist;
- restores private config files only when the destination does not already exist;
- copies systemd units only after per-unit confirmation and does not enable or start them;
- does not automatically overwrite Pi-hole configuration or run remote installer scripts.

## Important limitations
- This is not yet a one-command, fully automatic recovery. Test each service after restoring.
- Python virtual environments are not restored; recreate them for the installed Python version and install verified requirements.
- Review systemd units and paths before enabling services.
- Pi-hole configuration restoration is version-sensitive; use the supported Pi-hole backup/restore workflow for the installed version.
- Cloudflare tunnel settings, DNS/hostname, credentials and permissions must be checked.
- Telegram Bot API source may need dependencies and a fresh ARM64 build.
- Local changes made after the backup date are not included.
