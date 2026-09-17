# Trayecto

Tus proyectos y su avance, en una línea.

En reposo Trayecto es solo eso: una línea vertical. La tocas y se abre en un cuadrado con los nombres de tus proyectos; las barras de avance se despliegan **por fuera** del cuadrado, cada una con su porcentaje al final. Nunca ves la barra completa, solo lo que llevas. Tocas un proyecto y aparecen sus faltantes. Cuando algo llega al 100 % desaparece, pero queda guardado en un archivo de finalizadas por si quieres revertirlo.

![La lista abierta, con las barras por fuera](capturas/lista.png)

| Los faltantes de un proyecto | Personalizar, como una carátula de reloj |
| --- | --- |
| ![Detalle](capturas/detalle.png) | ![Personalizar](capturas/personalizar.png) |

![Multicolor, tema claro, del lado derecho](capturas/multicolor-claro.png)

Sin cuentas, sin nube, sin dependencias. Tus datos son dos archivos JSON en tu computadora (o el almacenamiento de tu navegador).

## Instalar

```sh
git clone https://github.com/AxelC-Reyes/trayecto.git
cd trayecto
```

Y eliges cómo usarlo:

### 1. En cualquier computadora (macOS, Windows, Linux)

```sh
./trayecto            # Windows: trayecto.bat
```

Solo necesita Python 3, que en macOS y Linux ya viene instalado. Abre Trayecto en tu navegador y guarda tus datos en `~/.trayecto/`.

- `./trayecto --ventana` lo abre en una ventana sin barras (Chrome, Edge o Brave).
- `./trayecto --red` lo comparte con tu red wifi para abrirlo desde el teléfono. Ojo: cualquiera en esa red puede verlo y editarlo.
- `./trayecto --datos otra/carpeta` o la variable `TRAYECTO_DIR` cambian dónde viven los JSON.

### 2. Widget flotante en macOS

```sh
mac/construir.sh --abrir
```

Compila `mac/build/Trayecto.app` (unos segundos; requiere `xcode-select --install`). La línea queda pegada al borde de tu pantalla, encima de todo, en todos los escritorios. Desde el ícono de la barra de menús puedes mandarla detrás de tus ventanas o salir. Para que arranque con tu Mac: Ajustes del Sistema → General → Ítems de inicio.

### 3. Sin instalar nada (teléfono incluido)

Abre `web/index.html` con doble clic, o publica la carpeta `web/` en cualquier hosting estático (este repo trae un flujo para GitHub Pages). En iPhone y Android: *Compartir → Agregar a pantalla de inicio* y se comporta como app, incluso sin conexión. En este modo los datos viven en el navegador; usa *Personalizar → Exportar* para respaldarlos.

## Usarlo

- **La línea** se abre con un toque. Se cierra tocando fuera o con `Esc`.
- **＋** crea un proyecto. Tocar su nombre abre sus faltantes.
- **El círculo** de una tarea la da por terminada: sale de la lista, la barra crece y la tarea pasa a *Finalizadas*. Hay *Deshacer* durante unos segundos.
- Borrar el texto de una tarea la quita, como en Recordatorios.
- **Ajustar avance** sirve para proyectos que ya iban empezados: dices en qué porcentaje van y a partir de ahí cada tarea terminada suma.
- **Finalizadas** (la palomita) es el archivo. La flecha regresa una tarea a pendientes; si su proyecto ya se había ido, regresa con ella.
- **Personalizar**: color de las barras (automático, diez colores, multicolor o el que quieras), forma (redondeada, píldora o fina), lado de la pantalla y tema.

## Tus datos

```
~/.trayecto/
  trayecto.json      proyectos activos y ajustes
  finalizadas.json   lo terminado, para poder revertirlo
```

Son JSON legibles y puedes editarlos a mano o con scripts; Trayecto detecta el cambio y se actualiza solo. El formato completo está en [ESQUEMA.md](ESQUEMA.md). Lo mínimo que acepta:

```json
{
  "proyectos": [
    { "nombre": "Huerto", "tareas": ["Armar las camas", "Sembrar jitomate"] }
  ]
}
```

El avance de un proyecto es `hecho / (hecho + pendiente)`, contando tareas (o su `peso`, si se lo pones).

## Estado por plataforma

| Plataforma | Hoy | Falta |
| --- | --- | --- |
| macOS | Widget flotante nativo + web | Desenfoque a la medida del cuadrado |
| iOS / Android | Web app en pantalla de inicio | Widget de inicio (WidgetKit / Glance). Los widgets del sistema son estáticos: mostrarían las barras y al tocarlos abrirían la app |
| Windows | Web, ventana con `--ventana` | Widget del panel de Windows 11 vía PWA |
| Linux | Web, ventana con `--ventana` | Applet de bandeja o plasmoide. Se aceptan manos |

## Desarrollo

No hay paso de compilación: HTML, CSS y JavaScript a mano en `web/`, y un servidor de un solo archivo con la biblioteca estándar de Python.

```sh
node --test pruebas/                      # lógica (avance, completar, revertir)
python3 -m unittest discover -s pruebas   # servidor
```

Para capturas o demos, la URL acepta parámetros: `?abierto=1&vista=detalle&p=0&color=%230a84ff&forma=pildora&lado=derecha&tema=claro`.

El código y los nombres están en español. La interfaz sale en español o inglés según el idioma del navegador; los textos viven en `web/textos.js`.

## English, briefly

Trayecto is a tiny progress widget: a single line that opens into a rounded square listing your projects, with progress bars unfolding *outside* of it. Tap a project to see what's left; finished items move to an archive so you can revert them. No accounts, no cloud, no dependencies. Run `./trayecto` (Python 3), build the floating macOS widget with `mac/construir.sh --abrir`, or just open `web/index.html`. The UI switches to English automatically.

## Licencia

[MIT](LICENSE)
