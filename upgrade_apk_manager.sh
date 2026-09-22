#!/usr/bin/env bash

set -Eeuo pipefail

BOT_FILE="$HOME/speedtest-bot/bot_server.py"
BACKUP_FILE="$HOME/speedtest-bot/bot_server.before-apk-auto.py"

echo
echo "=============================================="
echo "       APK MANAGER - AUTO APK LIBRARY"
echo "=============================================="
echo

if [[ ! -f "$BOT_FILE" ]]; then
    echo "❌ bot_server.py tak dijumpai."
    exit 1
fi

if [[ ! -d "$HOME/apk-manager/apk" ]]; then
    echo "❌ Folder APK tak dijumpai."
    exit 1
fi

echo ">>> Backup..."

cp "$BOT_FILE" "$BACKUP_FILE"

echo "✅ Backup dibuat:"
echo "$BACKUP_FILE"

python3 <<'PY'
from pathlib import Path
import re

bot = Path.home() / "speedtest-bot" / "bot_server.py"
text = bot.read_text()

# Cari blok APK Manager yang telah ditambah sebelum ini
start_marker = "# =========================================================\n# APK MANAGER\n# ========================================================="
end_marker = "# =========================================================\n# CALLBACK HANDLER\n# ========================================================="

start = text.find(start_marker)
end = text.find(end_marker, start)

if start == -1 or end == -1:
    raise SystemExit(
        "❌ Blok APK Manager lama tak dijumpai.\n"
        "Pastikan script APK Manager sebelum ini sudah berjaya dijalankan."
    )

new_apk_code = r'''# =========================================================
# APK MANAGER
# =========================================================

APK_DIR = "/home/azam/apk-manager/apk"


def get_apk_files():
    apk_dir = Path(APK_DIR)

    if not apk_dir.exists():
        return []

    return sorted(
        [
            file
            for file in apk_dir.iterdir()
            if file.is_file() and file.suffix.lower() == ".apk"
        ],
        key=lambda x: x.name.lower(),
    )


def apk_menu_keyboard():
    apk_files = get_apk_files()

    keyboard = []

    for index, apk in enumerate(apk_files):
        keyboard.append(
            [
                InlineKeyboardButton(
                    f"📦 {apk.stem}",
                    callback_data=f"apk_file_{index}",
                )
            ]
        )

    keyboard.append(
        [
            InlineKeyboardButton(
                "🔄 Refresh",
                callback_data="apk_menu",
            )
        ]
    )

    keyboard.append(
        [
            InlineKeyboardButton(
                "⬅️ Back",
                callback_data="home",
            )
        ]
    )

    return InlineKeyboardMarkup(keyboard)


async def show_apk_menu(query):
    apk_files = get_apk_files()

    if not apk_files:
        await query.edit_message_text(
            "📱 <b>APK MANAGER</b>\n\n"
            "❌ Tiada APK dalam library.\n\n"
            f"📂 Folder:\n<code>{APK_DIR}</code>",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "🔄 Refresh",
                            callback_data="apk_menu",
                        )
                    ],
                    [
                        InlineKeyboardButton(
                            "⬅️ Back",
                            callback_data="home",
                        )
                    ],
                ]
            ),
        )
        return

    await query.edit_message_text(
        "📱 <b>APK MANAGER</b>\n\n"
        f"📦 Jumlah APK: <b>{len(apk_files)}</b>\n\n"
        "Pilih aplikasi:",
        parse_mode="HTML",
        reply_markup=apk_menu_keyboard(),
    )


async def show_apk_file(query, index):
    apk_files = get_apk_files()

    try:
        index = int(index)
        apk = apk_files[index]
    except (ValueError, IndexError):
        await query.edit_message_text(
            "❌ APK tidak dijumpai.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "⬅️ APK Manager",
                            callback_data="apk_menu",
                        )
                    ]
                ]
            ),
        )
        return

    size_mb = apk.stat().st_size / (1024 * 1024)

    await query.edit_message_text(
        "📦 <b>APK INFO</b>\n\n"
        f"📱 Nama: <b>{apk.stem}</b>\n"
        f"📄 Fail: <code>{apk.name}</code>\n"
        f"💾 Saiz: <b>{size_mb:.1f} MB</b>\n\n"
        "Pilih tindakan:",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(
            [
                [
                    InlineKeyboardButton(
                        "⬇️ Download APK",
                        callback_data=f"apk_download_{index}",
                    )
                ],
                [
                    InlineKeyboardButton(
                        "⬅️ APK Manager",
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


async def send_apk(query, context, index):
    apk_files = get_apk_files()

    try:
        index = int(index)
        apk = apk_files[index]
    except (ValueError, IndexError):
        await query.edit_message_text(
            "❌ APK tidak dijumpai.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "⬅️ APK Manager",
                            callback_data="apk_menu",
                        )
                    ]
                ]
            ),
        )
        return

    await query.edit_message_text(
        "📦 <b>APK MANAGER</b>\n\n"
        f"📱 <b>{apk.stem}</b>\n"
        "⏳ <i>Sedang hantar APK...</i>",
        parse_mode="HTML",
    )

    try:
        with open(apk, "rb") as apk_file:
            await context.bot.send_document(
                chat_id=query.message.chat_id,
                document=apk_file,
                filename=apk.name,
                caption=f"📱 <b>{apk.stem}</b>",
                parse_mode="HTML",
            )

        await query.edit_message_text(
            "✅ <b>APK berjaya dihantar.</b>\n\n"
            f"📱 {apk.stem}",
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
        logger.exception("Gagal hantar APK")

        await query.edit_message_text(
            "❌ <b>Gagal menghantar APK.</b>\n\n"
            f"<code>{error}</code>",
            parse_mode="HTML",
        )


'''

text = text[:start] + new_apk_code + text[end:]

# Pastikan pathlib import wujud
if "from pathlib import Path" not in text:
    import_match = re.search(r"^(import .+|from .+ import .+)$", text, re.MULTILINE)

    if import_match:
        pos = import_match.end()
        text = text[:pos] + "\nfrom pathlib import Path" + text[pos:]
    else:
        text = "from pathlib import Path\n" + text

# Tambah callback auto APK
home_marker = '''    # =====================================================
    # HOME
    # =====================================================
'''

callback_code = '''    # =====================================================
    # APK MANAGER
    # =====================================================

    if callback == "apk_menu":
        await show_apk_menu(query)
        return

    if callback.startswith("apk_file_"):
        index = callback.replace("apk_file_", "", 1)
        await show_apk_file(query, index)
        return

    if callback.startswith("apk_download_"):
        index = callback.replace("apk_download_", "", 1)
        await send_apk(query, context, index)
        return

'''

# Buang callback APK lama kalau masih ada
patterns = [
    r'    # =====================================================\n'
    r'    # APK MANAGER\n'
    r'    # =====================================================\n\n'
    r'    if callback == "apk_menu":.*?'
    r'        return\n\n'
]

for pattern in patterns:
    text = re.sub(
        pattern,
        "",
        text,
        count=1,
        flags=re.DOTALL,
    )

if home_marker not in text:
    raise SystemExit("❌ HOME callback section tak dijumpai.")

text = text.replace(
    home_marker,
    callback_code + home_marker,
    1,
)

bot.write_text(text)

print("✅ APK Manager ditukar kepada Auto APK Library.")
PY

echo
echo ">>> Check syntax..."

"$HOME/speedtest-bot/venv/bin/python" -m py_compile "$BOT_FILE"

echo "✅ Syntax OK."

echo
echo ">>> Restart bot..."

sudo systemctl restart speedtest-bot

sleep 3

if sudo systemctl is-active --quiet speedtest-bot; then
    echo
    echo "=============================================="
    echo "       ✅ BERJAYA"
    echo "=============================================="
    echo
    echo "APK Manager sekarang AUTO-DETECT."
    echo
    echo "Tambah APK dengan:"
    echo
    echo "cp nama.apk ~/apk-manager/apk/"
    echo
    echo "Kemudian Telegram:"
    echo "📱 APK Manager → 🔄 Refresh"
    echo
else
    echo "❌ Bot gagal start."
    echo
    echo "Semak:"
    echo "sudo journalctl -u speedtest-bot -n 50 --no-pager"
    echo
    echo "Backup:"
    echo "$BACKUP_FILE"
    exit 1
fi
