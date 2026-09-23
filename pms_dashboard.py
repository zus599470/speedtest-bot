import asyncio
import socket
import subprocess

from telegram import InlineKeyboardButton, InlineKeyboardMarkup


PMS = "/home/azam/.local/bin/pms"


def run_pms(*args):
    try:
        result = subprocess.run(
            [PMS, *args],
            capture_output=True,
            text=True,
            timeout=90,
        )

        output = (result.stdout + "\n" + result.stderr).strip()

        if not output:
            return "Tiada output."

        return output[-3000:]

    except FileNotFoundError:
        return "❌ Command pms tidak dijumpai."

    except subprocess.TimeoutExpired:
        return "❌ Command pms timeout."

    except Exception as e:
        return f"❌ Error: {e}"


def pms_running():
    try:
        with socket.create_connection(("127.0.0.1", 8088), timeout=1):
            return True
    except Exception:
        return False


def pms_status():
    return "🟢 Running" if pms_running() else "🔴 Stopped"


def pms_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton(
                "▶️ Start",
                callback_data="pms_start",
            ),
            InlineKeyboardButton(
                "⏹️ Stop",
                callback_data="pms_stop",
            ),
        ],
        [
            InlineKeyboardButton(
                "🔄 Restart",
                callback_data="pms_restart",
            ),
            InlineKeyboardButton(
                "📡 Tunnel",
                callback_data="pms_tunnel",
            ),
        ],
        [
            InlineKeyboardButton(
                "🚀 Auto ON",
                callback_data="pms_auto_on",
            ),
            InlineKeyboardButton(
                "🛑 Auto OFF",
                callback_data="pms_auto_off",
            ),
        ],
        [
            InlineKeyboardButton(
                "🔄 Refresh",
                callback_data="pms_refresh",
            ),
        ],
        [
            InlineKeyboardButton(
                "◀️ Back",
                callback_data="back_main",
            ),
            InlineKeyboardButton(
                "🏠 Home",
                callback_data="home",
            ),
        ],
    ])


async def show_pms(query):
    status = pms_status()

    text = (
        "🎬 <b>PENCARIMOVIE SERVER</b>\n\n"
        f"🖥️ Server: {status}\n"
        "🌐 Local: http://127.0.0.1:8088\n"
        "🌐 Network: http://192.168.0.12:8088\n\n"
        "👇 Pilih tindakan:"
    )

    await query.edit_message_text(
        text=text,
        parse_mode="HTML",
        reply_markup=pms_keyboard(),
    )


async def show_processing(query, title):
    await query.edit_message_text(
        f"🎬 <b>PENCARIMOVIE</b>\n\n"
        f"⏳ <b>{title}</b>\n\n"
        "🔄 Sedang menjalankan operasi...\n"
        "Sila tunggu...",
        parse_mode="HTML",
    )


async def handle_pms_callback(query, callback):

    # Refresh
    if callback == "pms_refresh":
        await query.answer("🔄 Refresh...")
        await show_pms(query)
        return True

    commands = {
        "pms_start": ("▶️ START", "start"),
        "pms_stop": ("⏹️ STOP", "stop"),
        "pms_restart": ("🔄 RESTART", "restart"),
        "pms_tunnel": ("📡 TUNNEL", "tunnel"),
        "pms_auto_on": ("🚀 AUTOSTART ON", "autostart", "on"),
        "pms_auto_off": ("🛑 AUTOSTART OFF", "autostart", "off"),
    }

    if callback not in commands:
        return False

    title = commands[callback][0]
    args = commands[callback][1:]

    await query.answer()

    # Paparkan animation/status
    await show_processing(query, title)

    # Sedikit delay supaya user nampak status
    await asyncio.sleep(1)

    # Jalankan command
    output = await asyncio.to_thread(run_pms, *args)

    # Tunggu server settle
    await asyncio.sleep(1)

    status = pms_status()

    success = not output.startswith("❌")

    if success:
        result_icon = "✅"
        result_text = "SELESAI"
    else:
        result_icon = "❌"
        result_text = "GAGAL"

    text = (
        f"🎬 <b>PENCARIMOVIE</b>\n\n"
        f"{result_icon} <b>{title} {result_text}</b>\n\n"
        f"🖥️ Status: {status}\n\n"
        f"📋 <b>Output:</b>\n"
        f"<pre>{output}</pre>\n\n"
        "👇 Pilih tindakan:"
    )

    await query.edit_message_text(
        text=text,
        parse_mode="HTML",
        reply_markup=pms_keyboard(),
    )

    return True
