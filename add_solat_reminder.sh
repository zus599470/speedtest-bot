#!/bin/bash

set -e

APP_DIR="$HOME/speedtest-bot"
BOT_FILE="$APP_DIR/bot_server.py"
BACKUP_FILE="$APP_DIR/bot_server.before-reminder.py"

echo "========================================"
echo "  ADD REMINDER WAKTU SOLAT"
echo "========================================"

cd "$APP_DIR"

if [ ! -f "$BOT_FILE" ]; then
    echo "❌ bot_server.py tidak dijumpai."
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    cp "$BOT_FILE" "$BACKUP_FILE"
    echo "✅ Backup dibuat: $BACKUP_FILE"
else
    echo "ℹ️ Backup sudah wujud."
fi

python3 <<'PY'
from pathlib import Path

path = Path("bot_server.py")
text = path.read_text(encoding="utf-8")

# =========================================================
# 1. Pastikan ZoneInfo ada
# =========================================================

if "from zoneinfo import ZoneInfo" not in text:
    marker = "from datetime import datetime\n"

    if marker in text:
        text = text.replace(
            marker,
            marker + "from zoneinfo import ZoneInfo\n",
            1,
        )

# =========================================================
# 2. Tambah fungsi reminder
# =========================================================

if "# SOLAT REMINDER SYSTEM" not in text:

    marker = "async def auto_speedtest_job("

    if marker not in text:
        raise SystemExit(
            "❌ Tidak jumpa auto_speedtest_job()."
        )

    reminder_code = r'''
# =========================================================
# SOLAT REMINDER SYSTEM
# =========================================================

SOLAT_REMINDER_NAMES = {
    "fajr": "Subuh",
    "dhuhr": "Zohor",
    "asr": "Asar",
    "maghrib": "Maghrib",
    "isha": "Isyak",
}


def get_user_reminder_enabled(user_id):
    users = load_users()
    info = users.get(str(user_id), {})

    # Default ON
    return info.get("solat_reminder", True)


def set_user_reminder_enabled(user_id, enabled):
    users = load_users()
    user_id = str(user_id)

    if user_id not in users:
        users[user_id] = {
            "name": "",
            "username": "",
            "status": "pending",
        }

    users[user_id]["solat_reminder"] = bool(enabled)

    save_users(users)


def get_user_reminder_log(user_id):
    users = load_users()
    info = users.get(str(user_id), {})

    log = info.get("solat_reminder_log", [])

    if not isinstance(log, list):
        return []

    return log


def add_user_reminder_log(user_id, key):
    users = load_users()
    user_id = str(user_id)

    if user_id not in users:
        return

    log = users[user_id].get(
        "solat_reminder_log",
        [],
    )

    if not isinstance(log, list):
        log = []

    if key not in log:
        log.append(key)

    # Simpan maksimum 100 rekod sahaja
    users[user_id]["solat_reminder_log"] = log[-100:]

    save_users(users)


def solat_reminder_keyboard(enabled):
    if enabled:
        reminder_button = InlineKeyboardButton(
            "🔕 Matikan Reminder",
            callback_data="solat_reminder_off",
        )
    else:
        reminder_button = InlineKeyboardButton(
            "🔔 Hidupkan Reminder",
            callback_data="solat_reminder_on",
        )

    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "📍 Tukar Lokasi",
                    callback_data="solat_location",
                ),
                InlineKeyboardButton(
                    "🔄 Refresh",
                    callback_data="solat_refresh",
                ),
            ],
            [
                reminder_button,
            ],
            [
                InlineKeyboardButton(
                    "⬅️ Back",
                    callback_data="solat_back",
                ),
                InlineKeyboardButton(
                    "🏠 Home",
                    callback_data="home",
                ),
            ],
        ]
    )


def get_solat_reminder_times(prayer):
    return {
        key: prayer.get(key)
        for key in SOLAT_REMINDER_NAMES
        if prayer.get(key)
    }


async def send_solat_reminder(
    application,
    user_id,
    zone,
    prayer_name,
    prayer_time,
    minutes_before,
):
    if minutes_before == 5:
        text = (
            "⏰ <b>PERINGATAN WAKTU SOLAT</b>\n\n"
            f"🕌 <b>{prayer_name}</b>\n\n"
            f"⏳ Lagi <b>5 minit</b> sebelum masuk waktu.\n"
            f"🕐 Waktu: <b>{prayer_time[:5]}</b>\n"
            f"📍 Zon: <code>{zone}</code>"
        )
    else:
        text = (
            "🕌 <b>WAKTU SOLAT TELAH MASUK</b>\n\n"
            f"🤲 <b>{prayer_name}</b>\n\n"
            f"🕐 Waktu: <b>{prayer_time[:5]}</b>\n"
            f"📍 Zon: <code>{zone}</code>"
        )

    try:
        await application.bot.send_message(
            chat_id=int(user_id),
            text=text,
            parse_mode="HTML",
        )

        logger.info(
            "Solat reminder sent: user=%s zone=%s prayer=%s offset=%s",
            user_id,
            zone,
            prayer_name,
            minutes_before,
        )

    except Exception as error:
        logger.warning(
            "Gagal hantar solat reminder kepada %s: %s",
            user_id,
            error,
        )


async def solat_reminder_job(context):
    """
    Semak reminder setiap 30 saat.

    5 minit sebelum:
        diff 300-359 saat

    Tepat masuk:
        diff 0-59 saat
    """

    try:
        users = load_users()

        if not users:
            return

        now = datetime.now(
            ZoneInfo("Asia/Kuala_Lumpur")
        )

        today_key = now.strftime("%Y-%m-%d")

        # Elak duplicate API request untuk zone sama.
        zone_cache = {}

        for user_id, info in users.items():

            # Admin / user yang belum approved
            # tidak menerima reminder.
            if not is_approved(int(user_id)):
                continue

            zone = info.get("solat_zone")

            if not zone:
                continue

            if not info.get(
                "solat_reminder",
                True,
            ):
                continue

            # Ambil data JAKIM sekali sahaja
            # untuk setiap zone.
            if zone not in zone_cache:
                try:
                    zone_cache[zone] = await asyncio.to_thread(
                        get_jakim_today,
                        zone,
                    )
                except Exception as error:
                    logger.warning(
                        "Gagal ambil waktu solat %s: %s",
                        zone,
                        error,
                    )
                    zone_cache[zone] = None

            prayer = zone_cache.get(zone)

            if not prayer:
                continue

            reminder_times = get_solat_reminder_times(
                prayer
            )

            reminder_log = get_user_reminder_log(
                user_id
            )

            for prayer_key, prayer_time in reminder_times.items():

                try:
                    hour, minute = map(
                        int,
                        prayer_time[:5].split(":"),
                    )

                    prayer_dt = now.replace(
                        hour=hour,
                        minute=minute,
                        second=0,
                        microsecond=0,
                    )

                except Exception:
                    continue

                diff = (
                    prayer_dt - now
                ).total_seconds()

                prayer_name = SOLAT_REMINDER_NAMES[
                    prayer_key
                ]

                # =========================================
                # 5 MINIT SEBELUM
                # =========================================

                if 300 <= diff < 360:

                    log_key = (
                        f"{today_key}|"
                        f"{zone}|"
                        f"{prayer_key}|5"
                    )

                    if log_key not in reminder_log:

                        await send_solat_reminder(
                            context.application,
                            user_id,
                            zone,
                            prayer_name,
                            prayer_time,
                            5,
                        )

                        add_user_reminder_log(
                            user_id,
                            log_key,
                        )

                # =========================================
                # TEPAT MASUK WAKTU
                # =========================================

                elif 0 <= diff < 60:

                    log_key = (
                        f"{today_key}|"
                        f"{zone}|"
                        f"{prayer_key}|0"
                    )

                    if log_key not in reminder_log:

                        await send_solat_reminder(
                            context.application,
                            user_id,
                            zone,
                            prayer_name,
                            prayer_time,
                            0,
                        )

                        add_user_reminder_log(
                            user_id,
                            log_key,
                        )


async def solat_reminder_on(query):
    user_id = query.from_user.id

    if not is_approved(user_id):
        await query.answer(
            "🚫 Akses diperlukan.",
            show_alert=True,
        )
        return

    set_user_reminder_enabled(
        user_id,
        True,
    )

    await query.answer(
        "🔔 Reminder dihidupkan.",
        show_alert=True,
    )

    await show_solat_menu(query)


async def solat_reminder_off(query):
    user_id = query.from_user.id

    if not is_approved(user_id):
        await query.answer(
            "🚫 Akses diperlukan.",
            show_alert=True,
        )
        return

    set_user_reminder_enabled(
        user_id,
        False,
    )

    await query.answer(
        "🔕 Reminder dimatikan.",
        show_alert=True,
    )

    await show_solat_menu(query)

'''

    text = text.replace(
        marker,
        reminder_code + "\n\n" + marker,
        1,
    )

else:
    print("ℹ️ Solat reminder system sudah ada.")

# =========================================================
# 3. Tukar keyboard waktu solat supaya ada ON/OFF
# =========================================================

if "get_user_reminder_enabled(query.from_user.id)" not in text:

    old = '''    await query.edit_message_text(
        text,
        parse_mode="HTML",
        reply_markup=solat_menu_keyboard(),
    )
'''

    new = '''    reminder_enabled = get_user_reminder_enabled(
        query.from_user.id
    )

    await query.edit_message_text(
        text
        + "\\n\\n"
        + (
            "🔔 Reminder: <b>ON</b>"
            if reminder_enabled
            else "🔕 Reminder: <b>OFF</b>"
        ),
        parse_mode="HTML",
        reply_markup=solat_reminder_keyboard(
            reminder_enabled
        ),
    )
'''

    if old in text:
        text = text.replace(old, new, 1)
    else:
        print(
            "⚠️ Bahagian show_solat_menu tidak sepadan."
        )

# =========================================================
# 4. Tambah callback ON/OFF
# =========================================================

if 'callback == "solat_reminder_on"' not in text:

    marker = '    if callback == "solat_refresh":'

    if marker not in text:
        raise SystemExit(
            "❌ Callback solat_refresh tidak dijumpai."
        )

    callback = '''    if callback == "solat_reminder_on":
        await solat_reminder_on(query)
        return

    if callback == "solat_reminder_off":
        await solat_reminder_off(query)
        return

'''

    text = text.replace(
        marker,
        callback + marker,
        1,
    )
else:
    print("ℹ️ Callback reminder sudah ada.")

# =========================================================
# 5. Schedule job setiap 30 saat
# =========================================================

if "solat_reminder_job" not in text[text.rfind("def main()"):]:
    main_marker = "def main():"

    if main_marker not in text:
        raise SystemExit(
            "❌ def main() tidak dijumpai."
        )

    main_start = text.index(main_marker)

    job_marker = (
        "    application.add_handler"
    )

    job_pos = text.find(
        job_marker,
        main_start,
    )

    if job_pos == -1:
        raise SystemExit(
            "❌ Tidak jumpa application.add_handler "
            "dalam main()."
        )

    job_code = '''    # Waktu Solat reminder
    # Semak setiap 30 saat.
    application.job_queue.run_repeating(
        solat_reminder_job,
        interval=30,
        first=10,
    )

'''

    text = (
        text[:job_pos]
        + job_code
        + text[job_pos:]
    )

else:
    print("ℹ️ Job reminder sudah dijadualkan.")

path.write_text(text, encoding="utf-8")

print("✅ Kod reminder berjaya ditambah.")
PY

echo
echo "🔍 Semak syntax..."
python3 -m py_compile bot_server.py

echo
echo "========================================"
echo "✅ REMINDER WAKTU SOLAT SIAP"
echo "========================================"
echo
echo "Reminder:"
echo "  ⏰ 5 minit sebelum"
echo "  🕌 Tepat masuk waktu"
echo
echo "Backup:"
echo "  $BACKUP_FILE"
echo
