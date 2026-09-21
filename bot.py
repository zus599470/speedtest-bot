import asyncio
import json
import logging
import os
import socket
import subprocess
from datetime import datetime

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
)

# ============================================================
# CONFIG
# ============================================================

BOT_TOKEN = os.getenv("BOT_TOKEN", "")

SPEEDTEST_PATH = "/usr/bin/speedtest"
INTERVAL_MINUTES = 10

# Paksa IPv4 untuk sambungan Telegram
_original_getaddrinfo = socket.getaddrinfo


def ipv4_only(*args, **kwargs):
    results = _original_getaddrinfo(*args, **kwargs)

    ipv4_results = [
        result for result in results
        if result[0] == socket.AF_INET
    ]

    return ipv4_results if ipv4_results else results


socket.getaddrinfo = ipv4_only


# ============================================================
# LOGGING
# ============================================================

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)

logger = logging.getLogger(__name__)


# ============================================================
# SPEEDTEST
# ============================================================

def run_speedtest():
    """
    Jalankan Ookla Speedtest dan ambil output JSON.
    """

    try:
        result = subprocess.run(
            [
                SPEEDTEST_PATH,
                "--accept-license",
                "--accept-gdpr",
                "--format=json",
                "--progress=no",
            ],
            capture_output=True,
            text=True,
            timeout=180,
        )

        if result.returncode != 0:
            return {
                "success": False,
                "error": result.stderr.strip()
                or "Speedtest gagal dijalankan.",
            }

        output = result.stdout.strip()

        if not output:
            return {
                "success": False,
                "error": "Speedtest tidak menghasilkan output.",
            }

        data = json.loads(output)

        # ----------------------------------------------------
        # Ping
        # ----------------------------------------------------

        ping = data.get("ping", {})

        latency = ping.get("latency")
        jitter = ping.get("jitter")
        low = ping.get("low")
        high = ping.get("high")

        # ----------------------------------------------------
        # Download
        # Ookla bandwidth = bytes/sec
        # ----------------------------------------------------

        download = data.get("download", {})
        download_bandwidth = download.get("bandwidth", 0)

        download_mbps = (
            download_bandwidth * 8 / 1_000_000
            if download_bandwidth
            else 0
        )

        download_bytes = download.get("bytes", 0)
        download_mb = download_bytes / 1_000_000

        # ----------------------------------------------------
        # Upload
        # ----------------------------------------------------

        upload = data.get("upload", {})
        upload_bandwidth = upload.get("bandwidth", 0)

        upload_mbps = (
            upload_bandwidth * 8 / 1_000_000
            if upload_bandwidth
            else 0
        )

        upload_bytes = upload.get("bytes", 0)
        upload_mb = upload_bytes / 1_000_000

        # ----------------------------------------------------
        # Packet Loss
        # ----------------------------------------------------

        packet_loss = data.get("packetLoss")

        if packet_loss is None:
            packet_loss_text = "N/A"
        else:
            packet_loss_text = f"{packet_loss:.2f}%"

        # ----------------------------------------------------
        # ISP
        # ----------------------------------------------------

        isp = data.get("isp", "Unknown")

        # ----------------------------------------------------
        # Server
        # ----------------------------------------------------

        server = data.get("server", {})

        server_name = server.get("name", "Unknown")
        server_location = server.get("location", "Unknown")
        server_country = server.get("country", "Unknown")
        server_id = server.get("id", "Unknown")

        # ----------------------------------------------------
        # Timestamp
        # ----------------------------------------------------

        timestamp = data.get("timestamp")

        if timestamp:
            try:
                dt = datetime.fromisoformat(
                    timestamp.replace("Z", "+00:00")
                )

                test_time = dt.strftime("%d/%m/%Y %H:%M:%S")

            except Exception:
                test_time = timestamp
        else:
            test_time = datetime.now().strftime(
                "%d/%m/%Y %H:%M:%S"
            )

        return {
            "success": True,
            "latency": latency,
            "jitter": jitter,
            "low": low,
            "high": high,
            "download": download_mbps,
            "download_mb": download_mb,
            "upload": upload_mbps,
            "upload_mb": upload_mb,
            "packet_loss": packet_loss_text,
            "isp": isp,
            "server_name": server_name,
            "server_location": server_location,
            "server_country": server_country,
            "server_id": server_id,
            "timestamp": test_time,
        }

    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "error": "Speedtest timeout selepas 180 saat.",
        }

    except json.JSONDecodeError as error:
        logger.error("JSON error: %s", error)

        return {
            "success": False,
            "error": "Output Speedtest bukan JSON yang sah.",
        }

    except Exception as error:
        logger.exception("Speedtest error")

        return {
            "success": False,
            "error": str(error),
        }


# ============================================================
# FORMAT RESULT
# ============================================================

def format_result(result):
    if not result["success"]:
        return (
            "❌ <b>Speedtest Gagal</b>\n\n"
            f"<code>{result['error']}</code>"
        )

    return (
        "⚡ <b>SPEEDTEST RESULT</b>\n"
        "━━━━━━━━━━━━━━━━━━\n\n"

        f"🏓 <b>Ping:</b> "
        f"{result['latency']:.2f} ms\n"

        f"📡 <b>Jitter:</b> "
        f"{result['jitter']:.2f} ms\n"

        f"📉 <b>Low:</b> "
        f"{result['low']:.2f} ms\n"

        f"📈 <b>High:</b> "
        f"{result['high']:.2f} ms\n\n"

        f"📥 <b>Download:</b> "
        f"{result['download']:.2f} Mbps\n"

        f"📤 <b>Upload:</b> "
        f"{result['upload']:.2f} Mbps\n\n"

        f"🏢 <b>ISP:</b> "
        f"{result['isp']}\n"

        f"🌐 <b>Server:</b> "
        f"{result['server_name']}\n"

        f"📍 <b>Location:</b> "
        f"{result['server_location']}, "
        f"{result['server_country']}\n"

        f"🆔 <b>Server ID:</b> "
        f"{result['server_id']}\n\n"

        f"📦 <b>Packet Loss:</b> "
        f"{result['packet_loss']}\n"

        f"💾 <b>Download Data:</b> "
        f"{result['download_mb']:.1f} MB\n"

        f"💾 <b>Upload Data:</b> "
        f"{result['upload_mb']:.1f} MB\n\n"

        f"🕒 <b>Time:</b> "
        f"{result['timestamp']}\n"

        "━━━━━━━━━━━━━━━━━━"
    )


# ============================================================
# KEYBOARD
# ============================================================

def main_keyboard():
    keyboard = [
        [
            InlineKeyboardButton(
                "⚡ Speedtest Sekarang",
                callback_data="speedtest",
            )
        ],
        [
            InlineKeyboardButton(
                "▶️ Start Auto",
                callback_data="start_auto",
            ),
            InlineKeyboardButton(
                "⏹️ Stop Auto",
                callback_data="stop_auto",
            ),
        ],
        [
            InlineKeyboardButton(
                "📊 Status",
                callback_data="status",
            )
        ],
    ]

    return InlineKeyboardMarkup(keyboard)


# ============================================================
# START
# ============================================================

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):

    await update.message.reply_text(
        "⚡ <b>Speedtest Bot</b>\n\n"
        "Bot Speedtest Ookla untuk Raspberry Pi.\n\n"
        "Pilih fungsi di bawah:",
        parse_mode="HTML",
        reply_markup=main_keyboard(),
    )


# ============================================================
# SPEEDTEST HANDLER
# ============================================================

async def do_speedtest(
    chat_id,
    context: ContextTypes.DEFAULT_TYPE,
):

    status_message = await context.bot.send_message(
        chat_id=chat_id,
        text=(
            "⏳ <b>Speedtest sedang dijalankan...</b>\n\n"
            "Tunggu sehingga selesai."
        ),
        parse_mode="HTML",
    )

    result = await asyncio.to_thread(run_speedtest)

    message = format_result(result)

    try:
        await context.bot.edit_message_text(
            chat_id=chat_id,
            message_id=status_message.message_id,
            text=message,
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )

    except Exception:
        await context.bot.send_message(
            chat_id=chat_id,
            text=message,
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )


# ============================================================
# AUTO SPEEDTEST
# ============================================================

async def auto_speedtest_job(context: ContextTypes.DEFAULT_TYPE):

    chat_id = context.job.chat_id

    logger.info(
        "Auto Speedtest dimulakan untuk chat %s",
        chat_id,
    )

    await do_speedtest(chat_id, context)


# ============================================================
# CALLBACK BUTTON
# ============================================================

async def button_handler(
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
):

    query = update.callback_query

    # Jawab callback SEGERA supaya Telegram tidak expired
    try:
        await query.answer()
    except Exception as error:
        logger.warning(
            "Callback sudah expired: %s",
            error,
        )

    chat_id = query.message.chat_id

    # --------------------------------------------------------
    # Speedtest sekarang
    # --------------------------------------------------------

    if query.data == "speedtest":

        await do_speedtest(
            chat_id,
            context,
        )

    # --------------------------------------------------------
    # Start Auto
    # --------------------------------------------------------

    elif query.data == "start_auto":

        # Elak duplicate job
        current_jobs = context.job_queue.get_jobs_by_name(
            f"speedtest_{chat_id}"
        )

        if current_jobs:

            await context.bot.send_message(
                chat_id=chat_id,
                text=(
                    "⚠️ <b>Auto Speedtest sudah aktif.</b>\n\n"
                    "Speedtest akan dijalankan setiap "
                    f"{INTERVAL_MINUTES} minit."
                ),
                parse_mode="HTML",
                reply_markup=main_keyboard(),
            )

            return

        context.job_queue.run_repeating(
            auto_speedtest_job,
            interval=INTERVAL_MINUTES * 60,
            first=INTERVAL_MINUTES * 60,
            chat_id=chat_id,
            name=f"speedtest_{chat_id}",
        )

        await context.bot.send_message(
            chat_id=chat_id,
            text=(
                "✅ <b>Auto Speedtest AKTIF</b>\n\n"
                f"⏱️ Interval: setiap {INTERVAL_MINUTES} minit\n"
                "📡 Engine: Ookla Speedtest\n"
                "📊 Output: JSON\n\n"
                "Speedtest pertama akan dijalankan "
                f"dalam {INTERVAL_MINUTES} minit."
            ),
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )

    # --------------------------------------------------------
    # Stop Auto
    # --------------------------------------------------------

    elif query.data == "stop_auto":

        jobs = context.job_queue.get_jobs_by_name(
            f"speedtest_{chat_id}"
        )

        if not jobs:

            await context.bot.send_message(
                chat_id=chat_id,
                text=(
                    "ℹ️ <b>Auto Speedtest tidak aktif.</b>"
                ),
                parse_mode="HTML",
                reply_markup=main_keyboard(),
            )

            return

        for job in jobs:
            job.schedule_removal()

        await context.bot.send_message(
            chat_id=chat_id,
            text=(
                "⏹️ <b>Auto Speedtest dihentikan.</b>"
            ),
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )

    # --------------------------------------------------------
    # Status
    # --------------------------------------------------------

    elif query.data == "status":

        jobs = context.job_queue.get_jobs_by_name(
            f"speedtest_{chat_id}"
        )

        if jobs:

            status = (
                "🟢 <b>Auto Speedtest: AKTIF</b>\n\n"
                f"⏱️ Setiap {INTERVAL_MINUTES} minit\n"
                "⚡ Engine: Ookla Speedtest"
            )

        else:

            status = (
                "🔴 <b>Auto Speedtest: TIDAK AKTIF</b>\n\n"
                "Tekan ▶️ Start Auto untuk aktifkan."
            )

        await context.bot.send_message(
            chat_id=chat_id,
            text=status,
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )


# ============================================================
# ERROR HANDLER
# ============================================================

async def error_handler(
    update: object,
    context: ContextTypes.DEFAULT_TYPE,
):

    logger.error(
        "Telegram error: %s",
        context.error,
    )


# ============================================================
# MAIN
# ============================================================

def main():

    if BOT_TOKEN == "MASUKKAN_BOT_TOKEN_DI_SINI":

        print()
        print("==========================================")
        print(" ERROR: BOT TOKEN BELUM DIMASUKKAN")
        print("==========================================")
        print()
        print("Edit bot.py dan masukkan token BotFather.")
        print()

        return

    print()
    print("==========================================")
    print(" SPEEDTEST TELEGRAM BOT")
    print("==========================================")
    print(" Engine         : Ookla Speedtest")
    print(" Speedtest      : /usr/bin/speedtest")
    print(" Auto Speedtest : Setiap 10 minit")
    print(" Output         : JSON")
    print(" Telegram       : IPv4 / 30s timeout")
    print(" Status         : RUNNING")
    print("==========================================")
    print()

    application = (
        Application.builder()
        .token(BOT_TOKEN)
        .connect_timeout(30)
        .read_timeout(30)
        .write_timeout(30)
        .pool_timeout(30)
        .build()
    )

    application.add_handler(
        CommandHandler("start", start)
    )

    application.add_handler(
        CallbackQueryHandler(button_handler)
    )

    application.add_error_handler(
        error_handler
    )

    application.run_polling(
        allowed_updates=Update.ALL_TYPES
    )


if __name__ == "__main__":
    main()
