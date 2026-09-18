#!/usr/bin/env python3
"""Servidor local de Flecha. Solo biblioteca estándar de Python 3.8+.

Sirve la interfaz (carpeta web/) y guarda el estado en dos archivos JSON:

    flecha.json      proyectos activos y ajustes
    finalizadas.json   tareas y proyectos terminados (para poder revertirlos)

Por defecto solo escucha en esta computadora (127.0.0.1).
"""

import argparse
import hashlib
import hmac
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from uso import Uso  # noqa: E402

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
    ruta = valor or os.environ.get("FLECHA_DIR") or "~/.flecha"
    return Path(ruta).expanduser().resolve()


class Almacen:
    """Lee y escribe los dos archivos de estado de forma atómica."""

    def __init__(self, carpeta):
        self.carpeta = Path(carpeta)
        self.activos = self.carpeta / "flecha.json"
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
    server_version = "Flecha"
    almacen = None
    uso = None
    anfitriones = None  # None = cualquiera (modo --red)
    clave = None  # con --red: lo que deben presentar los demás dispositivos
    emparejador = None
    clave_siempre = False  # solo para pruebas: exigirla también a esta computadora

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

    def _es_esta_maquina(self):
        return self.client_address[0] in ("127.0.0.1", "::1", "::ffff:127.0.0.1")

    def _clave_presentada(self):
        directa = self.headers.get("X-Flecha-Clave")
        if directa:
            return directa
        for trozo in self.headers.get("Cookie", "").split(";"):
            nombre, _, valor = trozo.strip().partition("=")
            if nombre == "flecha_clave":
                return valor
        return None

    def _autorizado(self):
        """Con --red, los demás dispositivos deben traer la clave del enlace."""
        if self.clave is None or (self._es_esta_maquina() and not self.clave_siempre):
            return True
        presentada = self._clave_presentada()
        return bool(presentada) and hmac.compare_digest(presentada, self.clave)

    def _canjear_clave(self):
        """`/?clave=...` guarda la clave en una cookie y limpia la URL. Devuelve si respondió."""
        partes = urlsplit(self.path)
        ofrecida = parse_qs(partes.query).get("clave", [None])[0]
        if self.clave is None or not ofrecida:
            return False
        if not hmac.compare_digest(ofrecida, self.clave):
            return False
        galleta = f"flecha_clave={self.clave}; Path=/; Max-Age=31536000; HttpOnly; SameSite=Strict"
        self._responder(HTTPStatus.FOUND, extra={"Location": partes.path or "/", "Set-Cookie": galleta})
        return True

    def _sin_clave(self):
        cuerpo = "Falta la clave. Abre el enlace completo que imprime ./flecha --red (incluye ?clave=...).".encode("utf-8")
        self._responder(HTTPStatus.UNAUTHORIZED, cuerpo)

    def _origen_valido(self):
        origen = self.headers.get("Origin")
        if not origen:
            return True
        return origen.split("://", 1)[-1].lower() == self.headers.get("Host", "").lower()

    # ---- rutas ----

    def do_GET(self):
        if not self._anfitrion_valido():
            return self._responder(HTTPStatus.FORBIDDEN, b"Host no permitido")
        if self._canjear_clave():
            return None
        if not self._autorizado():
            return self._sin_clave()
        ruta = self.path.split("?", 1)[0].split("#", 1)[0]
        if ruta == "/api/enlace":
            return self._enlace()
        if ruta == "/api/emparejar":
            return self._codigo()
        if ruta == "/api/estado":
            return self._leer_estado()
        if ruta == "/api/uso":
            return self._json(HTTPStatus.OK, self.uso.resumen())
        if ruta.startswith("/api/"):
            return self._json(HTTPStatus.NOT_FOUND, {"error": "no existe"})
        return self._archivo(ruta)

    do_HEAD = do_GET

    def do_POST(self):
        """Emparejar un teléfono: trae el código de 6 dígitos y recibe la clave. Solo con --red."""
        if not self._anfitrion_valido() or not self._origen_valido():
            return self._responder(HTTPStatus.FORBIDDEN, b"Origen no permitido")
        if self.path.split("?", 1)[0] != "/api/emparejar":
            return self._json(HTTPStatus.NOT_FOUND, {"error": "no existe"})
        if self.clave is None:
            return self._json(HTTPStatus.FORBIDDEN, {"error": "el servidor no está compartido en la red"})
        try:
            largo = int(self.headers.get("Content-Length", "0"))
            cuerpo = json.loads(self.rfile.read(min(max(largo, 0), 4096)).decode("utf-8"))
            codigo = str(cuerpo.get("codigo", "")).replace(" ", "")
        except (ValueError, AttributeError, UnicodeDecodeError):
            return self._json(HTTPStatus.BAD_REQUEST, {"error": "falta el código"})
        if not self.emparejador.validar(codigo):
            return self._json(HTTPStatus.FORBIDDEN, {"error": "código incorrecto o vencido"})
        self._json(HTTPStatus.OK, {"clave": self.clave, "nombre": socket.gethostname().split(".")[0]})

    def do_PUT(self):
        if not self._anfitrion_valido() or not self._origen_valido():
            return self._responder(HTTPStatus.FORBIDDEN, b"Origen no permitido")
        if not self._autorizado():
            return self._sin_clave()
        if self.path.split("?", 1)[0] != "/api/estado":
            return self._json(HTTPStatus.NOT_FOUND, {"error": "no existe"})
        # Una página ajena no puede mandar este encabezado sin permiso CORS, que nunca damos.
        if self.headers.get("X-Flecha") != "1":
            return self._json(HTTPStatus.FORBIDDEN, {"error": "falta X-Flecha"})
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

    def _codigo(self):
        """Un código nuevo para emparejar un teléfono. Solo se le entrega a esta misma computadora."""
        if not self._es_esta_maquina():
            return self._json(HTTPStatus.FORBIDDEN, {"error": "solo desde esta computadora"})
        if self.clave is None:
            return self._json(HTTPStatus.OK, {"red": False, "codigo": None})
        codigo, vence = self.emparejador.nuevo()
        self._json(HTTPStatus.OK, {"red": True, "codigo": codigo, "vence": vence, "url": enlace_red(self.server.server_address[1], self.clave)})

    def _enlace(self):
        """El enlace para el teléfono. Solo se le entrega a esta misma computadora."""
        if not self._es_esta_maquina():
            return self._json(HTTPStatus.FORBIDDEN, {"error": "solo desde esta computadora"})
        self._json(HTTPStatus.OK, {"red": self.clave is not None, "url": enlace_red(self.server.server_address[1], self.clave)})

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


class Emparejador:
    """Códigos de 6 dígitos, de 10 minutos y 5 intentos, para que un teléfono reciba la clave."""

    def __init__(self):
        self.codigo = None
        self.vence = 0
        self.intentos = 0
        self.candado = threading.Lock()

    def nuevo(self):
        with self.candado:
            self.codigo = "".join(secrets.choice("0123456789") for _ in range(6))
            self.vence = time.time() + 600
            self.intentos = 0
            return self.codigo, self.vence

    def validar(self, presentado):
        with self.candado:
            if not self.codigo or time.time() > self.vence:
                return False
            self.intentos += 1
            if self.intentos > 5:
                self.codigo = None
                return False
            if not hmac.compare_digest(presentado, self.codigo):
                return False
            self.codigo = None  # cada código sirve una sola vez
            return True


def anunciar_en_red(puerto):
    """Que el teléfono encuentre esta computadora solo (Bonjour), si el sistema lo permite."""
    nombre = f"Flecha en {socket.gethostname().split('.')[0]}"
    ordenes = [
        ["dns-sd", "-R", nombre, "_flecha._tcp", "local", str(puerto)],
        ["avahi-publish-service", nombre, "_flecha._tcp", str(puerto)],
    ]
    for orden in ordenes:
        if shutil.which(orden[0]):
            try:
                return subprocess.Popen(orden, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError:
                continue
    return None


def clave_de_red(carpeta):
    """La clave vive en <datos>/clave. Bórrala para generar otra y desconectar a todos."""
    ruta = Path(carpeta) / "clave"
    try:
        guardada = ruta.read_text(encoding="utf-8").strip()
        if len(guardada) >= 8:
            return guardada
    except OSError:
        pass
    nueva = secrets.token_urlsafe(9)
    ruta.parent.mkdir(parents=True, exist_ok=True)
    ruta.write_text(nueva + "\n", encoding="utf-8")
    os.chmod(ruta, 0o600)
    return nueva


def enlace_red(puerto, clave):
    ip = ip_local()
    if not ip or not clave:
        return None
    return f"http://{ip}:{puerto}/?clave={clave}"


def crear_servidor(carpeta, puerto=PUERTO, red=False, ruidoso=False, casa=None):
    manejador = type("ManejadorFlecha", (Manejador,), {})
    manejador.almacen = Almacen(carpeta)
    manejador.clave = clave_de_red(carpeta) if red else None
    manejador.emparejador = Emparejador()
    manejador.uso = Uso(carpeta, casa)
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


def conectar_claude():
    """Registra integraciones/claude_statusline.py como status line de Claude Code."""
    ajustes = Path(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude").expanduser() / "settings.json"
    guion = RAIZ / "integraciones" / "claude_statusline.py"
    comando = f'python3 "{guion}"'
    try:
        datos = json.loads(ajustes.read_text(encoding="utf-8")) if ajustes.exists() else {}
    except (OSError, ValueError) as error:
        print(f"No pude leer {ajustes}: {error}", file=sys.stderr)
        return 1
    actual = datos.get("statusLine")
    if isinstance(actual, dict) and "claude_statusline.py" in str(actual.get("command", "")):
        print("Claude Code ya está conectado con Flecha.")
        return 0
    if actual:
        print("Ya tienes una status line en Claude Code y no la voy a pisar:")
        print(f"  {json.dumps(actual, ensure_ascii=False)}")
        print("Para conservarla y conectar Flecha, cambia su comando por este:")
        print(f"  FLECHA_STATUSLINE_SIGUIENTE='<tu comando actual>' {comando}")
        return 1
    datos["statusLine"] = {"type": "command", "command": comando}
    ajustes.parent.mkdir(parents=True, exist_ok=True)
    if ajustes.exists():
        shutil.copyfile(ajustes, ajustes.with_name("settings.json.antes-de-flecha"))
    temporal = ajustes.with_name("settings.json.tmp")
    temporal.write_text(json.dumps(datos, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporal, ajustes)
    print(f"Listo. Claude Code le pasará sus límites a Flecha ({ajustes}).")
    print("Los porcentajes aparecen después del primer mensaje de tu siguiente sesión.")
    print('Para quitarlo, borra "statusLine" de ese archivo.')
    return 0


def vigilar_padre(servidor):
    """Si quien nos arrancó desaparece (aunque sea a la fuerza), no dejamos el servidor huérfano."""
    padre = os.getppid()

    def ronda():
        while os.getppid() == padre:
            threading.Event().wait(2)
        servidor.shutdown()

    threading.Thread(target=ronda, daemon=True).start()


def pedir_codigo(puerto):
    import urllib.request

    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{puerto}/api/emparejar", timeout=3) as respuesta:
            datos = json.load(respuesta)
    except (OSError, ValueError):
        print(f"No hay un Flecha corriendo en el puerto {puerto}. Arráncalo con ./flecha --red.", file=sys.stderr)
        return 1
    if not datos.get("codigo"):
        print("Ese Flecha no está compartido en la red. Arráncalo con ./flecha --red.", file=sys.stderr)
        return 1
    print(f"Código para la app del teléfono: {datos['codigo'][:3]} {datos['codigo'][3:]}   (vale 10 minutos)")
    return 0


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)  # que el enlace y el código salgan al instante
    p = argparse.ArgumentParser(prog="flecha", description="Tus proyectos y su avance, en una línea.")
    p.add_argument("--puerto", type=int, default=int(os.environ.get("FLECHA_PUERTO", PUERTO)))
    p.add_argument("--datos", help="carpeta de los JSON (por defecto ~/.flecha o $FLECHA_DIR)")
    p.add_argument("--red", action="store_true", help="permite abrirlo desde otros dispositivos de tu red (tu teléfono)")
    p.add_argument("--ventana", action="store_true", help="abre una ventana sin barras (Chrome, Edge o Brave)")
    p.add_argument("--sin-abrir", action="store_true", help="no abre el navegador")
    p.add_argument("--ruidoso", action="store_true", help="muestra cada petición")
    p.add_argument("--con-padre", action="store_true", help=argparse.SUPPRESS)  # lo usa la app de Mac: salir si ella muere
    p.add_argument("--codigo", action="store_true", help="pide un código nuevo para emparejar el teléfono al servidor que ya corre, y termina")
    p.add_argument("--conectar-claude", action="store_true", help="conecta los límites de Claude Code con la sección Uso, y termina")
    args = p.parse_args(argv)
    if args.conectar_claude:
        return conectar_claude()
    if args.codigo:
        return pedir_codigo(args.puerto)

    carpeta = carpeta_datos(args.datos)
    try:
        servidor = crear_servidor(carpeta, args.puerto, args.red, args.ruidoso)
    except OSError as error:
        print(f"No pude abrir el puerto {args.puerto}: {error}", file=sys.stderr)
        print("¿Ya está corriendo Flecha? Prueba con --puerto 4748.", file=sys.stderr)
        return 1

    url = f"http://127.0.0.1:{servidor.server_address[1]}/"
    print(f"Flecha   {url}")
    print(f"Datos      {carpeta}")
    if args.red:
        enlace = enlace_red(servidor.server_address[1], servidor.RequestHandlerClass.clave)
        print(f"En tu red  {enlace or '(no encontré la IP de esta computadora)'}")
        print("Ese enlace lleva una clave: ábrelo en tu teléfono, o pégalo en la app de Flecha.")
        codigo, _ = servidor.RequestHandlerClass.emparejador.nuevo()
        print(f"Código para la app del teléfono: {codigo[:3]} {codigo[3:]}   (vale 10 minutos; ./flecha --codigo da otro)")
        anuncio = anunciar_en_red(servidor.server_address[1])
        print(f"Para cambiarla, borra {carpeta / 'clave'} y vuelve a arrancar.")
    print("Ctrl+C para salir.")

    if args.con_padre:
        vigilar_padre(servidor)
    if not args.sin_abrir:
        if not (args.ventana and abrir_ventana(url)):
            webbrowser.open(url)
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        servidor.server_close()
        if args.red and anuncio:
            anuncio.terminate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
