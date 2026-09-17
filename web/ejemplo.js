// Proyectos ficticios para la primera vez que alguien abre Flecha.
// Va como script (y no como .json) para que funcione también con doble clic.

(function (raiz) {
  'use strict';

  const es = {
    ajustes: { ejemplo: true },
    proyectos: [
      { id: 'ej-cafe', nombre: 'Cafetería', previo: 11, tareas: ['Permiso de uso de suelo', 'Probar el menú con amigos', 'Letrero de la entrada'] },
      { id: 'ej-disco', nombre: 'Disco', previo: 4, tareas: ['Grabar las voces', 'Mezcla', 'Masterización', 'Portada', 'Subirlo a plataformas'] },
      { id: 'ej-maraton', nombre: 'Maratón', previo: 9, tareas: ['Tirada larga de 28 km', 'Tirada larga de 32 km', 'Semana de descarga', 'Recoger el número'] },
      { id: 'ej-huerto', nombre: 'Huerto', previo: 1, tareas: ['Armar las camas', 'Comprar composta', 'Sistema de riego', 'Sembrar jitomate', 'Sembrar hierbas'] },
      { id: 'ej-tesis', nombre: 'Tesis', previo: 0, tareas: ['Elegir asesor', 'Protocolo', 'Marco teórico'] },
    ],
    finalizadas: {
      tareas: [
        { id: 'ej-f1', titulo: 'Firmar el contrato de renta', proyectoId: 'ej-cafe', fin: '2026-01-10T18:00:00.000Z' },
        { id: 'ej-f2', titulo: 'Comprar la máquina de espresso', proyectoId: 'ej-cafe', fin: '2026-01-18T18:00:00.000Z' },
        { id: 'ej-f3', titulo: 'Inscribirme', proyectoId: 'ej-maraton', fin: '2026-01-05T18:00:00.000Z' },
      ],
      proyectos: [],
    },
  };

  const en = {
    ajustes: { ejemplo: true },
    proyectos: [
      { id: 'ej-cafe', nombre: 'Coffee shop', previo: 11, tareas: ['Zoning permit', 'Test the menu with friends', 'Entrance sign'] },
      { id: 'ej-disco', nombre: 'Album', previo: 4, tareas: ['Record vocals', 'Mixing', 'Mastering', 'Cover art', 'Release on streaming'] },
      { id: 'ej-maraton', nombre: 'Marathon', previo: 9, tareas: ['18-mile long run', '20-mile long run', 'Taper week', 'Pick up race bib'] },
      { id: 'ej-huerto', nombre: 'Garden', previo: 1, tareas: ['Build the beds', 'Buy compost', 'Irrigation', 'Plant tomatoes', 'Plant herbs'] },
      { id: 'ej-tesis', nombre: 'Thesis', previo: 0, tareas: ['Pick an advisor', 'Proposal', 'Literature review'] },
    ],
    finalizadas: {
      tareas: [
        { id: 'ej-f1', titulo: 'Sign the lease', proyectoId: 'ej-cafe', fin: '2026-01-10T18:00:00.000Z' },
        { id: 'ej-f2', titulo: 'Buy the espresso machine', proyectoId: 'ej-cafe', fin: '2026-01-18T18:00:00.000Z' },
        { id: 'ej-f3', titulo: 'Sign up', proyectoId: 'ej-maraton', fin: '2026-01-05T18:00:00.000Z' },
      ],
      proyectos: [],
    },
  };

  raiz.Flecha = Object.assign(raiz.Flecha || {}, {
    ejemplo: () => structuredClone(raiz.Flecha.idioma === 'en' ? en : es),
  });
})(typeof globalThis !== 'undefined' ? globalThis : this);
