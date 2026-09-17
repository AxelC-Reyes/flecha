import test from 'node:test';
import assert from 'node:assert/strict';
import L from '../web/logica.js';

function base() {
  return L.normalizar({
    proyectos: [
      { id: 'casa', nombre: 'Casa', tareas: ['Pintar', 'Barnizar', { id: 't3', titulo: 'Cortinas', peso: 2 }] },
      { id: 'libro', nombre: 'Libro', previo: 3, tareas: [{ id: 'cap', titulo: 'Capítulo final' }] },
    ],
  });
}

test('normalizar acepta JSON escrito a mano', () => {
  const e = base();
  assert.equal(e.version, L.VERSION);
  assert.deepEqual(e.ajustes, { ...L.AJUSTES_BASE });
  assert.equal(e.proyectos[0].tareas.length, 3);
  assert.equal(e.proyectos[0].tareas[0].titulo, 'Pintar');
  assert.ok(e.proyectos[0].tareas[0].id);
  assert.equal(e.proyectos[0].tareas[2].peso, 2);
});

test('normalizar descarta basura sin romperse', () => {
  const e = L.normalizar({
    ajustes: { color: 'rojo', forma: 'estrella', lado: 7, tema: null },
    proyectos: [null, 4, { nombre: '   ' }, { nombre: 'Ok', tareas: [null, '', { titulo: 'x' }] }],
    finalizadas: { tareas: [{ titulo: 'huérfana', proyectoId: 'nadie' }] },
  });
  assert.deepEqual(e.ajustes, { ...L.AJUSTES_BASE });
  assert.equal(e.proyectos.length, 1);
  assert.equal(e.proyectos[0].tareas.length, 1);
  assert.equal(e.finalizadas.tareas.length, 0);
  assert.deepEqual(L.normalizar(null), L.estadoVacio());
});

test('normalizar no deja ids repetidos', () => {
  const e = L.normalizar({
    proyectos: [
      { id: 'a', nombre: 'Uno', tareas: [{ id: 't', titulo: '1' }] },
      { id: 'a', nombre: 'Dos', tareas: [{ id: 't', titulo: '2' }] },
    ],
  });
  assert.notEqual(e.proyectos[0].id, e.proyectos[1].id);
  assert.notEqual(e.proyectos[0].tareas[0].id, e.proyectos[1].tareas[0].id);
});

test('el avance respeta pesos y trabajo previo', () => {
  const e = base();
  assert.equal(L.porcentaje(e, 'casa'), 0);
  assert.equal(L.porcentaje(e, 'libro'), 75);
  const { estado } = L.completarTarea(e, 'casa', 't3');
  assert.equal(L.porcentaje(estado, 'casa'), 50);
});

test('nunca enseña 100 con pendientes', () => {
  const e = L.normalizar({ proyectos: [{ id: 'p', nombre: 'P', previo: 999, tareas: ['última'] }] });
  assert.equal(L.porcentaje(e, 'p'), 99);
});

test('completar manda la tarea al archivo sin tocar el original', () => {
  const e = base();
  const { estado, proyectoFinalizado } = L.completarTarea(e, 'casa', 't3', new Date('2026-01-02T03:04:05Z'));
  assert.equal(proyectoFinalizado, false);
  assert.equal(e.proyectos[0].tareas.length, 3);
  assert.equal(estado.proyectos[0].tareas.length, 2);
  assert.deepEqual(estado.finalizadas.tareas[0], {
    id: 't3',
    titulo: 'Cortinas',
    peso: 2,
    proyectoId: 'casa',
    fin: '2026-01-02T03:04:05.000Z',
  });
});

test('la última tarea archiva el proyecto y restaurarla lo revive', () => {
  const e = base();
  const r = L.completarTarea(e, 'libro', 'cap');
  assert.equal(r.proyectoFinalizado, true);
  assert.equal(r.estado.proyectos.some((p) => p.id === 'libro'), false);
  assert.equal(L.estaFinalizado(r.estado, 'libro'), true);
  assert.equal(L.porcentaje(r.estado, 'libro'), 100);

  const vuelta = L.restaurarTarea(r.estado, 'cap');
  assert.equal(L.estaFinalizado(vuelta, 'libro'), false);
  const libro = vuelta.proyectos.find((p) => p.id === 'libro');
  assert.deepEqual(libro.tareas, [{ id: 'cap', titulo: 'Capítulo final' }]);
  assert.equal(libro.previo, 3);
  assert.equal(L.porcentaje(vuelta, 'libro'), 75);
  assert.equal(vuelta.finalizadas.tareas.length, 0);
});

test('restaurar proyecto devuelve su tarea más reciente', () => {
  let e = base();
  e = L.completarTarea(e, 'casa', e.proyectos[0].tareas[0].id, new Date('2026-01-01')).estado;
  e = L.completarTarea(e, 'casa', e.proyectos[0].tareas[0].id, new Date('2026-01-02')).estado;
  e = L.completarTarea(e, 'casa', 't3', new Date('2026-01-03')).estado;
  assert.equal(L.estaFinalizado(e, 'casa'), true);
  e = L.restaurarProyecto(e, 'casa');
  const casa = e.proyectos.find((p) => p.id === 'casa');
  assert.deepEqual(casa.tareas.map((t) => t.id), ['t3']);
  assert.equal(L.porcentaje(e, 'casa'), 50);
});

test('restaurar una tarea de un proyecto activo solo la regresa', () => {
  let e = base();
  e = L.completarTarea(e, 'casa', 't3').estado;
  e = L.restaurarTarea(e, 't3');
  assert.equal(e.proyectos[0].tareas.length, 3);
  assert.equal(e.finalizadas.tareas.length, 0);
  assert.equal(L.restaurarTarea(e, 'no-existe'), e);
});

test('eliminar proyecto limpia también su archivo', () => {
  let e = base();
  e = L.completarTarea(e, 'casa', 't3').estado;
  e = L.eliminarProyecto(e, 'casa');
  assert.equal(e.proyectos.length, 1);
  assert.equal(e.finalizadas.tareas.length, 0);
});

test('crear, renombrar y eliminar tareas', () => {
  let e = base();
  const r = L.crearTarea(e, 'casa', '  Lámparas ');
  assert.equal(r.estado.proyectos[0].tareas.at(-1).titulo, 'Lámparas');
  assert.equal(L.crearTarea(e, 'casa', '   ').id, null);
  e = L.renombrarTarea(r.estado, 'casa', r.id, 'Focos');
  assert.equal(e.proyectos[0].tareas.at(-1).titulo, 'Focos');
  e = L.renombrarTarea(e, 'casa', r.id, '');
  assert.equal(e.proyectos[0].tareas.length, 3);
});

test('crear y mover proyectos', () => {
  let e = base();
  const r = L.crearProyecto(e, 'Huerto');
  assert.equal(r.estado.proyectos.length, 3);
  assert.equal(L.crearProyecto(e, '').id, null);
  e = L.moverProyecto(r.estado, r.id, 0);
  assert.equal(e.proyectos[0].nombre, 'Huerto');
});

test('ajustarAvance fija el porcentaje visible', () => {
  let e = base();
  e = L.ajustarAvance(e, 'casa', 80);
  assert.equal(L.porcentaje(e, 'casa'), 80);
  e = L.completarTarea(e, 'casa', 't3').estado;
  assert.ok(L.porcentaje(e, 'casa') > 80);
  // no puede bajar de lo que ya suman las tareas finalizadas
  e = L.ajustarAvance(e, 'casa', 0);
  assert.equal(e.proyectos[0].previo, 0);
  assert.equal(L.porcentaje(e, 'casa'), 50);
});

test('cambiarAjustes valida los valores', () => {
  let e = base();
  e = L.cambiarAjustes(e, { color: '#FF9F0A', forma: 'pildora', lado: 'derecha', tema: 'oscuro' });
  assert.deepEqual(e.ajustes, { color: '#ff9f0a', forma: 'pildora', lado: 'derecha', tema: 'oscuro' });
  e = L.cambiarAjustes(e, { forma: 'hexágono' });
  assert.equal(e.ajustes.forma, 'redondeada');
});

test('finalizadasPorProyecto agrupa y ordena', () => {
  let e = base();
  e = L.completarTarea(e, 'casa', 't3', new Date('2026-01-01')).estado;
  e = L.completarTarea(e, 'libro', 'cap', new Date('2026-02-01')).estado;
  const grupos = L.finalizadasPorProyecto(e);
  assert.deepEqual(grupos.map((g) => [g.proyecto.id, g.finalizado]), [['libro', true], ['casa', false]]);
});

test('el estado sobrevive un viaje por JSON', () => {
  let e = base();
  e = L.completarTarea(e, 'libro', 'cap').estado;
  assert.deepEqual(L.normalizar(JSON.parse(JSON.stringify(e))), e);
});

// ---------- fechas límite y rutinas ----------

function conRutina(extra = {}) {
  return L.normalizar({
    proyectos: [{
      id: 'm', nombre: 'Maestría', tareas: [{ id: 't', titulo: 'Constancia de inglés', vence: '2026-10-01' }],
      rutinas: [{ id: 'r', titulo: 'Ejercicios', veces: 3, dias: [1, 2, 3, 4, 5], ...extra }],
    }],
  });
}

test('la fecha límite sobrevive, también al finalizar y restaurar', () => {
  let e = conRutina();
  assert.equal(e.proyectos[0].tareas[0].vence, '2026-10-01');
  assert.equal(L.normalizar({ proyectos: [{ nombre: 'X', tareas: [{ titulo: 'a', vence: 'mañana' }] }] }).proyectos[0].tareas[0].vence, undefined);
  e = L.completarTarea(e, 'm', 't').estado;
  assert.equal(e.finalizadas.tareas[0].vence, '2026-10-01');
  e = L.restaurarTarea(e, 't');
  assert.equal(e.proyectos[0].tareas[0].vence, '2026-10-01');
  e = L.fijarVence(e, 'm', 't', null);
  assert.equal('vence' in e.proyectos[0].tareas[0], false);
});

test('una rutina sin meta no mueve el avance ni deja archivar el proyecto', () => {
  let e = conRutina();
  assert.equal(L.porcentaje(e, 'm'), 0);
  const r = L.completarTarea(e, 'm', 't');
  assert.equal(r.proyectoFinalizado, false);
  assert.equal(L.porcentaje(r.estado, 'm'), 100);
});

test('registrar veces del día, con tope y borrado', () => {
  let e = conRutina();
  e = L.registrarRutina(e, 'm', 'r', '2026-09-17', 2).estado;
  assert.equal(e.proyectos[0].rutinas[0].registro['2026-09-17'], 2);
  assert.equal(L.cumplida(e.proyectos[0].rutinas[0], '2026-09-17'), false);
  e = L.registrarRutina(e, 'm', 'r', '2026-09-17', 9).estado;
  assert.equal(e.proyectos[0].rutinas[0].registro['2026-09-17'], 3);
  e = L.registrarRutina(e, 'm', 'r', '2026-09-17', 0).estado;
  assert.deepEqual(e.proyectos[0].rutinas[0].registro, {});
});

test('la racha salta los días de descanso y no se rompe por el día de hoy', () => {
  // 2026-09-17 es jueves. Descansa sábado y domingo.
  let e = conRutina();
  for (const f of ['2026-09-11', '2026-09-14', '2026-09-15', '2026-09-16']) e = L.registrarRutina(e, 'm', 'r', f, 3).estado;
  const r = () => e.proyectos[0].rutinas[0];
  assert.equal(L.diaSemana('2026-09-17'), 4);
  assert.equal(L.tocaHoy(r(), '2026-09-13'), false);
  assert.equal(L.racha(r(), '2026-09-17'), 4); // vie, (sáb y dom descanso), lun, mar, mié; hoy aún no
  e = L.registrarRutina(e, 'm', 'r', '2026-09-17', 3).estado;
  assert.equal(L.racha(r(), '2026-09-17'), 5);
  assert.equal(L.racha(r(), '2026-09-18'), 5); // viernes sin hacer todavía: no la rompe
  e = L.registrarRutina(e, 'm', 'r', '2026-09-18', 3).estado;
  assert.equal(L.racha(r(), '2026-09-20'), 6); // domingo: el descanso no la rompe
  assert.equal(L.racha(r(), '2026-09-22'), 0); // faltó el lunes 21
});

test('con meta, la rutina suma al avance y al cumplirla puede terminar el proyecto', () => {
  let e = conRutina({ meta: 4 });
  e = L.registrarRutina(e, 'm', 'r', '2026-09-14', 3).estado;
  assert.equal(L.avanceRutina(e.proyectos[0].rutinas[0]), 0.25);
  assert.equal(L.porcentaje(e, 'm'), 13); // 0.25 de 2 unidades
  e = L.completarTarea(e, 'm', 't').estado;
  assert.equal(L.estaFinalizado(e, 'm'), false);
  for (const f of ['2026-09-15', '2026-09-16']) e = L.registrarRutina(e, 'm', 'r', f, 3).estado;
  const fin = L.registrarRutina(e, 'm', 'r', '2026-09-17', 3);
  assert.equal(fin.proyectoFinalizado, true);
  assert.equal(L.estaFinalizado(fin.estado, 'm'), true);
  // al restaurar la tarea, el proyecto vuelve con su rutina intacta
  const vuelta = L.restaurarTarea(fin.estado, 't');
  assert.equal(vuelta.proyectos[0].rutinas[0].registro['2026-09-17'], 3);
});

test('crear y eliminar rutinas; el estado sigue sobreviviendo a JSON', () => {
  let e = conRutina();
  const r = L.crearRutina(e, 'm', { titulo: 'Gimnasio', veces: 1, dias: [1, 3, 5], meta: 100 });
  assert.equal(r.estado.proyectos[0].rutinas.length, 2);
  assert.deepEqual(r.estado.proyectos[0].rutinas[1].dias, [1, 3, 5]);
  assert.equal(L.crearRutina(e, 'm', { titulo: '  ' }).id, null);
  assert.deepEqual(L.normalizar(JSON.parse(JSON.stringify(r.estado))), r.estado);
  e = L.eliminarRutina(r.estado, 'm', r.id);
  e = L.eliminarRutina(e, 'm', 'r');
  assert.equal('rutinas' in e.proyectos[0], false);
});
