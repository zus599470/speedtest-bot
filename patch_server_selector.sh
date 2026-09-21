#!/bin/bash

set -e

cd ~/speedtest-bot

echo "=========================================="
echo " PATCH SERVER SELECTOR"
echo "=========================================="

# Pastikan module wujud
if [ ! -f "server_selector/selector.py" ]; then
    echo "ERROR: server_selector belum wujud."
    exit 1
fi

# Backup
cp bot.py "bot.py.backup-$(date +%Y%m%d-%H%M%S)"

python3 <<'PYEOF'
from pathlib import Path

path = Path("bot.py")
text = path.read_text()

# ============================================================
# 1. TAMBAH IMPORT SERVER SELECTOR
# ============================================================

old = """from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
)
"""

new = """from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
)

from server_selector.selector import (
    get_servers,
    get_selected_server,
    set_selected_server,
    clear_selected_server,
)
"""

if "from server_selector.selector import" not in text:
    if old not in text:
        raise SystemExit("ERROR: Bahagian import telegram tidak dijumpai.")
    text = text.replace(old, new, 1)


# ============================================================
# 2. TAMBAH SERVER SELECTOR KE run_speedtest()
# ============================================================

old = """        result = subprocess.run(
            [
                SPEEDTEST_PATH,
                "--accept-license",
                "--accept-gdpr",
                "--format=json",
                "--progress=no",
            ],
"""

new = """        speedtest_command = [
            SPEEDTEST_PATH,
            "--accept-license",
            "--accept-gdpr",
            "--format=json",
            "--progress=no",
        ]

        # Gunakan server yang dipilih jika ada.
        selected_server = get_selected_server()

        if selected_server and selected_server.get("id"):
            speedtest_command.append(
                f"--server-id={selected_server['id']}"
            )

        result = subprocess.run(
            speedtest_command,
"""

if old not in text:
    raise SystemExit("ERROR: Command speedtest tidak dijumpai.")

text = text.replace(old, new, 1)


# ============================================================
# 3. TAMBAH BUTANG PILIH SERVER
# ============================================================

old = """        [
            InlineKeyboardButton(
                "📊 Status",
                callback_data="status",
            )
        ],
"""

new = """        [
            InlineKeyboardButton(
                "🌐 Pilih Server",
                callback_data="server_menu",
            )
        ],
        [
            InlineKeyboardButton(
                "📊 Status",
                callback_data="status",
            )
        ],
"""

if 'callback_data="server_menu"' not in text:
    if old not in text:
        raise SystemExit("ERROR: Butang Status tidak dijumpai.")
    text = text.replace(old, new, 1)


# ============================================================
# 4. TAMBAH FUNGSI SERVER MENU
# ============================================================

marker = """# ============================================================
# CALLBACK BUTTON
# ============================================================

async def button_handler(
"""

server_functions = r'''# ============================================================
# SERVER SELECTOR
# ============================================================

async def show_server_menu(
    chat_id,
    context: ContextTypes.DEFAULT_TYPE,
):

    servers = await asyncio.to_thread(get_servers)

    if not servers:
        await context.bot.send_message(
            chat_id=chat_id,
            text=(
                "❌ <b>Gagal mendapatkan senarai server.</b>\n\n"
                "Cuba lagi sebentar."
            ),
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )
        return

    selected = get_selected_server()
    selected_id = selected.get("id") if selected else None

    keyboard = []

    for server in servers:

        server_id = server["id"]
        name = server["name"]
        location = server["location"]

        if server_id == selected_id:
            prefix = "✅"
        else:
            prefix = "🌐"

        button_text = f"{prefix} {name} - {location}"

        keyboard.append(
            [
                InlineKeyboardButton(
                    button_text,
                    callback_data=f"select_server:{server_id}",
                )
            ]
        )

    keyboard.append(
        [
            InlineKeyboardButton(
                "🔄 Auto / Reset",
                callback_data="server_auto",
            )
        ]
    )

    keyboard.append(
        [
            InlineKeyboardButton(
                "🔙 Kembali",
                callback_data="back_menu",
            )
        ]
    )

    await context.bot.send_message(
        chat_id=chat_id,
        text=(
            "🌐 <b>PILIH SERVER SPEEDTEST</b>\n\n"
            "Pilih server yang mahu digunakan "
            "untuk Speedtest.\n\n"
            "✅ = Server sedang dipilih"
        ),
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(keyboard),
    )


async def select_server(
    chat_id,
    server_id,
    context: ContextTypes.DEFAULT_TYPE,
):

    servers = await asyncio.to_thread(get_servers)

    selected = None

    for server in servers:
        if server["id"] == server_id:
            selected = server
            break

    if selected is None:
        await context.bot.send_message(
            chat_id=chat_id,
            text="❌ Server tidak dijumpai.",
            reply_markup=main_keyboard(),
        )
        return

    set_selected_server(selected)

    await context.bot.send_message(
        chat_id=chat_id,
        text=(
            "✅ <b>Server berjaya dipilih</b>\n\n"
            f"🌐 <b>{selected['name']}</b>\n"
            f"📍 {selected['location']}, "
            f"{selected['country']}\n"
            f"🆔 {selected['id']}\n\n"
            "Speedtest seterusnya akan menggunakan "
            "server ini."
        ),
        parse_mode="HTML",
        reply_markup=main_keyboard(),
    )


async def reset_server(
    chat_id,
    context: ContextTypes.DEFAULT_TYPE,
):

    clear_selected_server()

    await context.bot.send_message(
        chat_id=chat_id,
        text=(
            "🔄 <b>Server di-reset</b>\n\n"
            "Ookla akan memilih server terbaik "
            "secara automatik untuk Speedtest seterusnya."
        ),
        parse_mode="HTML",
        reply_markup=main_keyboard(),
    )


# ============================================================
# CALLBACK BUTTON
# ============================================================

async def button_handler(
'''

if marker not in text:
    raise SystemExit("ERROR: CALLBACK BUTTON marker tidak dijumpai.")

text = text.replace(marker, server_functions, 1)


# ============================================================
# 5. TAMBAH CALLBACK SERVER
# ============================================================

old = """    chat_id = query.message.chat_id

    # --------------------------------------------------------
    # Speedtest sekarang
    # --------------------------------------------------------
"""

new = """    chat_id = query.message.chat_id

    # --------------------------------------------------------
    # Server menu
    # --------------------------------------------------------

    if query.data == "server_menu":

        await show_server_menu(
            chat_id,
            context,
        )

        return

    # --------------------------------------------------------
    # Pilih server
    # --------------------------------------------------------

    if query.data.startswith("select_server:"):

        try:
            server_id = int(
                query.data.split(":", 1)[1]
            )
        except ValueError:

            await context.bot.send_message(
                chat_id=chat_id,
                text="❌ Server ID tidak sah.",
                reply_markup=main_keyboard(),
            )

            return

        await select_server(
            chat_id,
            server_id,
            context,
        )

        return

    # --------------------------------------------------------
    # Reset / Auto server
    # --------------------------------------------------------

    if query.data == "server_auto":

        await reset_server(
            chat_id,
            context,
        )

        return

    # --------------------------------------------------------
    # Kembali
    # --------------------------------------------------------

    if query.data == "back_menu":

        await context.bot.send_message(
            chat_id=chat_id,
            text=(
                "⚡ <b>Speedtest Bot</b>\n\n"
                "Pilih fungsi di bawah:"
            ),
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )

        return

    # --------------------------------------------------------
    # Speedtest sekarang
    # --------------------------------------------------------
"""

if old not in text:
    raise SystemExit("ERROR: Bahagian callback speedtest tidak dijumpai.")

text = text.replace(old, new, 1)


# ============================================================
# SAVE
# ============================================================

path.write_text(text)

print("Patch berjaya dimasukkan.")
PYEOF

echo ""
echo "Semak syntax..."
python3 -m py_compile bot.py

echo ""
echo "=========================================="
echo " PATCH BERJAYA"
echo "=========================================="
echo ""
echo "Backup asal:"
ls -1t bot.py.backup-* 2>/dev/null | head -1
echo ""
echo "Bot syntax: OK"
echo ""
