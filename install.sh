#!/usr/bin/env bash

set -Eeuo pipefail

# =========================================================
# Telegram Speedtest Bot - ONE CLICK RECOVERY
# GitHub:
# https://github.com/zus599470/speedtest-bot
#
# Usage:
# curl -fsSL https://raw.githubusercontent.com/zus599470/speedtest-bot/main/install.sh | bash
# =========================================================

REPO="zus599470/speedtest-bot"
BRANCH="main"

APP_DIR="$HOME/speedtest-bot"
SERVICE_NAME="speedtest-bot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo
echo "=============================================="
echo " Telegram Speedtest Bot - Recovery Installer"
echo "=============================================="
echo
echo "User   : $USER"
echo "Folder : $APP_DIR"
echo

# =========================================================
# 1. Check sudo
# =========================================================

if ! command -v sudo >/dev/null 2>&1; then
    echo "❌ sudo tidak dijumpai."
    echo "Pasang sudo dahulu."
    exit 1
fi

# =========================================================
# 2. Install system packages
# =========================================================

echo ">>> [1/8] Install system packages..."

sudo apt-get update

sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 \
    python3-full \
    python3-venv \
    python3-pip \
    curl \
    ca-certificates \
    git \
    tar

echo "✅ System packages siap."

# =========================================================
# 3. Download repository from GitHub
# =========================================================

echo
echo ">>> [2/8] Download project dari GitHub..."

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

curl -fL "$ARCHIVE_URL" -o "$TMP_DIR/repo.tar.gz"

tar -xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR"

SRC_DIR="$TMP_DIR/${REPO##*/}-${BRANCH}"

if [[ ! -d "$SRC_DIR" ]]; then
    echo "❌ Folder repository tak dijumpai."
    exit 1
fi

echo "✅ Repository berjaya dimuat turun."

# =========================================================
# 4. Create application folder
# =========================================================

echo
echo ">>> [3/8] Setup folder bot..."

mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/server_selector"

# Copy required files
cp "$SRC_DIR/bot.py" "$APP_DIR/"
cp "$SRC_DIR/bot_server.py" "$APP_DIR/"
cp "$SRC_DIR/pihole_api.py" "$APP_DIR/"
cp "$SRC_DIR/requirements.txt" "$APP_DIR/"

cp "$SRC_DIR/server_selector/__init__.py" \
   "$APP_DIR/server_selector/"

cp "$SRC_DIR/server_selector/selector.py" \
   "$APP_DIR/server_selector/"

# Restore selected server file if it exists in repo
if [[ -f "$SRC_DIR/server_selector/selected_server.json" ]]; then
    cp "$SRC_DIR/server_selector/selected_server.json" \
       "$APP_DIR/server_selector/"
fi

echo "✅ Fail bot dipulihkan."

# =========================================================
# 5. Create Python virtual environment
# =========================================================

echo
echo ">>> [4/8] Setup Python virtual environment..."

if [[ ! -x "$APP_DIR/venv/bin/python" ]]; then
    python3 -m venv "$APP_DIR/venv"
    echo "✅ venv baru dibuat."
else
    echo "✅ venv sedia ada digunakan."
fi

VENV_PYTHON="$APP_DIR/venv/bin/python"
VENV_PIP="$APP_DIR/venv/bin/pip"

# =========================================================
# 6. Install Python packages
# =========================================================

echo
echo ">>> [5/8] Install Python packages..."

"$VENV_PIP" install --upgrade pip
"$VENV_PIP" install -r "$APP_DIR/requirements.txt"

echo "✅ Python packages siap."

# =========================================================
# 7. Install Ookla Speedtest
# =========================================================

echo
echo ">>> [6/8] Check Ookla Speedtest..."

if command -v speedtest >/dev/null 2>&1; then

    echo "✅ Speedtest sudah ada."

else

    echo "📥 Speedtest belum ada."
    echo "Memasang repository Ookla..."

    curl -fsSL \
        https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh \
        | sudo bash

    sudo apt-get update

    sudo env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y speedtest

    if ! command -v speedtest >/dev/null 2>&1; then
        echo "❌ Speedtest gagal dipasang."
        exit 1
    fi

    echo "✅ Speedtest berjaya dipasang."
fi

speedtest --version || true

# =========================================================
# 8. Create / preserve config.env
# =========================================================

echo
echo ">>> [7/8] Setup config..."

if [[ -f "$APP_DIR/config.env" ]]; then

    echo "✅ config.env sudah ada."
    echo "Tidak diubah."

else

    echo
    echo "=============================================="
    echo " Config belum wujud"
    echo "=============================================="
    echo

    read -r -s -p "Masukkan Telegram Bot Token: " BOT_TOKEN
    echo

    if [[ -z "$BOT_TOKEN" ]]; then
        echo "❌ Telegram Bot Token kosong."
        exit 1
    fi

    read -r -p "Pi-hole URL [http://192.168.0.12]: " PIHOLE_URL

    if [[ -z "$PIHOLE_URL" ]]; then
        PIHOLE_URL="http://192.168.0.12"
    fi

    read -r -s -p "Masukkan Pi-hole Password: " PIHOLE_PASSWORD
    echo

    if [[ -z "$PIHOLE_PASSWORD" ]]; then
        echo "❌ Pi-hole password kosong."
        exit 1
    fi

    cat > "$APP_DIR/config.env" <<EOF
BOT_TOKEN="$BOT_TOKEN"
PIHOLE_URL="$PIHOLE_URL"
PIHOLE_PASSWORD="$PIHOLE_PASSWORD"
EOF

    chmod 600 "$APP_DIR/config.env"

    echo "✅ config.env berjaya dibuat."
fi

chmod 600 "$APP_DIR/config.env"

# =========================================================
# Python syntax check
# =========================================================

echo
echo ">>> Python syntax check..."

"$VENV_PYTHON" -m py_compile \
    "$APP_DIR/bot.py" \
    "$APP_DIR/bot_server.py" \
    "$APP_DIR/pihole_api.py"

echo "✅ Python syntax OK."

# =========================================================
# Create systemd service
# =========================================================

echo
echo ">>> [8/8] Setup systemd..."

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Telegram Speedtest Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/config.env
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/bot_server.py
Restart=always
RestartSec=5

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

echo "✅ systemd configured."

# =========================================================
# Start bot
# =========================================================

echo
echo ">>> Starting Telegram bot..."

sudo systemctl restart "$SERVICE_NAME"

sleep 5

if sudo systemctl is-active --quiet "$SERVICE_NAME"; then

    echo
    echo "=============================================="
    echo " ✅ RECOVERY BERJAYA"
    echo "=============================================="
    echo
    echo "Telegram Bot : RUNNING"
    echo "Speedtest    : INSTALLED"
    echo "Pi-hole API  : CONFIGURED"
    echo "systemd      : ENABLED"
    echo
    echo "Bot akan hidup semula selepas reboot."
    echo
    echo "Check status:"
    echo "sudo systemctl status speedtest-bot --no-pager"
    echo

else

    echo
    echo "=============================================="
    echo " ❌ BOT GAGAL START"
    echo "=============================================="
    echo
    echo "Semak error:"
    echo
    echo "sudo journalctl -u speedtest-bot -n 50 --no-pager"
    echo

    exit 1

fi
