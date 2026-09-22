#!/usr/bin/env bash

set -Eeuo pipefail

BOT_FILE="$HOME/speedtest-bot/bot_server.py"
APK_FILE="$HOME/apk-manager/apk/Nuvio.apk"
BACKUP_FILE="$HOME/speedtest-bot/bot_server.before-apk-manager.py"

echo
echo "=============================================="
echo "       ADD APK MANAGER - NUVIO"
echo "=============================================="
echo

if [[ ! -f "$BOT_FILE" ]]; then
    echo "❌ bot_server.py tak dijumpai."
    exit 1
fi

if [[ ! -f "$APK_FILE" ]]; then
    echo "❌ Nuvio.apk tak dijumpai:"
    echo "$APK_FILE"
    exit 1
fi

echo ">>> Backup bot_server.py..."

cp "$BOT_FILE" "$BACKUP_FILE"

echo "✅ Backup:"
echo "$BACKUP_FILE"

python3 <<'PY'
from pathlib import Path

bot = Path.home() / "speedtest-bot" / "bot_server.py"
text = bot.read_text()

# -----------------------------------------------------
# 1. Pastikan import os
# -----------------------------------------------------

if "import os" not in text:
    lines = text.splitlines()

    insert_at = 0

    while insert_at < len(lines) and (
        lines[insert_at].startswith("#")
        or not lines[insert_at].strip()
    ):
        insert_at += 1

    lines.insert(insert_at, "import os")
    text = "\n".join(lines) + "\n"

    print("✅ import os ditambah.")
else:
    print("✅ import os sudah ada.")

# -----------------------------------------------------
# 2. Tambah APK Manager button
# -----------------------------------------------------

old_button = '''        [
            InlineKeyboardButton(
                "🛡️ Pi-hole",
                callback_data="pihole_menu",
            )
        ],
    ]

    return InlineKeyboardMarkup(keyboard)
'''

new_button = '''        [
            InlineKeyboardButton(
                "🛡️ Pi-hole",
                callback_data="pihole_menu",
            )
        ],
        [
            InlineKeyboardButton(
                "📱 APK Manager",
                callback_data="apk_menu",
            )
        ],
    ]

    return InlineKeyboardMarkup(keyboard)
'''

if 'callback_data="apk_menu"' not in text:
    if old_button not in text:
        raise SystemExit(
            "❌ Struktur main_keyboard() tak sepadan. "
            "Tiada perubahan dibuat."
        )

    text = text.replace(old_button, new_button, 1)
    print("✅ Butang APK Manager ditambah.")
else:
    print("ℹ️ Butang APK Manager sudah ada.")

# -----------------------------------------------------
# 3. Tambah fungsi APK Manager
# -----------------------------------------------------

if "async def show_apk_menu(query):" not in text:

    marker = '''# =========================================================
# CALLBACK HANDLER
# =========================================================
'''

    if marker not in text:
        raise SystemExit(
            "❌ CALLBACK HANDLER tak dijumpai. "
            "Tiada perubahan fungsi APK dibuat."
        )

    apk_code = r'''
# =========================================================
# APK MANAGER
# =========================================================

APK_DIR = "/home/azam/apk-manager/apk"
NUVIO_APK = "/home/azam/apk-manager/apk/Nuvio.apk"


def apk_menu_keyboard():
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "📦 Nuvio",
                    callback_data="apk_nuvio",
                )
            ],
            [
                InlineKeyboardButton(
                    "⬅️ Back",
                    callback_data="home",
                )
            ],
        ]
    )


async def show_apk_menu(query):
    if not os.path.exists(NUVIO_APK):
        await query.edit_message_text(
            "❌ <b>Nuvio.apk tidak dijumpai.</b>",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "⬅️ Home",
                            callback_data="home",
                        )
                    ]
                ]
            ),
        )
        return

    size_mb = os.path.getsize(NUVIO_APK) / (1024 * 1024)

    await query.edit_message_text(
        "📱 <b>APK MANAGER</b>\n\n"
        "📦 <b>Nuvio</b>\n"
        f"💾 Saiz: <b>{size_mb:.1f} MB</b>\n\n"
        "Pilih APK:",
        parse_mode="HTML",
        reply_markup=apk_menu_keyboard(),
    )


async def show_nuvio(query):
    if not os.path.exists(NUVIO_APK):
        await query.edit_message_text(
            "❌ <b>Nuvio.apk tidak dijumpai.</b>",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "⬅️ Back",
                            callback_data="apk_menu",
                        )
                    ]
                ]
            ),
        )
        return

    size_mb = os.path.getsize(NUVIO_APK) / (1024 * 1024)

    await query.edit_message_text(
        "📦 <b>NUVIO</b>\n\n"
        f"💾 Saiz: <b>{size_mb:.1f} MB</b>\n\n"
        "Pilih tindakan:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(
            [
                [
                    InlineKeyboardButton(
                        "⬇️ Download Nuvio",
                        callback_data="apk_download_nuvio",
                    )
                ],
                [
                    InlineKeyboardButton(
                        "⬅️ Back",
                        callback_data="apk_menu",
                    ),
                    InlineKeyboardButton(
                        "🏠 Home",
                        callback_data="home",
                    ),
                ],
            ]
        ),
    )


async def send_nuvio(query, context):
    if not os.path.exists(NUVIO_APK):
        await query.edit_message_text(
            "❌ <b>Nuvio.apk tidak dijumpai.</b>",
            parse_mode="HTML",
        )
        return

    await query.edit_message_text(
        "📦 <b>NUVIO</b>\n\n"
        "⏳ <i>Sedang hantar APK...</i>",
        parse_mode="HTML",
    )

    try:
        with open(NUVIO_APK, "rb") as apk_file:
            await context.bot.send_document(
                chat_id=query.message.chat_id,
                document=apk_file,
                filename="Nuvio.apk",
                caption="📱 <b>Nuvio APK</b>",
                parse_mode="HTML",
            )

        await query.edit_message_text(
            "✅ <b>Nuvio.apk berjaya dihantar.</b>",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "⬅️ APK Manager",
                            callback_data="apk_menu",
                        )
                    ],
                    [
                        InlineKeyboardButton(
                            "🏠 Home",
                            callback_data="home",
                        )
                    ],
                ]
            ),
        )

    except Exception as error:
        logger.exception("Gagal hantar Nuvio APK")

        await query.edit_message_text(
            "❌ <b>Gagal menghantar Nuvio.apk.</b>\n\n"
            f"<code>{error}</code>",
            parse_mode="HTML",
        )


'''

    text = text.replace(marker, apk_code + marker, 1)
    print("✅ Fungsi APK Manager ditambah.")
else:
    print("ℹ️ Fungsi APK Manager sudah ada.")

# -----------------------------------------------------
# 4. Tambah callback
# -----------------------------------------------------

if 'if callback == "apk_download_nuvio":' not in text:

    marker = '''    # =====================================================
    # HOME
    # =====================================================
'''

    callback_code = '''    # =====================================================
    # APK MANAGER
    # =====================================================

    if callback == "apk_menu":
        await show_apk_menu(query)
        return

    if callback == "apk_nuvio":
        await show_nuvio(query)
        return

    if callback == "apk_download_nuvio":
        await send_nuvio(query, context)
        return

'''

    if marker not in text:
        raise SystemExit(
            "❌ HOME callback section tak dijumpai. "
            "Tiada callback APK ditambah."
        )

    text = text.replace(marker, callback_code + marker, 1)
    print("✅ Callback APK Manager ditambah.")
else:
    print("ℹ️ Callback APK Manager sudah ada.")

bot.write_text(text)

print("✅ bot_server.py berjaya dikemaskini.")

PY

echo
echo ">>> Check Python syntax..."

"$HOME/speedtest-bot/venv/bin/python" -m py_compile "$BOT_FILE"

echo "✅ Syntax OK."

echo
echo ">>> Restart Telegram bot..."

sudo systemctl restart speedtest-bot

sleep 3

if sudo systemctl is-active --quiet speedtest-bot; then
    echo
    echo "=============================================="
    echo "       ✅ APK MANAGER BERJAYA"
    echo "=============================================="
    echo
    echo "📱 APK Manager : Ditambah"
    echo "📦 Nuvio       : Ada"
    echo "💾 APK size    : $(du -h "$APK_FILE" | awk '{print $1}')"
    echo "🤖 Bot         : RUNNING"
    echo
    echo "Telegram:"
    echo "  Home → 📱 APK Manager → 📦 Nuvio"
    echo
else
    echo
    echo "❌ Bot gagal start."
    echo
    echo "Semak:"
    echo "sudo journalctl -u speedtest-bot -n 50 --no-pager"
    echo
    echo "Backup asal masih ada:"
    echo "$BACKUP_FILE"
    exit 1
fi
