#!/usr/bin/env bash

set -Eeuo pipefail

# =========================================================
# Telegram Speedtest Bot - Recovery / Install Script
# =========================================================

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="speedtest-bot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

if [[ "$EUID" -eq 0 ]]; then
    SUDO=""
    APP_USER="${SUDO_USER:-azam}"
else
    SUDO="sudo"
    APP_USER="$USER"
fi

if ! id "$APP_USER" >/dev/null 2>&1; then
    echo "❌ User '$APP_USER' tidak dijumpai."
    exit 1
fi

echo
echo "=============================================="
echo "   Telegram Speedtest Bot - Auto Recovery"
echo "=============================================="
echo
echo "📁 Folder : $APP_DIR"
echo "👤 User   : $APP_USER"
echo

# =========================================================
# 1. Update package list
# =========================================================

echo ">>> [1/9] Update Ubuntu..."

$SUDO apt-get update

# =========================================================
# 2. Install system packages
# =========================================================

echo
echo ">>> [2/9] Install keperluan sistem..."

$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 \
    python3-full \
    python3-venv \
    python3-pip \
    git \
    curl \
    ca-certificates

# =========================================================
# 3. Install Ookla Speedtest
# =========================================================

echo
echo ">>> [3/9] Check Ookla Speedtest..."

if command -v speedtest >/dev/null 2>&1; then
    echo "✅ Speedtest sudah ada."
    speedtest --version || true
else
    echo "📥 Speedtest belum ada."
    echo "Mencuba pasang repository rasmi Ookla..."

    if curl -fsSL \
        https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh \
        | $SUDO bash; then

        if $SUDO apt-get install -y speedtest; then
            echo "✅ Speedtest berjaya dipasang."
        fi
    fi

    # Fallback untuk ARM64 jika repository tidak menyediakan
    # build yang sesuai dengan versi Ubuntu semasa.
    if ! command -v speedtest >/dev/null 2>&1; then
        echo "⚠️ Repository tidak berjaya memasang Speedtest."
        echo "📥 Cuba pakej ARM64 Ookla 1.2.0.84..."

        TMP_DEB="$(mktemp --suffix=.deb)"

        curl -fL \
            "https://packagecloud.io/ookla/speedtest-cli/packages/ubuntu/jammy/speedtest_1.2.0.84-1.ea6b6773cf_arm64.deb/download.deb?distro_version_id=237" \
            -o "$TMP_DEB"

        $SUDO dpkg -i "$TMP_DEB" || true
        $SUDO apt-get install -f -y

        rm -f "$TMP_DEB"
    fi

    if ! command -v speedtest >/dev/null 2>&1; then
        echo "❌ Speedtest gagal dipasang."
        exit 1
    fi

    echo "✅ Speedtest berjaya dipasang."
fi

# =========================================================
# 4. Create Python virtual environment
# =========================================================

echo
echo ">>> [4/9] Setup Python virtual environment..."

if [[ ! -x "$APP_DIR/venv/bin/python" ]]; then
    python3 -m venv "$APP_DIR/venv"
    echo "✅ Virtual environment baru dibuat."
else
    echo "✅ Virtual environment sudah ada."
fi

VENV_PYTHON="$APP_DIR/venv/bin/python"
VENV_PIP="$APP_DIR/venv/bin/pip"

# =========================================================
# 5. Install Python dependencies
# =========================================================

echo
echo ">>> [5/9] Install Python packages..."

"$VENV_PIP" install --upgrade pip
"$VENV_PIP" install -r "$APP_DIR/requirements.txt"

echo "✅ Python packages siap."

# =========================================================
# 6. Create config.env
# =========================================================

echo
echo ">>> [6/9] Setup config.env..."

escape_env_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

if [[ -f "$APP_DIR/config.env" ]]; then
    echo "✅ config.env sudah ada. Tidak diubah."
else
    echo
    echo "Config belum ada."
    echo "Script akan minta Telegram token dan Pi-hole password."
    echo

    read -r -s -p "Masukkan Telegram Bot Token: " BOT_TOKEN
    echo

    if [[ -z "$BOT_TOKEN" ]]; then
        echo "❌ Telegram Bot Token kosong."
        exit 1
    fi

    read -r -p "Pi-hole URL [http://192.168.0.12]: " PIHOLE_URL
    PIHOLE_URL="${PIHOLE_URL:-http://192.168.0.12}"

    read -r -s -p "Masukkan Pi-hole Password: " PIHOLE_PASSWORD
    echo

    if [[ -z "$PIHOLE_PASSWORD" ]]; then
        echo "❌ Pi-hole password kosong."
        exit 1
    fi

    BOT_TOKEN_ESC="$(escape_env_value "$BOT_TOKEN")"
    PIHOLE_URL_ESC="$(escape_env_value "$PIHOLE_URL")"
    PIHOLE_PASSWORD_ESC="$(escape_env_value "$PIHOLE_PASSWORD")"

    cat > "$APP_DIR/config.env" <<EOF
BOT_TOKEN=$BOT_TOKEN_ESC
PIHOLE_URL=$PIHOLE_URL_ESC
PIHOLE_PASSWORD=$PIHOLE_PASSWORD_ESC
EOF

    chmod 600 "$APP_DIR/config.env"

    echo "✅ config.env berjaya dibuat."
fi

chmod 600 "$APP_DIR/config.env"

# =========================================================
# 7. Check Python files
# =========================================================

echo
echo ">>> [7/9] Check Python code..."

"$VENV_PYTHON" -m py_compile "$APP_DIR/bot.py"
"$VENV_PYTHON" -m py_compile "$APP_DIR/bot_server.py"
"$VENV_PYTHON" -m py_compile "$APP_DIR/pihole_api.py"

echo "✅ Semua Python file lulus syntax check."

# =========================================================
# 8. Create systemd service
# =========================================================

echo
echo ">>> [8/9] Setup systemd service..."

$SUDO tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Telegram Speedtest Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
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

$SUDO systemctl daemon-reload
$SUDO systemctl enable "$SERVICE_NAME"

echo "✅ systemd siap."

# =========================================================
# 9. Start bot
# =========================================================

echo
echo ">>> [9/9] Start Telegram bot..."

$SUDO systemctl restart "$SERVICE_NAME"

sleep 3

if $SUDO systemctl is-active --quiet "$SERVICE_NAME"; then
    echo
    echo "=============================================="
    echo "✅ RECOVERY BERJAYA"
    echo "=============================================="
    echo
    echo "Telegram Bot : RUNNING"
    echo "Speedtest    : $(speedtest --version 2>/dev/null | head -n 1 || echo OK)"
    echo "Service      : ENABLED"
    echo
    echo "Check status:"
    echo "sudo systemctl status speedtest-bot --no-pager"
    echo
else
    echo
    echo "❌ Bot gagal start."
    echo
    echo "Semak log dengan:"
    echo "sudo journalctl -u speedtest-bot -n 50 --no-pager"
    exit 1
fi
