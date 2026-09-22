#!/bin/bash

# =========================================================
# 🍓 Raspberry Pi Speedtest Bot - Restore Manager
# GitHub: https://github.com/zus599470/speedtest-bot
# =========================================================

set -u

BASE_DIR="$HOME/speedtest-bot"

# =========================
# COLORS
# =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# =========================
# HEADER
# =========================
clear_screen() {
    clear 2>/dev/null || true
}

header() {
    clear_screen
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}        🍓 RASPBERRY PI RESTORE SYSTEM       ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}              SPEEDTEST BOT                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo
}

line() {
    echo -e "${GRAY}──────────────────────────────────────────────${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error_msg() {
    echo -e "${RED}❌ $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# =========================
# CHECK DIRECTORY
# =========================
if [ ! -d "$BASE_DIR" ]; then
    error_msg "Folder $BASE_DIR tidak dijumpai."
    echo
    echo "Clone repository dahulu:"
    echo
    echo "git clone https://github.com/zus599470/speedtest-bot.git ~/speedtest-bot"
    exit 1
fi

cd "$BASE_DIR" || exit 1

# =========================
# RUN SCRIPT
# =========================
run_script() {
    local SCRIPT="$1"

    if [ ! -f "$SCRIPT" ]; then
        error_msg "Fail tidak dijumpai: $SCRIPT"
        return 1
    fi

    chmod +x "$SCRIPT"

    echo
    echo -e "${CYAN}▶ Menjalankan:${NC} $SCRIPT"
    echo

    bash "$SCRIPT"
}

# =========================
# 1. TELEGRAM BOT
# =========================
restore_bot() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE} 1. ⚡ TELEGRAM SPEEDTEST BOT                 ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

    echo "📦 Semak Python..."

    if ! command -v python3 >/dev/null 2>&1; then
        echo "📥 Memasang Python..."
        sudo apt update
        sudo apt install -y python3 python3-venv python3-pip
    fi

    if [ ! -d "$BASE_DIR/venv" ]; then
        echo "📦 Membuat virtual environment..."
        python3 -m venv "$BASE_DIR/venv"
    fi

    if [ -f "$BASE_DIR/requirements.txt" ]; then
        echo "📦 Memasang requirements..."
        "$BASE_DIR/venv/bin/pip" install -r "$BASE_DIR/requirements.txt"
    fi

    if [ ! -f "$BASE_DIR/config.env" ]; then
        warning "config.env belum ada."
        echo "   Salin config.example.env → config.env"
        echo "   kemudian masukkan BOT_TOKEN / tetapan Pi-hole."
    else
        success "config.env dijumpai."
    fi

    if python3 -m py_compile "$BASE_DIR/bot_server.py"; then
        success "bot_server.py syntax OK."
        return 0
    else
        error_msg "bot_server.py mempunyai syntax error."
        return 1
    fi
}

# =========================
# 2. OOKLA
# =========================
install_ookla() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE} 2. 🚀 OOKLA SPEEDTEST CLI                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

    if command -v speedtest >/dev/null 2>&1; then
        success "Ookla Speedtest sudah dipasang."
        speedtest --version
        return 0
    fi

    echo "📥 Memasang Ookla Speedtest..."

    if ! command -v apt >/dev/null 2>&1; then
        error_msg "apt tidak dijumpai."
        return 1
    fi

    sudo apt update
    sudo apt install -y curl gnupg ca-certificates

    if curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash; then
        if sudo apt install -y speedtest; then
            success "Ookla Speedtest siap."
            speedtest --version
            return 0
        fi
    fi

    error_msg "Gagal memasang Ookla Speedtest."
    return 1
}

# =========================
# 3. PI-HOLE
# =========================
install_pihole() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE} 3. 🛡️  PI-HOLE                              ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

    if command -v pihole >/dev/null 2>&1; then
        success "Pi-hole sudah dipasang."
        pihole -v
        return 0
    fi

    echo "📥 Memasang Pi-hole..."

    if curl -sSL https://install.pi-hole.net | bash; then
        success "Pi-hole selesai dipasang."
        return 0
    fi

    error_msg "Gagal memasang Pi-hole."
    return 1
}

# =========================
# 4. SERVER SELECTOR
# =========================
restore_server_selector() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE} 4. 🌐 SERVER SELECTOR                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

    if [ -f "$BASE_DIR/install_server_selector.sh" ]; then
        chmod +x "$BASE_DIR/install_server_selector.sh"

        if bash "$BASE_DIR/install_server_selector.sh"; then
            success "Server Selector selesai."
            return 0
        fi
    fi

    error_msg "install_server_selector.sh tidak dijumpai atau gagal."
    return 1
}

# =========================
# 5. WAKTU SOLAT
# =========================
restore_solat() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE} 5. 🕌 WAKTU SOLAT JAKIM                     ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

    if run_script "add_solat.sh"; then
        success "Waktu Solat JAKIM siap."
        return 0
    fi

    error_msg "Waktu Solat gagal."
    return 1
}

# =========================
# 6. SOLAT REMINDER
# =========================
restore_reminder() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE} 6. 🔔 SOLAT REMINDER                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

    if [ -f "$BASE_DIR/add_solat_reminder_v2.sh" ]; then
        if run_script "add_solat_reminder_v2.sh"; then
            success "Solat Reminder V2 siap."
            return 0
        fi
    elif [ -f "$BASE_DIR/add_solat_reminder.sh" ]; then
        if run_script "add_solat_reminder.sh"; then
            success "Solat Reminder siap."
            return 0
        fi
    fi

    error_msg "Script Solat Reminder tidak dijumpai."
    return 1
}

# =========================
# 7. APPROVAL
# =========================
restore_approval() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE} 7. 👥 APPROVAL / MANAGE USERS               ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

    if grep -q "ADMIN_IDS" bot_server.py &&
       grep -q "admin_users" bot_server.py &&
       grep -q "users.json" bot_server.py &&
       grep -q "approve_user" bot_server.py; then

        success "Approval System sudah ada."
        success "Manage Users sudah ada."
        success "users.json sudah ada."
        info "Tiada patch diperlukan."
        return 0
    fi

    warning "Approval System belum lengkap."

    if [ -f "$BASE_DIR/add_approval_system.sh" ]; then
        if bash "$BASE_DIR/add_approval_system.sh"; then
            success "Approval System berjaya ditambah."
            return 0
        fi
    fi

    error_msg "Approval System gagal."
    return 1
}

# =========================
# 8. SERVER STATUS
# =========================
restore_server_status() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE} 8. 🖥️  SERVER STATUS                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

    if run_script "add_server_status.sh"; then
        success "Server Status siap."
        return 0
    fi

    error_msg "Server Status gagal."
    return 1
}

# =========================
# 9. APK MANAGER
# =========================
restore_apk() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE} 9. 📱 APK MANAGER                           ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

    if [ -f "$BASE_DIR/upgrade_apk_manager.sh" ]; then
        if run_script "upgrade_apk_manager.sh"; then
            success "APK Manager siap."
            return 0
        fi
    elif [ -f "$BASE_DIR/add_apk_manager.sh" ]; then
        if run_script "add_apk_manager.sh"; then
            success "APK Manager siap."
            return 0
        fi
    fi

    error_msg "Script APK Manager tidak dijumpai."
    return 1
}

# =========================
# 10. SYSTEMD
# =========================
restore_systemd() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE} 10. ⚙️  SYSTEMD BOT SERVICE                 ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

    if [ -f "$BASE_DIR/install_speedbot_service.sh" ]; then
        chmod +x "$BASE_DIR/install_speedbot_service.sh"

        if bash "$BASE_DIR/install_speedbot_service.sh"; then
            success "Systemd Bot Service siap."
            return 0
        fi
    fi

    error_msg "install_speedbot_service.sh tidak dijumpai atau gagal."
    return 1
}

# =========================
# 11. RESTORE SEMUA
# =========================
restore_all() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}        🚀 RESTORE SEMUA                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo

    warning "Semua komponen akan diperiksa/dipulihkan."
    echo
    read -rp "Teruskan? [y/N]: " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        warning "Restore dibatalkan."
        return 0
    fi

    local FAILED=0

    echo
    echo -e "${WHITE}[1/10] ⚡ Telegram Speedtest Bot${NC}"
    if restore_bot; then success "1/10 BERJAYA"; else error_msg "1/10 GAGAL"; FAILED=1; fi

    echo
    echo -e "${WHITE}[2/10] 🚀 Ookla Speedtest CLI${NC}"
    if install_ookla; then success "2/10 BERJAYA"; else error_msg "2/10 GAGAL"; FAILED=1; fi

    echo
    echo -e "${WHITE}[3/10] 🛡️ Pi-hole${NC}"
    if install_pihole; then success "3/10 BERJAYA"; else error_msg "3/10 GAGAL"; FAILED=1; fi

    echo
    echo -e "${WHITE}[4/10] 🌐 Server Selector${NC}"
    if restore_server_selector; then success "4/10 BERJAYA"; else error_msg "4/10 GAGAL"; FAILED=1; fi

    echo
    echo -e "${WHITE}[5/10] 🕌 Waktu Solat JAKIM${NC}"
    if restore_solat; then success "5/10 BERJAYA"; else error_msg "5/10 GAGAL"; FAILED=1; fi

    echo
    echo -e "${WHITE}[6/10] 🔔 Solat Reminder${NC}"
    if restore_reminder; then success "6/10 BERJAYA"; else error_msg "6/10 GAGAL"; FAILED=1; fi

    echo
    echo -e "${WHITE}[7/10] 👥 Approval / Manage Users${NC}"
    if restore_approval; then success "7/10 BERJAYA"; else error_msg "7/10 GAGAL"; FAILED=1; fi

    echo
    echo -e "${WHITE}[8/10] 🖥️ Server Status${NC}"
    if restore_server_status; then success "8/10 BERJAYA"; else error_msg "8/10 GAGAL"; FAILED=1; fi

    echo
    echo -e "${WHITE}[9/10] 📱 APK Manager${NC}"
    if restore_apk; then success "9/10 BERJAYA"; else error_msg "9/10 GAGAL"; FAILED=1; fi

    echo
    echo -e "${WHITE}[10/10] ⚙️ Systemd Bot Service${NC}"
    if restore_systemd; then success "10/10 BERJAYA"; else error_msg "10/10 GAGAL"; FAILED=1; fi

    echo
    line

    if [ "$FAILED" -eq 0 ]; then
        echo -e "${GREEN}"
        echo "╔══════════════════════════════════════════════╗"
        echo "║          🎉 RESTORE SELESAI!               ║"
        echo "╚══════════════════════════════════════════════╝"
        echo -e "${NC}"
        success "Semua 10 komponen berjaya diproses."
    else
        echo -e "${YELLOW}"
        echo "╔══════════════════════════════════════════════╗"
        echo "║       ⚠️ RESTORE SELESAI DENGAN ERROR      ║"
        echo "╚══════════════════════════════════════════════╝"
        echo -e "${NC}"
        warning "Satu atau lebih komponen gagal."
        return 1
    fi

    echo
    echo "🤖 Bot        : Telegram Speedtest Bot"
    echo "⚙️ Systemd    : Auto Start"
    echo "🔄 AutoRestart : Enabled"
    echo
    echo "📌 GitHub:"
    echo "https://github.com/zus599470/speedtest-bot"
}

# =========================
# MENU
# =========================
while true; do
    header

    echo -e "${WHITE}1.${NC}  ⚡ Telegram Speedtest Bot"
    echo -e "${WHITE}2.${NC}  🚀 Ookla Speedtest CLI"
    echo -e "${WHITE}3.${NC}  🛡️  Pi-hole"
    echo -e "${WHITE}4.${NC}  🌐 Server Selector"
    echo -e "${WHITE}5.${NC}  🕌 Waktu Solat JAKIM"
    echo -e "${WHITE}6.${NC}  🔔 Solat Reminder"
    echo -e "${WHITE}7.${NC}  👥 Approval / Manage Users"
    echo -e "${WHITE}8.${NC}  🖥️  Server Status"
    echo -e "${WHITE}9.${NC}  📱 APK Manager"
    echo -e "${WHITE}10.${NC} ⚙️  Systemd Bot Service"
    echo
    echo -e "${CYAN}11.${NC} 🚀 RESTORE SEMUA"
    echo
    echo -e "${RED}0.${NC}  ❌ Keluar"
    echo

    line

    read -rp "👉 Pilih nombor [0-11]: " CHOICE

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
        11) restore_all ;;
        0)
            echo
            success "Keluar. Jumpa lagi 👋"
            exit 0
            ;;
        *)
            error_msg "Pilihan tidak sah."
            ;;
    esac

    echo
    line
    read -rp "Tekan ENTER untuk kembali ke menu..."
done
