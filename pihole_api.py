import os
import requests
import logging

PIHOLE_URL = "http://192.168.0.12"

# Masukkan password Pi-hole kau di sini
PIHOLE_PASSWORD = os.getenv("PIHOLE_PASSWORD", "")

logger = logging.getLogger(__name__)

session = requests.Session()


def login():
    try:
        response = session.post(
            f"{PIHOLE_URL}/api/auth",
            json={"password": PIHOLE_PASSWORD},
            timeout=10,
        )

        data = response.json()
        info = data.get("session", {})

        if info.get("valid"):
            session.headers.update({
                "X-FTL-SID": info["sid"]
            })
            return True

        logger.error("Pi-hole login gagal: %s", data)
        return False

    except Exception as error:
        logger.error("Pi-hole login error: %s", error)
        return False


def get(endpoint):
    try:
        response = session.get(
            f"{PIHOLE_URL}{endpoint}",
            timeout=15,
        )

        if response.status_code == 401:
            if not login():
                return None

            response = session.get(
                f"{PIHOLE_URL}{endpoint}",
                timeout=15,
            )

        response.raise_for_status()
        return response.json()

    except Exception as error:
        logger.error("Pi-hole API error: %s", error)
        return None


def set_blocking(enabled):
    try:
        response = session.post(
            f"{PIHOLE_URL}/api/dns/blocking",
            json={"blocking": enabled},
            timeout=15,
        )

        if response.status_code == 401:
            if not login():
                return None

            response = session.post(
                f"{PIHOLE_URL}/api/dns/blocking",
                json={"blocking": enabled},
                timeout=15,
            )

        response.raise_for_status()
        return response.json()

    except Exception as error:
        logger.error(
            "Pi-hole protection error: %s",
            error,
        )
        return None
