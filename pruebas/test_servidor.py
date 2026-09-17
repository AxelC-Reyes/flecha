import http.client
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import servidor  # noqa: E402

ESTADO = {
    "version": 1,
    "ajustes": {"color": "#0a84ff"},
    "proyectos": [{"id": "p1", "nombre": "Huerto", "previo": 0, "tareas": [{"id": "t1", "titulo": "Sembrar"}]}],
    "finalizadas": {"tareas": [{"id": "t0", "titulo": "Tierra", "proyectoId": "p1"}], "proyectos": []},
}


class PruebaServidor(unittest.TestCase):
    def setUp(self):
        self.temporal = tempfile.TemporaryDirectory()
        self.carpeta = Path(self.temporal.name) / "datos"
        self.servidor = servidor.crear_servidor(self.carpeta, puerto=0)
        self.puerto = self.servidor.server_address[1]
        self.hilo = threading.Thread(target=self.servidor.serve_forever, daemon=True)
        self.hilo.start()

    def tearDown(self):
        self.servidor.shutdown()
        self.servidor.server_close()
        self.temporal.cleanup()

    def pedir(self, metodo, ruta, cuerpo=None, encabezados=None):
        conexion = http.client.HTTPConnection("127.0.0.1", self.puerto, timeout=5)
        datos = json.dumps(cuerpo).encode("utf-8") if cuerpo is not None else None
        conexion.request(metodo, ruta, body=datos, headers=encabezados or {})
        respuesta = conexion.getresponse()
        contenido = respuesta.read()
        conexion.close()
        return respuesta, contenido

    def guardar(self, estado, extra=None):
        encabezados = {"X-Trayecto": "1", "Content-Type": "application/json", **(extra or {})}
        return self.pedir("PUT", "/api/estado", estado, encabezados)

    def test_estado_vacio_sin_archivos(self):
        r, cuerpo = self.pedir("GET", "/api/estado")
        self.assertEqual(r.status, 200)
        estado = json.loads(cuerpo)
        self.assertEqual(estado["proyectos"], [])
        self.assertEqual(estado["finalizadas"], {"tareas": [], "proyectos": []})
        self.assertFalse(self.carpeta.exists())

    def test_guardar_separa_en_dos_archivos(self):
        r, _ = self.guardar(ESTADO)
        self.assertEqual(r.status, 200)
        activos = json.loads((self.carpeta / "trayecto.json").read_text(encoding="utf-8"))
        finalizadas = json.loads((self.carpeta / "finalizadas.json").read_text(encoding="utf-8"))
        self.assertEqual(activos["proyectos"][0]["nombre"], "Huerto")
        self.assertNotIn("finalizadas", activos)
        self.assertEqual(finalizadas["tareas"][0]["titulo"], "Tierra")
        r, cuerpo = self.pedir("GET", "/api/estado")
        self.assertEqual(json.loads(cuerpo), ESTADO)

    def test_etag_y_304(self):
        r, _ = self.guardar(ESTADO)
        huella = r.getheader("ETag")
        r, _ = self.pedir("GET", "/api/estado", encabezados={"If-None-Match": huella})
        self.assertEqual(r.status, 304)

    def test_conflicto_si_el_archivo_cambio_por_fuera(self):
        r, _ = self.guardar(ESTADO)
        huella = r.getheader("ETag")
        ruta = self.carpeta / "trayecto.json"
        activos = json.loads(ruta.read_text(encoding="utf-8"))
        activos["proyectos"][0]["nombre"] = "Editado a mano"
        ruta.write_text(json.dumps(activos), encoding="utf-8")
        r, _ = self.guardar(ESTADO, {"If-Match": huella})
        self.assertEqual(r.status, 409)
        self.assertIn("Editado a mano", ruta.read_text(encoding="utf-8"))

    def test_respaldo_antes_de_sobrescribir(self):
        self.guardar(ESTADO)
        otro = json.loads(json.dumps(ESTADO))
        otro["proyectos"][0]["nombre"] = "Jardín"
        self.guardar(otro)
        respaldo = json.loads((self.carpeta / "trayecto.json.bak").read_text(encoding="utf-8"))
        self.assertEqual(respaldo["proyectos"][0]["nombre"], "Huerto")

    def test_rechaza_escrituras_sin_encabezado(self):
        r, _ = self.pedir("PUT", "/api/estado", ESTADO, {"Content-Type": "application/json"})
        self.assertEqual(r.status, 403)

    def test_rechaza_otro_origen_y_otro_host(self):
        r, _ = self.guardar(ESTADO, {"Origin": "https://malo.example"})
        self.assertEqual(r.status, 403)
        r, _ = self.pedir("GET", "/api/estado", encabezados={"Host": "malo.example"})
        self.assertEqual(r.status, 403)

    def test_rechaza_estado_invalido(self):
        r, _ = self.guardar({"proyectos": "no"})
        self.assertEqual(r.status, 400)
        r, _ = self.guardar([1, 2, 3])
        self.assertEqual(r.status, 400)

    def test_sirve_la_interfaz_y_no_sale_de_web(self):
        r, cuerpo = self.pedir("GET", "/")
        self.assertEqual(r.status, 200)
        self.assertIn(b"<html", cuerpo.lower())
        r, _ = self.pedir("GET", "/../servidor.py")
        self.assertEqual(r.status, 404)
        r, _ = self.pedir("GET", "/%2e%2e/servidor.py")
        self.assertEqual(r.status, 404)


if __name__ == "__main__":
    unittest.main()
