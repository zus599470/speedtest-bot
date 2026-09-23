#!/bin/bash

# =========================================================
# Raspberry Pi Speedtest Bot - Restore Manager
# Repository:
# https://github.com/zus599470/speedtest-bot
# =========================================================

set -u

BASE_DIR="$HOME/speedtest-bot"
cd "$BASE_DIR" || exit 1

echo
echo "=============================================="
echo " Raspberry Pi Speedtest Bot Restore Manager"
echo "=============================================="
echo
echo "1.  ⚡ Telegram Speedtest Bot"
echo "2.  🚀 Ookla Speedtest CLI"
echo "3.  🛡️  Pi-hole"
echo "4.  🌐 Server Selector"
echo "5.  🕌 Waktu Solat JAKIM"
echo "6.  🔔 Solat Reminder"
echo "7.  👥 Approval / Manage Users"
echo "8.  🖥️  Server Status"
echo "9.  📱 APK Manager"
echo "10. ⚙️  Systemd Bot Service"
echo "11. 📡 Local Telegram Bot API"
echo "12. 📊 Raspberry Dashboard"
echo "13. 🚀 RESTORE SEMUA"
echo "0.  ❌ Keluar"
echo
read -rp "Pilih [0-13]: " CHOICE

run_script() {
    local SCRIPT="$1"

    if [ ! -f "$SCRIPT" ]; then
        echo
        echo "❌ Fail tidak dijumpai: $SCRIPT"
        return 1
    fi

    echo
    echo "▶️ Menjalankan $SCRIPT..."
    echo

    chmod +x "$SCRIPT"
    bash "$SCRIPT"
}

install_ookla() {
    echo
    echo "=============================================="
    echo "2. INSTALL / RESTORE OOKLA SPEEDTEST"
    echo "=============================================="

    if command -v speedtest >/dev/null 2>&1; then
        echo "✅ Ookla Speedtest sudah dipasang."
        speedtest --version
        return 0
    fi

    echo "📥 Memasang Ookla Speedtest..."

    if command -v apt >/dev/null 2>&1; then
        sudo apt update
        sudo apt install -y curl gnupg ca-certificates

        curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh \
            | sudo bash

        sudo apt install -y speedtest

        echo
        echo "✅ Ookla Speedtest siap."
        speedtest --version
    else
        echo "❌ apt tidak dijumpai."
        return 1
    fi
}

install_pihole() {
    echo
    echo "=============================================="
    echo "3. INSTALL / RESTORE PI-HOLE"
    echo "=============================================="

    if command -v pihole >/dev/null 2>&1; then
        echo "✅ Pi-hole sudah dipasang."
        pihole -v
        return 0
    fi

    echo "📥 Memasang Pi-hole..."

    curl -sSL https://install.pi-hole.net | bash
}

restore_bot() {
    echo
    echo "=============================================="
    echo "1. TELEGRAM SPEEDTEST BOT"
    echo "=============================================="

    echo "📦 Memeriksa Python..."

    if ! command -v python3 >/dev/null 2>&1; then
        sudo apt update
        sudo apt install -y python3 python3-venv python3-pip
    fi

    if [ ! -d "$BASE_DIR/venv" ]; then
        echo "📦 Membuat virtual environment..."
        python3 -m venv "$BASE_DIR/venv"
    fi

    echo "📦 Memasang Python requirements..."

    if [ -f "$BASE_DIR/requirements.txt" ]; then
        "$BASE_DIR/venv/bin/pip" install -r "$BASE_DIR/requirements.txt"
    fi

    if [ ! -f "$BASE_DIR/config.env" ]; then
        echo
        echo "⚠️ config.env belum ada."
        echo "Salin config.example.env menjadi config.env"
        echo "dan masukkan BOT_TOKEN / tetapan lain secara manual."
        echo
    fi

    python3 -m py_compile "$BASE_DIR/bot_server.py"

    if [ $? -ne 0 ]; then
        echo "❌ bot_server.py mempunyai syntax error."
        return 1
    fi

    echo "✅ bot_server.py syntax OK."
}

restore_server_selector() {
    echo
    echo "=============================================="
    echo "4. SERVER SELECTOR"
    echo "=============================================="

    if [ -f "$BASE_DIR/install_server_selector.sh" ]; then
        chmod +x "$BASE_DIR/install_server_selector.sh"
        bash "$BASE_DIR/install_server_selector.sh"
    else
        echo "❌ install_server_selector.sh tidak dijumpai."
    fi
}

restore_solat() {
    echo
    echo "=============================================="
    echo "5. WAKTU SOLAT JAKIM"
    echo "=============================================="

    run_script "add_solat.sh"
}

restore_reminder() {
    echo
    echo "=============================================="
    echo "6. SOLAT REMINDER"
    echo "=============================================="

    if [ -f "add_solat_reminder_v2.sh" ]; then
        run_script "add_solat_reminder_v2.sh"
    else
        run_script "add_solat_reminder.sh"
    fi
}

restore_approval() {
    echo
    echo "=============================================="
    echo "   APPROVAL / MANAGE USERS"
    echo "=============================================="

    if grep -q "ADMIN_IDS" bot_server.py &&
       grep -q "admin_users" bot_server.py &&
       grep -q "users.json" bot_server.py &&
       grep -q "approve_user" bot_server.py; then
        echo "✅ Approval System sudah ada."
        echo "✅ Manage Users sudah ada."
        echo "✅ users.json sudah ada."
        echo "ℹ️ Tiada patch diperlukan."
    else
        echo "⚠️ Approval System belum lengkap."
        bash add_approval_system.sh
    fi
}

restore_server_status() {
    echo
    echo "=============================================="
    echo "8. SERVER STATUS"
    echo "=============================================="

    run_script "add_server_status.sh"
}

restore_apk() {
    echo
    echo "=============================================="
    echo "9. APK MANAGER"
    echo "=============================================="

    if [ -f "upgrade_apk_manager.sh" ]; then
        run_script "upgrade_apk_manager.sh"
    else
        run_script "add_apk_manager.sh"
    fi
}

restore_systemd() {
    echo
    echo "=============================================="
    echo "10. SYSTEMD BOT SERVICE"
    echo "=============================================="

    if [ -f "$BASE_DIR/install_speedbot_service.sh" ]; then
        chmod +x "$BASE_DIR/install_speedbot_service.sh"
        bash "$BASE_DIR/install_speedbot_service.sh"
    else
        echo "❌ install_speedbot_service.sh tidak dijumpai."
    fi
}


restore_local_telegram_api() {
    echo
    echo "=============================================="
    echo " 📡 Local Telegram Bot API"
    echo "=============================================="

    API_DIR="$HOME/telegram-bot-api"
    ENV_FILE="$HOME/telegram_api.env"
    LAUNCHER="/usr/local/bin/start-telegram-bot-api.sh"
    SERVICE="/etc/systemd/system/telegram-bot-api.service"

    if [ ! -d "$API_DIR" ]; then
        echo "📥 Clone Telegram Bot API..."
        git clone --recursive https://github.com/tdlib/telegram-bot-api.git "$API_DIR" || {
            echo "❌ Gagal clone Telegram Bot API."
            return 1
        }
    else
        echo "✅ telegram-bot-api source sudah ada."
    fi

    if ! command -v /usr/local/bin/telegram-bot-api >/dev/null 2>&1; then
        echo "🔨 Build Telegram Bot API..."

        cd "$API_DIR" || return 1
        mkdir -p build
        cd build || return 1

        cmake -DCMAKE_BUILD_TYPE=Release .. || return 1
        cmake --build . --target telegram-bot-api -j1 || return 1
        sudo cmake --install . || return 1
    else
        echo "✅ Telegram Bot API binary sudah ada."
    fi

    if [ ! -f "$ENV_FILE" ]; then
        echo
        echo "⚠️ $ENV_FILE belum ada."
        echo "Sila buat fail tersebut dengan:"
        echo
        echo "TELEGRAM_API_ID=YOUR_API_ID"
        echo "TELEGRAM_API_HASH=YOUR_API_HASH"
        echo
        echo "❌ Restore Local Telegram Bot API dihentikan."
        return 1
    fi

    sudo tee "$LAUNCHER" >/dev/null <<'EOF'
#!/bin/bash
set -a
source /home/azam/telegram_api.env
set +a

exec /usr/local/bin/telegram-bot-api \
  --api-id="${TELEGRAM_API_ID}" \
  --api-hash="${TELEGRAM_API_HASH}" \
  --local \
  --http-port=8081
EOF

    sudo chmod 755 "$LAUNCHER"
    sudo sed -i 's/\r$//' "$LAUNCHER"

    sudo tee "$SERVICE" >/dev/null <<'EOF'
[Unit]
Description=Telegram Local Bot API Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=azam
WorkingDirectory=/home/azam/telegram-bot-api
ExecStart=/usr/local/bin/start-telegram-bot-api.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable telegram-bot-api
    sudo systemctl restart telegram-bot-api

    sleep 3

    if systemctl is-active --quiet telegram-bot-api; then
        echo "✅ Local Telegram Bot API RUNNING."
    else
        echo "❌ Local Telegram Bot API gagal berjalan."
        sudo systemctl status telegram-bot-api --no-pager
        return 1
    fi
}


restore_dashboard() {
    echo
    echo "=============================================="
    echo " 📊 Raspberry Dashboard"
    echo "=============================================="

    DASHBOARD_DIR="/home/azam/raspberry-dashboard"
    REPO_DIR="/home/azam/speedtest-bot/raspberry-dashboard"

    mkdir -p "$DASHBOARD_DIR"

    if [ ! -f "$REPO_DIR/app.py" ]; then
        echo "❌ app.py tidak dijumpai dalam GitHub repo."
        return 1
    fi

    cp "$REPO_DIR/app.py" "$DASHBOARD_DIR/app.py"

    if [ -f "$REPO_DIR/.gitignore" ]; then
        cp "$REPO_DIR/.gitignore" "$DASHBOARD_DIR/.gitignore"
    fi

    echo "📁 Dashboard: $DASHBOARD_DIR"
    echo "📄 app.py berjaya dipulihkan."

    if [ ! -d "$DASHBOARD_DIR/venv" ]; then
        echo "🐍 Membina Python virtual environment..."
        python3 -m venv "$DASHBOARD_DIR/venv"
    fi

    echo "📦 Memasang Flask..."
    "$DASHBOARD_DIR/venv/bin/pip" install --upgrade pip >/dev/null 2>&1
    "$DASHBOARD_DIR/venv/bin/pip" install flask >/dev/null 2>&1

    echo
    echo "✅ Raspberry Dashboard berjaya dipulihkan."
    echo "📍 Lokasi: $DASHBOARD_DIR"
    echo
}

restore_all() {
    echo
    echo "=============================================="
    echo " 🚀 RESTORE SEMUA"
    echo "=============================================="

    echo
    echo "⚠️ Restore semua komponen akan dijalankan."
    read -rp "Teruskan? [y/N]: " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "❌ Dibatalkan."
        return
    fi

    restore_bot
    install_ookla
    install_pihole
    restore_server_selector
    restore_solat
    restore_reminder
    restore_approval
    restore_server_status
    restore_apk
    restore_systemd
    restore_local_telegram_api
    restore_dashboard

    echo
    echo "=============================================="
    echo "✅ RESTORE SEMUA SELESAI"
    echo "=============================================="
}

case "$CHOICE" in
    1)  restore_bot ;;
    2)  install_ookla ;;
    3)  install_pihole ;;
    4)  restore_server_selector ;;
    5)  restore_solat ;;
    6)  restore_reminder ;;
    7)  restore_approval ;;
    8)  restore_server_status ;;
    9)  restore_apk ;;
    10) restore_systemd ;;
    11) restore_local_telegram_api ;;
    12) restore_dashboard ;;
    13) restore_all ;;
    0)
        echo "👋 Keluar."
        exit 0
        ;;
    *)
        echo "❌ Pilihan tidak sah."
        exit 1
        ;;
esac

echo
echo "=============================================="
echo " Selesai."
echo "=============================================="

