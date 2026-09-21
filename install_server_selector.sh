#!/bin/bash

set -e

echo "=========================================="
echo " SERVER SELECTOR INSTALLER"
echo "=========================================="

mkdir -p server_selector

cat > server_selector/__init__.py <<'PYEOF'
from .selector import (
    get_servers,
    get_selected_server,
    set_selected_server,
    clear_selected_server,
)
PYEOF

cat > server_selector/selector.py <<'PYEOF'
import json
import os
import subprocess

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, "selected_server.json")

SPEEDTEST = "/usr/bin/speedtest"


def get_selected_server():
    if not os.path.exists(CONFIG_FILE):
        return None

    try:
        with open(CONFIG_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return None


def set_selected_server(server):
    with open(CONFIG_FILE, "w") as f:
        json.dump(server, f, indent=2)


def clear_selected_server():
    if os.path.exists(CONFIG_FILE):
        os.remove(CONFIG_FILE)


def get_servers():
    try:
        result = subprocess.run(
            [
                SPEEDTEST,
                "--servers",
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )

        if result.returncode != 0:
            return []

        servers = []

        for line in result.stdout.splitlines():

            line = line.strip()

            if not line:
                continue

            # Contoh:
            # 64137) Telekom Malaysia Berhad (Brickfields, Malaysia) [x.xx km]

            if ")" not in line:
                continue

            try:
                server_id = line.split(")", 1)[0].strip()

                if not server_id.isdigit():
                    continue

                remaining = line.split(")", 1)[1].strip()

                if " [" in remaining:
                    name_location = remaining.split(" [", 1)[0]
                else:
                    name_location = remaining

                if " (" in name_location and name_location.endswith(")"):
                    name = name_location.rsplit(" (", 1)[0]
                    location = name_location.rsplit(" (", 1)[1][:-1]
                else:
                    name = name_location
                    location = "Unknown"

                servers.append(
                    {
                        "id": int(server_id),
                        "name": name,
                        "location": location,
                    }
                )

            except Exception:
                continue

        return servers

    except Exception:
        return []
PYEOF

cat > server_selector/selected_server.json <<'PYEOF'
{}
PYEOF

echo ""
echo "Folder server_selector berjaya dibuat."
echo ""
echo "Isi:"
echo "  server_selector/__init__.py"
echo "  server_selector/selector.py"
echo "  server_selector/selected_server.json"
echo ""
echo "Sekarang kita semak server Ookla..."
echo ""

python3 -c "from server_selector.selector import get_servers; s=get_servers(); print('Jumlah server:', len(s)); print(*s[:10], sep='\n')"

echo ""
echo "=========================================="
echo " SIAP"
echo "=========================================="
