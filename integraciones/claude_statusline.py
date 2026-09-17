#!/usr/bin/env python3
"""Puente entre Claude Code y Trayecto.

Claude Code le pasa a su "status line" un JSON con el uso de tus límites
(ventana de 5 horas y semanal). Este script guarda ese dato donde Trayecto
lo lee (<datos>/uso/claude.json) y pinta una línea de estado mínima.

Se instala con:   ./trayecto --conectar-claude
o a mano, en ~/.claude/settings.json:

    "statusLine": { "type": "command", "command": "python3 /ruta/a/trayecto/integraciones/claude_statusline.py" }

Si ya tienes una status line y quieres conservarla, pon su comando en la
variable TRAYECTO_STATUSLINE_SIGUIENTE: recibe la misma entrada y se muestra
su salida en lugar de la de este script.

No guarda nada de tus conversaciones: solo `rate_limits` y la hora.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path


def guardar(limites):
    carpeta = Path(os.environ.get("TRAYECTO_DIR") or "~/.trayecto").expanduser() / "uso"
    carpeta.mkdir(parents=True, exist_ok=True)
    destino = carpeta / "claude.json"
    temporal = carpeta / f"claude.json.{os.getpid()}.tmp"
    temporal.write_text(json.dumps({"visto": time.time(), "rate_limits": limites}), encoding="utf-8")
    os.replace(temporal, destino)


def linea(datos):
    partes = [(datos.get("model") or {}).get("display_name") or "Claude"]
    limites = datos.get("rate_limits") or {}
    for clave, nombre in (("five_hour", "5 h"), ("seven_day", "7 d")):
        usado = (limites.get(clave) or {}).get("used_percentage")
        if isinstance(usado, (int, float)):
            partes.append(f"{nombre} {round(usado)}%")
    return " · ".join(partes)


def main():
    crudo = sys.stdin.read()
    try:
        datos = json.loads(crudo)
    except ValueError:
        datos = {}
    # Sin `rate_limits` (inicio de sesión, o cuenta sin límites) se conserva lo último visto.
    if isinstance(datos.get("rate_limits"), dict):
        try:
            guardar(datos["rate_limits"])
        except OSError:
            pass
    siguiente = os.environ.get("TRAYECTO_STATUSLINE_SIGUIENTE")
    if siguiente:
        try:
            salida = subprocess.run(siguiente, shell=True, input=crudo, capture_output=True, text=True, timeout=5).stdout
            print(salida, end="")
            return
        except (OSError, subprocess.SubprocessError):
            pass
    print(linea(datos))


if __name__ == "__main__":
    main()
