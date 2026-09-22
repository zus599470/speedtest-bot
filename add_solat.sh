#!/bin/bash

set -e

APP_DIR="$HOME/speedtest-bot"
BOT_FILE="$APP_DIR/bot_server.py"
BACKUP_FILE="$APP_DIR/bot_server.before-solat.py"

echo "========================================"
echo "  ADD WAKTU SOLAT JAKIM"
echo "========================================"

cd "$APP_DIR"

if [ ! -f "$BOT_FILE" ]; then
    echo "❌ bot_server.py tidak dijumpai."
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    cp "$BOT_FILE" "$BACKUP_FILE"
    echo "✅ Backup dibuat:"
    echo "   $BACKUP_FILE"
else
    echo "ℹ️ Backup sudah wujud."
fi

python3 <<'PY'
from pathlib import Path

bot = Path("bot_server.py")
text = bot.read_text(encoding="utf-8")

# ---------------------------------------------------------
# 1. Tambah import urllib jika belum ada
# ---------------------------------------------------------

if "from urllib.parse import urlencode" not in text:
    marker = "from datetime import datetime\n"

    if marker not in text:
        raise SystemExit(
            "❌ Tidak jumpa import datetime. Patch dihentikan."
        )

    text = text.replace(
        marker,
        marker
        + "from urllib.parse import urlencode\n"
        + "from urllib.request import Request, urlopen\n",
        1,
    )

# ---------------------------------------------------------
# 2. Kod Waktu Solat JAKIM
# ---------------------------------------------------------

solat_code = r'''
# =========================================================
# WAKTU SOLAT JAKIM
# =========================================================

JAKIM_SOLAT_API = (
    "https://www.e-solat.gov.my/index.php"
    "?r=esolatApi/takwimsolat"
)

SOLAT_ZONES = {
    "Johor": {
        "JHR01": "Pulau Aur dan Pulau Pemanggil",
        "JHR02": "Johor Bahru, Kota Tinggi, Mersing",
        "JHR03": "Kluang, Pontian",
        "JHR04": "Batu Pahat, Muar, Segamat, Gemas Johor",
    },
    "Kedah": {
        "KDH01": "Kota Setar, Kubang Pasu, Pokok Sena",
        "KDH02": "Kuala Muda, Yan, Pendang",
        "KDH03": "Padang Terap, Sik",
        "KDH04": "Baling",
        "KDH05": "Bandar Baharu, Kulim",
        "KDH06": "Langkawi",
        "KDH07": "Gunung Jerai",
    },
    "Kelantan": {
        "KTN01": "Bachok, Kota Bharu, Machang, Pasir Mas, Pasir Puteh, Tanah Merah, Tumpat, Kuala Krai",
        "KTN03": "Gua Musang, Jeli",
    },
    "Melaka": {
        "MLK01": "Seluruh Negeri Melaka",
    },
    "Negeri Sembilan": {
        "NGS01": "Tampin, Jempol",
        "NGS02": "Jelebu, Kuala Pilah, Port Dickson, Rembau, Seremban",
    },
    "Pahang": {
        "PHG01": "Pulau Tioman",
        "PHG02": "Kuantan, Pekan, Rompin, Muadzam Shah",
        "PHG03": "Jerantut, Temerloh, Maran, Bera, Chenor, Jengka",
        "PHG04": "Bentong, Lipis, Raub",
        "PHG05": "Genting Sempah, Janda Baik, Bukit Tinggi",
        "PHG06": "Cameron Highlands, Genting Highlands, Bukit Fraser",
    },
    "Perlis": {
        "PLS01": "Kangar, Padang Besar, Arau",
    },
    "Pulau Pinang": {
        "PNG01": "Seluruh Negeri Pulau Pinang",
    },
    "Perak": {
        "PRK01": "Tapah, Slim River, Tanjung Malim",
        "PRK02": "Kuala Kangsar, Sungai Siput, Ipoh, Batu Gajah, Kampar",
    },
    "Selangor": {
        "SGR01": "Gombak, Petaling, Sepang, Hulu Langat, Hulu Selangor, Shah Alam",
        "SGR02": "Kuala Selangor, Sabak Bernam",
        "SGR03": "Klang, Kuala Langat",
    },
    "Sarawak": {
        "SWK01": "Limbang, Lawas, Sundar, Trusan",
        "SWK02": "Miri, Niah, Bekenu, Sibuti, Marudi",
        "SWK03": "Pandan, Belaga, Suai, Tatau, Sebauh, Bintulu",
        "SWK04": "Sibu, Mukah, Dalat, Song, Igan, Oya, Balingian, Kanowit, Kapit",
        "SWK05": "Sarikei, Matu, Julau, Rajang, Daro, Bintangor, Belawai",
        "SWK06": "Lubok Antu, Sri Aman, Roban, Debak, Kabong, Lingga, Engkilili, Betong, Spaoh, Pusa, Saratok",
        "SWK07": "Serian, Simunjan, Samarahan, Sebuyau, Meludam",
        "SWK08": "Kuching, Bau, Lundu, Sematan",
        "SWK09": "Zon Khas Kampung Patarikan",
    },
    "Terengganu": {
        "TRG01": "Kuala Terengganu, Marang, Kuala Nerus",
        "TRG02": "Besut, Setiu",
        "TRG03": "Hulu Terengganu",
        "TRG04": "Dungun, Kemaman",
    },
    "Wilayah Persekutuan": {
        "WLY01": "Kuala Lumpur, Putrajaya",
        "WLY02": "Labuan",
    },
}


def get_user_solat_zone(user_id):
    users = load_users()
    info = users.get(str(user_id), {})

    zone = info.get("solat_zone")

    if zone:
        return zone

    return None


def set_user_solat_zone(user_id, zone):
    users = load_users()
    user_id = str(user_id)

    if user_id not in users:
        users[user_id] = {
            "name": "",
            "username": "",
            "status": "pending",
        }

    users[user_id]["solat_zone"] = zone

    save_users(users)


def get_zone_state(zone):
    for state, zones in SOLAT_ZONES.items():
        if zone in zones:
            return state

    return "Tidak diketahui"


def get_zone_name(zone):
    for state, zones in SOLAT_ZONES.items():
        if zone in zones:
            return zones[zone]

    return "Tidak diketahui"


def get_jakim_today(zone):
    url = (
        JAKIM_SOLAT_API
        + "&zone="
        + zone
        + "&period=today"
    )

    request = Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 Telegram-Solat-Bot"
        },
    )

    with urlopen(request, timeout=20) as response:
        raw = response.read().decode("utf-8")

    data = json.loads(raw)

    if data.get("status") != "OK!":
        raise RuntimeError("JAKIM API tidak memberikan data.")

    prayer = data.get("prayerTime", [])

    if not prayer:
        raise RuntimeError("Data waktu solat kosong.")

    return prayer[0]


def clean_time(value):
    if not value:
        return "--:--"

    return str(value)[:5]


def get_next_prayer(prayer):
    from datetime import datetime
    from zoneinfo import ZoneInfo

    now = datetime.now(ZoneInfo("Asia/Kuala_Lumpur"))

    prayers = [
        ("Subuh", prayer.get("fajr")),
        ("Zohor", prayer.get("dhuhr")),
        ("Asar", prayer.get("asr")),
        ("Maghrib", prayer.get("maghrib")),
        ("Isyak", prayer.get("isha")),
    ]

    for name, value in prayers:
        if not value:
            continue

        try:
            hour, minute = map(
                int,
                value[:5].split(":"),
            )
        except Exception:
            continue

        prayer_time = now.replace(
            hour=hour,
            minute=minute,
            second=0,
            microsecond=0,
        )

        if prayer_time > now:
            return name, clean_time(value)

    return "Subuh", clean_time(prayer.get("fajr"))


def solat_menu_keyboard():
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


def solat_state_keyboard():
    states = list(SOLAT_ZONES.keys())

    rows = []

    for i in range(0, len(states), 2):
        row = []

        for state in states[i:i + 2]:
            row.append(
                InlineKeyboardButton(
                    state,
                    callback_data="solat_state_" + state,
                )
            )

        rows.append(row)

    rows.append(
        [
            InlineKeyboardButton(
                "⬅️ Back",
                callback_data="solat_menu",
            ),
            InlineKeyboardButton(
                "🏠 Home",
                callback_data="home",
            ),
        ]
    )

    return InlineKeyboardMarkup(rows)


def solat_zone_keyboard(state):
    zones = SOLAT_ZONES.get(state, {})

    rows = []

    for zone, description in zones.items():
        short_description = description

        if len(short_description) > 48:
            short_description = short_description[:45] + "..."

        rows.append(
            [
                InlineKeyboardButton(
                    f"{zone} - {short_description}",
                    callback_data="solat_zone_" + zone,
                )
            ]
        )

    rows.append(
        [
            InlineKeyboardButton(
                "⬅️ Negeri",
                callback_data="solat_location",
            ),
            InlineKeyboardButton(
                "🏠 Home",
                callback_data="home",
            ),
        ]
    )

    return InlineKeyboardMarkup(rows)


async def show_solat_menu(query):
    zone = get_user_solat_zone(query.from_user.id)

    if not zone:
        await query.edit_message_text(
            "🕌 <b>WAKTU SOLAT</b>\n\n"
            "📍 Lokasi belum ditetapkan.\n\n"
            "Sila pilih lokasi anda terlebih dahulu.",
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "📍 Pilih Lokasi",
                            callback_data="solat_location",
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

    try:
        prayer = await asyncio.to_thread(
            get_jakim_today,
            zone,
        )
    except Exception as error:
        logger.exception(
            "Gagal mengambil waktu solat JAKIM: %s",
            error,
        )

        await query.edit_message_text(
            "🕌 <b>WAKTU SOLAT</b>\n\n"
            "❌ Tidak dapat mengambil data daripada "
            "e-Solat JAKIM sekarang.\n\n"
            "Sila cuba lagi.",
            parse_mode="HTML",
            reply_markup=solat_menu_keyboard(),
        )
        return

    state = get_zone_state(zone)
    zone_name = get_zone_name(zone)

    next_name, next_time = get_next_prayer(prayer)

    text = (
        "🕌 <b>WAKTU SOLAT</b>\n\n"
        f"📍 <b>{state}</b>\n"
        f"🗺️ Zon: <code>{zone}</code>\n"
        f"📌 {zone_name}\n"
        f"📅 {prayer.get('date', '')}\n\n"
        f"🌙 Imsak     <b>{clean_time(prayer.get('imsak'))}</b>\n"
        f"🌅 Subuh     <b>{clean_time(prayer.get('fajr'))}</b>\n"
        f"☀️ Syuruk    <b>{clean_time(prayer.get('syuruk'))}</b>\n"
        f"🕛 Zohor     <b>{clean_time(prayer.get('dhuhr'))}</b>\n"
        f"🌤️ Asar      <b>{clean_time(prayer.get('asr'))}</b>\n"
        f"🌇 Maghrib   <b>{clean_time(prayer.get('maghrib'))}</b>\n"
        f"🌙 Isyak     <b>{clean_time(prayer.get('isha'))}</b>\n\n"
        f"⏭️ Seterusnya: <b>{next_name}</b> "
        f"pada <b>{next_time}</b>\n\n"
        "📡 Sumber: e-Solat JAKIM"
    )

    await query.edit_message_text(
        text,
        parse_mode="HTML",
        reply_markup=solat_menu_keyboard(),
    )


async def show_solat_states(query):
    await query.edit_message_text(
        "📍 <b>PILIH NEGERI</b>\n\n"
        "Pilih negeri untuk melihat zon waktu solat:",
        parse_mode="HTML",
        reply_markup=solat_state_keyboard(),
    )


async def show_solat_zones(query, state):
    if state not in SOLAT_ZONES:
        await query.answer(
            "Negeri tidak dijumpai.",
            show_alert=True,
        )
        return

    await query.edit_message_text(
        f"📍 <b>{state}</b>\n\n"
        "Pilih zon kawasan anda:",
        parse_mode="HTML",
        reply_markup=solat_zone_keyboard(state),
    )


async def select_solat_zone(query, zone):
    valid = any(
        zone in zones
        for zones in SOLAT_ZONES.values()
    )

    if not valid:
        await query.answer(
            "Zon tidak sah.",
            show_alert=True,
        )
        return

    set_user_solat_zone(
        query.from_user.id,
        zone,
    )

    await query.answer(
        f"✅ Lokasi disimpan: {zone}",
        show_alert=False,
    )

    await show_solat_menu(query)
'''

# Insert solat code before main_keyboard.
if "# WAKTU SOLAT JAKIM" not in text:
    marker = "def main_keyboard():"

    if marker not in text:
        raise SystemExit(
            "❌ Tidak jumpa def main_keyboard()."
        )

    text = text.replace(
        marker,
        solat_code
        + "\n\n"
        + marker,
        1,
    )
else:
    print("ℹ️ Kod Waktu Solat sudah ada.")

# ---------------------------------------------------------
# 3. Wrapper main_keyboard supaya menu lama kekal
# ---------------------------------------------------------

if "_original_main_keyboard_for_solat" not in text:

    marker = "def home_text():"

    if marker not in text:
        raise SystemExit(
            "❌ Tidak jumpa def home_text()."
        )

    wrapper = r'''
# Tambah butang Waktu Solat tanpa mengubah menu asal.
_original_main_keyboard_for_solat = main_keyboard


def main_keyboard():
    keyboard = _original_main_keyboard_for_solat()

    rows = [
        list(row)
        for row in keyboard.inline_keyboard
    ]

    if not any(
        button.callback_data == "solat_menu"
        for row in rows
        for button in row
        if button.callback_data
    ):
        rows.append(
            [
                InlineKeyboardButton(
                    "🕌 Waktu Solat",
                    callback_data="solat_menu",
                )
            ]
        )

    return InlineKeyboardMarkup(rows)


'''

    text = text.replace(
        marker,
        wrapper + marker,
        1,
    )
else:
    print("ℹ️ Wrapper main_keyboard sudah ada.")

# ---------------------------------------------------------
# 4. Tambah callback handler
# ---------------------------------------------------------

if '# SOLAT CALLBACKS' not in text:

    marker = "async def button_handler("

    if marker not in text:
        raise SystemExit(
            "❌ Tidak jumpa button_handler()."
        )

    callback_code = r'''
    # =====================================================
    # SOLAT CALLBACKS
    # =====================================================

    if callback == "solat_menu":
        await show_solat_menu(query)
        return

    if callback == "solat_refresh":
        await show_solat_menu(query)
        return

    if callback == "solat_location":
        await show_solat_states(query)
        return

    if callback.startswith("solat_state_"):
        state = callback.replace(
            "solat_state_", "", 1
        )
        await show_solat_zones(query, state)
        return

    if callback.startswith("solat_zone_"):
        zone = callback.replace(
            "solat_zone_", "", 1
        )
        await select_solat_zone(query, zone)
        return

    if callback == "solat_back":
        await query.edit_message_text(
            home_text(),
            parse_mode="HTML",
            reply_markup=main_keyboard(),
        )
        return

'''

    # Find callback assignment inside button_handler.
    start = text.index(marker)
    next_function = text.find(
        "\nasync def ",
        start + len(marker),
    )

    if next_function == -1:
        section = text[start:]
    else:
        section = text[start:next_function]

    possible_assignments = [
        "callback = query.data",
        "callback_data = query.data",
        "data = query.data",
    ]

    assignment = None

    for candidate in possible_assignments:
        if candidate in section:
            assignment = candidate
            break

    if assignment is None:
        raise SystemExit(
            "❌ Tidak jumpa query.data dalam button_handler()."
        )

    # Insert immediately after assignment line.
    pos = text.index(
        assignment,
        start,
    )

    line_end = text.find("\n", pos)

    if line_end == -1:
        raise SystemExit(
            "❌ Gagal mencari akhir baris callback."
        )

    text = (
        text[:line_end + 1]
        + "\n"
        + callback_code
        + text[line_end + 1:]
    )

else:
    print("ℹ️ Callback Waktu Solat sudah ada.")

bot.write_text(text, encoding="utf-8")

print("✅ Patch Waktu Solat siap.")
PY

echo
echo "🔍 Semak syntax..."
python3 -m py_compile bot_server.py

echo
echo "========================================"
echo "✅ WAKTU SOLAT BERJAYA DITAMBAH"
echo "========================================"
echo
echo "Backup:"
echo "  $BACKUP_FILE"
echo
echo "Sekarang restart bot:"
echo
echo "  sudo systemctl restart speedtest-bot"
echo
