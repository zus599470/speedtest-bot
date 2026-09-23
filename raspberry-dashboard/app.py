import json
from urllib.request import Request, urlopen
import ast
from datetime import datetime
from zoneinfo import ZoneInfo
import os
import subprocess
import shutil
import socket
import time
from pathlib import Path
from functools import wraps

import psutil
from flask import (
    Flask,
    request,
    redirect,
    url_for,
    session,
    jsonify,
    send_from_directory,
    render_template_string,
)
from werkzeug.utils import secure_filename


APP_DIR = Path("/home/azam/raspberry-dashboard")
UPLOAD_DIR = Path("/home/azam/telegram-upload")

APP_DIR.mkdir(parents=True, exist_ok=True)
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

app = Flask(__name__)
app.secret_key = os.environ.get(
    "DASHBOARD_SECRET",
    "CHANGE_THIS_SECRET_2026"
)

USERNAME = os.environ.get("DASHBOARD_USER", "admin")
PASSWORD = os.environ.get("DASHBOARD_PASSWORD", "raspberry")


ALLOWED_SERVICES = {
    "speedtest-bot",
    "telegram-bot-api",
    "pihole-FTL",
    "raspberry-dashboard",
    "picloud",
}


def login_required(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        if not session.get("logged_in"):
            if request.path.startswith("/api/"):
                return jsonify({"ok": False, "error": "Unauthorized"}), 401
            return redirect(url_for("login"))
        return func(*args, **kwargs)

    return wrapper


def run_command(command, timeout=20):
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout
        )

        return {
            "returncode": result.returncode,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip()
        }

    except subprocess.TimeoutExpired:
        return {
            "returncode": 124,
            "stdout": "",
            "stderr": "Command timed out"
        }

    except Exception as e:
        return {
            "returncode": 1,
            "stdout": "",
            "stderr": str(e)
        }


def get_temperature():
    temps = psutil.sensors_temperatures()

    for name, entries in temps.items():
        for entry in entries:
            if entry.current:
                return round(entry.current, 1)

    thermal_files = [
        "/sys/class/thermal/thermal_zone0/temp",
    ]

    for file in thermal_files:
        try:
            value = int(Path(file).read_text().strip())
            return round(value / 1000, 1)
        except Exception:
            pass

    return None


def get_uptime():
    try:
        seconds = int(time.time() - psutil.boot_time())

        days = seconds // 86400
        hours = (seconds % 86400) // 3600
        minutes = (seconds % 3600) // 60

        return f"{days}d {hours}h {minutes}m"
    except Exception:
        return "Unknown"


def get_ip_addresses():
    result = []

    try:
        hostname = socket.gethostname()

        for info in socket.getaddrinfo(
            hostname,
            None,
            socket.AF_INET
        ):
            ip = info[4][0]

            if ip != "127.0.0.1" and ip not in result:
                result.append(ip)

    except Exception:
        pass

    return result


def get_tailscale_ip():
    result = run_command("tailscale ip -4")

    if result["returncode"] == 0:
        return result["stdout"]

    return None


def service_status(service):
    if service not in ALLOWED_SERVICES:
        return "unknown"

    result = run_command(
        f"systemctl is-active {service}"
    )

    return result["stdout"] or "unknown"


def get_disk():
    usage = shutil.disk_usage("/")

    total = usage.total
    used = usage.used
    free = usage.free

    return {
        "total": total,
        "used": used,
        "free": free,
        "percent": round((used / total) * 100, 1)
    }


def bytes_to_gb(value):
    return round(value / 1024 / 1024 / 1024, 2)


@app.route("/")
@login_required
def index():

    html = r"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport"
      content="width=device-width, initial-scale=1.0">

<title>Raspberry Pi Control Center</title>

<style>

* {
    box-sizing: border-box;
}

body {
    margin: 0;
    font-family:
        Inter,
        system-ui,
        -apple-system,
        BlinkMacSystemFont,
        "Segoe UI",
        sans-serif;

    background: #090d13;
    color: #f1f5f9;
}

.topbar {
    background: #111827;
    border-bottom: 1px solid #263244;
    padding: 18px 24px;

    display: flex;
    justify-content: space-between;
    align-items: center;

    position: sticky;
    top: 0;
    z-index: 10;
}

.logo {
    font-size: 20px;
    font-weight: 800;
}

.subtitle {
    color: #94a3b8;
    font-size: 12px;
    margin-top: 3px;
}

.logout {
    color: #fff;
    background: #dc2626;
    text-decoration: none;
    padding: 9px 14px;
    border-radius: 8px;
    font-size: 13px;
}

.layout {
    display: flex;
    min-height: calc(100vh - 70px);
}

.sidebar {
    width: 220px;
    background: #0d131d;
    border-right: 1px solid #263244;
    padding: 18px;
}

.nav {
    display: block;
    width: 100%;
    border: 0;
    background: transparent;
    color: #cbd5e1;
    text-align: left;
    padding: 12px;
    margin-bottom: 6px;
    border-radius: 8px;
    cursor: pointer;
    font-size: 14px;
}

.nav:hover,
.nav.active {
    background: #1e293b;
    color: white;
}

.content {
    flex: 1;
    padding: 24px;
    min-width: 0;
}

.page {
    display: none;
}

.page.active {
    display: block;
}

h1 {
    margin-top: 0;
    font-size: 26px;
}

h2 {
    font-size: 19px;
}

.grid {
    display: grid;
    grid-template-columns:
        repeat(auto-fit, minmax(210px, 1fr));

    gap: 16px;
}

.card {
    background: #111827;
    border: 1px solid #263244;
    border-radius: 14px;
    padding: 18px;
}

.card-title {
    color: #94a3b8;
    font-size: 13px;
}

.card-value {
    margin-top: 8px;
    font-size: 25px;
    font-weight: 800;
}

.small {
    color: #94a3b8;
    font-size: 12px;
}

.status {
    display: inline-block;
    padding: 5px 9px;
    border-radius: 999px;
    font-size: 12px;
}

.online {
    background: #064e3b;
    color: #6ee7b7;
}

.offline {
    background: #450a0a;
    color: #fca5a5;
}

.btn {
    border: 0;
    border-radius: 8px;
    padding: 10px 14px;
    cursor: pointer;
    color: white;
    background: #2563eb;
    margin: 4px;
}

.btn.red {
    background: #dc2626;
}

.btn.green {
    background: #059669;
}

.btn.gray {
    background: #475569;
}

.btn:hover {
    opacity: .88;
}

table {
    width: 100%;
    border-collapse: collapse;
}

th,
td {
    padding: 11px;
    border-bottom: 1px solid #263244;
    text-align: left;
    font-size: 13px;
}

input[type=file] {
    width: 100%;
    padding: 12px;
    background: #0f172a;
    color: white;
    border: 1px solid #334155;
    border-radius: 8px;
}

.progress {
    height: 18px;
    background: #1e293b;
    border-radius: 10px;
    overflow: hidden;
    margin-top: 12px;
}

.progress-bar {
    height: 100%;
    width: 0%;
    background: #2563eb;
    transition: width .2s;
}

.log {
    white-space: pre-wrap;
    background: #020617;
    border: 1px solid #263244;
    padding: 14px;
    border-radius: 8px;
    min-height: 100px;
    color: #cbd5e1;
    font-family: monospace;
    font-size: 12px;
}

@media(max-width: 800px) {

    .layout {
        display: block;
    }

    .sidebar {
        width: 100%;
        display: flex;
        overflow-x: auto;
        gap: 5px;
    }

    .nav {
        min-width: max-content;
        margin: 0;
    }

    .content {
        padding: 15px;
    }
}

</style>
</head>

<body>

<div class="topbar">

    <div>
        <div class="logo">
            🍓 Raspberry Pi Control Center
        </div>

        <div class="subtitle">
            Server management dashboard
        </div>
    </div>

    <a class="logout" href="/logout">
        Logout
    </a>

</div>

<div class="layout">

<div class="sidebar">

<button class="nav active" data-page="dashboard">
🏠 Dashboard
</button>

<button class="nav" data-page="pihole">
🛡️ Pi-hole
</button>

<button class="nav" data-page="speedtest">
⚡ Speedtest
</button>

<button class="nav" data-page="files">
📁 File Manager
</button>

<button class="nav" data-page="telegram">
🤖 Telegram
</button>

<button class="nav" data-page="solat">
🕌 Waktu Solat
</button>

<button class="nav" data-page="system">
🖥️ System
</button>

<button class="nav" data-page="manage-device">
⚙️ Manage Device
</button>

</div>

<div class="content">

<!-- DASHBOARD -->

<section id="dashboard" class="page active">

<h1>Dashboard</h1>

<div class="grid">

<div class="card">
<div class="card-title">CPU</div>
<div class="card-value" id="cpu">--</div>
</div>

<div class="card">
<div class="card-title">RAM</div>
<div class="card-value" id="ram">--</div>
</div>

<div class="card">
<div class="card-title">Temperature</div>
<div class="card-value" id="temp">--</div>
</div>

<div class="card">
<div class="card-title">Storage</div>
<div class="card-value" id="storage">--</div>
</div>

<div class="card">
<div class="card-title">Uptime</div>
<div class="card-value" id="uptime">--</div>
</div>

<div class="card">
<div class="card-title">Tailscale</div>
<div class="card-value" id="tailscale">--</div>
</div>

</div>

<h2>Services</h2>

<div class="card">

<table>

<thead>
<tr>
<th>Service</th>
<th>Status</th>
</tr>
</thead>

<tbody id="services"></tbody>

</table>

</div>

</section>


<!-- PIHOLE -->

<section id="pihole" class="page">

<h1>🛡️ Pi-hole</h1>

<div class="grid">

<div class="card">
<div class="card-title">Pi-hole FTL</div>
<div class="card-value" id="piholeStatus">Checking...</div>
</div>

<div class="card">
<div class="card-title">Blocking</div>
<div class="card-value" id="piholeBlocking">Checking...</div>
</div>

<div class="card">
<div class="card-title">Queries</div>
<div class="card-value" id="piholeQueries">--</div>
</div>

<div class="card">
<div class="card-title">Blocked</div>
<div class="card-value" id="piholeBlocked">--</div>
</div>

<div class="card">
<div class="card-title">% Blocked</div>
<div class="card-value" id="piholePercent">--</div>
</div>

<div class="card">
<div class="card-title">Unique Domains</div>
<div class="card-value" id="piholeDomains">--</div>
</div>

<div class="card">
<div class="card-title">Active Clients</div>
<div class="card-value" id="piholeClients">--</div>
</div>

<div class="card">
<div class="card-title">Gravity Domains</div>
<div class="card-value" id="piholeGravity">--</div>
</div>

</div>

<br>

<div class="card">

<h2>⚙️ Controls</h2>

<button class="btn" onclick="loadPihole()">
🔄 Refresh
</button>

<button class="btn green" onclick="piholeCommand('enable')">
🟢 Enable
</button>

<button class="btn red" onclick="piholeCommand('disable')">
🔴 Disable
</button>

<div class="log" id="piholeLog">
Ready.
</div>

</div>

<br>

<div class="card">

<h2>🔎 Query Log</h2>

<button class="btn" onclick="loadPiholeQueries()">
🔄 Refresh Queries
</button>

<div style="overflow-x:auto">

<table>

<thead>
<tr>
<th>Domain</th>
<th>Client</th>
<th>Status</th>
<th>Type</th>
<th>Upstream</th>
</tr>
</thead>

<tbody id="piholeQueriesTable">

<tr>
<td colspan="5">Loading...</td>
</tr>

</tbody>

</table>

</div>

</div>

</section>


<!-- SPEEDTEST -->

<section id="speedtest" class="page">

<h1>⚡ Speedtest</h1>

<div class="card">

<button class="btn green"
onclick="runSpeedtest()">
🚀 Start Speedtest
</button>

<div class="log" id="speedtestResult">
Ready.
</div>

</div>

</section>


<!-- FILES -->

<section id="files" class="page">

<h1>📁 File Manager</h1>

<div class="card">

<input
type="file"
id="uploadFile"
>

<button class="btn green"
onclick="uploadFile()">
📤 Upload
</button>

<div class="progress">
<div
class="progress-bar"
id="uploadProgress">
</div>
</div>

<div id="uploadStatus"
class="small">
Ready.
</div>

</div>

<br>

<div class="card">

<h2>Files</h2>

<table>

<thead>
<tr>
<th>Name</th>
<th>Size</th>
<th>Action</th>
</tr>
</thead>

<tbody id="fileList"></tbody>

</table>

</div>

</section>


<!-- TELEGRAM -->

<section id="telegram" class="page">

<h1>🤖 Telegram</h1>

<div class="card">

<table>

<tbody>

<tr>
<td>Speedtest Bot</td>
<td id="telegramBot">Checking...</td>
</tr>

<tr>
<td>Local Bot API</td>
<td id="telegramApi">Checking...</td>
</tr>

</tbody>

</table>

<br>

<button class="btn"
onclick="serviceAction('speedtest-bot','restart')">
🔄 Restart Bot
</button>

<button class="btn"
onclick="serviceAction('telegram-bot-api','restart')">
🔄 Restart Local API
</button>

</div>


<!-- TELEGRAM USER MANAGEMENT -->

<section class="card" style="margin-top:20px">

<h2>👥 Telegram User Management</h2>

<div id="telegramUserStats" class="grid">
    Loading...
</div>

<br>

<div id="telegramUsers">
    Loading users...
</div>

</section>

</section>


<!-- SOLAT -->

<section id="solat" class="page">

<h1>🕌 Waktu Solat</h1>

<div class="card">

<p>
Dashboard ini disediakan untuk disambungkan
kepada sistem waktu solat JAKIM yang sedia ada.
</p>

<div id="solatData">
Loading...
</div>

</div>

</section>


<!-- SYSTEM -->

<section id="system" class="page">

<h1>🖥️ System</h1>

<div class="card">

<h2>Services</h2>

<div id="systemServices"></div>

</div>

<br>

<div class="card">

<h2>Power</h2>

<button
class="btn"
onclick="powerAction('reboot')">
🔄 Reboot Raspberry Pi
</button>

<button
class="btn red"
onclick="powerAction('poweroff')">
⛔ Shutdown Raspberry Pi
</button>

</div>

</section>


<!-- MANAGE DEVICE -->

<section id="manage-device" class="page">

<h1>⚙️ Manage Device</h1>

<div class="card">

<h2>📊 Raspberry Pi</h2>

<div id="deviceInfo">
Loading...
</div>

</div>

<br>

<div class="card">

<h2>🔧 Services</h2>

<div id="deviceServices">
Loading...
</div>

</div>

<br>

<div class="card">

<h2>⚡ Power</h2>

<button
class="btn"
onclick="powerAction('reboot')">
🔄 Reboot Raspberry Pi
</button>

<button
class="btn red"
onclick="powerAction('poweroff')">
⛔ Shutdown Raspberry Pi
</button>

</div>

</section>

</div>
</div>


<script>

const pages = document.querySelectorAll(".page");
const navs = document.querySelectorAll(".nav");

navs.forEach(button => {

    button.addEventListener("click", () => {

        navs.forEach(x =>
            x.classList.remove("active")
        );

        pages.forEach(x =>
            x.classList.remove("active")
        );

        button.classList.add("active");

        document
            .getElementById(button.dataset.page)
            .classList.add("active");

        if (button.dataset.page === "files") {
            loadFiles();
        }

        if (button.dataset.page === "pihole") {
            loadPiHole();
        }

        if (button.dataset.page === "telegram") {
            loadServices();
            loadTelegramUsers();
        }

        if (button.dataset.page === "manage-device") {
            loadManageDevice();
        }

    });

});




async function loadTelegramUsers() {

    const stats = document.getElementById("telegramUserStats");
    const container = document.getElementById("telegramUsers");

    if (!stats || !container) {
        return;
    }

    stats.innerHTML = "Loading...";
    container.innerHTML = "Loading users...";

    try {

        const response = await api("/api/telegram/users");

        const users = response.users || [];

        const counts = {
            approved: 0,
            pending: 0,
            rejected: 0,
            revoked: 0,
            blocked: 0
        };

        users.forEach(user => {

            const status =
                user.status || "pending";

            if (counts[status] !== undefined) {
                counts[status]++;
            }

        });

        stats.innerHTML = `
            <div class="card">
                <b>🟢 Approved</b><br>
                <strong>${counts.approved}</strong>
            </div>

            <div class="card">
                <b>🟡 Pending</b><br>
                <strong>${counts.pending}</strong>
            </div>

            <div class="card">
                <b>⚪ Rejected</b><br>
                <strong>${counts.rejected}</strong>
            </div>

            <div class="card">
                <b>🚫 Revoked</b><br>
                <strong>${counts.revoked}</strong>
            </div>

            <div class="card">
                <b>🔴 Blocked</b><br>
                <strong>${counts.blocked}</strong>
            </div>
        `;

        if (!users.length) {

            container.innerHTML =
                "<p>Tiada user Telegram.</p>";

            return;
        }

        let html = "";

        users.forEach(user => {

            const id = user.id || "";
            const name = user.name || "Tiada nama";
            const username = user.username
                ? "@" + user.username
                : "Tiada username";

            const status =
                user.status || "pending";

            let statusText = "🟡 PENDING";

            if (status === "approved")
                statusText = "🟢 APPROVED";

            if (status === "rejected")
                statusText = "⚪ REJECTED";

            if (status === "revoked")
                statusText = "🚫 REVOKED";

            if (status === "blocked")
                statusText = "🔴 BLOCKED";

            const isAdmin =
                String(id) === "202940674";

            let buttons = "";

            if (!isAdmin) {

                if (status !== "approved") {

                    buttons += `
                        <button class="btn"
                            onclick="telegramUserStatus('${id}','approved')">
                            ✅ Approve
                        </button>
                    `;
                }

                if (status !== "rejected") {

                    buttons += `
                        <button class="btn"
                            onclick="telegramUserStatus('${id}','rejected')">
                            ❌ Reject
                        </button>
                    `;
                }

                if (status !== "revoked") {

                    buttons += `
                        <button class="btn"
                            onclick="telegramUserStatus('${id}','revoked')">
                            🚫 Revoke
                        </button>
                    `;
                }

                if (status !== "blocked") {

                    buttons += `
                        <button class="btn red"
                            onclick="telegramUserStatus('${id}','blocked')">
                            🔴 Block
                        </button>
                    `;
                }

                if (status === "blocked") {

                    buttons += `
                        <button class="btn"
                            onclick="telegramUserStatus('${id}','approved')">
                            🔓 Unblock
                        </button>
                    `;
                }

                if (status === "rejected") {

                    buttons += `
                        <button class="btn"
                            onclick="telegramUserStatus('${id}','approved')">
                            🔄 Reapprove
                        </button>
                    `;
                }

            } else {

                buttons = `
                    <span>
                        🔐 <b>Admin utama</b>
                    </span>
                `;
            }

            html += `
                <div class="card" style="margin-bottom:15px">

                    <h3>
                        👤 ${escapeHtml(name)}
                    </h3>

                    <div>
                        <b>Telegram ID:</b>
                        ${escapeHtml(String(id))}
                    </div>

                    <div>
                        <b>Username:</b>
                        ${escapeHtml(username)}
                    </div>

                    <div style="margin-top:8px">
                        <b>Status:</b>
                        ${statusText}
                    </div>

                    <div style="margin-top:12px">
                        ${buttons}
                    </div>

                </div>
            `;

        });

        container.innerHTML = html;

    } catch (error) {

        stats.innerHTML =
            `<p style="color:red">
                ❌ Gagal mendapatkan user Telegram.
            </p>`;

        container.innerHTML =
            `<p style="color:red">
                ❌ ${escapeHtml(error.message)}
            </p>`;

    }

}


async function telegramUserStatus(userId, status) {

    let actionText = status;

    if (status === "approved")
        actionText = "approve";

    if (status === "rejected")
        actionText = "reject";

    if (status === "revoked")
        actionText = "revoke";

    if (status === "blocked")
        actionText = "block";

    if (!confirm(
        "Anda pasti mahu " +
        actionText +
        " user Telegram " +
        userId +
        "?"
    )) {
        return;
    }

    try {

        const response = await fetch(
            "/api/telegram/user/" +
            encodeURIComponent(userId) +
            "/status",
            {
                method: "POST",

                headers: {
                    "Content-Type": "application/json"
                },

                body: JSON.stringify({
                    status: status
                })
            }
        );

        const result =
            await response.json();

        if (!response.ok) {

            throw new Error(
                result.error ||
                "Operasi gagal."
            );

        }

        alert(
            "✅ " +
            (result.message || "Status berjaya diubah.")
        );

        loadTelegramUsers();

    } catch (error) {

        alert(
            "❌ " +
            error.message
        );

    }

}


function escapeHtml(value) {

    return String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");

}


async function loadManageDevice() {

    const info = document.getElementById("deviceInfo");
    const services = document.getElementById("deviceServices");

    info.innerHTML = "Loading...";
    services.innerHTML = "Loading...";

    try {

        const [systemResponse, serviceResponse] = await Promise.all([
            api("/api/system"),
            api("/api/services")
        ]);

        const system = systemResponse;
        const serviceData = serviceResponse;

        const ips = system.ips || {};

        info.innerHTML = `
            <div class="grid">

                <div class="card">
                    <b>CPU</b><br>
                    ${system.cpu ?? "-"}%
                </div>

                <div class="card">
                    <b>RAM</b><br>
                    ${system.ram ?? "-"}%
                </div>

                <div class="card">
                    <b>Storage</b><br>
                    ${(() => {
                        const disk = system.disk || {};

                        const usedBytes =
                            Number(
                                disk.used_gb ??
                                disk.used ??
                                0
                            );

                        const totalBytes =
                            Number(
                                disk.total_gb ??
                                disk.total ??
                                0
                            );

                        const percent =
                            Number(
                                disk.percent ??
                                0
                            );

                        const used =
                            usedBytes / (1024 ** 3);

                        const total =
                            totalBytes / (1024 ** 3);

                        if (total > 0) {
                            return `${used.toFixed(1)} / ${total.toFixed(1)} GB (${percent.toFixed(1)}%)`;
                        }

                        return `${percent.toFixed(1)}%`;
                    })()}
                </div>

                <div class="card">
                    <b>Temperature</b><br>
                    ${system.temperature ?? "-"} °C
                </div>

                <div class="card">
                    <b>Uptime</b><br>
                    ${system.uptime ?? "-"}
                </div>

                <div class="card">
                    <b>LAN IP</b><br>
                    ${Array.isArray(ips)
                        ? ips.join("<br>")
                        : (ips || "-")}
                </div>

                <div class="card">
                    <b>Tailscale IP</b><br>
                    ${system.tailscale || "-"}
                </div>

            </div>
        `;

        let html = "";

        const serviceNames = [
            ["speedtest-bot", "⚡ Speedtest Bot"],
            ["telegram-bot-api", "🤖 Telegram Bot API"],
            ["pihole-FTL", "🛡️ Pi-hole"],
            ["picloud", "☁️ PiCloud"],
            ["raspberry-dashboard", "🖥️ Dashboard"]
        ];

        for (const [service, label] of serviceNames) {

            const status = serviceData[service] ?? "unknown";

            const running =
                status === "active" ||
                status === "running" ||
                status === true;

            html += `
                <div class="card" style="margin-bottom:10px">

                    <strong>${label}</strong>

                    <span style="margin-left:10px">
                        ${running ? "🟢 Running" : "🔴 Stopped"}
                    </span>

                    <br><br>

                    <button class="btn"
                        onclick="manageService('${service}','start')">
                        ▶️ Start
                    </button>

                    <button class="btn"
                        onclick="manageService('${service}','restart')">
                        🔄 Restart
                    </button>

                    <button class="btn red"
                        onclick="manageService('${service}','stop')">
                        ⛔ Stop
                    </button>

                </div>
            `;
        }

        services.innerHTML = html;

    } catch (error) {

        info.innerHTML =
            `<p style="color:red">❌ ${error.message}</p>`;

        services.innerHTML =
            `<p style="color:red">
                ❌ Gagal mendapatkan status service.
            </p>`;
    }
}


async function manageService(service, action) {

    if (!confirm(
        "Anda pasti mahu " +
        action +
        " service " +
        service +
        "?"
    )) {
        return;
    }

    try {

        const response = await fetch("/api/service", {

            method: "POST",

            headers: {
                "Content-Type": "application/json"
            },

            body: JSON.stringify({
                service: service,
                action: action
            })

        });

        const result = await response.json();

        if (!response.ok) {
            throw new Error(
                result.error || "Operation gagal"
            );
        }

        alert("✅ " + result.message);

        loadManageDevice();

    } catch (error) {

        alert("❌ " + error.message);

    }

}


async function api(url, options = {}) {

    const response = await fetch(url, options);

    if (!response.ok) {
        throw new Error(
            "HTTP " + response.status
        );
    }

    return response.json();
}


async function loadSystem() {

    try {

        const data =
            await api("/api/system");

        document.getElementById("cpu").textContent =
            data.cpu + "%";

        document.getElementById("ram").textContent =
            data.ram + "%";

        document.getElementById("temp").textContent =
            data.temperature
                ? data.temperature + " °C"
                : "N/A";

        const disk = data.disk || {};

        const usedBytes =
            Number(disk.used_gb ?? disk.used ?? 0);

        const totalBytes =
            Number(disk.total_gb ?? disk.total ?? 0);

        const used =
            usedBytes / (1024 ** 3);

        const total =
            totalBytes / (1024 ** 3);

        const percent =
            Number(disk.percent ?? 0);

        if (total > 0) {

            document.getElementById("storage").textContent =
                `${used.toFixed(1)} / ${total.toFixed(1)} GB (${percent.toFixed(1)}%)`;

        } else {

            document.getElementById("storage").textContent =
                `${percent.toFixed(1)}%`;

        }

        document.getElementById("uptime").textContent =
            data.uptime;

        document.getElementById("tailscale").textContent =
            data.tailscale || "N/A";

        let html = "";

        for (const [name, status] of
             Object.entries(data.services)) {

            const cls =
                status === "active"
                ? "online"
                : "offline";

            html += `
            <tr>
                <td>${name}</td>
                <td>
                    <span class="status ${cls}">
                        ${status}
                    </span>
                </td>
            </tr>`;
        }

        document.getElementById(
            "services"
        ).innerHTML = html;

    } catch (error) {

        console.error(error);

    }

}


async function loadServices() {

    try {

        const data =
            await api("/api/services");

        let html = "";

        for (const [name, status] of
             Object.entries(data)) {

            const cls =
                status === "active"
                ? "online"
                : "offline";

            html += `
            <div class="card"
                 style="margin-bottom:10px">

                <b>${name}</b>

                <span class="status ${cls}">
                    ${status}
                </span>

                <br>

                <button
                class="btn"
                onclick="serviceAction('${name}','restart')">
                Restart
                </button>

                <button
                class="btn gray"
                onclick="serviceAction('${name}','stop')">
                Stop
                </button>

                <button
                class="btn green"
                onclick="serviceAction('${name}','start')">
                Start
                </button>

            </div>`;
        }

        document.getElementById(
            "systemServices"
        ).innerHTML = html;

        document.getElementById(
            "telegramBot"
        ).innerHTML =
            data["speedtest-bot"] === "active"
            ? '<span class="status online">ONLINE</span>'
            : '<span class="status offline">OFFLINE</span>';

        document.getElementById(
            "telegramApi"
        ).innerHTML =
            data["telegram-bot-api"] === "active"
            ? '<span class="status online">ONLINE</span>'
            : '<span class="status offline">OFFLINE</span>';

    } catch (error) {

        console.error(error);

    }

}


async function serviceAction(service, action) {

    if (!confirm(
        `${action.toUpperCase()} ${service}?`
    )) {
        return;
    }

    try {

        const result = await api(
            "/api/service",
            {
                method: "POST",

                headers: {
                    "Content-Type":
                        "application/json"
                },

                body: JSON.stringify({
                    service,
                    action
                })
            }
        );

        alert(
            result.message ||
            result.error ||
            "Done"
        );

        loadSystem();
        loadServices();

    } catch (error) {

        alert(error.message);

    }

}


async function powerAction(action) {

    const message =
        action === "reboot"
        ? "Reboot Raspberry Pi?"
        : "Shutdown Raspberry Pi?";

    if (!confirm(message)) {
        return;
    }

    try {

        const result = await api(
            "/api/power",
            {
                method: "POST",

                headers: {
                    "Content-Type":
                        "application/json"
                },

                body: JSON.stringify({
                    action
                })
            }
        );

        alert(
            result.message ||
            result.error ||
            "Command sent"
        );

    } catch (error) {

        alert(error.message);

    }

}


async function loadFiles() {

    try {

        const data =
            await api("/api/files");

        let html = "";

        for (const file of data.files) {

            html += `
            <tr>

                <td>
                    ${escapeHtml(file.name)}
                </td>

                <td>
                    ${file.size}
                </td>

                <td>

                    <a
                    class="btn"
                    href="/download/${encodeURIComponent(file.name)}">
                    Download
                    </a>

                    <button
                    class="btn red"
                    onclick="deleteFile('${escapeJs(file.name)}')">
                    Delete
                    </button>

                </td>

            </tr>`;
        }

        document.getElementById(
            "fileList"
        ).innerHTML =
            html ||
            "<tr><td colspan='3'>No files</td></tr>";

    } catch (error) {

        console.error(error);

    }

}


function escapeHtml(value) {

    return value
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");

}


function escapeJs(value) {

    return value
        .replaceAll("\\", "\\\\")
        .replaceAll("'", "\\'");

}


function uploadFile() {

    const input =
        document.getElementById(
            "uploadFile"
        );

    if (!input.files.length) {

        alert("Pilih file dahulu.");

        return;
    }

    const file = input.files[0];

    const xhr = new XMLHttpRequest();

    xhr.open(
        "POST",
        "/api/upload"
    );

    const progress =
        document.getElementById(
            "uploadProgress"
        );

    const status =
        document.getElementById(
            "uploadStatus"
        );

    xhr.upload.onprogress =
        function(event) {

            if (!event.lengthComputable) {
                return;
            }

            const percent =
                Math.round(
                    event.loaded /
                    event.total *
                    100
                );

            progress.style.width =
                percent + "%";

            status.textContent =
                percent + "% uploaded";

        };


    xhr.onload = function() {

        if (
            xhr.status >= 200 &&
            xhr.status < 300
        ) {

            progress.style.width =
                "100%";

            status.textContent =
                "Upload selesai.";

            loadFiles();

        } else {

            status.textContent =
                "Upload gagal.";

        }

    };


    xhr.onerror = function() {

        status.textContent =
            "Connection error.";

    };


    const form =
        new FormData();

    form.append(
        "file",
        file
    );

    xhr.send(form);

}


async function deleteFile(name) {

    if (!confirm(
        "Delete " + name + "?"
    )) {
        return;
    }

    try {

        const result =
            await api(
                "/api/files/" +
                encodeURIComponent(name),
                {
                    method: "DELETE"
                }
            );

        alert(
            result.message ||
            result.error ||
            "Done"
        );

        loadFiles();

    } catch (error) {

        alert(error.message);

    }

}


async function runSpeedtest() {

    const output =
        document.getElementById(
            "speedtestResult"
        );

    output.textContent =
        "🚀 Running speedtest...";

    try {

        const data =
            await api(
                "/api/speedtest",
                {
                    method: "POST"
                }
            );

        let result = data;

        /*
         * Backend mungkin pulangkan JSON
         * dalam data.output.
         */
        if (
            typeof data.output === "string"
        ) {

            try {

                result =
                    JSON.parse(
                        data.output
                    );

            } catch (e) {

                output.textContent =
                    data.output ||
                    data.error ||
                    "Speedtest gagal.";

                return;
            }
        }

        /*
         * Kalau backend pulangkan
         * wrapper {result: {...}}
         */
        if (
            result.result &&
            typeof result.result === "object"
        ) {
            result = result;
        }

        const ping =
            result.ping || {};

        const download =
            result.download || {};

        const upload =
            result.upload || {};

        const server =
            result.server || {};

        const interfaceInfo =
            result.interface || {};

        const downloadMbps =
            Number(
                download.bandwidth || 0
            ) * 8 / 1000000;

        const uploadMbps =
            Number(
                upload.bandwidth || 0
            ) * 8 / 1000000;

        const pingMs =
            Number(
                ping.latency || 0
            );

        const isp =
            result.isp ||
            "Unknown";

        const serverName =
            server.name ||
            "Unknown";

        const serverLocation =
            server.location ||
            "";

        const externalIp =
            interfaceInfo.externalIp ||
            "";

        const resultUrl =
            result.result &&
            result.result.url
                ? result.result.url
                : "";

        output.innerHTML = `

<div style="
    display:grid;
    grid-template-columns:
        repeat(auto-fit,minmax(150px,1fr));
    gap:12px;
">

    <div class="card">
        <div class="card-title">
            📥 Download
        </div>

        <div class="card-value">
            ${downloadMbps.toFixed(2)}
            Mbps
        </div>
    </div>


    <div class="card">
        <div class="card-title">
            📤 Upload
        </div>

        <div class="card-value">
            ${uploadMbps.toFixed(2)}
            Mbps
        </div>
    </div>


    <div class="card">
        <div class="card-title">
            🏓 Ping
        </div>

        <div class="card-value">
            ${pingMs.toFixed(2)}
            ms
        </div>
    </div>

</div>


<div style="
    margin-top:15px;
    line-height:1.8;
">

    <div>
        📡 <b>ISP:</b>
        ${escapeHtml(isp)}
    </div>

    <div>
        🌐 <b>Server:</b>
        ${escapeHtml(serverName)}
        ${serverLocation
            ? " - " +
              escapeHtml(serverLocation)
            : ""}
    </div>

    ${
        externalIp
        ? `
        <div>
            🌍 <b>External IP:</b>
            ${escapeHtml(externalIp)}
        </div>
        `
        : ""
    }

    ${
        resultUrl
        ? `
        <div style="margin-top:10px">
            🔗
            <a
                href="${escapeHtml(resultUrl)}"
                target="_blank"
                rel="noopener"
            >
                View Speedtest Result
            </a>
        </div>
        `
        : ""
    }

</div>
`;

    } catch (error) {

        console.error(error);

        output.textContent =
            "❌ " +
            error.message;

    }

}
 
 
async function loadPiHole() {

    try {

        const data =
            await api("/api/pihole");

        document.getElementById(
            "piholeStatus"
        ).textContent =
            data.status || "unknown";

        document.getElementById(
            "piholeBlocking"
        ).textContent =
            data.blocking === "enabled"
                ? "🟢 ENABLED"
                : "🔴 DISABLED";

        const q =
            data.queries || {};

        document.getElementById(
            "piholeQueries"
        ).textContent =
            Number(q.total || 0).toLocaleString();

        document.getElementById(
            "piholeBlocked"
        ).textContent =
            Number(q.blocked || 0).toLocaleString();

        document.getElementById(
            "piholePercent"
        ).textContent =
            Number(
                q.percent_blocked || 0
            ).toFixed(2) + "%";

        document.getElementById(
            "piholeDomains"
        ).textContent =
            Number(
                q.unique_domains || 0
            ).toLocaleString();

        const clients =
            data.clients || {};

        document.getElementById(
            "piholeClients"
        ).textContent =
            (clients.active || 0) +
            " / " +
            (clients.total || 0);

        const gravity =
            data.gravity || {};

        document.getElementById(
            "piholeGravity"
        ).textContent =
            Number(
                gravity.domains || 0
            ).toLocaleString();

        document.getElementById(
            "piholeLog"
        ).textContent =
            "Pi-hole API v6 connected.";

    } catch (error) {

        console.error(error);

        document.getElementById(
            "piholeLog"
        ).textContent =
            "❌ " + error.message;

    }
}


async function loadPiholeQueries() {

    const table =
        document.getElementById(
            "piholeQueriesTable"
        );

    if (!table) return;

    table.innerHTML =
        '<tr><td colspan="5">Loading...</td></tr>';

    try {

        const data =
            await api(
                "/api/pihole/queries?length=20"
            );

        const queries =
            data.queries || [];

        if (!queries.length) {

            table.innerHTML =
                '<tr><td colspan="5">Tiada query.</td></tr>';

            return;
        }

        table.innerHTML =
            queries.map(q => {

                const domain =
                    escapeHtml(
                        q.domain || "-"
                    );

                const client =
                    escapeHtml(
                        (
                            q.client &&
                            (
                                q.client.name ||
                                q.client.ip
                            )
                        ) || "-"
                    );

                const status =
                    escapeHtml(
                        q.status || "-"
                    );

                const type =
                    escapeHtml(
                        q.type || "-"
                    );

                const upstream =
                    escapeHtml(
                        q.upstream || "-"
                    );

                return `
<tr>
<td>${domain}</td>
<td>${client}</td>
<td>${status}</td>
<td>${type}</td>
<td>${upstream}</td>
</tr>
`;

            }).join("");

    } catch (error) {

        console.error(error);

        table.innerHTML =
            `<tr>
                <td colspan="5">
                    ❌ ${escapeHtml(error.message)}
                </td>
            </tr>`;

    }

}


async function piholeCommand(action) {

    try {

        const data =
            await api(
                "/api/pihole/" + action,
                {
                    method: "POST"
                }
            );

        document.getElementById(
            "piholeLog"
        ).textContent =
            data.output ||
            data.error ||
            "Done";

        await loadPiHole();

        if (
            action === "status" ||
            action === "enable" ||
            action === "disable"
        ) {

            await loadPiholeQueries();

        }

    } catch (error) {

        alert(error.message);

    }

}


async function loadSolat() {

    const box =
        document.getElementById(
            "solatData"
        );

    if (!box) return;

    box.innerHTML =
        "🕌 Memuatkan waktu solat...";

    try {

        const data =
            await api(
                "/api/solat"
            );

        if (!data.ok) {

            throw new Error(
                data.error ||
                "Gagal mendapatkan waktu solat."
            );
        }

        const p =
            data.prayer || {};

        box.innerHTML = `

<div style="
    display:flex;
    flex-wrap:wrap;
    gap:10px;
    align-items:center;
    margin-bottom:18px;
">

    <div>
        📍 <b>${escapeHtml(data.state)}</b>
        — ${escapeHtml(data.zone)}
    </div>

    <div style="color:#9ca3af">
        ${escapeHtml(data.zone_name)}
    </div>

</div>


<div style="
    background:#111827;
    border:1px solid #263244;
    border-radius:14px;
    padding:18px;
    margin-bottom:18px;
">

    <div style="
        font-size:14px;
        color:#9ca3af;
    ">
        ⏳ Waktu seterusnya
    </div>

    <div
        id="nextPrayerName"
        style="
            font-size:25px;
            font-weight:700;
            margin-top:5px;
        "
    >
        --
    </div>

    <div
        id="nextPrayerCountdown"
        style="
            font-size:20px;
            margin-top:5px;
        "
    >
        --
    </div>

</div>


<div style="
    display:grid;
    grid-template-columns:
        repeat(auto-fit,minmax(135px,1fr));
    gap:12px;
">

    ${solatCard("🌙", "Imsak", p.imsak)}

    ${solatCard("🌅", "Subuh", p.fajr)}

    ${solatCard("☀️", "Syuruk", p.syuruk)}

    ${solatCard("🕛", "Zohor", p.dhuhr)}

    ${solatCard("🌤️", "Asar", p.asr)}

    ${solatCard("🌇", "Maghrib", p.maghrib)}

    ${solatCard("🌙", "Isyak", p.isha)}

</div>


<div style="
    display:flex;
    flex-wrap:wrap;
    gap:10px;
    margin-top:18px;
">

    <button
        class="btn"
        type="button"
        onclick="loadSolat()"
    >
        🔄 Refresh
    </button>

    <button
        class="btn"
        type="button"
        onclick="showSolatZones()"
    >
        📍 Tukar Zon
    </button>

</div>


<div
    id="solatZonePicker"
    style="
        display:none;
        margin-top:18px;
    "
></div>


<div style="
    margin-top:14px;
    color:#9ca3af;
    font-size:13px;
">
    📅 ${escapeHtml(data.date)}
    &nbsp; • &nbsp;
    📡 Sumber: e-Solat JAKIM
</div>

`;

        startSolatCountdown(
            p
        );

    } catch (error) {

        box.innerHTML = `

<div style="color:#ef4444">

❌ ${escapeHtml(
    error.message
)}

<br><br>

<button
    class="btn"
    type="button"
    onclick="loadSolat()"
>
🔄 Cuba Lagi
</button>

</div>

`;

    }

}


function solatCard(
    icon,
    name,
    time
) {

    return `

<div style="
    background:#111827;
    border:1px solid #263244;
    border-radius:14px;
    padding:15px;
">

    <div style="
        color:#9ca3af;
        font-size:14px;
    ">
        ${icon} ${name}
    </div>

    <div style="
        font-size:25px;
        font-weight:700;
        margin-top:7px;
    ">
        ${escapeHtml(time || "--:--")}
    </div>

</div>

`;

}


let solatCountdownTimer = null;


function startSolatCountdown(
    prayer
) {

    if (solatCountdownTimer) {

        clearInterval(
            solatCountdownTimer
        );

    }

    const prayers = [

        ["Subuh", prayer.fajr],

        ["Syuruk", prayer.syuruk],

        ["Zohor", prayer.dhuhr],

        ["Asar", prayer.asr],

        ["Maghrib", prayer.maghrib],

        ["Isyak", prayer.isha]

    ];

    function update() {

        const now =
            new Date();

        let next = null;

        for (
            const item
            of prayers
        ) {

            if (!item[1]) continue;

            const parts =
                item[1]
                    .split(":")
                    .map(Number);

            if (
                parts.length < 2 ||
                Number.isNaN(parts[0]) ||
                Number.isNaN(parts[1])
            ) continue;

            const target =
                new Date(now);

            target.setHours(
                parts[0],
                parts[1],
                0,
                0
            );

            if (
                target.getTime()
                > now.getTime()
            ) {

                next = {
                    name: item[0],
                    time: target
                };

                break;
            }

        }

        if (!next) {

            const fajr =
                prayers.find(
                    x => x[0] === "Subuh"
                );

            if (fajr && fajr[1]) {

                const parts =
                    fajr[1]
                        .split(":")
                        .map(Number);

                const tomorrow =
                    new Date(now);

                tomorrow.setDate(
                    tomorrow.getDate() + 1
                );

                tomorrow.setHours(
                    parts[0],
                    parts[1],
                    0,
                    0
                );

                next = {
                    name: "Subuh",
                    time: tomorrow
                };

            }

        }

        const nameEl =
            document.getElementById(
                "nextPrayerName"
            );

        const countEl =
            document.getElementById(
                "nextPrayerCountdown"
            );

        if (
            !nameEl ||
            !countEl ||
            !next
        ) return;

        let seconds =
            Math.max(
                0,
                Math.floor(
                    (
                        next.time.getTime()
                        - now.getTime()
                    ) / 1000
                )
            );

        const hours =
            Math.floor(
                seconds / 3600
            );

        seconds %= 3600;

        const minutes =
            Math.floor(
                seconds / 60
            );

        seconds %= 60;

        nameEl.textContent =
            `⏭️ ${next.name} — ${next.time
                .toLocaleTimeString(
                    "ms-MY",
                    {
                        hour: "2-digit",
                        minute: "2-digit"
                    }
                )}`;

        countEl.textContent =
            `⏱️ ${String(hours).padStart(2,"0")}:` +
            `${String(minutes).padStart(2,"0")}:` +
            `${String(seconds).padStart(2,"0")}`;

    }

    update();

    solatCountdownTimer =
        setInterval(
            update,
            1000
        );

}


async function showSolatZones() {

    const picker =
        document.getElementById(
            "solatZonePicker"
        );

    if (!picker) return;

    picker.style.display =
        "block";

    picker.innerHTML =
        "📍 Memuatkan senarai zon...";

    try {

        const data =
            await api(
                "/api/solat/zones"
            );

        let html = `

<div style="
    background:#111827;
    border:1px solid #263244;
    border-radius:14px;
    padding:16px;
">

<h3 style="
    margin-top:0;
">
📍 Pilih Zon JAKIM
</h3>

`;

        for (
            const state
            of Object.keys(
                data.zones
            )
        ) {

            html += `

<div style="
    margin-top:14px;
">

<div style="
    font-weight:700;
    margin-bottom:7px;
">
${escapeHtml(state)}
</div>

<div style="
    display:grid;
    grid-template-columns:
        repeat(auto-fit,minmax(220px,1fr));
    gap:8px;
">

`;

            for (
                const zone
                of Object.keys(
                    data.zones[state]
                )
            ) {

                const selected =
                    zone === data.selected;

                html += `

<button
    type="button"
    class="btn"
    style="
        text-align:left;
        ${selected
            ? "border:2px solid #22c55e;"
            : ""}
    "
    onclick="selectSolatZone(
        '${escapeHtml(zone)}'
    )"
>
${selected ? "✅ " : ""}
<b>${escapeHtml(zone)}</b><br>
<span style="
    font-size:12px;
    color:#9ca3af;
">
${escapeHtml(
    data.zones[state][zone]
)}
</span>
</button>

`;

            }

            html += `
</div>
</div>
`;

        }

        html += `
</div>
`;

        picker.innerHTML =
            html;

    } catch (error) {

        picker.innerHTML =
            "❌ " +
            escapeHtml(
                error.message
            );

    }

}


async function selectSolatZone(
    zone
) {

    try {

        const data =
            await api(
                "/api/solat/zone",
                {
                    method: "POST",
                    headers: {
                        "Content-Type":
                            "application/json"
                    },
                    body: JSON.stringify({
                        zone: zone
                    })
                }
            );

        if (!data.ok) {

            throw new Error(
                data.error ||
                "Gagal simpan zon."
            );

        }

        alert(
            "✅ Zon " +
            zone +
            " berjaya disimpan."
        );

        const picker =
            document.getElementById(
                "solatZonePicker"
            );

        if (picker) {

            picker.style.display =
                "none";

        }

        await loadSolat();

    } catch (error) {

        alert(
            "❌ " +
            error.message
        );

    }

}


loadSystem();
loadServices();
loadSolat();

setInterval(
    loadSystem,
    10000
);

</script>

</body>
</html>
"""

    return render_template_string(html)


@app.route("/login", methods=["GET", "POST"])
def login():

    error = ""

    if request.method == "POST":

        username = request.form.get(
            "username",
            ""
        )

        password = request.form.get(
            "password",
            ""
        )

        if (
            username == USERNAME
            and password == PASSWORD
        ):

            session["logged_in"] = True

            return redirect(
                url_for("index")
            )

        error = "Username atau password salah."

    return f"""
<!DOCTYPE html>
<html>
<head>

<meta charset="UTF-8">

<meta name="viewport"
content="width=device-width, initial-scale=1.0">

<title>Raspberry Pi Login</title>

<style>

body {{
    margin: 0;
    min-height: 100vh;

    display: flex;
    align-items: center;
    justify-content: center;

    background: #090d13;
    color: white;

    font-family:
        system-ui,
        sans-serif;
}}

.box {{
    width: min(90%, 380px);

    background: #111827;
    border: 1px solid #263244;

    border-radius: 16px;
    padding: 28px;
}}

h1 {{
    margin-top: 0;
}}

input {{
    width: 100%;
    box-sizing: border-box;

    margin-bottom: 12px;

    padding: 13px;

    background: #020617;
    color: white;

    border: 1px solid #334155;
    border-radius: 8px;
}}

button {{
    width: 100%;
    padding: 13px;

    background: #2563eb;
    color: white;

    border: 0;
    border-radius: 8px;

    cursor: pointer;
}}

.error {{
    color: #fca5a5;
    margin-bottom: 12px;
}}

</style>

</head>

<body>

<div class="box">

<h1>🍓 Raspberry Pi</h1>

<p>
Control Center
</p>

<div class="error">
{error}
</div>

<form method="POST">

<input
name="username"
placeholder="Username"
required
>

<input
name="password"
type="password"
placeholder="Password"
required
>

<button type="submit">
Login
</button>

</form>

</div>

</body>
</html>
"""


@app.route("/logout")
def logout():

    session.clear()

    return redirect(
        url_for("login")
    )


@app.route("/api/system")
@login_required
def api_system():

    memory = psutil.virtual_memory()

    services = {}

    for service in ALLOWED_SERVICES:
        services[service] = service_status(service)

    return jsonify({

        "cpu":
            round(
                psutil.cpu_percent(
                    interval=0.3
                ),
                1
            ),

        "ram":
            round(
                memory.percent,
                1
            ),

        "temperature":
            get_temperature(),

        "disk":
            get_disk(),

        "uptime":
            get_uptime(),

        "ips":
            get_ip_addresses(),

        "tailscale":
            get_tailscale_ip(),

        "services":
            services

    })


@app.route("/api/services")
@login_required
def api_services():

    result = {}

    for service in ALLOWED_SERVICES:
        result[service] = service_status(service)

    return jsonify(result)


@app.route("/api/service", methods=["POST"])
@login_required
def api_service():

    data = request.get_json(
        silent=True
    ) or {}

    service = data.get("service")
    action = data.get("action")

    if service not in ALLOWED_SERVICES:
        return jsonify({
            "ok": False,
            "error": "Service not allowed"
        }), 400

    if action not in {
        "start",
        "stop",
        "restart"
    }:
        return jsonify({
            "ok": False,
            "error": "Action not allowed"
        }), 400

    result = run_command(
        f"sudo /usr/bin/systemctl "
        f"{action} {service}",
        timeout=30
    )

    return jsonify({
        "ok":
            result["returncode"] == 0,

        "message":
            f"{action} {service}",

        "output":
            result["stdout"],

        "error":
            result["stderr"]
    })


@app.route("/api/power", methods=["POST"])
@login_required
def api_power():

    data = request.get_json(
        silent=True
    ) or {}

    action = data.get("action")

    if action == "reboot":

        subprocess.Popen(
            [
                "sudo",
                "/usr/sbin/reboot"
            ]
        )

        return jsonify({
            "ok": True,
            "message":
                "Raspberry Pi sedang reboot."
        })

    if action == "poweroff":

        subprocess.Popen(
            [
                "sudo",
                "/usr/sbin/poweroff"
            ]
        )

        return jsonify({
            "ok": True,
            "message":
                "Raspberry Pi sedang shutdown."
        })

    return jsonify({
        "ok": False,
        "error": "Invalid action"
    }), 400


@app.route("/api/files")
@login_required
def api_files():

    files = []

    for item in sorted(
        UPLOAD_DIR.iterdir(),
        key=lambda x: x.name.lower()
    ):

        if item.is_file():

            files.append({
                "name":
                    item.name,

                "size":
                    f"{bytes_to_gb(item.stat().st_size):.2f} GB"
                    if item.stat().st_size >= 1024**3
                    else
                    f"{item.stat().st_size / 1024**2:.2f} MB"
            })

    return jsonify({
        "files": files
    })


@app.route("/api/upload", methods=["POST"])
@login_required
def api_upload():

    file = request.files.get("file")

    if not file:
        return jsonify({
            "ok": False,
            "error": "No file"
        }), 400

    filename = secure_filename(
        file.filename
    )

    if not filename:
        return jsonify({
            "ok": False,
            "error": "Invalid filename"
        }), 400

    destination = (
        UPLOAD_DIR /
        filename
    )

    file.save(
        str(destination)
    )

    return jsonify({
        "ok": True,
        "message": "Upload complete",
        "filename": filename
    })


@app.route("/download/<path:filename>")
@login_required
def download(filename):

    safe = secure_filename(
        filename
    )

    target = UPLOAD_DIR / safe

    if not target.exists() or not target.is_file():
        return "File not found", 404

    response = Response()
    response.headers["X-Accel-Redirect"] = (
        "/protected-download/" + safe
    )
    response.headers["Content-Disposition"] = (
        f'attachment; filename="{safe}"'
    )
    response.headers["Content-Type"] = (
        "application/octet-stream"
    )

    return response


@app.route("/api/files/<path:filename>",
           methods=["DELETE"])
@login_required
def delete_file(filename):

    safe = secure_filename(
        filename
    )

    target = (
        UPLOAD_DIR /
        safe
    )

    if not target.exists():
        return jsonify({
            "ok": False,
            "error": "File not found"
        }), 404

    if not target.is_file():
        return jsonify({
            "ok": False,
            "error": "Not a file"
        }), 400

    target.unlink()

    return jsonify({
        "ok": True,
        "message": "File deleted"
    })


@app.route("/api/speedtest",
           methods=["POST"])
@login_required
def api_speedtest():

    result = run_command(
        "speedtest --accept-license "
        "--accept-gdpr --format=json",
        timeout=180
    )

    output = (
        result["stdout"]
        or result["stderr"]
    )

    return jsonify({
        "ok":
            result["returncode"] == 0,

        "output":
            output
    })


# ==============================
# PI-HOLE API V6
# ==============================

@app.route("/api/pihole")
@login_required
def api_pihole():

    blocking = run_command(
        "sudo pihole api dns/blocking",
        timeout=20
    )

    stats = run_command(
        "sudo pihole api stats/summary",
        timeout=20
    )

    try:
        blocking_data = json.loads(
            blocking["stdout"] or "{}"
        )
    except Exception:
        blocking_data = {}

    try:
        stats_data = json.loads(
            stats["stdout"] or "{}"
        )
    except Exception:
        stats_data = {}

    queries = stats_data.get("queries", {})
    clients = stats_data.get("clients", {})
    gravity = stats_data.get("gravity", {})

    return jsonify({
        "ok": True,

        "status": service_status("pihole-FTL"),

        "blocking":
            blocking_data.get(
                "blocking",
                "unknown"
            ),

        "timer":
            blocking_data.get("timer"),

        "queries": {
            "total":
                queries.get("total", 0),

            "blocked":
                queries.get("blocked", 0),

            "percent_blocked":
                queries.get(
                    "percent_blocked",
                    0
                ),

            "unique_domains":
                queries.get(
                    "unique_domains",
                    0
                ),

            "forwarded":
                queries.get(
                    "forwarded",
                    0
                ),

            "cached":
                queries.get(
                    "cached",
                    0
                )
        },

        "clients": {
            "active":
                clients.get("active", 0),

            "total":
                clients.get("total", 0)
        },

        "gravity": {
            "domains":
                gravity.get(
                    "domains_being_blocked",
                    0
                ),

            "last_update":
                gravity.get(
                    "last_update"
                )
        }
    })


@app.route("/api/pihole/queries")
@login_required
def api_pihole_queries():

    length = request.args.get(
        "length",
        "20"
    )

    try:
        length = int(length)
    except Exception:
        length = 20

    length = max(
        1,
        min(length, 100)
    )

    result = run_command(
        f"sudo pihole api 'queries?length={length}'",
        timeout=20
    )

    try:
        data = json.loads(
            result["stdout"] or "{}"
        )

        return jsonify({
            "ok": True,
            **data
        })

    except Exception as e:

        return jsonify({
            "ok": False,
            "error": str(e),
            "output":
                result["stderr"]
                or result["stdout"]
        }), 500


@app.route("/api/pihole/<action>", methods=["POST"])
@login_required
def api_pihole_action(action):

    if action == "status":

        result = run_command(
            "sudo pihole api dns/blocking",
            timeout=20
        )

    elif action == "enable":

        result = run_command(
            "sudo pihole enable",
            timeout=30
        )

    elif action == "disable":

        result = run_command(
            "sudo pihole disable",
            timeout=30
        )

    elif action == "refresh":

        result = run_command(
            "sudo pihole reloaddns",
            timeout=30
        )

    else:

        return jsonify({
            "ok": False,
            "error": "Invalid Pi-hole action"
        }), 400

    return jsonify({
        "ok":
            result["returncode"] == 0,

        "output":
            result["stdout"],

        "error":
            result["stderr"]
    })


# ==============================
# TELEGRAM USER MANAGEMENT
# ==============================

TELEGRAM_USERS_FILE = Path("/home/azam/speedtest-bot/users.json")
TELEGRAM_ADMIN_ID = "202940674"

@app.route("/api/telegram/users")
@login_required
def api_telegram_users():

    try:
        with open(TELEGRAM_USERS_FILE, "r", encoding="utf-8") as f:
            users = json.load(f)

        result = []

        for user_id, info in users.items():

            result.append({
                "id": user_id,
                "name": info.get("name", ""),
                "username": info.get("username", ""),
                "status": info.get("status", "pending")
            })

        return jsonify({
            "ok": True,
            "users": result
        })

    except Exception as e:

        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500


@app.route("/api/telegram/user/<user_id>/status", methods=["POST"])
@login_required
def api_telegram_user_status(user_id):

    allowed_statuses = {
        "approved",
        "pending",
        "rejected",
        "revoked",
        "blocked"
    }

    data = request.get_json(silent=True) or {}
    status = data.get("status")

    if status not in allowed_statuses:

        return jsonify({
            "ok": False,
            "error": "Status tidak sah"
        }), 400

    # Lindungi admin utama
    if str(user_id) == TELEGRAM_ADMIN_ID and status != "approved":

        return jsonify({
            "ok": False,
            "error": "Admin utama tidak boleh diubah status."
        }), 403

    try:

        with open(TELEGRAM_USERS_FILE, "r", encoding="utf-8") as f:
            users = json.load(f)

        if str(user_id) not in users:

            return jsonify({
                "ok": False,
                "error": "User tidak dijumpai."
            }), 404

        users[str(user_id)]["status"] = status

        with open(
            TELEGRAM_USERS_FILE,
            "w",
            encoding="utf-8"
        ) as f:

            json.dump(
                users,
                f,
                indent=2,
                ensure_ascii=False
            )

        return jsonify({
            "ok": True,
            "message": f"User {user_id} → {status}"
        })

    except Exception as e:

        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500



# ============================================================
# WAKTU SOLAT JAKIM
# ============================================================

SOLAT_BOT_FILE = Path("/home/azam/speedtest-bot/bot_server.py")
SOLAT_USERS_FILE = Path("/home/azam/speedtest-bot/users.json")
SOLAT_ADMIN_ID = "202940674"

JAKIM_SOLAT_API = (
    "https://www.e-solat.gov.my/index.php"
    "?r=esolatApi/takwimsolat"
)


def load_solat_zones():

    try:

        source = SOLAT_BOT_FILE.read_text(
            encoding="utf-8"
        )

        tree = ast.parse(source)

        for node in tree.body:

            if isinstance(node, ast.Assign):

                for target in node.targets:

                    if (
                        isinstance(target, ast.Name)
                        and target.id == "SOLAT_ZONES"
                    ):

                        return ast.literal_eval(
                            node.value
                        )

    except Exception:

        pass

    return {
        "Melaka": {
            "MLK01": "Seluruh Negeri Melaka"
        }
    }


def get_solat_zone():

    try:

        with open(
            SOLAT_USERS_FILE,
            "r",
            encoding="utf-8"
        ) as f:

            users = json.load(f)

        return users.get(
            SOLAT_ADMIN_ID,
            {}
        ).get(
            "solat_zone",
            "MLK01"
        )

    except Exception:

        return "MLK01"


def set_solat_zone(zone):

    zones = load_solat_zones()

    valid = any(
        zone in state_zones
        for state_zones in zones.values()
    )

    if not valid:

        raise ValueError(
            "Zon JAKIM tidak sah."
        )

    with open(
        SOLAT_USERS_FILE,
        "r",
        encoding="utf-8"
    ) as f:

        users = json.load(f)

    user = users.setdefault(
        SOLAT_ADMIN_ID,
        {}
    )

    user["solat_zone"] = zone

    with open(
        SOLAT_USERS_FILE,
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            users,
            f,
            indent=2,
            ensure_ascii=False
        )


def get_solat_zone_info(zone):

    zones = load_solat_zones()

    for state, state_zones in zones.items():

        if zone in state_zones:

            return {
                "state": state,
                "zone": zone,
                "name": state_zones[zone]
            }

    return {
        "state": "Tidak diketahui",
        "zone": zone,
        "name": "Tidak diketahui"
    }


def get_jakim_dashboard(zone):

    url = (
        JAKIM_SOLAT_API
        + "&zone="
        + zone
        + "&period=today"
    )

    request = Request(
        url,
        headers={
            "User-Agent":
                "Mozilla/5.0 Raspberry-Dashboard"
        }
    )

    with urlopen(
        request,
        timeout=20
    ) as response:

        raw = response.read().decode(
            "utf-8"
        )

    data = json.loads(raw)

    if data.get("status") != "OK!":

        raise RuntimeError(
            "JAKIM API tidak memberikan data."
        )

    prayer = data.get(
        "prayerTime",
        []
    )

    if not prayer:

        raise RuntimeError(
            "Data waktu solat kosong."
        )

    return prayer[0]


def clean_solat_time(value):

    if not value:
        return "--:--"

    return str(value)[:5]


@app.route("/api/solat")
@login_required
def api_solat():

    try:

        zone = get_solat_zone()

        info = get_solat_zone_info(
            zone
        )

        prayer = get_jakim_dashboard(
            zone
        )

        return jsonify({
            "ok": True,
            "zone": zone,
            "state": info["state"],
            "zone_name": info["name"],
            "date": datetime.now(
                ZoneInfo("Asia/Kuala_Lumpur")
            ).strftime("%d-%m-%Y"),
            "prayer": {
                "imsak": clean_solat_time(
                    prayer.get("imsak")
                ),
                "fajr": clean_solat_time(
                    prayer.get(
                        "fajr",
                        prayer.get("subuh")
                    )
                ),
                "syuruk": clean_solat_time(
                    prayer.get("syuruk")
                ),
                "dhuhr": clean_solat_time(
                    prayer.get(
                        "dhuhr",
                        prayer.get("zohor")
                    )
                ),
                "asr": clean_solat_time(
                    prayer.get(
                        "asr",
                        prayer.get("asar")
                    )
                ),
                "maghrib": clean_solat_time(
                    prayer.get("maghrib")
                ),
                "isha": clean_solat_time(
                    prayer.get(
                        "isha",
                        prayer.get("isyak")
                    )
                )
            }
        })

    except Exception as e:

        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500


@app.route(
    "/api/solat/zones",
    methods=["GET"]
)
@login_required
def api_solat_zones():

    zones = load_solat_zones()

    return jsonify({
        "ok": True,
        "zones": zones,
        "selected": get_solat_zone()
    })


@app.route(
    "/api/solat/zone",
    methods=["POST"]
)
@login_required
def api_solat_set_zone():

    try:

        data = request.get_json(
            silent=True
        ) or {}

        zone = str(
            data.get("zone", "")
        ).strip()

        if not zone:

            return jsonify({
                "ok": False,
                "error": "Sila pilih zon."
            }), 400

        set_solat_zone(zone)

        return jsonify({
            "ok": True,
            "zone": zone,
            "message":
                f"Zon {zone} berjaya disimpan."
        })

    except Exception as e:

        return jsonify({
            "ok": False,
            "error": str(e)
        }), 500


if __name__ == "__main__":

    app.run(
        host="0.0.0.0",
        port=8080
    )
