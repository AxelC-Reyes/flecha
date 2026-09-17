# Formato de los datos

Flecha guarda todo en dos archivos JSON (por defecto en `~/.flecha/`). Puedes escribirlos a mano: al leerlos, Flecha completa lo que falte (ids, valores por defecto) y descarta lo que no entienda.

## `flecha.json`: lo activo

```json
{
  "version": 1,
  "ajustes": {
    "color": "auto",
    "forma": "redondeada",
    "lado": "izquierda",
    "tema": "auto"
  },
  "proyectos": [
    {
      "id": "huerto",
      "nombre": "Huerto",
      "previo": 1,
      "creado": "2026-01-05T18:00:00.000Z",
      "tareas": [
        { "id": "h1", "titulo": "Armar las camas" },
        { "id": "h2", "titulo": "Sistema de riego", "peso": 3 },
        "Sembrar jitomate"
      ]
    }
  ]
}
```

| Campo | Valores | Notas |
| --- | --- | --- |
| `ajustes.color` | `"auto"`, `"multicolor"` o `"#rrggbb"` | `auto` es blanco en tema oscuro y negro en claro |
| `ajustes.forma` | `"redondeada"`, `"pildora"`, `"fina"` | forma de las barras |
| `ajustes.lado` | `"izquierda"`, `"derecha"` | de qué lado vive la línea |
| `ajustes.tema` | `"auto"`, `"claro"`, `"oscuro"` | |
| `proyectos[].id` | texto único | opcional; se genera si falta |
| `proyectos[].nombre` | texto | obligatorio |
| `proyectos[].previo` | número ≥ 0 | trabajo hecho antes de llevarlo en Flecha, en unidades de tarea. Es lo que mueve *Ajustar avance* |
| `proyectos[].tareas[]` | objeto o texto | los faltantes. Un texto simple equivale a `{ "titulo": ... }` |
| `tareas[].peso` | número > 0 | opcional, 1 por defecto. Una tarea de peso 3 cuenta como tres |

El orden de `proyectos` es el orden en pantalla.

## `finalizadas.json`: el archivo

```json
{
  "version": 1,
  "tareas": [
    { "id": "h0", "titulo": "Comprar composta", "proyectoId": "huerto", "fin": "2026-01-20T18:00:00.000Z" }
  ],
  "proyectos": []
}
```

- Al terminar una tarea, se mueve de `proyectos[].tareas` a `finalizadas.tareas`, con su `proyectoId` y la fecha `fin`.
- Al terminar la última tarea de un proyecto, el proyecto entero pasa a `finalizadas.proyectos` (sin tareas; las suyas ya están en `finalizadas.tareas`).
- Revertir es el camino inverso. Si regresas una tarea de un proyecto archivado, el proyecto vuelve a `flecha.json`.
- Las tareas finalizadas cuyo `proyectoId` no exista se ignoran.

## Cómo se calcula el avance

```
hecho     = previo + suma de pesos de sus tareas en finalizadas.json
pendiente = suma de pesos de sus tareas en flecha.json
avance    = hecho / (hecho + pendiente)
```

En pantalla se redondea, y nunca se muestra 100 % mientras quede algo pendiente.

## API local

`servidor.py` expone el estado completo (los dos archivos juntos) en una sola ruta:

- `GET /api/estado` devuelve `{ version, ajustes, proyectos, finalizadas: { tareas, proyectos } }` con un `ETag`.
- `PUT /api/estado` lo reemplaza. Requiere el encabezado `X-Flecha: 1`; con `If-Match` responde `409` si los archivos cambiaron por fuera. Antes de escribir deja una copia `.bak`.

- `GET /api/uso` devuelve el consumo de asistentes de código: `{ generado, herramientas: [{ id, nombre, plan, conectado, visto, limites: [{ id, usado, reinicia }], tokens: { hoy, semana } }] }`. `usado` va de 0 a 100 y `reinicia` es epoch en segundos. Solo lectura; ver `uso.py`.

Por defecto solo escucha en `127.0.0.1` y rechaza peticiones con otro `Host` u `Origin`.
