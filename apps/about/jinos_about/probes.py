"""Hardware checks for About Phone.

Plain Python with no GTK, so the same checks can run from a terminal:

    python3 -m jinos_about.probes

They report what the system can see, not that every feature works:
"detected" means the kernel or a system service found the hardware.
"""

from __future__ import annotations

import glob
import json
import os
import platform
import shutil
import subprocess
from dataclasses import dataclass
from enum import Enum


class Status(Enum):
    DETECTED = "detected"
    NOT_FOUND = "not found"
    UNKNOWN = "unknown"


@dataclass
class Probe:
    name: str
    icon: str
    status: Status
    detail: str


def _read(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().strip().strip("\0")
    except OSError:
        return None


def _os_release() -> dict[str, str]:
    values = {}
    text = _read("/etc/os-release") or _read("/usr/lib/os-release") or ""
    for line in text.splitlines():
        key, sep, value = line.partition("=")
        if sep:
            values[key] = value.strip('"')
    return values


def device_info() -> dict[str, str]:
    model = _read("/sys/firmware/devicetree/base/model")
    if not model:
        vendor = _read("/sys/class/dmi/id/sys_vendor") or ""
        product = _read("/sys/class/dmi/id/product_name") or ""
        model = f"{vendor} {product}".strip() or "Unknown device"
    release = _os_release()
    return {
        "Model": model,
        "System": release.get("PRETTY_NAME", "Unknown"),
        "Image version": release.get("IMAGE_VERSION", "Development build"),
        "Kernel": platform.release(),
        "Architecture": platform.machine(),
    }


def probe_display() -> Probe:
    outputs = []
    for status_file in sorted(glob.glob("/sys/class/drm/card*-*/status")):
        if _read(status_file) != "connected":
            continue
        connector = os.path.basename(os.path.dirname(status_file)).split("-", 1)[1]
        modes = (_read(os.path.join(os.path.dirname(status_file), "modes")) or "").splitlines()
        outputs.append(f"{connector}, preferred mode {modes[0]}" if modes else connector)
    if outputs:
        return Probe("Display", "video-display-symbolic", Status.DETECTED, "; ".join(outputs))
    return Probe("Display", "video-display-symbolic", Status.UNKNOWN, "No connected display reported")


def probe_touchscreen() -> Probe:
    names = []
    for data in glob.glob("/run/udev/data/c13:*"):
        if "E:ID_INPUT_TOUCHSCREEN=1" not in (_read(data) or ""):
            continue
        minor = int(data.rsplit(":", 1)[1])
        if minor >= 64:
            names.append(_read(f"/sys/class/input/event{minor - 64}/device/name") or "Touchscreen")
    if names:
        return Probe("Touchscreen", "input-tablet-symbolic", Status.DETECTED, ", ".join(sorted(set(names))))
    return Probe("Touchscreen", "input-tablet-symbolic", Status.NOT_FOUND, "No touchscreen found")


def probe_wifi() -> Probe:
    ifaces = []
    for iface in sorted(glob.glob("/sys/class/net/*")):
        if os.path.isdir(os.path.join(iface, "wireless")) or os.path.exists(os.path.join(iface, "phy80211")):
            state = _read(os.path.join(iface, "operstate")) or "unknown"
            ifaces.append(f"{os.path.basename(iface)} ({state})")
    if ifaces:
        return Probe("Wi-Fi", "network-wireless-symbolic", Status.DETECTED, ", ".join(ifaces))
    return Probe("Wi-Fi", "network-wireless-symbolic", Status.NOT_FOUND, "No Wi-Fi adapter found")


def _mmcli(*args: str) -> dict | None:
    try:
        out = subprocess.run(["mmcli", "-J", *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return None


def probe_modem() -> Probe:
    name, icon = "Mobile network", "network-cellular-symbolic"
    if not shutil.which("mmcli"):
        return Probe(name, icon, Status.UNKNOWN, "ModemManager is not installed")
    listing = _mmcli("-L")
    if listing is None:
        return Probe(name, icon, Status.UNKNOWN, "ModemManager is not running")
    modems = listing.get("modem-list", [])
    if not modems:
        return Probe(name, icon, Status.NOT_FOUND, "No modem found")
    info = (_mmcli("-m", modems[0]) or {}).get("modem", {})
    generic = info.get("generic", {})
    operator = info.get("3gpp", {}).get("operator-name", "--")
    parts = [generic.get("model", "Modem"), generic.get("state", "unknown state")]
    if operator and operator != "--":
        parts.append(operator)
    return Probe(name, icon, Status.DETECTED, " · ".join(parts))


def probe_battery() -> Probe:
    for supply in sorted(glob.glob("/sys/class/power_supply/*")):
        if _read(os.path.join(supply, "type")) != "Battery":
            continue
        capacity = _read(os.path.join(supply, "capacity"))
        state = (_read(os.path.join(supply, "status")) or "").lower()
        detail = f"{capacity}%" if capacity else "Level unknown"
        if state:
            detail += f", {state}"
        return Probe("Battery", "battery-level-80-symbolic", Status.DETECTED, detail)
    return Probe("Battery", "battery-level-80-symbolic", Status.NOT_FOUND, "No battery found")


def probe_bluetooth() -> Probe:
    adapters = sorted(os.path.basename(p) for p in glob.glob("/sys/class/bluetooth/hci*") if ":" not in p)
    if adapters:
        return Probe("Bluetooth", "bluetooth-symbolic", Status.DETECTED, ", ".join(adapters))
    return Probe("Bluetooth", "bluetooth-symbolic", Status.NOT_FOUND, "No Bluetooth adapter found")


def probe_audio() -> Probe:
    cards = []
    for line in (_read("/proc/asound/cards") or "").splitlines():
        if "]: " in line:
            cards.append(line.split("]: ", 1)[1].split(" - ", 1)[-1].strip())
    if cards:
        return Probe("Audio", "audio-speakers-symbolic", Status.DETECTED, ", ".join(cards))
    return Probe("Audio", "audio-speakers-symbolic", Status.NOT_FOUND, "No sound card found")


def probe_camera() -> Probe:
    names = sorted({_read(os.path.join(p, "name")) or os.path.basename(p)
                    for p in glob.glob("/sys/class/video4linux/video*")})
    if names:
        return Probe("Camera", "camera-photo-symbolic", Status.DETECTED,
                     f"{len(names)} video device{'s' if len(names) != 1 else ''}: {', '.join(names)}")
    return Probe("Camera", "camera-photo-symbolic", Status.NOT_FOUND, "No camera device found")


_SENSOR_KINDS = {
    "in_accel_x_raw": "accelerometer",
    "in_anglvel_x_raw": "gyroscope",
    "in_magn_x_raw": "compass",
    "in_illuminance_raw": "light",
    "in_illuminance_input": "light",
    "in_proximity_raw": "proximity",
    "in_pressure_raw": "pressure",
}


def probe_sensors() -> Probe:
    kinds = set()
    for dev in glob.glob("/sys/bus/iio/devices/iio:device*"):
        for attr, kind in _SENSOR_KINDS.items():
            if os.path.exists(os.path.join(dev, attr)):
                kinds.add(kind)
    if kinds:
        return Probe("Sensors", "find-location-symbolic", Status.DETECTED, ", ".join(sorted(kinds)))
    return Probe("Sensors", "find-location-symbolic", Status.NOT_FOUND, "No motion or light sensors found")


PROBES = [
    probe_display,
    probe_touchscreen,
    probe_wifi,
    probe_modem,
    probe_battery,
    probe_bluetooth,
    probe_audio,
    probe_camera,
    probe_sensors,
]


def run_all() -> list[Probe]:
    results = []
    for probe in PROBES:
        try:
            results.append(probe())
        except Exception as error:  # one broken check must not hide the others
            name = probe.__name__.removeprefix("probe_").title()
            results.append(Probe(name, "dialog-question-symbolic", Status.UNKNOWN, f"Check failed: {error}"))
    return results


def report(info: dict[str, str], probes: list[Probe]) -> str:
    lines = [f"{key}: {value}" for key, value in info.items()]
    lines.append("")
    lines += [f"{p.name}: {p.status.value} ({p.detail})" for p in probes]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    print(report(device_info(), run_all()), end="")
