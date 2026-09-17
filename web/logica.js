// Lógica pura de Flecha: sin DOM ni red, para poder probarla con `node --test`.
// Es un script clásico (no módulo) para que index.html también abra con doble clic.
// Todas las funciones que cambian el estado devuelven una copia nueva.

(function (raiz) {
  'use strict';

  const VERSION = 1;

  const AJUSTES_BASE = Object.freeze({
    color: 'auto', // 'auto' | 'multicolor' | '#rrggbb'
    forma: 'redondeada', // 'redondeada' | 'pildora' | 'fina'
    lado: 'izquierda', // 'izquierda' | 'derecha'
    tema: 'auto', // 'auto' | 'claro' | 'oscuro'
  });

  const FORMAS = ['redondeada', 'pildora', 'fina'];
  const LADOS = ['izquierda', 'derecha'];
  const TEMAS = ['auto', 'claro', 'oscuro'];

  function nuevoId() {
    if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID().slice(0, 8);
    return Math.random().toString(36).slice(2, 10).padEnd(8, '0');
  }

  function estadoVacio() {
    return {
      version: VERSION,
      ajustes: { ...AJUSTES_BASE },
      proyectos: [],
      finalizadas: { tareas: [], proyectos: [] },
    };
  }

  const copia = (x) => structuredClone(x);
  const texto = (x) => (typeof x === 'string' ? x.trim() : '');
  const numero = (x, base) => (Number.isFinite(x) && x >= 0 ? x : base);
  const peso = (t) => numero(t.peso, 1) || 1;

  function normalizarTarea(cruda, usados) {
    const t = typeof cruda === 'string' ? { titulo: cruda } : cruda;
    if (!t || typeof t !== 'object' || !texto(t.titulo)) return null;
    const tarea = { id: idUnico(t.id, usados), titulo: texto(t.titulo) };
    if (Number.isFinite(t.peso) && t.peso > 0 && t.peso !== 1) tarea.peso = t.peso;
    if (esFecha(t.vence)) tarea.vence = t.vence;
    return tarea;
  }

  // Fechas como texto "AAAA-MM-DD", en hora local: una fecha límite es un día, no un instante.
  const esFecha = (x) => typeof x === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(x);

  function fechaLocal(d = new Date()) {
    const dos = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${dos(d.getMonth() + 1)}-${dos(d.getDate())}`;
  }

  function deFecha(texto) {
    const [a, m, d] = texto.split('-').map(Number);
    return new Date(a, m - 1, d);
  }

  // Día de la semana ISO: 1 = lunes ... 7 = domingo.
  const diaSemana = (texto) => ((deFecha(texto).getDay() + 6) % 7) + 1;

  // Una rutina es algo que se repite: "3 ejercicios diarios", "gimnasio de lunes a viernes".
  //   veces     cuántas veces por día cuenta como cumplido
  //   dias      días de la semana en que toca (los demás son descanso y no rompen la racha)
  //   meta      opcional: días cumplidos para darla por terminada; con meta, suma al avance del proyecto
  //   registro  { "AAAA-MM-DD": veces hechas ese día }
  function normalizarRutina(cruda, usados) {
    if (!cruda || typeof cruda !== 'object' || !texto(cruda.titulo)) return null;
    const rutina = { id: idUnico(cruda.id, usados), titulo: texto(cruda.titulo), veces: 1, registro: {} };
    if (Number.isInteger(cruda.veces) && cruda.veces >= 1) rutina.veces = Math.min(cruda.veces, 99);
    const dias = Array.isArray(cruda.dias) ? [...new Set(cruda.dias.filter((d) => Number.isInteger(d) && d >= 1 && d <= 7))].sort() : [];
    if (dias.length && dias.length < 7) rutina.dias = dias;
    if (Number.isInteger(cruda.meta) && cruda.meta >= 1) rutina.meta = cruda.meta;
    if (Number.isFinite(cruda.peso) && cruda.peso > 0 && cruda.peso !== 1) rutina.peso = cruda.peso;
    if (texto(cruda.creado)) rutina.creado = cruda.creado;
    const registro = cruda.registro && typeof cruda.registro === 'object' ? cruda.registro : {};
    for (const [fecha, cuenta] of Object.entries(registro)) {
      if (esFecha(fecha) && Number.isInteger(cuenta) && cuenta > 0) rutina.registro[fecha] = Math.min(cuenta, rutina.veces);
    }
    return rutina;
  }

  const tocaHoy = (rutina, fecha) => !rutina.dias || rutina.dias.includes(diaSemana(fecha));
  const cumplida = (rutina, fecha) => (rutina.registro[fecha] || 0) >= rutina.veces;
  const diasCumplidos = (rutina) => Object.keys(rutina.registro).filter((f) => cumplida(rutina, f)).length;

  // De 0 a 1 si tiene meta; null si es una rutina sin fin.
  const avanceRutina = (rutina) => (rutina.meta ? Math.min(1, diasCumplidos(rutina) / rutina.meta) : null);

  // Días seguidos cumplidos. Los días de descanso no cuentan ni rompen; hoy no rompe si aún no lo haces.
  function racha(rutina, hoy = fechaLocal()) {
    let seguidos = 0;
    const dia = deFecha(hoy);
    for (let i = 0; i < 3660; i++) {
      const fecha = fechaLocal(dia);
      if (tocaHoy(rutina, fecha)) {
        if (cumplida(rutina, fecha)) seguidos++;
        else if (fecha !== hoy) break;
      }
      dia.setDate(dia.getDate() - 1);
    }
    return seguidos;
  }

  function idUnico(id, usados) {
    let final = texto(id) || nuevoId();
    while (usados.has(final)) final = nuevoId();
    usados.add(final);
    return final;
  }

  // Acepta JSON escrito a mano (tareas como texto simple, ids faltantes, campos
  // de más) y devuelve un estado completo y coherente.
  function normalizar(crudo) {
    const estado = estadoVacio();
    if (!crudo || typeof crudo !== 'object') return estado;

    const a = crudo.ajustes && typeof crudo.ajustes === 'object' ? crudo.ajustes : {};
    if (a.color === 'multicolor' || /^#[0-9a-f]{6}$/i.test(a.color || '')) estado.ajustes.color = a.color.toLowerCase();
    if (FORMAS.includes(a.forma)) estado.ajustes.forma = a.forma;
    if (LADOS.includes(a.lado)) estado.ajustes.lado = a.lado;
    if (TEMAS.includes(a.tema)) estado.ajustes.tema = a.tema;
    if (a.ejemplo === true) estado.ajustes.ejemplo = true;
    if (a.iniciado === true) estado.ajustes.iniciado = true;

    const idsProyecto = new Set();
    const idsTarea = new Set();
    const idsRutina = new Set();
    const proyecto = (p) => {
      if (!p || typeof p !== 'object' || !texto(p.nombre)) return null;
      const limpio = { id: idUnico(p.id, idsProyecto), nombre: texto(p.nombre), previo: numero(p.previo, 0), tareas: [] };
      if (texto(p.creado)) limpio.creado = p.creado;
      for (const t of Array.isArray(p.tareas) ? p.tareas : []) {
        const tarea = normalizarTarea(t, idsTarea);
        if (tarea) limpio.tareas.push(tarea);
      }
      const rutinas = (Array.isArray(p.rutinas) ? p.rutinas : []).map((r) => normalizarRutina(r, idsRutina)).filter(Boolean);
      if (rutinas.length) limpio.rutinas = rutinas;
      return limpio;
    };

    for (const p of Array.isArray(crudo.proyectos) ? crudo.proyectos : []) {
      const limpio = proyecto(p);
      if (limpio) estado.proyectos.push(limpio);
    }

    const f = crudo.finalizadas && typeof crudo.finalizadas === 'object' ? crudo.finalizadas : {};
    for (const p of Array.isArray(f.proyectos) ? f.proyectos : []) {
      const limpio = proyecto(p);
      if (!limpio) continue;
      limpio.tareas = [];
      if (texto(p.fin)) limpio.fin = p.fin;
      estado.finalizadas.proyectos.push(limpio);
    }
    for (const t of Array.isArray(f.tareas) ? f.tareas : []) {
      const tarea = normalizarTarea(t, idsTarea);
      if (!tarea || !idsProyecto.has(t.proyectoId)) continue;
      tarea.proyectoId = t.proyectoId;
      if (texto(t.fin)) tarea.fin = t.fin;
      estado.finalizadas.tareas.push(tarea);
    }
    return estado;
  }

  // ---------- avance ----------

  function pesos(estado, proyectoId) {
    const p = buscarProyecto(estado, proyectoId);
    if (!p) return { hecho: 0, pendiente: 0 };
    const hecho = estado.finalizadas.tareas
      .filter((t) => t.proyectoId === proyectoId)
      .reduce((s, t) => s + peso(t), 0);
    let pendiente = p.tareas.reduce((s, t) => s + peso(t), 0);
    let deRutinas = 0;
    // Una rutina con meta pesa como una tarea (o su `peso`) que se va llenando poco a poco.
    for (const r of p.rutinas || []) {
      const f = avanceRutina(r);
      if (f === null) continue;
      deRutinas += peso(r) * f;
      pendiente += peso(r) * (1 - f);
    }
    return { hecho: hecho + deRutinas + (p.previo || 0), pendiente };
  }

  // Fracción de 0 a 1.
  function avance(estado, proyectoId) {
    const { hecho, pendiente } = pesos(estado, proyectoId);
    const total = hecho + pendiente;
    return total > 0 ? hecho / total : 0;
  }

  // Entero para mostrar. Nunca enseña 100 mientras quede algo pendiente.
  function porcentaje(estado, proyectoId) {
    const { pendiente } = pesos(estado, proyectoId);
    const pct = Math.round(avance(estado, proyectoId) * 100);
    return pendiente > 1e-9 ? Math.min(pct, 99) : pct;
  }

  function buscarProyecto(estado, id) {
    return (
      estado.proyectos.find((p) => p.id === id) ||
      estado.finalizadas.proyectos.find((p) => p.id === id) ||
      null
    );
  }

  const estaFinalizado = (estado, id) => estado.finalizadas.proyectos.some((p) => p.id === id);

  // ---------- proyectos ----------

  function crearProyecto(estado, nombre, ahora = new Date()) {
    const limpio = texto(nombre);
    if (!limpio) return { estado, id: null };
    const nuevo = copia(estado);
    const id = nuevoId();
    nuevo.proyectos.push({ id, nombre: limpio, previo: 0, tareas: [], creado: ahora.toISOString() });
    return { estado: nuevo, id };
  }

  function renombrarProyecto(estado, id, nombre) {
    const limpio = texto(nombre);
    if (!limpio) return estado;
    const nuevo = copia(estado);
    const p = buscarProyecto(nuevo, id);
    if (p) p.nombre = limpio;
    return nuevo;
  }

  function eliminarProyecto(estado, id) {
    const nuevo = copia(estado);
    nuevo.proyectos = nuevo.proyectos.filter((p) => p.id !== id);
    nuevo.finalizadas.proyectos = nuevo.finalizadas.proyectos.filter((p) => p.id !== id);
    nuevo.finalizadas.tareas = nuevo.finalizadas.tareas.filter((t) => t.proyectoId !== id);
    return nuevo;
  }

  function moverProyecto(estado, id, posicion) {
    const nuevo = copia(estado);
    const desde = nuevo.proyectos.findIndex((p) => p.id === id);
    if (desde < 0) return estado;
    const [p] = nuevo.proyectos.splice(desde, 1);
    nuevo.proyectos.splice(Math.max(0, Math.min(posicion, nuevo.proyectos.length)), 0, p);
    return nuevo;
  }

  // Fija el avance visible de un proyecto ajustando `previo`: el trabajo hecho
  // antes de empezar a llevarlo en Flecha, medido en unidades de tarea.
  // No puede bajar de lo que ya suman las tareas finalizadas.
  function ajustarAvance(estado, id, objetivoPct) {
    const nuevo = copia(estado);
    const p = nuevo.proyectos.find((x) => x.id === id);
    if (!p) return estado;
    const objetivo = Math.max(0, Math.min(99, objetivoPct)) / 100;
    const { hecho, pendiente } = pesos(nuevo, id);
    const hechoReal = hecho - (p.previo || 0);
    if (pendiente <= 0) return estado;
    const previo = (objetivo * (hechoReal + pendiente) - hechoReal) / (1 - objetivo);
    p.previo = Math.max(0, Math.round(previo * 100) / 100);
    return nuevo;
  }

  // ---------- tareas ----------

  function crearTarea(estado, proyectoId, titulo) {
    const limpio = texto(titulo);
    if (!limpio) return { estado, id: null };
    const nuevo = copia(estado);
    const p = nuevo.proyectos.find((x) => x.id === proyectoId);
    if (!p) return { estado, id: null };
    const id = nuevoId();
    p.tareas.push({ id, titulo: limpio });
    return { estado: nuevo, id };
  }

  function renombrarTarea(estado, proyectoId, tareaId, titulo) {
    const limpio = texto(titulo);
    if (!limpio) return eliminarTarea(estado, proyectoId, tareaId);
    const nuevo = copia(estado);
    const t = nuevo.proyectos.find((p) => p.id === proyectoId)?.tareas.find((x) => x.id === tareaId);
    if (t) t.titulo = limpio;
    return nuevo;
  }

  function eliminarTarea(estado, proyectoId, tareaId) {
    const nuevo = copia(estado);
    const p = nuevo.proyectos.find((x) => x.id === proyectoId);
    if (p) p.tareas = p.tareas.filter((t) => t.id !== tareaId);
    return nuevo;
  }

  // Pasa la tarea al archivo de finalizadas. Si era la última pendiente, el
  // proyecto llegó al 100 % y también se archiva. Devuelve si eso ocurrió.
  function completarTarea(estado, proyectoId, tareaId, ahora = new Date()) {
    const nuevo = copia(estado);
    const p = nuevo.proyectos.find((x) => x.id === proyectoId);
    const i = p ? p.tareas.findIndex((t) => t.id === tareaId) : -1;
    if (i < 0) return { estado, proyectoFinalizado: false };
    const [tarea] = p.tareas.splice(i, 1);
    const fin = ahora.toISOString();
    nuevo.finalizadas.tareas.push({ ...tarea, proyectoId, fin });
    const proyectoFinalizado = sinPendientes(p);
    if (proyectoFinalizado) archivarProyecto(nuevo, p, fin);
    return { estado: nuevo, proyectoFinalizado };
  }

  // Un proyecto con una rutina sin meta nunca se da por terminado solo: la rutina sigue viva.
  const sinPendientes = (p) => p.tareas.length === 0 && (p.rutinas || []).every((r) => avanceRutina(r) === 1);

  function archivarProyecto(estado, p, fin) {
    estado.proyectos = estado.proyectos.filter((x) => x.id !== p.id);
    estado.finalizadas.proyectos.push({ ...p, fin });
  }

  function fijarVence(estado, proyectoId, tareaId, fecha) {
    const nuevo = copia(estado);
    const t = nuevo.proyectos.find((p) => p.id === proyectoId)?.tareas.find((x) => x.id === tareaId);
    if (!t) return estado;
    if (esFecha(fecha)) t.vence = fecha;
    else delete t.vence;
    return nuevo;
  }

  // ---------- rutinas ----------

  function crearRutina(estado, proyectoId, datos, ahora = new Date()) {
    const nuevo = copia(estado);
    const p = nuevo.proyectos.find((x) => x.id === proyectoId);
    const rutina = p && normalizarRutina({ ...datos, id: nuevoId(), registro: {}, creado: ahora.toISOString() }, new Set());
    if (!rutina) return { estado, id: null };
    p.rutinas = [...(p.rutinas || []), rutina];
    return { estado: nuevo, id: rutina.id };
  }

  function eliminarRutina(estado, proyectoId, rutinaId) {
    const nuevo = copia(estado);
    const p = nuevo.proyectos.find((x) => x.id === proyectoId);
    if (!p || !p.rutinas) return estado;
    p.rutinas = p.rutinas.filter((r) => r.id !== rutinaId);
    if (!p.rutinas.length) delete p.rutinas;
    return nuevo;
  }

  // Deja en `cuenta` las veces hechas ese día (0 lo borra). Si con eso se cumple la meta y
  // no queda nada más pendiente, el proyecto se archiva igual que al terminar su última tarea.
  function registrarRutina(estado, proyectoId, rutinaId, fecha, cuenta, ahora = new Date()) {
    const nuevo = copia(estado);
    const p = nuevo.proyectos.find((x) => x.id === proyectoId);
    const r = p && (p.rutinas || []).find((x) => x.id === rutinaId);
    if (!r || !esFecha(fecha)) return { estado, proyectoFinalizado: false };
    const limpia = Math.max(0, Math.min(r.veces, Math.round(cuenta) || 0));
    if (limpia > 0) r.registro[fecha] = limpia;
    else delete r.registro[fecha];
    const proyectoFinalizado = sinPendientes(p) && pesos(nuevo, proyectoId).hecho > 0;
    if (proyectoFinalizado) archivarProyecto(nuevo, p, ahora.toISOString());
    return { estado: nuevo, proyectoFinalizado };
  }

  // Revierte una tarea finalizada: vuelve a pendientes y, si su proyecto estaba
  // archivado, el proyecto reaparece.
  function restaurarTarea(estado, tareaId) {
    const nuevo = copia(estado);
    const i = nuevo.finalizadas.tareas.findIndex((t) => t.id === tareaId);
    if (i < 0) return estado;
    const [{ proyectoId, fin, ...tarea }] = nuevo.finalizadas.tareas.splice(i, 1);
    revivirProyecto(nuevo, proyectoId);
    const p = nuevo.proyectos.find((x) => x.id === proyectoId);
    if (!p) return estado;
    p.tareas.push(tarea);
    return nuevo;
  }

  // Revierte un proyecto finalizado devolviendo su última tarea a pendientes.
  function restaurarProyecto(estado, proyectoId) {
    if (!estaFinalizado(estado, proyectoId)) return estado;
    const ultima = estado.finalizadas.tareas
      .filter((t) => t.proyectoId === proyectoId)
      .sort((a, b) => (a.fin || '').localeCompare(b.fin || ''))
      .at(-1);
    if (ultima) return restaurarTarea(estado, ultima.id);
    const nuevo = copia(estado);
    revivirProyecto(nuevo, proyectoId);
    return nuevo;
  }

  function revivirProyecto(estado, proyectoId) {
    const i = estado.finalizadas.proyectos.findIndex((p) => p.id === proyectoId);
    if (i < 0) return;
    const [{ fin, ...p }] = estado.finalizadas.proyectos.splice(i, 1);
    estado.proyectos.push({ ...p, tareas: [] });
  }

  // ---------- ajustes ----------

  function cambiarAjustes(estado, cambios) {
    const nuevo = copia(estado);
    nuevo.ajustes = normalizar({ ajustes: { ...nuevo.ajustes, ...cambios } }).ajustes;
    return nuevo;
  }

  // Finalizadas agrupadas por proyecto, lo más reciente primero.
  function finalizadasPorProyecto(estado) {
    const grupos = new Map();
    for (const t of estado.finalizadas.tareas) {
      if (!grupos.has(t.proyectoId)) grupos.set(t.proyectoId, []);
      grupos.get(t.proyectoId).push(t);
    }
    const reciente = (ts) => ts.reduce((m, t) => ((t.fin || '') > m ? t.fin || '' : m), '');
    const ids = new Set([...grupos.keys(), ...estado.finalizadas.proyectos.map((p) => p.id)]);
    return [...ids]
      .map((id) => {
        const tareas = (grupos.get(id) || []).sort((a, b) => (b.fin || '').localeCompare(a.fin || ''));
        return { proyecto: buscarProyecto(estado, id), finalizado: estaFinalizado(estado, id), tareas };
      })
      .filter((g) => g.proyecto)
      .sort((a, b) => reciente(b.tareas).localeCompare(reciente(a.tareas)));
  }

  const api = { VERSION, AJUSTES_BASE, fechaLocal, diaSemana, tocaHoy, cumplida, diasCumplidos, avanceRutina, racha, fijarVence, crearRutina, eliminarRutina, registrarRutina, nuevoId, estadoVacio, normalizar, pesos, avance, porcentaje, buscarProyecto, estaFinalizado, crearProyecto, renombrarProyecto, eliminarProyecto, moverProyecto, ajustarAvance, crearTarea, renombrarTarea, eliminarTarea, completarTarea, restaurarTarea, restaurarProyecto, cambiarAjustes, finalizadasPorProyecto };
  raiz.Flecha = Object.assign(raiz.Flecha || {}, { logica: api });
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
