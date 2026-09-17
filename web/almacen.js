// Dónde vive el estado. Dos modos, elegidos solos al arrancar:
//   servidor  hay un `servidor.py` detrás: los datos son archivos JSON en tu computadora.
//   local     página estática (GitHub Pages, doble clic): los datos viven en localStorage.

(function (raiz) {
  'use strict';

  const L = raiz.Flecha.logica;
  const CLAVE = 'flecha.v1';
  const RUTA = 'api/estado';
  const ENCABEZADOS = { 'X-Flecha': '1' };
  const SONDEO_MS = 4000;
  const ESPERA_MS = 250;

  const sinDatos = (e) =>
    !e.ajustes.iniciado && !e.proyectos.length && !e.finalizadas.tareas.length && !e.finalizadas.proyectos.length;

  // La primera vez se muestran proyectos de ejemplo. No se guardan hasta que cambies algo.
  function conEjemplo(estado) {
    if (!sinDatos(estado)) return estado;
    const ejemplo = L.normalizar(raiz.Flecha.ejemplo());
    ejemplo.ajustes = { ...estado.ajustes, ejemplo: true };
    return ejemplo;
  }

  function almacenServidor(crudo, huellaInicial, avisos) {
    let huella = huellaInicial;
    let pendiente = null;
    let reloj = null;
    let enviando = false;

    async function enviar() {
      if (enviando || !pendiente) return;
      enviando = true;
      const cuerpo = pendiente;
      pendiente = null;
      try {
        const r = await fetch(RUTA, {
          method: 'PUT',
          headers: { ...ENCABEZADOS, 'Content-Type': 'application/json', ...(huella ? { 'If-Match': huella } : {}) },
          body: JSON.stringify(cuerpo),
        });
        if (r.status === 409) {
          pendiente = null;
          huella = null;
          await sondear(true);
        } else if (!r.ok) {
          throw new Error(String(r.status));
        } else {
          huella = r.headers.get('ETag');
        }
      } catch (error) {
        if (!pendiente) pendiente = cuerpo;
        avisos.fallo();
      } finally {
        enviando = false;
        if (pendiente) reloj = setTimeout(enviar, 3000);
      }
    }

    async function sondear(forzar) {
      if (!forzar && (pendiente || enviando || document.visibilityState !== 'visible')) return;
      try {
        const r = await fetch(RUTA, {
          headers: { ...ENCABEZADOS, ...(huella ? { 'If-None-Match': huella } : {}) },
          cache: 'no-store',
        });
        if (r.status !== 200) return;
        const nuevaHuella = r.headers.get('ETag');
        const estado = conEjemplo(L.normalizar(await r.json()));
        // Si la interfaz no puede aplicarlo ahora (alguien está escribiendo), se reintenta luego.
        if (avisos.externo(estado) !== false) huella = nuevaHuella;
      } catch (error) {
        /* el servidor se apagó: se reintenta en el siguiente sondeo */
      }
    }

    setInterval(sondear, SONDEO_MS);
    document.addEventListener('visibilitychange', () => sondear());

    return {
      modo: 'servidor',
      estado: conEjemplo(L.normalizar(crudo)),
      guardar(estado) {
        pendiente = estado;
        clearTimeout(reloj);
        reloj = setTimeout(enviar, ESPERA_MS);
      },
    };
  }

  function almacenLocal(avisos) {
    const leer = () => {
      try {
        return L.normalizar(JSON.parse(localStorage.getItem(CLAVE)));
      } catch (error) {
        return L.estadoVacio();
      }
    };

    raiz.addEventListener('storage', (e) => {
      if (e.key === CLAVE) avisos.externo(conEjemplo(leer()));
    });

    return {
      modo: 'local',
      estado: conEjemplo(leer()),
      guardar(estado) {
        try {
          localStorage.setItem(CLAVE, JSON.stringify(estado));
        } catch (error) {
          avisos.fallo();
        }
      },
    };
  }

  // avisos: { externo(estado) -> false si no pudo aplicarlo, fallo() }
  async function abrir(avisos) {
    if (location.protocol.startsWith('http')) {
      try {
        const r = await fetch(RUTA, { headers: ENCABEZADOS, cache: 'no-store' });
        if (r.ok && (r.headers.get('Content-Type') || '').includes('json')) {
          return almacenServidor(await r.json(), r.headers.get('ETag'), avisos);
        }
      } catch (error) {
        /* sin servidor: modo local */
      }
    }
    return almacenLocal(avisos);
  }

  raiz.Flecha = Object.assign(raiz.Flecha || {}, { almacen: { abrir } });
})(window);
