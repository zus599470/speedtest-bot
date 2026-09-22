#!/bin/bash

set -e

cd "$HOME/speedtest-bot"

echo "=========================================="
echo "   ADD USER APPROVAL SYSTEM"
echo "=========================================="

# Backup
BACKUP="bot_server.before-approval-$(date +%Y%m%d-%H%M%S).py"
cp bot_server.py "$BACKUP"
echo "[OK] Backup: $BACKUP"

python3 - <<'PY'
from pathlib import Path

path = Path("bot_server.py")
text = path.read_text()

# ---------------------------------------------------------
# 1. Tambah CONFIG
# ---------------------------------------------------------

old = '''SPEEDTEST_PATH = "/usr/bin/speedtest"
INTERVAL_MINUTES = 10
'''

new = '''SPEEDTEST_PATH = "/usr/bin/speedtest"
INTERVAL_MINUTES = 10

# =========================================================
# USER APPROVAL SYSTEM
# =========================================================

ADMIN_IDS = {202940674}

APPROVAL_FILE = Path(__file__).resolve().parent / "users.json"


def load_users():
    if not APPROVAL_FILE.exists():
        return {}

    try:
        with open(APPROVAL_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)

        return data if isinstance(data, dict) else {}

    except Exception:
        return {}


def save_users(users):
    temp_file = APPROVAL_FILE.with_suffix(".tmp")

    with open(temp_file, "w", encoding="utf-8") as f:
        json.dump(users, f, indent=2, ensure_ascii=False)

    temp_file.replace(APPROVAL_FILE)


def get_user_status(user_id):
    user_id = str(user_id)
    users = load_users()

    return users.get(user_id, {}).get("status", "pending")


def is_admin(user_id):
    return user_id in ADMIN_IDS


def is_approved(user_id):
    return is_admin(user_id) or get_user_status(user_id) == "approved"


def register_user(user):
    users = load_users()
    user_id = str(user.id)

    existing = users.get(user_id)

    if existing:
        existing["name"] = user.full_name or ""
        existing["username"] = user.username or ""
        users[user_id] = existing
    else:
        users[user_id] = {
            "name": user.full_name or "",
            "username": user.username or "",
            "status": "pending",
        }

    save_users(users)


def approval_request_keyboard():
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "🔐 Request Access",
                    callback_data="request_access",
                )
            ]
        ]
    )


def admin_keyboard():
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "👥 Manage Users",
                    callback_data="admin_users",
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


def admin_request_keyboard(user_id):
    return InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "✅ Approve",
                    callback_data=f"approve_user_{user_id}",
                ),
                InlineKeyboardButton(
                    "❌ Reject",
                    callback_data=f"reject_user_{user_id}",
                ),
            ]
        ]
    )


async def send_access_request(update, context):
    user = update.effective_user

    register_user(user)

    status = get_user_status(user.id)

    if status == "approved":
        return True

    if status == "rejected":
        await update.message.reply_text(
            "🚫 <b>ACCESS DITOLAK</b>\\n\\n"
            "Permintaan akses anda telah ditolak oleh admin.",
            parse_mode="HTML",
        )
        return False

    if status == "pending":
        await update.message.reply_text(
            "🔐 <b>ACCESS DIPERLUKAN</b>\\n\\n"
            "Anda perlu mendapatkan kelulusan admin "
            "sebelum boleh menggunakan bot ini.\\n\\n"
            "Tekan butang di bawah untuk menghantar "
            "permintaan akses.",
            parse_mode="HTML",
            reply_markup=approval_request_keyboard(),
        )

    return False


async def handle_access_request(query, context):
    user = query.from_user

    register_user(user)

    status = get_user_status(user.id)

    if status == "approved":
        await query.answer(
            "✅ Anda sudah diluluskan.",
            show_alert=True,
        )
        return

    if status == "rejected":
        await query.answer(
            "🚫 Akses anda telah ditolak.",
            show_alert=True,
        )
        return

    users = load_users()
    users[str(user.id)]["status"] = "pending"
    save_users(users)

    username = (
        f"@{user.username}"
        if user.username
        else "(tiada username)"
    )

    message = (
        "🔔 <b>ACCESS REQUEST BARU</b>\\n\\n"
        f"👤 Nama: {user.full_name}\\n"
        f"🔗 Username: {username}\\n"
        f"🆔 ID: <code>{user.id}</code>\\n\\n"
        "Sila pilih tindakan:"
    )

    await context.bot.send_message(
        chat_id=next(iter(ADMIN_IDS)),
        text=message,
        parse_mode="HTML",
        reply_markup=admin_request_keyboard(user.id),
    )

    await query.edit_message_text(
        "⏳ <b>PERMINTAAN DIHANTAR</b>\\n\\n"
        "Permintaan akses anda telah dihantar kepada admin.\\n"
        "Sila tunggu kelulusan.",
        parse_mode="HTML",
    )


async def show_admin_users(query):
    user_id = query.from_user.id

    if not is_admin(user_id):
        await query.answer(
            "🚫 Admin sahaja.",
            show_alert=True,
        )
        return

    users = load_users()

    approved = []
    pending = []
    rejected = []

    for uid, info in users.items():
        status = info.get("status", "pending")
        name = info.get("name", "")
        username = info.get("username", "")

        display = (
            f"• {name}"
            f" {'@' + username if username else ''}"
            f" — <code>{uid}</code>"
        )

        if status == "approved":
            approved.append(display)
        elif status == "rejected":
            rejected.append(display)
        else:
            pending.append(display)

    lines = [
        "👥 <b>USER MANAGEMENT</b>",
        "",
        f"⏳ Pending: <b>{len(pending)}</b>",
        f"✅ Approved: <b>{len(approved)}</b>",
        f"❌ Rejected: <b>{len(rejected)}</b>",
        "",
    ]

    if pending:
        lines.append("<b>⏳ PENDING</b>")
        lines.extend(pending)

    if approved:
        lines.append("")
        lines.append("<b>✅ APPROVED</b>")
        lines.extend(approved)

    if rejected:
        lines.append("")
        lines.append("<b>❌ REJECTED</b>")
        lines.extend(rejected)

    keyboard = InlineKeyboardMarkup(
        [
            [
                InlineKeyboardButton(
                    "🔄 Refresh",
                    callback_data="admin_users",
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
        "\\n".join(lines),
        parse_mode="HTML",
        reply_markup=keyboard,
    )


async def approve_user(query, context, target_id):
    if not is_admin(query.from_user.id):
        await query.answer(
            "🚫 Admin sahaja.",
            show_alert=True,
        )
        return

    users = load_users()
    target_id = str(target_id)

    if target_id not in users:
        await query.answer(
            "User tidak dijumpai.",
            show_alert=True,
        )
        return

    users[target_id]["status"] = "approved"
    save_users(users)

    info = users[target_id]

    await query.edit_message_text(
        "✅ <b>ACCESS APPROVED</b>\\n\\n"
        f"👤 {info.get('name', '')}\\n"
        f"🆔 <code>{target_id}</code>",
        parse_mode="HTML",
    )

    try:
        await context.bot.send_message(
            chat_id=int(target_id),
            text=(
                "✅ <b>ACCESS DILULUSKAN</b>\\n\\n"
                "Permintaan akses anda telah diluluskan.\\n"
                "Tekan /start untuk membuka menu utama."
            ),
            parse_mode="HTML",
        )
    except Exception as error:
        logger.warning(
            "Tidak dapat hantar approval notification: %s",
            error,
        )


async def reject_user(query, context, target_id):
    if not is_admin(query.from_user.id):
        await query.answer(
            "🚫 Admin sahaja.",
            show_alert=True,
        )
        return

    users = load_users()
    target_id = str(target_id)

    if target_id not in users:
        await query.answer(
            "User tidak dijumpai.",
            show_alert=True,
        )
        return

    users[target_id]["status"] = "rejected"
    save_users(users)

    info = users[target_id]

    await query.edit_message_text(
        "❌ <b>ACCESS REJECTED</b>\\n\\n"
        f"👤 {info.get('name', '')}\\n"
        f"🆔 <code>{target_id}</code>",
        parse_mode="HTML",
    )

    try:
        await context.bot.send_message(
            chat_id=int(target_id),
            text=(
                "❌ <b>ACCESS DITOLAK</b>\\n\\n"
                "Permintaan akses anda telah ditolak oleh admin."
            ),
            parse_mode="HTML",
        )
    except Exception as error:
        logger.warning(
            "Tidak dapat hantar rejection notification: %s",
            error,
        )


async def show_access_denied(query):
    await query.edit_message_text(
        "🔐 <b>ACCESS DIPERLUKAN</b>\\n\\n"
        "Akaun anda belum diluluskan.\\n\\n"
        "Tekan butang di bawah untuk meminta akses.",
        parse_mode="HTML",
        reply_markup=approval_request_keyboard(),
    )
'''

if old not in text:
    raise SystemExit("ERROR: CONFIG block tidak dijumpai.")

text = text.replace(old, new, 1)


# ---------------------------------------------------------
# 2. START COMMAND
# ---------------------------------------------------------

old = '''async def start_command(
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
):
    await update.message.reply_text(
        home_text(),
        parse_mode="HTML",
        reply_markup=main_keyboard(),
    )
'''

new = '''async def start_command(
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
):
    user = update.effective_user

    register_user(user)

    if not is_approved(user.id):
        await send_access_request(update, context)
        return

    keyboard = main_keyboard()

    if is_admin(user.id):
        rows = list(keyboard.inline_keyboard)
        rows.append(
            [
                InlineKeyboardButton(
                    "👥 Manage Users",
                    callback_data="admin_users",
                )
            ]
        )
        keyboard = InlineKeyboardMarkup(rows)

    await update.message.reply_text(
        home_text(),
        parse_mode="HTML",
        reply_markup=keyboard,
    )
'''

if old not in text:
    raise SystemExit("ERROR: start_command tidak dijumpai.")

text = text.replace(old, new, 1)


# ---------------------------------------------------------
# 3. BUTTON HANDLER - tambah approval callbacks
# ---------------------------------------------------------

old = '''    try:
        await query.answer()
    except Exception as error:
        logger.warning(
            "Callback expired: %s",
            error,
        )

    if callback == "apk_nuvio":
'''

new = '''    try:
        await query.answer()
    except Exception as error:
        logger.warning(
            "Callback expired: %s",
            error,
        )

    # =====================================================
    # USER APPROVAL SYSTEM
    # =====================================================

    if callback == "request_access":
        await handle_access_request(query, context)
        return

    if callback == "admin_users":
        await show_admin_users(query)
        return

    if callback.startswith("approve_user_"):
        target_id = callback.replace(
            "approve_user_", "", 1
        )
        await approve_user(
            query,
            context,
            target_id,
        )
        return

    if callback.startswith("reject_user_"):
        target_id = callback.replace(
            "reject_user_", "", 1
        )
        await reject_user(
            query,
            context,
            target_id,
        )
        return

    # Semua fungsi bot selepas ini hanya untuk
    # approved users atau admin.
    if not is_approved(query.from_user.id):
        await show_access_denied(query)
        return

    if callback == "apk_nuvio":
'''

if old not in text:
    raise SystemExit("ERROR: button_handler insertion point tidak dijumpai.")

text = text.replace(old, new, 1)


# ---------------------------------------------------------
# 4. Simpan
# ---------------------------------------------------------

path.write_text(text)

print("[OK] bot_server.py telah dipatch.")
PY

echo
echo "[1/4] Syntax check..."
python3 -m py_compile bot_server.py

echo "[2/4] Create users.json..."
if [ ! -f users.json ]; then
    cat > users.json <<'JSON'
{
  "202940674": {
    "name": "Admin",
    "username": "",
    "status": "approved"
  }
}
JSON
fi

chmod 600 users.json

echo "[3/4] Restart bot..."
sudo systemctl restart speedtest-bot

sleep 2

echo "[4/4] Check service..."
sudo systemctl status speedtest-bot --no-pager

echo
echo "=========================================="
echo "   APPROVAL SYSTEM SIAP"
echo "=========================================="
echo "Admin ID : 202940674"
echo "Database : $HOME/speedtest-bot/users.json"
echo "Backup   : $BACKUP"
