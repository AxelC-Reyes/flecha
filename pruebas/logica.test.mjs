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
