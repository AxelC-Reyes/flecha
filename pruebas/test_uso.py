import json
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import uso  # noqa: E402

AHORA = datetime(2026, 3, 10, 15, 0, 0).timestamp()


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat().replace("+00:00", "Z")


def linea_claude(ident, epoch, entrada=10, cache=100, salida=50, lectura=99999):
    return json.dumps({
        "type": "assistant", "requestId": "req-" + ident, "timestamp": iso(epoch),
        "message": {"id": ident, "content": "NO SE LEE", "usage": {
            "input_tokens": entrada, "cache_creation_input_tokens": cache,
            "cache_read_input_tokens": lectura, "output_tokens": salida}},
    })


def linea_codex(epoch, entrada, en_cache, salida, primario=None, secundario=None):
    carga = {"type": "token_count", "info": {"total_token_usage": {
        "input_tokens": entrada, "cached_input_tokens": en_cache, "output_tokens": salida}}}
    if primario:
        carga["rate_limits"] = {"plan_type": "plus",
                                "primary": {"used_percent": primario[0], "window_minutes": 300, "resets_at": primario[1]},
                                "secondary": {"used_percent": secundario[0], "window_minutes": 10080, "resets_at": secundario[1]}}
    return json.dumps({"timestamp": iso(epoch), "type": "event_msg", "payload": carga})


class PruebaUso(unittest.TestCase):
    def setUp(self):
        self.temporal = tempfile.TemporaryDirectory()
        self.casa = Path(self.temporal.name)
        self.datos = self.casa / "datos"
        self.lector = uso.Uso(self.datos, casa=self.casa)

    def tearDown(self):
        self.temporal.cleanup()

    def escribir(self, relativa, lineas, modo="w"):
        ruta = self.casa / relativa
        ruta.parent.mkdir(parents=True, exist_ok=True)
        with open(ruta, modo, encoding="utf-8") as archivo:
            archivo.write("".join(l + "\n" for l in lineas))
        return ruta

    def herramienta(self, ident):
        return next((h for h in self.lector.resumen(AHORA)["herramientas"] if h["id"] == ident), None)

    def test_sin_herramientas_instaladas(self):
        self.assertEqual(self.lector.resumen(AHORA)["herramientas"], [])

    def test_claude_cuenta_sin_duplicar_y_sin_lecturas_de_cache(self):
        self.escribir(".claude/projects/p/s.jsonl", [
            linea_claude("a", AHORA - 3600),
            linea_claude("a", AHORA - 3600),          # misma respuesta, otro bloque
            linea_claude("b", AHORA - 3 * 86400),     # esta semana, no hoy
            '{"type":"user","message":{"content":"hola"}}',
            "esto no es json",
        ])
        claude = self.herramienta("claude")
        self.assertEqual(claude["tokens"], {"hoy": 160, "semana": 320})
        self.assertFalse(claude["conectado"])
        self.assertEqual(claude["limites"], [])

    def test_claude_lee_solo_lo_nuevo(self):
        ruta = self.escribir(".claude/projects/p/s.jsonl", [linea_claude("a", AHORA - 60)])
        self.assertEqual(self.herramienta("claude")["tokens"]["hoy"], 160)
        self.escribir(".claude/projects/p/s.jsonl", [linea_claude("b", AHORA - 30)], modo="a")
        self.assertEqual(self.herramienta("claude")["tokens"]["hoy"], 320)
        with open(ruta, "a", encoding="utf-8") as archivo:
            archivo.write(linea_claude("c", AHORA - 10)[:40])  # línea a medio escribir
        self.assertEqual(self.herramienta("claude")["tokens"]["hoy"], 320)

    def test_claude_limites_desde_la_status_line(self):
        self.escribir(".claude/projects/p/s.jsonl", [linea_claude("a", AHORA - 60)])
        (self.datos / "uso").mkdir(parents=True)
        (self.datos / "uso" / "claude.json").write_text(json.dumps({"visto": AHORA - 60, "rate_limits": {
            "five_hour": {"used_percentage": 23.5, "resets_at": AHORA - 5},       # ya se reinició
            "seven_day": {"used_percentage": 41.2, "resets_at": AHORA + 86400}}}))
        claude = self.herramienta("claude")
        self.assertTrue(claude["conectado"])
        self.assertEqual(claude["limites"], [
            {"id": "5h", "usado": 0.0, "reinicia": None},
            {"id": "7d", "usado": 41.2, "reinicia": AHORA + 86400},
        ])

    def test_codex_limites_y_diferencias_del_acumulado(self):
        self.escribir(".codex/sessions/2026/03/10/rollout-a.jsonl", [
            linea_codex(AHORA - 7200, 1000, 800, 50),
            linea_codex(AHORA - 7100, 1000, 800, 50),                      # repetido: no suma
            linea_codex(AHORA - 3600, 3000, 2500, 150, (22.0, AHORA + 600), (97.0, AHORA + 86400)),
        ])
        codex = self.herramienta("codex")
        self.assertEqual(codex["tokens"], {"hoy": 650, "semana": 650})
        self.assertEqual(codex["plan"], "plus")
        self.assertEqual([(l["id"], l["usado"]) for l in codex["limites"]], [("5h", 22.0), ("7d", 97.0)])

    def test_gemini_en_ambos_formatos(self):
        mensaje = {"id": "m1", "timestamp": iso(AHORA - 60), "type": "gemini",
                   "tokens": {"input": 500, "cached": 400, "output": 30, "thoughts": 20, "total": 550}}
        self.escribir(".gemini/tmp/abc/chats/session-1.jsonl", [json.dumps(mensaje), json.dumps(mensaje)])
        viejo = dict(mensaje, id="m2")
        self.escribir(".gemini/tmp/abc/chats/session-0.json", [json.dumps({"messages": [viejo, {"type": "user"}]})])
        gemini = self.herramienta("gemini")
        self.assertEqual(gemini["tokens"]["hoy"], 300)
        self.assertEqual(gemini["limites"], [])

    def test_ignora_archivos_viejos(self):
        import os
        ruta = self.escribir(".claude/projects/p/viejo.jsonl", [linea_claude("z", AHORA - 60)])
        os.utime(ruta, (AHORA - 30 * 86400, AHORA - 30 * 86400))
        self.assertEqual(self.herramienta("claude")["tokens"]["semana"], 0)


if __name__ == "__main__":
    unittest.main()
