#!/usr/bin/env python3
"""Servidor local de Trayecto. Solo biblioteca estándar de Python 3.8+.

Sirve la interfaz (carpeta web/) y guarda el estado en dos archivos JSON:

    trayecto.json      proyectos activos y ajustes
    finalizadas.json   tareas y proyectos terminados (para poder revertirlos)

Por defecto solo escucha en esta computadora (127.0.0.1).
"""

import argparse
import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
WEB = RAIZ / "web"
PUERTO = 4747
LIMITE_BYTES = 5 * 1024 * 1024
VERSION = 1

TIPOS = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".webmanifest": "application/manifest+json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
}


def carpeta_datos(valor=None):
    ruta = valor or os.environ.get("TRAYECTO_DIR") or "~/.trayecto"
    return Path(ruta).expanduser().resolve()


class Almacen:
    """Lee y escribe los dos archivos de estado de forma atómica."""

    def __init__(self, carpeta):
        self.carpeta = Path(carpeta)
        self.activos = self.carpeta / "trayecto.json"
        self.finalizadas = self.carpeta / "finalizadas.json"
        self.candado = threading.Lock()

    @staticmethod
    def _leer(ruta):
        try:
            datos = json.loads(ruta.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}
        if not isinstance(datos, dict):
            raise ValueError(f"{ruta.name} no contiene un objeto JSON")
        return datos

    @staticmethod
    def _escribir(ruta, datos):
        texto = json.dumps(datos, ensure_ascii=False, indent=2) + "\n"
        if ruta.exists():
            shutil.copyfile(ruta, ruta.with_name(ruta.name + ".bak"))
        temporal = ruta.with_name(ruta.name + ".tmp")
        temporal.write_text(texto, encoding="utf-8")
        os.replace(temporal, ruta)

    def _estado(self):
        activos = self._leer(self.activos)
        finalizadas = self._leer(self.finalizadas)
        return {
            "version": activos.get("version", VERSION),
            "ajustes": activos.get("ajustes", {}),
            "proyectos": activos.get("proyectos", []),
            "finalizadas": {
                "tareas": finalizadas.get("tareas", []),
                "proyectos": finalizadas.get("proyectos", []),
            },
        }

    @staticmethod
    def _huella(estado):
        crudo = json.dumps(estado, ensure_ascii=False, sort_keys=True).encode("utf-8")
        return '"' + hashlib.sha256(crudo).hexdigest()[:20] + '"'

    def cargar(self):
        with self.candado:
            estado = self._estado()
        return estado, self._huella(estado)

    def guardar(self, estado, huella_esperada=None):
        """Devuelve la huella nueva, o None si el archivo cambió por fuera."""
        with self.candado:
            if huella_esperada and huella_esperada != self._huella(self._estado()):
                return None
            self.carpeta.mkdir(parents=True, exist_ok=True)
            finalizadas = estado["finalizadas"]
            self._escribir(
                self.finalizadas,
                {"version": VERSION, "tareas": finalizadas["tareas"], "proyectos": finalizadas["proyectos"]},
            )
            self._escribir(
                self.activos,
                {"version": VERSION, "ajustes": estado["ajustes"], "proyectos": estado["proyectos"]},
            )
            return self._huella(self._estado())


def validar(estado):
    if not isinstance(estado, dict):
        raise ValueError("el estado debe ser un objeto")
    if not isinstance(estado.get("ajustes"), dict):
        raise ValueError("falta 'ajustes'")
    if not isinstance(estado.get("proyectos"), list):
        raise ValueError("falta 'proyectos'")
    finalizadas = estado.get("finalizadas")
    if not isinstance(finalizadas, dict):
        raise ValueError("falta 'finalizadas'")
    for clave in ("tareas", "proyectos"):
        if not isinstance(finalizadas.get(clave), list):
            raise ValueError(f"falta 'finalizadas.{clave}'")


class Manejador(BaseHTTPRequestHandler):
    server_version = "Trayecto"
    almacen = None
    anfitriones = None  # None = cualquiera (modo --red)

    def log_message(self, formato, *args):
        if self.server.ruidoso:
            super().log_message(formato, *args)

    # ---- utilidades ----

    def _responder(self, estado, cuerpo=b"", tipo="text/plain; charset=utf-8", extra=None):
        self.send_response(estado)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(cuerpo)))
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        for clave, valor in (extra or {}).items():
            self.send_header(clave, valor)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(cuerpo)

    def _json(self, estado, datos, extra=None):
        cuerpo = json.dumps(datos, ensure_ascii=False).encode("utf-8")
        self._responder(estado, cuerpo, TIPOS[".json"], extra)

    def _anfitrion_valido(self):
        # Frena el "DNS rebinding": en modo local solo se aceptan nombres de esta máquina.
        if self.anfitriones is None:
            return True
        return self.headers.get("Host", "").lower() in self.anfitriones

    def _origen_valido(self):
        origen = self.headers.get("Origin")
        if not origen:
            return True
        return origen.split("://", 1)[-1].lower() == self.headers.get("Host", "").lower()

    # ---- rutas ----

    def do_GET(self):
        if not self._anfitrion_valido():
            return self._responder(HTTPStatus.FORBIDDEN, b"Host no permitido")
        ruta = self.path.split("?", 1)[0].split("#", 1)[0]
        if ruta == "/api/estado":
            return self._leer_estado()
        if ruta.startswith("/api/"):
            return self._json(HTTPStatus.NOT_FOUND, {"error": "no existe"})
        return self._archivo(ruta)

    do_HEAD = do_GET

    def do_PUT(self):
        if not self._anfitrion_valido() or not self._origen_valido():
            return self._responder(HTTPStatus.FORBIDDEN, b"Origen no permitido")
        if self.path.split("?", 1)[0] != "/api/estado":
            return self._json(HTTPStatus.NOT_FOUND, {"error": "no existe"})
        # Una página ajena no puede mandar este encabezado sin permiso CORS, que nunca damos.
        if self.headers.get("X-Trayecto") != "1":
            return self._json(HTTPStatus.FORBIDDEN, {"error": "falta X-Trayecto"})
        try:
            largo = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            largo = -1
        if largo < 0 or largo > LIMITE_BYTES:
            return self._json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "demasiado grande"})
        try:
            estado = json.loads(self.rfile.read(largo).decode("utf-8"))
            validar(estado)
        except (ValueError, UnicodeDecodeError) as error:
            return self._json(HTTPStatus.BAD_REQUEST, {"error": str(error)})
        try:
            huella = self.almacen.guardar(estado, self.headers.get("If-Match"))
        except (OSError, ValueError) as error:
            return self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(error)})
        if huella is None:
            return self._json(HTTPStatus.CONFLICT, {"error": "el archivo cambió por fuera"})
        self._json(HTTPStatus.OK, {"ok": True}, {"ETag": huella})

    def _leer_estado(self):
        try:
            estado, huella = self.almacen.cargar()
        except (OSError, ValueError) as error:
            return self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(error)})
        if self.headers.get("If-None-Match") == huella:
            return self._responder(HTTPStatus.NOT_MODIFIED, extra={"ETag": huella})
        self._json(HTTPStatus.OK, estado, {"ETag": huella})

    def _archivo(self, ruta):
        relativa = ruta.lstrip("/") or "index.html"
        destino = (WEB / relativa).resolve()
        if WEB not in destino.parents or not destino.is_file():
            return self._responder(HTTPStatus.NOT_FOUND, b"No encontrado")
        tipo = TIPOS.get(destino.suffix.lower(), "application/octet-stream")
        self._responder(HTTPStatus.OK, destino.read_bytes(), tipo)


def ip_local():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 9))  # no envía nada; solo elige la interfaz de salida
            return s.getsockname()[0]
    except OSError:
        return None


def crear_servidor(carpeta, puerto=PUERTO, red=False, ruidoso=False):
    manejador = type("ManejadorTrayecto", (Manejador,), {})
    manejador.almacen = Almacen(carpeta)
    servidor = ThreadingHTTPServer(("0.0.0.0" if red else "127.0.0.1", puerto), manejador)
    servidor.daemon_threads = True
    servidor.ruidoso = ruidoso
    real = servidor.server_address[1]
    manejador.anfitriones = None if red else {f"127.0.0.1:{real}", f"localhost:{real}"}
    return servidor


def abrir_ventana(url):
    """Intenta abrir una ventana sin barras con un navegador tipo Chromium."""
    candidatos = [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
        os.path.expandvars(r"%ProgramFiles%\Google\Chrome\Application\chrome.exe"),
        os.path.expandvars(r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"),
        os.path.expandvars(r"%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"),
    ]
    for nombre in ("google-chrome", "chromium", "chromium-browser", "microsoft-edge", "brave-browser"):
        ruta = shutil.which(nombre)
        if ruta:
            candidatos.append(ruta)
    for ruta in candidatos:
        if os.path.isfile(ruta):
            subprocess.Popen(
                [ruta, f"--app={url}", "--window-size=560,760"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return True
    return False


def main(argv=None):
    p = argparse.ArgumentParser(prog="trayecto", description="Tus proyectos y su avance, en una línea.")
    p.add_argument("--puerto", type=int, default=int(os.environ.get("TRAYECTO_PUERTO", PUERTO)))
    p.add_argument("--datos", help="carpeta de los JSON (por defecto ~/.trayecto o $TRAYECTO_DIR)")
    p.add_argument("--red", action="store_true", help="permite abrirlo desde otros dispositivos de tu red (tu teléfono)")
    p.add_argument("--ventana", action="store_true", help="abre una ventana sin barras (Chrome, Edge o Brave)")
    p.add_argument("--sin-abrir", action="store_true", help="no abre el navegador")
    p.add_argument("--ruidoso", action="store_true", help="muestra cada petición")
    args = p.parse_args(argv)

    carpeta = carpeta_datos(args.datos)
    try:
        servidor = crear_servidor(carpeta, args.puerto, args.red, args.ruidoso)
    except OSError as error:
        print(f"No pude abrir el puerto {args.puerto}: {error}", file=sys.stderr)
        print("¿Ya está corriendo Trayecto? Prueba con --puerto 4748.", file=sys.stderr)
        return 1

    url = f"http://127.0.0.1:{servidor.server_address[1]}/"
    print(f"Trayecto   {url}")
    print(f"Datos      {carpeta}")
    if args.red:
        ip = ip_local()
        if ip:
            print(f"En tu red  http://{ip}:{servidor.server_address[1]}/")
        print("Ojo: con --red cualquiera en tu misma red puede ver y editar tus proyectos.")
    print("Ctrl+C para salir.")

    if not args.sin_abrir:
        if not (args.ventana and abrir_ventana(url)):
            webbrowser.open(url)
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        servidor.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
