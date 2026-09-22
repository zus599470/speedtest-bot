#!/bin/bash

set -e

cd ~/speedtest-bot

BOT="bot_server.py"
BACKUP="bot_server.before-reminder-v2.py"

echo "========================================"
echo "  WAKTU SOLAT REMINDER V2"
echo "========================================"

if [ ! -f "$BOT" ]; then
    echo "❌ bot_server.py tidak dijumpai."
    exit 1
fi

cp "$BOT" "$BACKUP"

echo "✅ Backup:"
echo "   $BACKUP"

python3 <<'PY'
from pathlib import Path

p = Path("bot_server.py")
text = p.read_text(encoding="utf-8")

# =========================================================
# 1. Tambah background reminder system
# =========================================================

if "# SOLAT REMINDER V2" in text:
    raise SystemExit(
        "⚠️ Reminder V2 sudah ada. Patch dibatalkan."
    )

marker = "\n# =========================================================\n# /START\n# =========================================================\n"

if marker not in text:
    raise SystemExit(
        "❌ Tidak jumpa bahagian /START."
    )

reminder_code = r'''
# =========================================================
# SOLAT REMINDER V2
# =========================================================

SOLAT_REMINDER_NAMES = {
    "fajr": "Subuh",
    "dhuhr": "Zohor",
    "asr": "Asar",
    "maghrib": "Maghrib",
    "isha": "Isyak",
}

solat_reminder_task = None


def get_user_reminder_enabled(user_id):
    users = load_users()
    info = users.get(str(user_id), {})

    # Default ON untuk user yang telah approved.
    return info.get("solat_reminder", True)


def set_user_reminder_enabled(user_id, enabled):
    users = load_users()
    user_id = str(user_id)

    if user_id not in users:
        return

    users[user_id]["solat_reminder"] = bool(enabled)

    save_users(users)


def get_reminder_log(user_id):
    users = load_users()
    info = users.get(str(user_id), {})

    log = info.get("solat_reminder_log", [])

    if not isinstance(log, list):
        return []

    return log


def save_reminder_log(user_id, key):
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

    # Simpan 100 rekod terakhir sahaja.
    users[user_id]["solat_reminder_log"] = log[-100:]

    save_users(users)


async def send_solat_reminder(
    application,
    user_id,
    zone,
    prayer_name,
    prayer_time,
    minutes_before,
):
    if minutes_before == 5:
        message = (
            "⏰ <b>PERINGATAN WAKTU SOLAT</b>\n\n"
            f"🕌 <b>{prayer_name}</b>\n\n"
            "⏳ Lagi <b>5 minit</b> sebelum masuk waktu.\n"
            f"🕐 Waktu: <b>{prayer_time[:5]}</b>\n"
            f"📍 Zon: <code>{zone}</code>"
        )
    else:
        message = (
            "🕌 <b>WAKTU SOLAT TELAH MASUK</b>\n\n"
            f"🤲 <b>{prayer_name}</b>\n\n"
            f"🕐 Waktu: <b>{prayer_time[:5]}</b>\n"
            f"📍 Zon: <code>{zone}</code>"
        )

    try:
        await application.bot.send_message(
            chat_id=int(user_id),
            text=message,
            parse_mode="HTML",
        )

        logger.info(
            "Solat reminder dihantar: user=%s zone=%s prayer=%s offset=%s",
            user_id,
            zone,
            prayer_name,
            minutes_before,
        )

        return True

    except Exception as error:
        logger.warning(
            "Gagal hantar solat reminder user %s: %s",
            user_id,
            error,
        )

        return False


async def check_solat_reminders(application):
    users = load_users()

    if not users:
        return

    now = datetime.now(
        ZoneInfo("Asia/Kuala_Lumpur")
    )

    today = now.strftime("%Y-%m-%d")

    # Cache supaya satu zon hanya request JAKIM sekali
    # untuk setiap pusingan.
    zone_cache = {}

    for user_id, info in users.items():

        try:
            numeric_user_id = int(user_id)
        except Exception:
            continue

        # Hanya approved user.
        if not is_approved(numeric_user_id):
            continue

        # Reminder OFF.
        if not info.get(
            "solat_reminder",
            True,
        ):
            continue

        zone = info.get("solat_zone")

        if not zone:
            continue

        # Ambil data JAKIM untuk zon.
        if zone not in zone_cache:

            try:
                zone_cache[zone] = await asyncio.to_thread(
                    get_jakim_today,
                    zone,
                )

            except Exception as error:
                logger.warning(
                    "JAKIM gagal untuk zon %s: %s",
                    zone,
                    error,
                )

                zone_cache[zone] = None

        prayer = zone_cache.get(zone)

        if not prayer:
            continue

        reminder_log = get_reminder_log(
            numeric_user_id
        )

        for prayer_key, prayer_name in SOLAT_REMINDER_NAMES.items():

            prayer_time = prayer.get(prayer_key)

            if not prayer_time:
                continue

            try:
                hour, minute = map(
                    int,
                    prayer_time[:5].split(":"),
                )

                prayer_datetime = now.replace(
                    hour=hour,
                    minute=minute,
                    second=0,
                    microsecond=0,
                )

            except Exception:
                continue

            diff = (
                prayer_datetime - now
            ).total_seconds()

            # =============================================
            # 5 MINIT SEBELUM
            # =============================================

            if 300 <= diff < 360:

                key = (
                    f"{today}|{zone}|"
                    f"{prayer_key}|5"
                )

                if key not in reminder_log:

                    sent = await send_solat_reminder(
                        application,
                        numeric_user_id,
                        zone,
                        prayer_name,
                        prayer_time,
                        5,
                    )

                    if sent:
                        save_reminder_log(
                            numeric_user_id,
                            key,
                        )

            # =============================================
            # TEPAT MASUK WAKTU
            # =============================================

            elif 0 <= diff < 60:

                key = (
                    f"{today}|{zone}|"
                    f"{prayer_key}|0"
                )

                if key not in reminder_log:

                    sent = await send_solat_reminder(
                        application,
                        numeric_user_id,
                        zone,
                        prayer_name,
                        prayer_time,
                        0,
                    )

                    if sent:
                        save_reminder_log(
                            numeric_user_id,
                            key,
                        )


async def solat_reminder_loop(application):
    global solat_reminder_task

    logger.info(
        "🕌 Solat reminder background task bermula."
    )

    # Beri masa bot siap terlebih dahulu.
    await asyncio.sleep(10)

    while True:

        try:
            await check_solat_reminders(
                application
            )

        except asyncio.CancelledError:
            logger.info(
                "Solat reminder task dihentikan."
            )
            raise

        except Exception as error:
            logger.exception(
                "Error dalam solat reminder: %s",
                error,
            )

        # Semak setiap 30 saat.
        await asyncio.sleep(30)


async def start_solat_reminder(application):
    global solat_reminder_task

    if solat_reminder_task is not None:
        if not solat_reminder_task.done():
            return

    solat_reminder_task = asyncio.create_task(
        solat_reminder_loop(application)
    )


async def stop_solat_reminder(application):
    global solat_reminder_task

    if solat_reminder_task is not None:

        solat_reminder_task.cancel()

        try:
            await solat_reminder_task

        except asyncio.CancelledError:
            pass

        solat_reminder_task = None


async def post_init(application):
    await start_solat_reminder(
        application
    )

    logger.info(
        "🕌 Waktu Solat reminder diaktifkan."
    )


async def post_shutdown(application):
    await stop_solat_reminder(
        application
    )

    logger.info(
        "🕌 Waktu Solat reminder dihentikan."
    )

'''

text = text.replace(
    marker,
    "\n" + reminder_code + marker,
    1,
)

# =========================================================
# 2. Tambah callback ON/OFF
# =========================================================

callback_marker = '''    # =====================================================
    # SOLAT CALLBACKS
    # =====================================================
'''

if callback_marker not in text:
    raise SystemExit(
        "❌ SOLAT CALLBACKS tidak dijumpai."
    )

if 'callback == "solat_reminder_on"' not in text:

    callback_code = '''    if callback == "solat_reminder_on":
        if not is_approved(query.from_user.id):
            await query.answer(
                "🚫 Akses diperlukan.",
                show_alert=True,
            )
            return

        set_user_reminder_enabled(
            query.from_user.id,
            True,
        )

        await query.answer(
            "🔔 Reminder dihidupkan.",
            show_alert=True,
        )

        await show_solat_menu(query)
        return

    if callback == "solat_reminder_off":
        if not is_approved(query.from_user.id):
            await query.answer(
                "🚫 Akses diperlukan.",
                show_alert=True,
            )
            return

        set_user_reminder_enabled(
            query.from_user.id,
            False,
        )

        await query.answer(
            "🔕 Reminder dimatikan.",
            show_alert=True,
        )

        await show_solat_menu(query)
        return

'''

    text = text.replace(
        callback_marker,
        callback_marker + "\n" + callback_code,
        1,
    )

# =========================================================
# 3. Tukar keyboard dalam show_solat_menu
# =========================================================

# Kita tidak replace keseluruhan fungsi.
# Sebaliknya, masukkan status reminder sebelum
# fungsi edit_message_text yang berkaitan.

if "solat_reminder_keyboard(" not in text:

    old = '''    await query.edit_message_text(
        text,
        parse_mode="HTML",
        reply_markup=solat_menu_keyboard(),
    )
'''

    new = '''    reminder_enabled = get_user_reminder_enabled(
        query.from_user.id
    )

    reminder_status = (
        "🔔 Reminder: <b>ON</b>"
        if reminder_enabled
        else "🔕 Reminder: <b>OFF</b>"
    )

    await query.edit_message_text(
        text + "\\n\\n" + reminder_status,
        parse_mode="HTML",
        reply_markup=solat_reminder_keyboard(
            reminder_enabled
        ),
    )
'''

    if old in text:
        text = text.replace(
            old,
            new,
            1,
        )
    else:
        print(
            "⚠️ show_solat_menu keyboard tidak ditukar."
        )

# =========================================================
# 4. Tambah keyboard reminder
# =========================================================

if "def solat_reminder_keyboard(" not in text:

    marker2 = "def solat_menu_keyboard():"

    if marker2 not in text:
        raise SystemExit(
            "❌ solat_menu_keyboard tidak dijumpai."
        )

    keyboard_code = r'''
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


'''

    text = text.replace(
        marker2,
        keyboard_code + marker2,
        1,
    )

# =========================================================
# 5. Tambah post_init / post_shutdown ke Application
# =========================================================

old_builder = '''        .pool_timeout(30)
        .build()
'''

new_builder = '''        .pool_timeout(30)
        .post_init(post_init)
        .post_shutdown(post_shutdown)
        .build()
'''

if old_builder in text:

    text = text.replace(
        old_builder,
        new_builder,
        1,
    )

else:

    if ".post_init(post_init)" not in text:
        raise SystemExit(
            "❌ Tidak jumpa Application.builder()."
        )

p.write_text(
    text,
    encoding="utf-8",
)

print("✅ Reminder V2 dimasukkan.")
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
echo "Reminder V2:"
echo "  ⏰ 5 minit sebelum"
echo "  🕌 Tepat masuk waktu"
echo "  🔔 ON/OFF setiap user"
echo "  📍 Ikut zon user"
echo
echo "JANGAN jalankan bot manual."
echo
echo "Restart dengan:"
echo "  sudo systemctl restart speedtest-bot"
