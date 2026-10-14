# Raspberry Pi Recovery (Ubuntu Server / ARM64)

This directory contains a cautious restore helper for the private backup made on 2026-10-14.

## Important safety rules

- Never upload the private `raspi-private-backup-*.tar.gz` archive, `config.env`, `.env`, or Cloudflare token to this public repository.
- Keep at least two copies of the private archive (for example, Windows plus an external drive).
- The helper does **not** automatically start services, install all packages, or restore Pi-hole configuration. Those steps require checking the target system and versions.
- The archive was validated and its SHA-256 matched on Windows, but a full restore has not yet been tested on a clean Ubuntu installation.
- Existing project folders are skipped and never overwritten. If a folder already exists, back it up and decide manually before retrying.
- Review backed-up systemd unit files before installing them on a new OS.

## Backup layout expected

After extracting the private archive, pass the extracted directory to the helper. It should contain files such as:

- `speedtest-bot.tar.gz`
- `raspberry-dashboard.tar.gz`
- `hermes-pi-bot.tar.gz`
- `pencarimovie-server.tar.gz`
- `pencarimovie-bot.tar.gz`
- `telegram-api/telegram-bot-api-full.tar.gz`
- `pihole/pihole-config.tar.gz`
- `private/home/azam/speedtest-bot/config.env`
- `private/home/azam/raspberry-dashboard/.env`
- `private/home/azam/pencarimovie-bot/config.env`
- `private/cloudflared/token`
- `system/units/*.service`
- `system/inventory/*`

## Use

On the Raspberry Pi, extract the archive to a private directory, then run:

```bash
chmod 700 restore-from-backup.sh
./restore-from-backup.sh /path/to/raspi-private-backup-20261014-234757
```

Run as the normal user `azam`, not with `sudo`. The script asks for confirmation before each restore action. Choose the project restore first, then restore private configuration and inspect units. Install prerequisites and recreate virtual environments based on each project's requirements. Some project folders may need extra dependencies not captured in a requirements file.

Pi-hole restoration is intentionally manual: install a compatible Pi-hole version first, inspect the archive contents, and use Pi-hole's supported backup/restore workflow where possible. Do not blindly unpack old configuration over a different Pi-hole version.

Cloudflare's token is sensitive. The helper restores it only when explicitly selected and sets root ownership and mode 600. Do not print its contents or commit it.
