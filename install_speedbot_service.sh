#!/bin/bash

SERVICE_NAME="speedtest-bot"
USER_NAME="$USER"
WORK_DIR="$HOME/speedtest-bot"
PYTHON="$HOME/speedtest-bot/venv/bin/python"
SCRIPT="$HOME/speedtest-bot/bot_server.py"

echo "=== Install Speedtest Bot Service ==="

if [ ! -f "$SCRIPT" ]; then
    echo "❌ bot_server.py tak dijumpai."
    exit 1
fi

if [ ! -f "$PYTHON" ]; then
    echo "❌ Python venv tak dijumpai:"
    echo "$PYTHON"
    exit 1
fi

sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<SERVICE
[Unit]
Description=Telegram Speedtest Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
WorkingDirectory=${WORK_DIR}
ExecStart=${PYTHON} ${SCRIPT}
Restart=always
RestartSec=5

# Pastikan output masuk journal
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

echo "Reload systemd..."
sudo systemctl daemon-reload

echo "Enable service..."
sudo systemctl enable ${SERVICE_NAME}

echo "Start service..."
sudo systemctl restart ${SERVICE_NAME}

sleep 2

echo
echo "=== STATUS ==="
sudo systemctl status ${SERVICE_NAME} --no-pager

echo
echo "✅ Selesai."
echo
echo "Bot sekarang akan:"
echo "- terus berjalan walaupun SSH/Terminal ditutup"
echo "- auto start selepas Raspberry Pi reboot"
echo "- auto restart jika bot crash"
echo
echo "Untuk tengok log:"
echo "sudo journalctl -u ${SERVICE_NAME} -f"
