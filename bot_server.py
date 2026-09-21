import asyncio
import json
import logging
import socket
import subprocess
from datetime import datetime

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    ContextTypes,
)

from bot import BOT_TOKEN

from server_selector.selector import (
    get_servers,
    get_selected_server,
    set_selected_server,
    clear_selected_server,
)

from pihole_api import (
    login as pihole_login,
    get as pihole_get,
    set_blocking as pihole_set_blocking,
)


# =========================================================
# CONFIG
# =========================================================

SPEEDTEST_PATH = "/usr/bin/speedtest"
INTERVAL_MINUTES = 10

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)

logger = logging.getLogger(__name__)

auto_task = None


# =========================================================
# FORCE IPV4
# =========================================================

_original_getaddrinfo = socket.getaddrinfo


def ipv4_only_getaddrinfo(*args, **kwargs):
    results = _original_getaddrinfo(*args, **kwargs)

    ipv4 = [
        result
        for result in results
        if result[0] == socket.AF_INET
    ]

    return ipv4 if ipv4 else results


socket.getaddrinfo = ipv4_only_getaddrinfo


# =========================================================
# ANIMATION
# =========================================================

async def animate_message(
    query,
    title,
    messages,
    delay=0.45,
):
    """
    Paparkan animation pada mesej Telegram.
    """
    for message in messages:
        try:
            await query.edit_message_text(
                f"{title}\n\n{message}",
                parse_mode="HTML",
            )
            await asyncio.sleep(delay)

        except Exception as error:
            logger.warning(
                "Animation gagal dikemaskini: %s",
                error,
            )
            break


# =========================================================
# SPEEDTEST
# =========================================================

def run_speedtest():
    selected = get_selected_server()

    command = [
        SPEEDTEST_PATH,
        "--accept-license",
        "--accept-gdpr",
        "--format=json",
        "--progress=no",
    ]

    if selected:
        command.insert(
            1,
            f"--server-id={selected['id']}",
        )

    logger.info("Running: %s", command)

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=180,
        )

        if result.returncode != 0:
            return {
                "success": False,
                "error": (
                    result.stderr.strip()
                    or result.stdout.strip()
                    or "Speedtest gagal."
                ),
            }

        data = json.loads(result.stdout)

        ping = data.get("ping", {})
        download = data.get("download", {})
        upload = data.get("upload", {})
        server = data.get("server", {})
        result_info = data.get("result", {})

        download_mbps = (
            download.get("bandwidth", 0)
            * 8
            / 1_000_000
        )

        upload_mbps = (
            upload.get("bandwidth", 0)
            * 8
            / 1_000_000
        )

        return {
            "success": True,
            "ping": ping,
            "download": download,
            "upload": upload,
            "download_mbps": download_mbps,
            "upload_mbps": upload_mbps,
            "download_bytes": download.get("bytes", 0),
            "upload_bytes": upload.get("bytes", 0),
            "server": server,
            "isp": data.get("isp", "Unknown"),
            "packet_loss": data.get("packetLoss"),
            "timestamp": data.get("timestamp"),
            "result": result_info,
            "selected_server": selected,
        }

    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "error": "Speedtest timeout selepas 180 saat.",
        }

    except json.JSONDecodeError:
        return {
            "success": False,
            "error": "Output Speedtest bukan JSON.",
        }

    except Exception as error:
        logger.exception("Speedtest error")

        return {
            "success": False,
            "error": str(error),
        }


# =========================================================
# FORMAT BYTES
# =========================================================

def format_bytes(value):
    if not value:
        return "0 B"

    value = float(value)

    units = [
        "B",
        "KB",
        "MB",
        "GB",
        "TB",
    ]

    for unit in units:
        if value < 1024:
            return f"{value:.2f} {unit}"

        value /= 1024

    return f"{value:.2f} PB"


# =========================================================
# FORMAT SPEEDTEST RESULT
# =========================================================

def format_result(data):
    if not data.get("success"):
        return (
            "❌ <b>Speedtest gagal</b>\n\n"
            f"<code>{data.get('error', 'Unknown error')}</code>"
        )

    ping = data.get("ping", {})
    download = data.get("download", {})
    upload = data.get("upload", {})
    server = data.get("server", {})
    selected = data.get("selected_server")

    latency = ping.get("latency", 0)
    jitter = ping.get("jitter", 0)
    ping_low = ping.get("low", 0)
    ping_high = ping.get("high", 0)

    download_latency = download.get("latency", {})
    upload_latency = upload.get("latency", {})

    packet_loss = data.get("packet_loss")

    if packet_loss is None:
        packet_loss_text = "Tidak tersedia"
    else:
        packet_loss_text = f"{packet_loss:.2f}%"

    timestamp = data.get("timestamp")

    if timestamp:
        try:
            dt = datetime.fromisoformat(
                timestamp.replace("Z", "+00:00")
            )

            time_text = dt.astimezone().strftime(
                "%d/%m/%Y %H:%M:%S"
            )

        except Exception:
            time_text = timestamp
    else:
        time_text = "Tidak diketahui"

    if selected:
        selected_text = (
            "📌 <b>Mode Server:</b> Manual\n"
            f"└ {selected['name']}\n"
            f"└ ID: {selected['id']}"
        )
    else:
        selected_text = (
            "📌 <b>Mode Server:</b> Auto"
        )

    text = (
        "⚡ <b>SPEEDTEST RESULT</b>\n"
        "\n"
        "📶 <b>Ping</b>\n"
        f"├ Latency: {latency:.2f} ms\n"
        f"├ Jitter: {jitter:.2f} ms\n"
        f"├ Low: {ping_low:.2f} ms\n"
        f"└ High: {ping_high:.2f} ms\n"
        "\n"
        "⬇️ <b>Download</b>\n"
        f"├ Speed: {data['download_mbps']:.2f} Mbps\n"
        f"├ Data: {format_bytes(data['download_bytes'])}\n"
        f"└ Latency IQM: "
        f"{download_latency.get('iqm', 0):.2f} ms\n"
        "\n"
        "⬆️ <b>Upload</b>\n"
        f"├ Speed: {data['upload_mbps']:.2f} Mbps\n"
        f"├ Data: {format_bytes(data['upload_bytes'])}\n"
        f"└ Latency IQM: "
        f"{upload_latency.get('iqm', 0):.2f} ms\n"
        "\n"
        f"📉 <b>Packet Loss:</b> {packet_loss_text}\n"
        "\n"
        "🌐 <b>Network</b>\n"
        f"├ ISP: {data.get('isp', 'Unknown')}\n"
        f"├ Server: {server.get('name', 'Unknown')}\n"
        f"├ Location: {server.get('location', 'Unknown')}\n"
        f"└ Server ID: {server.get('id', 'Unknown')}\n"
        "\n"
        f"{selected_text}\n"
        "\n"
        f"🕒 <b>Masa:</b> {time_text}"
    )

    result_url = data.get("result", {}).get("url")

    if result_url:
        text += (
            "\n\n"
            f'<a href="{result_url}">'
            "🔗 Lihat keputusan Speedtest"
            "</a>"
        )

    return text


# =========================================================
# HOME KEYBOARD
# =========================================================

def main_keyboard():
    selected = get_selected_server()

    if auto_task and not auto_task.done():
        auto_text = "⏹️ Stop Auto"
        auto_callback = "stop_auto"
    else:
        auto_text = "▶️ Start Auto"
        auto_callback = "start_auto"

    if selected:
        server_text = f"🌐 {selected['name']}"
    else:
        server_text = "🌐 Pilih Server"

    keyboard = [
        [
            InlineKeyboardButton(
                "⚡ Speedtest Sekarang",
                callback_data="speedtest",
            )
        ],
        [
            InlineKeyboardButton(
                auto_text,
                callback_data=auto_callback,
            )
        ],
        [
            InlineKeyboardButton(
                server_text,
                callback_data="server_menu",
            )
        ],
        [
            InlineKeyboardButton(
                "📊 Status",
                callback_data="status",
            )
        ],
        [
            InlineKeyboardButton(
                "🛡️ Pi-hole",
                callback_data="pihole_menu",
            )
        ],
    ]

    return InlineKeyboardMarkup(keyboard)


# =========================================================
# HOME MESSAGE
# =========================================================

def home_text():
    selected = get_selected_server()

    if selected:
        server_text = (
            "🌐 <b>Server:</b> "
            f"{selected['name']}\n"
            "🆔 <b>ID:</b> "
            f"<code>{selected['id']}</code>\n"
            "📍 <b>Location:</b> "
            f"{selected['location']}"
        )
    else:
        server_text = (
            "🌐 <b>Server:</b> Auto\n"
            "ℹ️ Ookla akan memilih server secara automatik."
        )

    return (
        "🏠 <b>HOME</b>\n"
        "\n"
        f"{server_text}\n"
        "\n"
        "Pilih fungsi di bawah:"
    )


# =========================================================
# SERVER KEYBOARD
# =========================================================

def server_keyboard():
    servers = get_servers()
    selected = get_selected_server()

    keyboard = []

    for server in servers:
        if selected and server["id"] == selected["id"]:
            prefix = "✅ "
        else:
            prefix = ""

        button_text = (
            f"{prefix}"
            f"{server['name']} "
            f"({server['location']})"
        )

        keyboard.append(
            [
                InlineKeyboardButton(
                    button_text,
                    callback_data=(
                        f"select_server:{server['id']}"
                    ),
                )
            ]
        )

    keyboard.append(
        [
            InlineKeyboardButton(
                "🤖 Auto Server",
                callback_data="server_auto",
            )
        ]
    )

    keyboard.append(
        [
            InlineKeyboardButton(
                "⬅️ Back",
                callback_data="back_server",
            ),
            InlineKeyboardButton(
                "🏠 Home",
                callback_data="home",
            ),
        ]
    )

    return InlineKeyboardMarkup(keyboard)


# =========================================================
# SHOW SERVER MENU
# =========================================================

async def show_server_menu(query):
    await query.edit_message_text(
        "🌐 <b>PILIH SERVER</b>\n\n"
        "⏳ <i>Loading server...</i>",
        parse_mode="HTML",
    )

    await asyncio.sleep(0.5)

    servers = await asyncio.to_thread(
        get_servers
    )

    if not servers:
        await query.edit_message_text(
            "❌ <b>Server tidak dijumpai.</b>\n\n"
            "Ookla tidak dapat memberikan senarai server.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "🏠 Home",
                            callback_data="home",
                        )
                    ]
                ]
            ),
        )
        return

    selected = get_selected_server()

    if selected:
        current = (
            "📌 <b>Server sekarang</b>\n"
            f"├ {selected['name']}\n"
            f"├ ID: <code>{selected['id']}</code>\n"
            f"└ {selected['location']}\n"
        )
    else:
        current = (
            "🤖 <b>Server sekarang:</b> Auto\n"
        )

    text = (
        "🌐 <b>PILIH SERVER</b>\n"
        "\n"
        f"{current}\n"
        "Pilih server:"
    )

    await query.edit_message_text(
        text,
        parse_mode="HTML",
        reply_markup=server_keyboard(),
    )


# =========================================================
# STATUS
# =========================================================

async def show_status(query):
    await query.edit_message_text(
        "📊 <b>STATUS BOT</b>\n\n"
        "⏳ <i>Checking status...</i>",
        parse_mode="HTML",
    )

    await asyncio.sleep(0.5)

    selected = get_selected_server()

    if selected:
        server_text = (
            "🌐 <b>Server</b>\n"
            f"├ {selected['name']}\n"
            f"├ ID: <code>{selected['id']}</code>\n"
            f"└ {selected['location']}"
        )
    else:
        server_text = (
            "🌐 <b>Server:</b> Auto"
        )

    if auto_task and not auto_task.done():
        auto_status = "🟢 Aktif"
    else:
        auto_status = "🔴 Tidak aktif"

    text = (
        "📊 <b>STATUS BOT</b>\n"
        "\n"
        f"⚙️ <b>Auto Speedtest:</b> {auto_status}\n"
        f"⏱️ <b>Interval:</b> "
        f"{INTERVAL_MINUTES} minit\n"
        "\n"
        f"{server_text}\n"
        "\n"
        "🧪 <b>Engine:</b> Ookla Speedtest\n"
        f"📁 <b>Binary:</b> "
        f"<code>{SPEEDTEST_PATH}</code>"
    )

    keyboard = InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "⬅️ Back",
                    callback_data="back_menu",
                ),
                InlineKeyboardButton(
                    "🏠 Home",
                    callback_data="home",
                ),
            ]
        ]
    )

    await query.edit_message_text(
        text,
        parse_mode="HTML",
        reply_markup=keyboard,
    )



# =========================================================
# PI-HOLE MENU
# =========================================================

def pihole_menu_keyboard():
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "📊 Status",
                    callback_data="pihole_status",
                ),
                InlineKeyboardButton(
                    "📈 Statistics",
                    callback_data="pihole_stats",
                ),
            ],
            [
                InlineKeyboardButton(
                    "🔍 Query Log",
                    callback_data="pihole_queries",
                ),
                InlineKeyboardButton(
                    "🚫 Blocked",
                    callback_data="pihole_blocked",
                ),
            ],
            [
                InlineKeyboardButton(
                    "🛡️ Protection ON/OFF",
                    callback_data="pihole_protection",
                )
            ],
            [
                InlineKeyboardButton(
                    "🔄 Refresh",
                    callback_data="pihole_menu",
                )
            ],
            [
                InlineKeyboardButton(
                    "⬅️ Back",
                    callback_data="back_menu",
                ),
                InlineKeyboardButton(
                    "🏠 Home",
                    callback_data="home",
                ),
            ],
        ]
    )


async def show_pihole_menu(query):
    await query.edit_message_text(
        "🛡️ <b>PI-HOLE</b>\n\n"
        "⏳ <i>Checking Pi-hole status...</i>",
        parse_mode="HTML",
    )

    await asyncio.sleep(0.5)

    data = await asyncio.to_thread(
        pihole_get,
        "/api/stats/summary",
    )

    if not data:
        await query.edit_message_text(
            "❌ <b>PI-HOLE</b>\n\n"
            "Tidak dapat berhubung dengan Pi-hole.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "🔄 Cuba Lagi",
                            callback_data="pihole_menu",
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
        return

    queries = data.get("queries", {})

    if isinstance(queries, dict):
        total = queries.get("total", 0)
        blocked = queries.get("blocked", 0)
        percent = queries.get("percent_blocked", 0)
    else:
        total = queries
        blocked = data.get("blocked", 0)
        percent = data.get("blocked_percentage", 0)

    text = (
        "🛡️ <b>PI-HOLE</b>\n"
        "\n"
        "🟢 <b>API:</b> Online\n"
        f"📊 <b>Queries:</b> {total}\n"
        f"🚫 <b>Blocked:</b> {blocked}\n"
        f"📉 <b>Blocked:</b> {percent}%\n"
        "\n"
        "Pilih fungsi di bawah:"
    )

    await query.edit_message_text(
        text,
        parse_mode="HTML",
        reply_markup=pihole_menu_keyboard(),
    )


async def show_pihole_status(query):
    await query.edit_message_text(
        "🛡️ <b>PI-HOLE STATUS</b>\n\n"
        "⏳ <i>Checking Pi-hole status...</i>",
        parse_mode="HTML",
    )

    await asyncio.sleep(0.5)

    data = await asyncio.to_thread(
        pihole_get,
        "/api/stats/summary",
    )

    if not data:
        await query.edit_message_text(
            "❌ <b>Pi-hole tidak dapat dicapai.</b>",
            parse_mode="HTML",
            reply_markup=pihole_menu_keyboard(),
        )
        return

    queries = data.get("queries", {})

    if isinstance(queries, dict):
        total = queries.get("total", 0)
        blocked = queries.get("blocked", 0)
        percent = queries.get("percent_blocked", 0)
    else:
        total = queries
        blocked = data.get("blocked", 0)
        percent = data.get("blocked_percentage", 0)

    text = (
        "🛡️ <b>PI-HOLE STATUS</b>\n"
        "\n"
        "🟢 <b>API:</b> Online\n"
        f"📊 <b>Total Queries:</b> {total}\n"
        f"🚫 <b>Blocked Queries:</b> {blocked}\n"
        f"📉 <b>Blocked Percentage:</b> {percent}%\n"
        "\n"
        "🌐 <b>Pi-hole:</b> "
        "<code>192.168.0.12</code>"
    )

    await query.edit_message_text(
        text,
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(
            [
                [
                    InlineKeyboardButton(
                        "🔄 Refresh",
                        callback_data="pihole_status",
                    )
                ],
                [
                    InlineKeyboardButton(
                        "⬅️ Back",
                        callback_data="pihole_menu",
                    ),
                    InlineKeyboardButton(
                        "🏠 Home",
                        callback_data="home",
                    ),
                ],
            ]
        ),
    )


async def show_pihole_stats(query):
    await query.edit_message_text(
        "📈 <b>PI-HOLE STATISTICS</b>\n\n"
        "⏳ <i>Loading statistics...</i>",
        parse_mode="HTML",
    )

    await asyncio.sleep(0.5)

    data = await asyncio.to_thread(
        pihole_get,
        "/api/stats/summary",
    )

    if not data:
        await query.edit_message_text(
            "❌ <b>Gagal mendapatkan statistics Pi-hole.</b>",
            parse_mode="HTML",
            reply_markup=pihole_menu_keyboard(),
        )
        return

    queries = data.get("queries", {})

    if isinstance(queries, dict):
        total = queries.get("total", 0)
        blocked = queries.get("blocked", 0)
        percent = queries.get("percent_blocked", 0)
        forwarded = queries.get("forwarded", 0)
        cached = queries.get("cached", 0)
        failed = queries.get("failed", 0)
    else:
        total = queries
        blocked = data.get("blocked", 0)
        percent = data.get("blocked_percentage", 0)
        forwarded = 0
        cached = 0
        failed = 0

    text = (
        "📈 <b>PI-HOLE STATISTICS</b>\n"
        "\n"
        f"📊 <b>Total Queries:</b> {total}\n"
        f"🚫 <b>Blocked:</b> {blocked}\n"
        f"📉 <b>Blocked:</b> {percent}%\n"
        f"➡️ <b>Forwarded:</b> {forwarded}\n"
        f"💾 <b>Cached:</b> {cached}\n"
        f"❌ <b>Failed:</b> {failed}\n"
    )

    await query.edit_message_text(
        text,
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(
            [
                [
                    InlineKeyboardButton(
                        "🔄 Refresh",
                        callback_data="pihole_stats",
                    )
                ],
                [
                    InlineKeyboardButton(
                        "⬅️ Back",
                        callback_data="pihole_menu",
                    ),
                    InlineKeyboardButton(
                        "🏠 Home",
                        callback_data="home",
                    ),
                ],
            ]
        ),
    )


async def show_pihole_queries(query, blocked_only=False):
    title = (
        "🚫 <b>BLOCKED QUERIES</b>"
        if blocked_only
        else "🔍 <b>QUERY LOG</b>"
    )

    loading = (
        "Loading blocked queries..."
        if blocked_only
        else "Loading query log..."
    )

    await query.edit_message_text(
        f"{title}\n\n"
        f"⏳ <i>{loading}</i>",
        parse_mode="HTML",
    )

    await asyncio.sleep(0.5)

    data = await asyncio.to_thread(
        pihole_get,
        "/api/queries",
    )

    if not data:
        await query.edit_message_text(
            "❌ <b>Gagal mendapatkan Query Log.</b>",
            parse_mode="HTML",
            reply_markup=pihole_menu_keyboard(),
        )
        return

    queries = data.get("queries", [])

    if not isinstance(queries, list):
        queries = []

    if blocked_only:
        queries = [
            item
            for item in queries
            if isinstance(item, dict)
            and (
                item.get("blocked") is True
                or item.get("blocked") == 1
            )
        ]

    queries = queries[:10]

    if not queries:
        text = (
            f"{title}\n\n"
            "ℹ️ Tiada data dijumpai."
        )
    else:
        lines = [title, ""]

        for item in queries:
            domain = (
                item.get("domain")
                or item.get("name")
                or item.get("query")
                or "Unknown"
            )

            client = (
                item.get("client")
                or item.get("client_name")
                or "-"
            )

            domain = (
                str(domain)
                .replace("<", "&lt;")
                .replace(">", "&gt;")
            )

            client = (
                str(client)
                .replace("<", "&lt;")
                .replace(">", "&gt;")
            )

            lines.append(
                f"• <code>{domain}</code>\n"
                f"  👤 {client}"
            )

        text = "\n".join(lines)

    refresh_callback = (
        "pihole_blocked"
        if blocked_only
        else "pihole_queries"
    )

    await query.edit_message_text(
        text,
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(
            [
                [
                    InlineKeyboardButton(
                        "🔄 Refresh",
                        callback_data=refresh_callback,
                    )
                ],
                [
                    InlineKeyboardButton(
                        "⬅️ Back",
                        callback_data="pihole_menu",
                    ),
                    InlineKeyboardButton(
                        "🏠 Home",
                        callback_data="home",
                    ),
                ],
            ]
        ),
        disable_web_page_preview=True,
    )


async def show_pihole_protection(query):
    await query.edit_message_text(
        "🛡️ <b>PI-HOLE PROTECTION</b>\n\n"
        "⏳ <i>Checking protection...</i>",
        parse_mode="HTML",
    )

    await asyncio.sleep(0.5)

    data = await asyncio.to_thread(
        pihole_get,
        "/api/stats/summary",
    )

    if not data:
        await query.edit_message_text(
            "❌ <b>Gagal mendapatkan status protection.</b>",
            parse_mode="HTML",
            reply_markup=pihole_menu_keyboard(),
        )
        return

    status = data.get("status", {})

    if isinstance(status, dict):
        blocking = status.get(
            "blocking",
            status.get("enabled"),
        )
    else:
        blocking = status

    if blocking is True:
        protection_text = "🟢 Protection sedang ON"
        action_text = "🔴 Turn OFF"
        action_callback = "pihole_off"
    elif blocking is False:
        protection_text = "🔴 Protection sedang OFF"
        action_text = "🟢 Turn ON"
        action_callback = "pihole_on"
    else:
        protection_text = "🟡 Status tidak dapat dikenal"
        action_text = "🔄 Refresh"
        action_callback = "pihole_protection"

    await query.edit_message_text(
        "🛡️ <b>PI-HOLE PROTECTION</b>\n\n"
        f"{protection_text}",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(
            [
                [
                    InlineKeyboardButton(
                        action_text,
                        callback_data=action_callback,
                    )
                ],
                [
                    InlineKeyboardButton(
                        "🔄 Refresh",
                        callback_data="pihole_protection",
                    )
                ],
                [
                    InlineKeyboardButton(
                        "⬅️ Back",
                        callback_data="pihole_menu",
                    ),
                    InlineKeyboardButton(
                        "🏠 Home",
                        callback_data="home",
                    ),
                ],
            ]
        ),
    )


async def set_pihole_protection(query, enabled):
    state = "ON" if enabled else "OFF"

    await query.edit_message_text(
        "🛡️ <b>PI-HOLE PROTECTION</b>\n\n"
        f"⏳ <i>Turning protection {state}...</i>",
        parse_mode="HTML",
    )

    result = await asyncio.to_thread(
        pihole_set_blocking,
        enabled,
    )

    if result is None:
        await query.edit_message_text(
            "❌ <b>Gagal menukar protection Pi-hole.</b>",
            parse_mode="HTML",
            reply_markup=pihole_menu_keyboard(),
        )
        return

    await asyncio.sleep(0.5)

    status_text = "🟢 ON" if enabled else "🔴 OFF"

    await query.edit_message_text(
        "🛡️ <b>PI-HOLE PROTECTION</b>\n\n"
        f"✅ Protection sekarang: <b>{status_text}</b>",
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(
            [
                [
                    InlineKeyboardButton(
                        "🔄 Refresh",
                        callback_data="pihole_protection",
                    )
                ],
                [
                    InlineKeyboardButton(
                        "⬅️ Back",
                        callback_data="pihole_menu",
                    ),
                    InlineKeyboardButton(
                        "🏠 Home",
                        callback_data="home",
                    ),
                ],
            ]
        ),
    )


# =========================================================
# CALLBACK HANDLER
# =========================================================

async def button_handler(
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
):
    global auto_task

    query = update.callback_query
    callback = query.data

    try:
        await query.answer()
    except Exception as error:
        logger.warning(
            "Callback expired: %s",
            error,
        )

    # =====================================================
    # HOME
    # =====================================================

    if callback == "home":
        await query.edit_message_text(
            "🏠 <b>HOME</b>\n\n"
            "⏳ <i>Loading...</i>",
            parse_mode="HTML",
        )

        await asyncio.sleep(0.35)

        await query.edit_message_text(
            home_text(),
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )
        return

    # =====================================================
    # BACK SERVER
    # =====================================================

    if callback == "back_server":
        await query.edit_message_text(
            "⬅️ <b>BACK</b>\n\n"
            "⏳ <i>Loading Home...</i>",
            parse_mode="HTML",
        )

        await asyncio.sleep(0.35)

        await query.edit_message_text(
            home_text(),
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )
        return

    # =====================================================
    # BACK MENU
    # =====================================================

    if callback == "back_menu":
        await query.edit_message_text(
            "⬅️ <b>BACK</b>\n\n"
            "⏳ <i>Loading Home...</i>",
            parse_mode="HTML",
        )

        await asyncio.sleep(0.35)

        await query.edit_message_text(
            home_text(),
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )
        return

    # =====================================================
    # SERVER MENU
    # =====================================================

    if callback == "server_menu":
        await show_server_menu(query)
        return

    # =====================================================
    # SELECT SERVER
    # =====================================================

    if callback.startswith("select_server:"):
        try:
            server_id = int(
                callback.split(":", 1)[1]
            )

        except ValueError:
            await query.answer(
                "Server ID tidak sah.",
                show_alert=True,
            )
            return

        await query.edit_message_text(
            "🌐 <b>SERVER</b>\n\n"
            "⏳ <i>Menukar server...</i>",
            parse_mode="HTML",
        )

        servers = await asyncio.to_thread(
            get_servers
        )

        selected_server = None

        for server in servers:
            if server["id"] == server_id:
                selected_server = server
                break

        if not selected_server:
            await query.edit_message_text(
                "❌ <b>Server tidak dijumpai.</b>",
                parse_mode="HTML",
                reply_markup=InlineKeyboardMarkup(
                    [
                        [
                            InlineKeyboardButton(
                                "⬅️ Back",
                                callback_data="server_menu",
                            )
                        ]
                    ]
                ),
            )
            return

        set_selected_server(
            selected_server
        )

        await asyncio.sleep(0.35)

        text = (
            "✅ <b>SERVER DIPILIH</b>\n"
            "\n"
            f"🌐 <b>{selected_server['name']}</b>\n"
            f"🆔 <b>ID:</b> "
            f"<code>{selected_server['id']}</code>\n"
            f"📍 <b>Location:</b> "
            f"{selected_server['location']}\n"
            f"🇲🇾 <b>Country:</b> "
            f"{selected_server['country']}\n"
            "\n"
            "Speedtest selepas ini akan menggunakan "
            "server ini."
        )

        keyboard = InlineKeyboardMarkup(
            [
                [
                    InlineKeyboardButton(
                        "⚡ Test Sekarang",
                        callback_data="speedtest",
                    )
                ],
                [
                    InlineKeyboardButton(
                        "⬅️ Back",
                        callback_data="server_menu",
                    ),
                    InlineKeyboardButton(
                        "🏠 Home",
                        callback_data="home",
                    ),
                ],
            ]
        )

        await query.edit_message_text(
            text,
            parse_mode="HTML",
            reply_markup=keyboard,
        )

        return

    # =====================================================
    # AUTO SERVER
    # =====================================================

    if callback == "server_auto":
        await query.edit_message_text(
            "🤖 <b>AUTO SERVER</b>\n\n"
            "⏳ <i>Setting Auto Server...</i>",
            parse_mode="HTML",
        )

        await asyncio.sleep(0.5)

        clear_selected_server()

        await query.edit_message_text(
            "🤖 <b>AUTO SERVER</b>\n"
            "\n"
            "✅ Server pilihan telah dibuang.\n\n"
            "Ookla Speedtest akan memilih "
            "server secara automatik.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "⚡ Test Sekarang",
                            callback_data="speedtest",
                        )
                    ],
                    [
                        InlineKeyboardButton(
                            "🌐 Pilih Server",
                            callback_data="server_menu",
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

        return

    # =====================================================
    # SPEEDTEST
    # =====================================================

    if callback == "speedtest":
        try:
            await query.edit_message_text(
                "⚡ <b>SPEEDTEST</b>\n\n"
                "⏳ Testing.",
                parse_mode="HTML",
            )

            await asyncio.sleep(0.45)

            await query.edit_message_text(
                "⚡ <b>SPEEDTEST</b>\n\n"
                "⏳ Testing..",
                parse_mode="HTML",
            )

            await asyncio.sleep(0.45)

            await query.edit_message_text(
                "⚡ <b>SPEEDTEST</b>\n\n"
                "⏳ Testing...",
                parse_mode="HTML",
            )

            await asyncio.sleep(0.45)

            await query.edit_message_text(
                "⚡ <b>SPEEDTEST</b>\n\n"
                "🔄 Connecting to Ookla...",
                parse_mode="HTML",
            )

            data = await asyncio.to_thread(
                run_speedtest
            )

        except Exception as error:
            logger.exception(
                "Speedtest animation error"
            )

            data = {
                "success": False,
                "error": str(error),
            }

        keyboard = InlineKeyboardMarkup(
            [
                [
                    InlineKeyboardButton(
                        "⚡ Test Lagi",
                        callback_data="speedtest",
                    )
                ],
                [
                    InlineKeyboardButton(
                        "🏠 Home",
                        callback_data="home",
                    )
                ],
            ]
        )

        await query.edit_message_text(
            format_result(data),
            parse_mode="HTML",
            disable_web_page_preview=True,
            reply_markup=keyboard,
        )

        return

    # =====================================================
    # START AUTO
    # =====================================================

    if callback == "start_auto":
        if auto_task and not auto_task.done():
            await query.answer(
                "Auto Speedtest sudah berjalan."
            )
            return

        await query.edit_message_text(
            "▶️ <b>START AUTO</b>\n\n"
            "⏳ <i>Starting Auto Speedtest...</i>",
            parse_mode="HTML",
        )

        await asyncio.sleep(0.6)

        auto_task = asyncio.create_task(
            auto_speedtest_job(
                update.effective_chat.id,
                context,
            )
        )

        await query.edit_message_text(
            "▶️ <b>AUTO SPEEDTEST DIMULAKAN</b>\n"
            "\n"
            f"⏱️ Interval: "
            f"setiap {INTERVAL_MINUTES} minit\n"
            "\n"
            "Bot akan menjalankan Speedtest "
            "secara automatik.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "⏹️ Stop Auto",
                            callback_data="stop_auto",
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

        return

    # =====================================================
    # STOP AUTO
    # =====================================================

    if callback == "stop_auto":
        await query.edit_message_text(
            "⏹️ <b>STOP AUTO</b>\n\n"
            "⏳ <i>Stopping Auto Speedtest...</i>",
            parse_mode="HTML",
        )

        await asyncio.sleep(0.5)

        if auto_task and not auto_task.done():
            auto_task.cancel()
            auto_task = None

        await query.edit_message_text(
            "⏹️ <b>AUTO SPEEDTEST DIHENTIKAN</b>\n"
            "\n"
            "Auto Speedtest tidak lagi berjalan.",
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )

        return

    # =====================================================
    # PI-HOLE MENU
    # =====================================================

    if callback == "pihole_menu":
        await show_pihole_menu(query)
        return

    # =====================================================
    # PI-HOLE STATUS
    # =====================================================

    if callback == "pihole_status":
        await show_pihole_status(query)
        return

    # =====================================================
    # PI-HOLE STATISTICS
    # =====================================================

    if callback == "pihole_stats":
        await show_pihole_stats(query)
        return

    # =====================================================
    # PI-HOLE QUERY LOG
    # =====================================================

    if callback == "pihole_queries":
        await show_pihole_queries(
            query,
            blocked_only=False,
        )
        return

    # =====================================================
    # PI-HOLE BLOCKED
    # =====================================================

    if callback == "pihole_blocked":
        await show_pihole_queries(
            query,
            blocked_only=True,
        )
        return

    # =====================================================
    # PI-HOLE PROTECTION
    # =====================================================

    if callback == "pihole_protection":
        await show_pihole_protection(query)
        return

    if callback == "pihole_on":
        await set_pihole_protection(
            query,
            True,
        )
        return

    if callback == "pihole_off":
        await set_pihole_protection(
            query,
            False,
        )
        return

    # =====================================================
    # STATUS
    # =====================================================

    if callback == "status":
        await show_status(query)
        return


# =========================================================
# AUTO SPEEDTEST
# =========================================================

async def auto_speedtest_job(
    chat_id,
    context,
):
    global auto_task

    try:
        while True:
            await asyncio.sleep(
                INTERVAL_MINUTES * 60
            )

            logger.info(
                "Auto Speedtest dimulakan..."
            )

            data = await asyncio.to_thread(
                run_speedtest
            )

            text = (
                "🤖 <b>AUTO SPEEDTEST</b>\n"
                "\n"
                + format_result(data)
            )

            try:
                await context.bot.send_message(
                    chat_id=chat_id,
                    text=text,
                    parse_mode="HTML",
                    disable_web_page_preview=True,
                )

            except Exception as error:
                logger.error(
                    "Gagal hantar auto result: %s",
                    error,
                )

    except asyncio.CancelledError:
        logger.info(
            "Auto Speedtest dihentikan."
        )

    finally:
        auto_task = None


# =========================================================
# /START
# =========================================================

async def start_command(
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
):
    await update.message.reply_text(
        home_text(),
        parse_mode="HTML",
        reply_markup=main_keyboard(),
    )


# =========================================================
# ERROR HANDLER
# =========================================================

async def error_handler(
    update: object,
    context: ContextTypes.DEFAULT_TYPE,
):
    logger.error(
        "Telegram error: %s",
        context.error,
    )


# =========================================================
# MAIN
# =========================================================

def main():
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
        CommandHandler(
            "start",
            start_command,
        )
    )

    application.add_handler(
        CallbackQueryHandler(
            button_handler
        )
    )

    application.add_error_handler(
        error_handler
    )

    logger.info(
        "Speedtest Bot Server sedang bermula..."
    )

    application.run_polling(
        drop_pending_updates=True
    )


if __name__ == "__main__":
    main()
