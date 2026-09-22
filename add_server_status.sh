#!/bin/bash

set -e

cd ~/speedtest-bot

BOT="bot_server.py"
BACKUP="bot_server.before-server-status.py"

echo "========================================"
echo "  ADD STATUS SERVER"
echo "========================================"

if [ ! -f "$BOT" ]; then
    echo "❌ bot_server.py tidak dijumpai."
    exit 1
fi

cp "$BOT" "$BACKUP"

echo "✅ Backup dibuat:"
echo "   $BACKUP"

python3 <<'PY'
from pathlib import Path

p = Path("bot_server.py")
text = p.read_text(encoding="utf-8")

# =========================================================
# 1. SERVER STATUS FUNCTIONS
# =========================================================

if "# SERVER STATUS SYSTEM" not in text:

    marker = "\n# =========================================================\n# /START\n# =========================================================\n"

    if marker not in text:
        raise SystemExit(
            "❌ Tidak jumpa bahagian /START."
        )

    code = r'''
# =========================================================
# SERVER STATUS SYSTEM
# =========================================================

def get_server_ip():
    try:
        result = subprocess.run(
            [
                "hostname",
                "-I",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )

        ips = result.stdout.strip().split()

        for ip in ips:
            if "." in ip:
                return ip

        return "N/A"

    except Exception:
        return "N/A"


def get_ram_usage():
    try:
        result = subprocess.run(
            [
                "free",
                "-m",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )

        lines = result.stdout.splitlines()

        for line in lines:
            if line.startswith("Mem:"):
                parts = line.split()

                total = int(parts[1])
                used = int(parts[2])

                percent = round(
                    used / total * 100
                )

                return percent

        return 0

    except Exception:
        return 0


def get_cpu_usage():
    try:
        result = subprocess.run(
            [
                "bash",
                "-c",
                "top -bn1 | grep 'Cpu(s)'",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )

        line = result.stdout.strip()

        if not line:
            return 0

        import re

        match = re.search(
            r"(\d+(?:\.\d+)?)\s*id",
            line,
        )

        if match:
            idle = float(match.group(1))
            return round(100 - idle)

        return 0

    except Exception:
        return 0


def get_storage_usage():
    try:
        result = subprocess.run(
            [
                "df",
                "-h",
                "/",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )

        lines = result.stdout.strip().splitlines()

        if len(lines) < 2:
            return "N/A"

        parts = lines[-1].split()

        total = parts[1]
        used = parts[2]
        percent = parts[4]

        return f"{used} / {total} ({percent})"

    except Exception:
        return "N/A"


def get_uptime():
    try:
        result = subprocess.run(
            [
                "uptime",
                "-p",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )

        value = result.stdout.strip()

        if value.startswith("up "):
            value = value[3:]

        return value

    except Exception:
        return "N/A"


def get_temperature():
    try:
        thermal_file = Path(
            "/sys/class/thermal/thermal_zone0/temp"
        )

        if thermal_file.exists():

            raw = thermal_file.read_text().strip()

            temp = int(raw) / 1000

            return f"{temp:.1f}°C"

    except Exception:
        pass

    try:
        result = subprocess.run(
            [
                "vcgencmd",
                "measure_temp",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )

        value = result.stdout.strip()

        if value:
            return value.replace(
                "temp=",
                "",
            )

    except Exception:
        pass

    return "N/A"


def get_pihole_running():
    try:
        result = subprocess.run(
            [
                "systemctl",
                "is-active",
                "--quiet",
                "pihole-FTL",
            ],
            timeout=5,
        )

        if result.returncode == 0:
            return "🟢 RUNNING"

    except Exception:
        pass

    try:
        result = subprocess.run(
            [
                "systemctl",
                "is-active",
                "--quiet",
                "pihole-FTL.service",
            ],
            timeout=5,
        )

        if result.returncode == 0:
            return "🟢 RUNNING"

    except Exception:
        pass

    return "🔴 NOT RUNNING"


def get_server_status_text():
    device = socket.gethostname()
    ip = get_server_ip()
    ram = get_ram_usage()
    cpu = get_cpu_usage()
    storage = get_storage_usage()
    uptime = get_uptime()
    temperature = get_temperature()
    pihole = get_pihole_running()

    current_time = datetime.now(
        ZoneInfo("Asia/Kuala_Lumpur")
    ).strftime("%H:%M:%S")

    return (
        "🍓 <b>STATUS SERVER</b>\n\n"
        f"🖥️ <b>Device</b>       : {device}\n"
        f"🌐 <b>IP Address</b>   : {ip}\n"
        f"🧠 <b>RAM Usage</b>    : {ram}%\n"
        f"⚙️ <b>CPU Usage</b>    : {cpu}%\n"
        f"💾 <b>Storage</b>      : {storage}\n"
        f"🕐 <b>Time</b>         : {current_time}\n"
        f"⏱️ <b>Uptime</b>       : {uptime}\n"
        f"🌡️ <b>Temperature</b>  : {temperature}\n"
        f"🛡️ <b>Pi-hole</b>      : {pihole}"
    )


def server_status_keyboard():
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "🔄 Refresh",
                    callback_data="server_status",
                )
            ],
            [
                InlineKeyboardButton(
                    "⬅️ Back",
                    callback_data="home",
                ),
                InlineKeyboardButton(
                    "🏠 Home",
                    callback_data="home",
                ),
            ],
        ]
    )


async def show_server_status(query):

    if not is_approved(query.from_user.id):
        await show_access_denied(query)
        return

    try:
        status_text = await asyncio.to_thread(
            get_server_status_text
        )

        await query.edit_message_text(
            status_text,
            parse_mode="HTML",
            reply_markup=server_status_keyboard(),
        )

    except Exception as error:

        logger.exception(
            "Gagal mendapatkan server status: %s",
            error,
        )

        await query.edit_message_text(
            "🍓 <b>STATUS SERVER</b>\n\n"
            "❌ Gagal mendapatkan status server.",
            parse_mode="HTML",
            reply_markup=server_status_keyboard(),
        )

'''

    text = text.replace(
        marker,
        "\n" + code + marker,
        1,
    )

else:
    print("ℹ️ Server Status System sudah ada.")

# =========================================================
# 2. TAMBAH BUTTON DALAM MAIN KEYBOARD
# =========================================================

if 'callback_data="server_status"' not in text:

    marker = '''        [
            InlineKeyboardButton(
                "📊 Status",
                callback_data="status",
            )
        ],
'''

    replacement = '''        [
            InlineKeyboardButton(
                "📊 Status",
                callback_data="status",
            )
        ],
        [
            InlineKeyboardButton(
                "🖥️ Status Server",
                callback_data="server_status",
            )
        ],
'''

    if marker not in text:
        raise SystemExit(
            "❌ Button 📊 Status tidak dijumpai."
        )

    text = text.replace(
        marker,
        replacement,
        1,
    )

else:
    print("ℹ️ Button Status Server sudah ada.")

# =========================================================
# 3. TAMBAH CALLBACK
# =========================================================

if 'callback == "server_status"' not in text:

    marker = '''    # =====================================================
    # SOLAT CALLBACKS
    # =====================================================
'''

    if marker not in text:
        raise SystemExit(
            "❌ SOLAT CALLBACKS tidak dijumpai."
        )

    callback = '''    if callback == "server_status":
        await show_server_status(query)
        return

'''

    text = text.replace(
        marker,
        callback + marker,
        1,
    )

else:
    print("ℹ️ Callback Status Server sudah ada.")

# =========================================================
# 4. Pastikan ZoneInfo import
# =========================================================

if "from zoneinfo import ZoneInfo" not in text:

    marker = "from datetime import datetime\n"

    if marker in text:
        text = text.replace(
            marker,
            marker + "from zoneinfo import ZoneInfo\n",
            1,
        )

p.write_text(
    text,
    encoding="utf-8",
)

print("✅ Server Status berjaya ditambah.")

PY

echo
echo "========================================"
echo "  SEMAK SYNTAX"
echo "========================================"

python3 -m py_compile bot_server.py

echo
echo "✅ SYNTAX OK"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Menu baru:"
echo "  🖥️ Status Server"
echo
echo "Restart bot dengan:"
echo "  sudo systemctl restart speedtest-bot"
