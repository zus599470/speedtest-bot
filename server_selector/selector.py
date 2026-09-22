import json
import os
import subprocess
import re

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, "selected_server.json")

SPEEDTEST = "/usr/bin/speedtest"


def get_selected_server():
    if not os.path.exists(CONFIG_FILE):
        return None

    try:
        with open(CONFIG_FILE, "r") as f:
            data = json.load(f)

        if not data:
            return None

        return data

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

            # Skip separator/header
            if not re.match(r"^\d+", line):
                continue

            # Format Ookla:
            # 57147  Uni5G                          Cyberjaya            Malaysia

            match = re.match(
                r"^(\d+)\s+(.+?)\s{2,}(.+?)\s{2,}(.+?)$",
                line,
            )

            if not match:
                continue

            server_id = int(match.group(1))
            name = match.group(2).strip()
            location = match.group(3).strip()
            country = match.group(4).strip()

            servers.append(
                {
                    "id": server_id,
                    "name": name,
                    "location": location,
                    "country": country,
                }
            )

        return servers

    except Exception:
        return []


if __name__ == "__main__":
    servers = get_servers()

    print(f"Jumlah server: {len(servers)}")

    for server in servers:
        print(
            f'{server["id"]} | '
            f'{server["name"]} | '
            f'{server["location"]} | '
            f'{server["country"]}'
        )
