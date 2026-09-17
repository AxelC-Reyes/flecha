"""Uso de asistentes de código (Claude Code, Codex, Gemini CLI), leído de los
archivos que cada herramienta ya deja en tu computadora.

No usa contraseñas ni llama a ningún servicio, y nunca mira el contenido de
tus conversaciones: solo cuenta tokens y copia los porcentajes de límite.

    Claude Code   tokens: ~/.claude/projects/**/*.jsonl
                  límites (5 h y semana): los entrega Claude Code a su "status line";
                  integraciones/claude_statusline.py los guarda en <datos>/uso/claude.json
    Codex         tokens y límites: ~/.codex/sessions/**/*.jsonl (eventos token_count)
    Gemini CLI    tokens: ~/.gemini/tmp/*/chats/ (no publica límites)

"Tokens" aquí = entrada nueva + escritura de caché + salida. Las lecturas de
caché se dejan fuera: son enormes, casi gratis, y taparían todo lo demás.
"""

import json
import os
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path

DIAS = 7
REFRESCO_S = 20


def _epoch(valor):
    """Acepta segundos epoch o una fecha ISO 8601; devuelve segundos o None."""
    if isinstance(valor, (int, float)):
        return float(valor) if valor < 1e11 else valor / 1000.0
    if isinstance(valor, str) and valor:
        try:
            return datetime.fromisoformat(valor.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return None
    return None


def _entero(valor):
    return int(valor) if isinstance(valor, (int, float)) and valor > 0 else 0


class Bitacoras:
    """Lee archivos .jsonl que solo crecen, recordando hasta dónde iba en cada uno."""

    def __init__(self):
        self.archivos = {}  # ruta -> {"pos": int, "eventos": [(epoch, tokens)], "memoria": dict}

    def eventos(self, rutas, interpretar, desde):
        vivos = set()
        salida = []
        for ruta in rutas:
            try:
                info = ruta.stat()
            except OSError:
                continue
            if info.st_mtime < desde:
                continue
            clave = str(ruta)
            vivos.add(clave)
            estado = self.archivos.get(clave)
            if estado is None or info.st_size < estado["pos"]:
                estado = self.archivos[clave] = {"pos": 0, "eventos": [], "memoria": {}}
            if info.st_size > estado["pos"]:
                self._leer(ruta, estado, interpretar)
            salida.extend(e for e in estado["eventos"] if e[0] >= desde)
        for clave in [c for c in self.archivos if c not in vivos]:
            del self.archivos[clave]
        return salida

    @staticmethod
    def _leer(ruta, estado, interpretar):
        try:
            with open(ruta, "rb") as archivo:
                archivo.seek(estado["pos"])
                bloque = archivo.read()
        except OSError:
            return
        # Una línea a medio escribir se deja para la siguiente vuelta.
        corte = bloque.rfind(b"\n") + 1
        estado["pos"] += corte
        for linea in bloque[:corte].splitlines():
            evento = interpretar(linea, estado["memoria"])
            if evento:
                estado["eventos"].append(evento)


# ---------- Claude Code ----------

def _linea_claude(linea, memoria):
    if b'"usage"' not in linea:
        return None
    try:
        dato = json.loads(linea)
    except ValueError:
        return None
    mensaje = dato.get("message") if isinstance(dato, dict) else None
    uso = mensaje.get("usage") if isinstance(mensaje, dict) else None
    if not isinstance(uso, dict):
        return None
    # La misma respuesta aparece en varias líneas (una por bloque de contenido).
    clave = (mensaje.get("id"), dato.get("requestId"))
    if clave[0] and clave in memoria:
        return None
    memoria[clave] = True
    momento = _epoch(dato.get("timestamp"))
    tokens = _entero(uso.get("input_tokens")) + _entero(uso.get("cache_creation_input_tokens")) + _entero(uso.get("output_tokens"))
    return (momento, tokens) if momento and tokens else None


def _limites_claude(carpeta_datos, ahora):
    try:
        guardado = json.loads((carpeta_datos / "uso" / "claude.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None, None
    crudos = guardado.get("rate_limits") if isinstance(guardado, dict) else None
    if not isinstance(crudos, dict):
        return [], _epoch(guardado.get("visto")) if isinstance(guardado, dict) else None
    limites = []
    for clave, nombre in (("five_hour", "5h"), ("seven_day", "7d"), ("spend_limit", "gasto")):
        ventana = crudos.get(clave)
        if isinstance(ventana, dict) and isinstance(ventana.get("used_percentage"), (int, float)):
            limites.append(_limite(nombre, ventana["used_percentage"], _epoch(ventana.get("resets_at")), ahora))
    return limites, _epoch(guardado.get("visto"))


# ---------- Codex ----------

def _linea_codex(linea, memoria):
    if b'"token_count"' not in linea:
        return None
    try:
        dato = json.loads(linea)
    except ValueError:
        return None
    carga = dato.get("payload") if isinstance(dato, dict) else None
    if not isinstance(carga, dict) or carga.get("type") != "token_count":
        return None
    momento = _epoch(dato.get("timestamp"))
    if isinstance(carga.get("rate_limits"), dict) and momento:
        memoria["limites"] = (momento, carga["rate_limits"])
    info = carga.get("info")
    total = info.get("total_token_usage") if isinstance(info, dict) else None
    if not isinstance(total, dict) or not momento:
        return None
    # El total es acumulado por sesión: lo gastado en este paso es la diferencia.
    acumulado = _entero(total.get("input_tokens")) - _entero(total.get("cached_input_tokens")) + _entero(total.get("output_tokens"))
    gastado = acumulado - memoria.get("acumulado", 0)
    memoria["acumulado"] = acumulado
    return (momento, gastado) if gastado > 0 else None


def _limites_codex(bitacoras, ahora):
    reciente = None
    for estado in bitacoras.archivos.values():
        visto = estado["memoria"].get("limites")
        if visto and (reciente is None or visto[0] > reciente[0]):
            reciente = visto
    if not reciente:
        return [], None, None
    momento, crudos = reciente
    limites = []
    for clave in ("primary", "secondary"):
        ventana = crudos.get(clave)
        if not isinstance(ventana, dict) or not isinstance(ventana.get("used_percent"), (int, float)):
            continue
        minutos = ventana.get("window_minutes") or 0
        nombre = "5h" if minutos <= 300 else "7d" if minutos >= 10080 else f"{round(minutos / 60)}h"
        reinicia = _epoch(ventana.get("resets_at"))
        if reinicia is None and isinstance(ventana.get("resets_in_seconds"), (int, float)):
            reinicia = momento + ventana["resets_in_seconds"]
        limites.append(_limite(nombre, ventana["used_percent"], reinicia, ahora))
    plan = crudos.get("plan_type") if isinstance(crudos.get("plan_type"), str) else None
    return limites, momento, plan


# ---------- Gemini CLI ----------

def _tokens_gemini(registro):
    fichas = registro.get("tokens") if isinstance(registro, dict) else None
    momento = _epoch(registro.get("timestamp")) if isinstance(registro, dict) else None
    if not isinstance(fichas, dict) or not momento:
        return None
    tokens = max(0, _entero(fichas.get("input")) - _entero(fichas.get("cached"))) + _entero(fichas.get("output")) + _entero(fichas.get("thoughts"))
    return (momento, tokens) if tokens else None


def _linea_gemini(linea, memoria):
    if b'"tokens"' not in linea:
        return None
    try:
        dato = json.loads(linea)
    except ValueError:
        return None
    if not isinstance(dato, dict) or dato.get("id") in memoria:
        return None
    memoria[dato.get("id")] = True
    return _tokens_gemini(dato)


def _sesiones_gemini_json(rutas, desde):
    """Versiones anteriores de Gemini CLI guardaban cada sesión como un solo .json."""
    eventos = []
    for ruta in rutas:
        try:
            if ruta.stat().st_mtime < desde:
                continue
            sesion = json.loads(ruta.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for mensaje in sesion.get("messages", []) if isinstance(sesion, dict) else []:
            evento = _tokens_gemini(mensaje)
            if evento and evento[0] >= desde:
                eventos.append(evento)
    return eventos


# ---------- resumen ----------

def _limite(nombre, usado, reinicia, ahora):
    # Si la ventana ya se reinició desde la última lectura, el uso volvió a cero.
    vencido = reinicia is not None and reinicia <= ahora
    return {
        "id": nombre,
        "usado": 0.0 if vencido else round(max(0.0, float(usado)), 1),
        "reinicia": None if vencido else reinicia,
    }


def _tokens(eventos, ahora):
    hoy = datetime.fromtimestamp(ahora).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    return {
        "hoy": sum(t for momento, t in eventos if momento >= hoy),
        "semana": sum(t for _, t in eventos),
    }


class Uso:
    def __init__(self, carpeta_datos, casa=None):
        casa = Path(casa) if casa else Path.home()
        self.datos = Path(carpeta_datos)
        self.claude = Path(os.environ.get("CLAUDE_CONFIG_DIR") or casa / ".claude")
        self.codex = Path(os.environ.get("CODEX_HOME") or casa / ".codex")
        self.gemini = casa / ".gemini"
        self.bitacoras = {"claude": Bitacoras(), "codex": Bitacoras(), "gemini": Bitacoras()}
        self.candado = threading.Lock()
        self.ultimo = None

    def resumen(self, ahora=None, forzar=False):
        with self.candado:
            real = ahora is None
            ahora = time.time() if real else ahora
            if real and not forzar and self.ultimo and ahora - self.ultimo["generado"] < REFRESCO_S:
                return self.ultimo
            desde = (datetime.fromtimestamp(ahora) - timedelta(days=DIAS)).timestamp()
            herramientas = [h for h in (self._claude(ahora, desde), self._codex(ahora, desde), self._gemini(ahora, desde)) if h]
            self.ultimo = {"generado": ahora, "herramientas": herramientas}
            return self.ultimo

    def _claude(self, ahora, desde):
        carpeta = self.claude / "projects"
        if not carpeta.is_dir():
            return None
        eventos = self.bitacoras["claude"].eventos(carpeta.rglob("*.jsonl"), _linea_claude, desde)
        limites, visto = _limites_claude(self.datos, ahora)
        return {
            "id": "claude",
            "nombre": "Claude",
            "plan": None,
            "limites": limites or [],
            "conectado": limites is not None,
            "visto": visto,
            "tokens": _tokens(eventos, ahora),
        }

    def _codex(self, ahora, desde):
        carpeta = self.codex / "sessions"
        if not carpeta.is_dir():
            return None
        eventos = self.bitacoras["codex"].eventos(carpeta.rglob("*.jsonl"), _linea_codex, desde)
        limites, visto, plan = _limites_codex(self.bitacoras["codex"], ahora)
        return {
            "id": "codex",
            "nombre": "Codex",
            "plan": plan,
            "limites": limites,
            "conectado": True,
            "visto": visto,
            "tokens": _tokens(eventos, ahora),
        }

    def _gemini(self, ahora, desde):
        carpeta = self.gemini / "tmp"
        if not carpeta.is_dir():
            return None
        eventos = self.bitacoras["gemini"].eventos(carpeta.glob("*/chats/**/*.jsonl"), _linea_gemini, desde)
        eventos += _sesiones_gemini_json(carpeta.glob("*/chats/**/*.json"), desde)
        return {
            "id": "gemini",
            "nombre": "Gemini",
            "plan": None,
            "limites": [],
            "conectado": True,
            "visto": max((m for m, _ in eventos), default=None),
            "tokens": _tokens(eventos, ahora),
        }
