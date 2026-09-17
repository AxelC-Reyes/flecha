// Interfaz de Flecha: una línea que se abre en un cuadrado con tus proyectos,
// con las barras de avance desplegándose por fuera.

(function () {
  'use strict';

  const { logica: L, t } = window.Flecha;
  const $ = (id) => document.getElementById(id);
  const html = document.documentElement;
  const escena = $('escena');
  const widget = $('widget');
  const contenido = $('contenido');
  const barras = $('barras');
  const cima = $('cima');
  const asa = $('asa');
  const aviso = $('aviso');

  const PALETA = ['#ff453a', '#ff9f0a', '#ffd60a', '#30d158', '#63e6e2', '#64d2ff', '#0a84ff', '#5e5ce6', '#bf5af2', '#ff375f'];
  const MORFOSIS_MS = 560;
  const CAMBIO_MS = 130;
  const calmado = window.matchMedia('(prefers-reduced-motion: reduce)');
  const puente = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.flecha;
  const nativo = (tipo, extra) => puente && puente.postMessage({ tipo, ...extra });
  // En iPhone y iPad la app guarda los datos y puede conectarse al servidor de tu Mac.
  const movil = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.flechaDatos;
  let conexion = (window.__flechaInicial && window.__flechaInicial.conexion) || { servidor: null, enLinea: false };

  let almacen = null;
  let estado = L.estadoVacio();
  let abierto = false;
  let vista = { nombre: 'lista' };
  let creando = false;
  let ajustando = false;
  let anterior = null; // copia del estado para "Deshacer"
  let uso = null; // consumo de asistentes de código, solo con servidor local
  let relojUso = null;
  let relojAviso = null;
  const pintado = new Map(); // id de proyecto -> fracción ya dibujada, para animar desde ahí

  // ---------- utilidades de DOM ----------

  function h(etiqueta, props, ...hijos) {
    const el = document.createElement(etiqueta);
    for (const [clave, valor] of Object.entries(props || {})) {
      if (valor === false || valor == null) continue;
      if (clave === 'class') el.className = valor;
      else if (clave === 'html') el.innerHTML = valor;
      else if (clave === 'style') el.style.cssText = valor;
      else if (clave.startsWith('on')) el.addEventListener(clave.slice(2), valor);
      else if (clave in el && clave !== 'list') el[clave] = valor;
      else el.setAttribute(clave, valor === true ? '' : valor);
    }
    for (const hijo of hijos.flat(Infinity)) if (hijo != null && hijo !== false) el.append(hijo);
    return el;
  }

  const trazo = (d, extra = '') =>
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ${extra}>${d}</svg>`;
  const ICONOS = {
    mas: trazo('<path d="M12 5.5v13M5.5 12h13"/>'),
    finalizadas: trazo('<circle cx="12" cy="12" r="8.5"/><path d="m8.4 12.3 2.5 2.5 4.8-5.3"/>'),
    ajustes: trazo('<path d="M4.5 7h15M4.5 12h15M4.5 17h15"/><circle cx="9" cy="7" r="2.1" fill="currentColor"/><circle cx="15.5" cy="12" r="2.1" fill="currentColor"/><circle cx="8" cy="17" r="2.1" fill="currentColor"/>'),
    atras: trazo('<path d="m14.5 5.5-6.5 6.5 6.5 6.5"/>', 'stroke-width="2.2"'),
    revertir: trazo('<path d="M8.5 5.5 4.5 9.5l4 4"/><path d="M4.5 9.5h9.2a5.3 5.3 0 0 1 0 10.6H9.5"/>'),
    uso: trazo('<path d="M5.2 17.2a8.3 8.3 0 1 1 13.6 0"/><path d="m12 13.2 3.4-4.4"/><circle cx="12" cy="13.2" r="1.1" fill="currentColor"/>'),
    equis: trazo('<path d="m6.5 6.5 11 11M17.5 6.5l-11 11"/>', 'stroke-width="2.4"'),
    palomita: '<svg viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6.4 11.4 3.1 3.1 6.1-6.7"/></svg>',
  };

  const icono = (nombre, etiqueta, alPulsar, clase = '') =>
    h('button', { class: `icono ${clase}`.trim(), type: 'button', 'aria-label': etiqueta, title: etiqueta, html: ICONOS[nombre], onclick: alPulsar });

  // ---------- apariencia ----------

  function contraste(hex) {
    const n = parseInt(hex.slice(1), 16);
    const canal = (v) => {
      const s = v / 255;
      return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
    };
    const luz = 0.2126 * canal(n >> 16) + 0.7152 * canal((n >> 8) & 255) + 0.0722 * canal(n & 255);
    return luz > 0.45 ? '#000' : '#fff';
  }

  function aplicarTinte(color) {
    const propio = /^#/.test(color);
    html.style.setProperty('--tinte', propio ? color : 'var(--auto)');
    html.style.setProperty('--sobre-tinte', propio ? contraste(color) : 'var(--sobre-auto)');
  }

  function aplicarAjustes() {
    const a = estado.ajustes;
    html.dataset.tema = a.tema;
    html.dataset.forma = a.forma;
    html.classList.toggle('derecha', a.lado === 'derecha');
    aplicarTinte(a.color);
    nativo('lado', { lado: a.lado });
    nativo('tema', { tema: a.tema });
  }

  const colorDeBarra = (i) => (estado.ajustes.color === 'multicolor' ? PALETA[i % PALETA.length] : null);

  // ---------- cifras y barras ----------

  function contar(el, hasta, { desde = 0, duracion = 800, espera = 0 } = {}) {
    cancelAnimationFrame(el._cuadro);
    clearTimeout(el._espera);
    clearTimeout(el._final);
    if (calmado.matches || desde === hasta) {
      el.textContent = hasta;
      return;
    }
    el.textContent = desde;
    // Los cuadros de animación se pausan en segundo plano; esto garantiza la cifra final.
    el._final = setTimeout(() => {
      cancelAnimationFrame(el._cuadro);
      el.textContent = hasta;
    }, espera + duracion + 60);
    el._espera = setTimeout(() => {
      const inicio = performance.now();
      const paso = (ahora) => {
        const x = Math.min(1, (ahora - inicio) / duracion);
        el.textContent = Math.round(desde + (hasta - desde) * (1 - (1 - x) ** 3));
        if (x < 1) el._cuadro = requestAnimationFrame(paso);
      };
      el._cuadro = requestAnimationFrame(paso);
    }, espera);
  }

  function crearBarra(i, color) {
    const relleno = h('span', { class: 'relleno', style: `--i:${i};${color ? `--color:${color};` : ''}` });
    const cifra = h('span', { class: 'n' }, '0');
    const pct = h('span', { class: 'pct', style: `--i:${i}` }, cifra, h('small', null, '%'));
    return { relleno, cifra, fila: h('div', { class: 'barra' }, relleno, pct) };
  }

  function fijarBarra(barra, fraccion, desde) {
    barra.relleno.style.setProperty('--p', desde);
    barra.relleno.toggleAttribute('data-cero', fraccion === 0);
    requestAnimationFrame(() => requestAnimationFrame(() => barra.relleno.style.setProperty('--p', fraccion)));
  }

  // Qué barras van por fuera del cuadrado: proyectos en la lista, límites en la vista de uso.
  function filasDeBarras() {
    if (vista.nombre === 'uso') {
      return filasUso().map((f) => ({
        id: `uso:${f.id}`,
        fraccion: Math.min(1, f.usado / 100),
        pct: Math.round(f.usado),
        color: f.usado >= 90 ? 'var(--peligro)' : null,
      }));
    }
    return estado.proyectos.map((p, i) => ({ id: p.id, fraccion: L.avance(estado, p.id), pct: L.porcentaje(estado, p.id), color: colorDeBarra(i) }));
  }

  function pintarBarras(entrada) {
    if (!abierto) pintado.clear();
    const filas = filasDeBarras().map((f, i) => {
      const barra = crearBarra(i, f.color);
      if (!abierto) {
        barra.relleno.style.setProperty('--p', 0);
        barra.cifra.textContent = f.pct;
      } else {
        const desde = entrada ? 0 : pintado.get(f.id) ?? 0;
        fijarBarra(barra, f.fraccion, desde);
        contar(barra.cifra, f.pct, { desde: Math.round(desde * 100), espera: entrada ? i * 32 + 300 : 0 });
        pintado.set(f.id, f.fraccion);
      }
      return barra.fila;
    });
    barras.replaceChildren(...filas);
    if (entrada) {
      barras.classList.add('entrando');
      clearTimeout(barras._reloj);
      barras._reloj = setTimeout(() => barras.classList.remove('entrando'), 1600);
    }
  }

  let barraCima = null;
  function pintarCima(entrada) {
    if (vista.nombre !== 'detalle') {
      barraCima = null;
      cima.replaceChildren();
      return;
    }
    const i = estado.proyectos.findIndex((p) => p.id === vista.id);
    const fraccion = L.avance(estado, vista.id);
    const pct = L.porcentaje(estado, vista.id);
    if (!barraCima || entrada) {
      barraCima = crearBarra(0, colorDeBarra(Math.max(i, 0)));
      barraCima.valor = 0;
      cima.replaceChildren(barraCima.relleno, barraCima.cifra.parentElement);
    }
    const desde = barraCima.valor;
    fijarBarra(barraCima, fraccion, desde);
    if (ajustando) barraCima.cifra.textContent = pct;
    else contar(barraCima.cifra, pct, { desde: Math.round(desde * 100), espera: entrada ? 260 : 0 });
    barraCima.valor = fraccion;
  }

  // ---------- tamaño del núcleo ----------

  function medir() {
    const estilo = getComputedStyle(escena);
    const libre = escena.clientHeight - parseFloat(estilo.paddingTop) - parseFloat(estilo.paddingBottom);
    const tope = conBarras() ? 'none' : `${Math.max(220, libre - (vista.nombre === 'detalle' ? 30 : 0))}px`;
    widget.style.setProperty('--tope', tope);
    widget.style.setProperty('--alto', `${contenido.offsetHeight}px`);
    zonaNativa();
  }

  const conBarras = () => vista.nombre === 'lista' || vista.nombre === 'uso';

  // Solo en la app de Mac: el rectángulo final del cuadro con sus barras, para que la
  // parte nativa ponga el panel de cristal exactamente detrás. Se calcula (no se mide)
  // porque el cuadro todavía está a media animación cuando hace falta.
  function zonaNativa() {
    if (!puente || !abierto) return;
    const MARGEN = 12;
    const CORRIMIENTO = 14; // el translateX de .nativo .widget.abierto
    const estilo = getComputedStyle(escena);
    const orilla = parseFloat(estilo.paddingLeft);
    const ancho = contenido.offsetWidth;
    const cimaAlto = vista.nombre === 'detalle' ? 30 : 0;
    const alto = contenido.offsetHeight + cimaAlto;
    let total = ancho;
    if (conBarras()) {
      const columna = escena.clientWidth - orilla * 2 - ancho - 10;
      const grosor = parseFloat(getComputedStyle(html).getPropertyValue('--grosor')) || 12;
      const mayor = Math.max(0, ...filasDeBarras().map((f) => f.fraccion));
      total += 10 + Math.max(grosor, mayor * (columna - 50)) + 8 + 40;
    }
    const arriba = Math.max(parseFloat(estilo.paddingTop), (escena.clientHeight - alto) / 2);
    const izquierda = estado.ajustes.lado === 'derecha' ? escena.clientWidth - orilla - CORRIMIENTO - total : orilla + CORRIMIENTO;
    nativo('zona', { x: izquierda - MARGEN, y: arriba - MARGEN, ancho: total + MARGEN * 2, alto: alto + MARGEN * 2 });
  }

  function crecer(campo) {
    if (window.CSS && CSS.supports('field-sizing', 'content')) return;
    campo.style.height = 'auto';
    campo.style.height = `${campo.scrollHeight}px`;
  }

  // ---------- estado ----------

  function confirmar(nuevo, { recordar = false } = {}) {
    if (nuevo === estado) return;
    anterior = recordar ? estado : anterior;
    estado = nuevo;
    almacen.guardar(estado);
  }

  function deshacer() {
    if (!anterior) return;
    estado = anterior;
    anterior = null;
    almacen.guardar(estado);
    ocultarAviso();
    if (vista.nombre === 'detalle' && !estado.proyectos.some((p) => p.id === vista.id)) vista = { nombre: 'lista' };
    aplicarAjustes();
    pintar();
  }

  function mostrarAviso(texto, conDeshacer) {
    aviso.replaceChildren(
      h('span', null, texto),
      conDeshacer && h('button', { type: 'button', onclick: deshacer }, t('deshacer')),
    );
    aviso.style.paddingInlineEnd = conDeshacer ? '' : '18px';
    aviso.classList.add('visible');
    clearTimeout(relojAviso);
    relojAviso = setTimeout(ocultarAviso, conDeshacer ? 6000 : 2600);
  }

  function ocultarAviso() {
    aviso.classList.remove('visible');
    clearTimeout(relojAviso);
  }

  // ---------- vistas ----------

  function pintar(entrada = false) {
    if (vista.nombre === 'detalle' && !estado.proyectos.some((p) => p.id === vista.id)) vista = { nombre: 'lista' };
    widget.dataset.vista = vista.nombre;
    if (vista.nombre === 'uso' && !hayUso()) vista = { nombre: 'lista' };
    widget.dataset.vista = vista.nombre;
    const vistas = { lista: vistaLista, detalle: vistaDetalle, finalizadas: vistaFinalizadas, ajustes: vistaAjustes, uso: vistaUso };
    contenido.replaceChildren(...vistas[vista.nombre]().flat().filter(Boolean));
    contenido.querySelectorAll('textarea').forEach(crecer);
    pintarBarras(entrada && conBarras());
    pintarCima(entrada);
    medir();
  }

  function ir(nueva, alLlegar) {
    if (!abierto) return;
    creando = false;
    ajustando = false;
    widget.classList.add('cambiando');
    clearInterval(relojUso);
    if (nueva.nombre === 'uso') {
      cargarUso();
      relojUso = setInterval(cargarUso, 30000);
    }
    setTimeout(() => {
      vista = nueva;
      pintar(true);
      widget.classList.remove('cambiando');
      if (alLlegar) alLlegar();
    }, calmado.matches ? 0 : CAMBIO_MS);
  }

  const volver = () => ir({ nombre: 'lista' });

  function encabezado(titulo) {
    return h(
      'header',
      { class: 'encabezado' },
      icono('atras', t('atras'), volver),
      typeof titulo === 'string' ? h('h2', { class: 'titulo' }, titulo) : titulo,
    );
  }

  // --- lista: los nombres dentro, las barras fuera ---

  function vistaLista() {
    const filas = estado.proyectos.map((p) =>
      h('li', null, h('button', { class: 'proyecto', type: 'button', onclick: () => ir({ nombre: 'detalle', id: p.id }) }, p.nombre)),
    );
    if (creando) filas.push(h('li', null, campoProyecto()));
    return [
      h('ul', { class: 'proyectos' }, filas),
      !filas.length && h('p', { class: 'vacio' }, t('sinProyectos')),
      h(
        'div',
        { class: 'herramientas' },
        icono('mas', t('nuevoProyecto'), () => {
          creando = true;
          pintar();
          contenido.querySelector('.campo-proyecto').focus();
        }),
        icono('finalizadas', t('finalizadas'), () => ir({ nombre: 'finalizadas' })),
        hayUso() && icono('uso', t('uso'), () => ir({ nombre: 'uso' })),
        icono('ajustes', t('personalizar'), () => ir({ nombre: 'ajustes' })),
      ),
    ];
  }

  function campoProyecto() {
    let resuelto = false;
    const terminar = (guardar, campo) => {
      if (resuelto) return;
      resuelto = true;
      creando = false;
      const { estado: nuevo, id } = guardar ? L.crearProyecto(estado, campo.value) : { estado, id: null };
      confirmar(nuevo);
      if (id) ir({ nombre: 'detalle', id }, () => contenido.querySelector('.nueva textarea')?.focus());
      else pintar();
    };
    return h('input', {
      class: 'campo-proyecto',
      type: 'text',
      placeholder: t('nombreProyecto'),
      'aria-label': t('nuevoProyecto'),
      maxLength: 60,
      autocomplete: 'off',
      enterKeyHint: 'done',
      onkeydown: (e) => {
        if (e.key === 'Enter') terminar(true, e.target);
        if (e.key === 'Escape') {
          e.stopPropagation();
          terminar(false, e.target);
        }
      },
      onblur: (e) => terminar(true, e.target),
    });
  }

  // --- detalle: los faltantes de un proyecto ---

  function vistaDetalle() {
    const p = estado.proyectos.find((x) => x.id === vista.id);
    if (!p) return vistaLista();

    const titulo = h('input', {
      class: 'titulo',
      type: 'text',
      value: p.nombre,
      'aria-label': t('nombreProyecto'),
      maxLength: 60,
      autocomplete: 'off',
      enterKeyHint: 'done',
      onkeydown: (e) => e.key === 'Enter' && e.target.blur(),
      onblur: (e) => {
        confirmar(L.renombrarProyecto(estado, p.id, e.target.value));
        e.target.value = L.buscarProyecto(estado, p.id).nombre;
      },
    });

    const nueva = h(
      'li',
      { class: 'tarea nueva' },
      h('span', { class: 'mas', html: ICONOS.mas }),
      campoTarea('', (valor, conEnter) => {
        const { estado: nuevo, id } = L.crearTarea(estado, p.id, valor);
        if (!id) return;
        confirmar(nuevo);
        pintar();
        const campo = contenido.querySelector('.nueva textarea');
        if (conEnter) campo.focus();
        campo.scrollIntoView({ block: 'nearest' });
      }),
    );

    const sinTareas = !p.tareas.length;
    return [
      encabezado(titulo),
      h(
        'div',
        { class: 'cuerpo' },
        h('ul', { class: 'tareas' }, p.tareas.map((tarea) => filaTarea(p, tarea)), nueva),
      ),
      ajustando && !sinTareas && controlAvance(p),
      h(
        'footer',
        { class: 'pie' },
        h(
          'button',
          {
            class: 'enlace',
            type: 'button',
            disabled: sinTareas,
            onclick: () => {
              ajustando = !ajustando;
              pintar();
            },
          },
          ajustando ? t('listo') : t('ajustarAvance'),
        ),
        botonEliminar(p),
      ),
    ];
  }

  function campoTarea(valor, alConfirmar) {
    let conEnter = false;
    return h('textarea', {
      class: 'texto-tarea',
      rows: 1,
      value: valor,
      placeholder: valor ? null : t('nuevaTarea'),
      'aria-label': valor || t('nuevaTarea'),
      maxLength: 200,
      enterKeyHint: 'done',
      oninput: (e) => {
        crecer(e.target);
        medir();
      },
      onkeydown: (e) => {
        if (e.key !== 'Enter') return;
        e.preventDefault();
        conEnter = true;
        e.target.blur();
      },
      onblur: (e) => {
        alConfirmar(e.target.value.replace(/\s+/g, ' '), conEnter);
        conEnter = false;
      },
    });
  }

  function filaTarea(p, tarea) {
    let titulo = tarea.titulo;
    const fila = h(
      'li',
      { class: 'tarea' },
      h('button', { class: 'circulo', type: 'button', 'aria-label': t('completar'), html: ICONOS.palomita, onclick: () => completar(p.id, tarea.id, fila) }),
      campoTarea(tarea.titulo, (valor) => {
        const limpio = valor.trim();
        if (limpio === titulo) return;
        // Dejar el título vacío quita la tarea, como en Recordatorios.
        confirmar(L.renombrarTarea(estado, p.id, tarea.id, limpio), { recordar: !limpio });
        if (limpio) titulo = limpio;
        else pintar();
      }),
      h('button', {
        class: 'quitar',
        type: 'button',
        'aria-label': t('quitar'),
        title: t('quitar'),
        html: ICONOS.equis,
        onclick: () => {
          confirmar(L.eliminarTarea(estado, p.id, tarea.id));
          pintar();
        },
      }),
    );
    return fila;
  }

  function completar(proyectoId, tareaId, fila) {
    if (fila.classList.contains('hecha')) return;
    fila.classList.add('hecha');
    fila.querySelectorAll('button, textarea').forEach((el) => (el.disabled = true));
    const rapido = calmado.matches;
    setTimeout(() => fila.classList.add('saliendo'), rapido ? 0 : 520);
    setTimeout(() => {
      const { estado: nuevo, proyectoFinalizado } = L.completarTarea(estado, proyectoId, tareaId);
      confirmar(nuevo, { recordar: true });
      fila.remove();
      if (vista.nombre !== 'detalle' || vista.id !== proyectoId) return pintar();
      if (!proyectoFinalizado) {
        pintarCima();
        medir();
        mostrarAviso(t('avisoTarea'), true);
        return;
      }
      // Llegó al 100 %: la barra se completa, y el proyecto se va a finalizadas.
      fijarBarra(barraCima, 1, barraCima.valor);
      contar(barraCima.cifra, 100, { desde: Math.round(barraCima.valor * 100) });
      barraCima.valor = 1;
      setTimeout(() => {
        if (vista.nombre === 'detalle' && vista.id === proyectoId) volver();
        mostrarAviso(t('avisoProyecto'), true);
      }, rapido ? 0 : 1100);
    }, rapido ? 0 : 860);
  }

  function controlAvance(p) {
    const { hecho, pendiente } = L.pesos(estado, p.id);
    const real = hecho - (p.previo || 0);
    const piso = Math.ceil((real / (real + pendiente)) * 100) || 0;
    const valor = L.porcentaje(estado, p.id);
    const cifra = h('span', { class: 'n' }, String(valor));
    const pintarPista = (el) => el.style.setProperty('--v', `${((el.value - piso) / (99 - piso)) * 100}%`);
    const regla = h('input', {
      type: 'range',
      min: piso,
      max: 99,
      step: 1,
      value: valor,
      'aria-label': t('ajustarAvance'),
      oninput: (e) => {
        estado = L.ajustarAvance(estado, p.id, Number(e.target.value));
        cifra.textContent = L.porcentaje(estado, p.id);
        pintarPista(e.target);
        barraCima.relleno.style.transition = 'none';
        pintarCima();
      },
      onchange: () => {
        barraCima.relleno.style.transition = '';
        almacen.guardar(estado);
      },
    });
    pintarPista(regla);
    return h('div', { class: 'ajuste-avance' }, regla, h('span', { class: 'pct' }, cifra, h('small', null, '%')));
  }

  function botonEliminar(p) {
    let armado = false;
    let reloj = null;
    return h(
      'button',
      {
        class: 'enlace peligro',
        type: 'button',
        onclick: (e) => {
          if (!armado) {
            armado = true;
            e.target.textContent = t('confirmarEliminar');
            reloj = setTimeout(() => {
              armado = false;
              e.target.textContent = t('eliminarProyecto');
            }, 3000);
            return;
          }
          clearTimeout(reloj);
          confirmar(L.eliminarProyecto(estado, p.id), { recordar: true });
          volver();
          mostrarAviso(t('avisoEliminado'), true);
        },
      },
      t('eliminarProyecto'),
    );
  }

  // --- finalizadas: el archivo, con botón para revertir ---

  function vistaFinalizadas() {
    const grupos = L.finalizadasPorProyecto(estado);
    const revertir = (nuevo) => {
      confirmar(nuevo, { recordar: true });
      pintar();
      mostrarAviso(t('avisoRevertida'), true);
    };
    const cuerpo = grupos.length
      ? grupos.map((g) => [
          h(
            'div',
            { class: 'seccion' },
            h('span', null, g.proyecto.nombre),
            g.finalizado && h('span', { class: 'sello' }, t('proyectoTerminado')),
          ),
          h(
            'ul',
            { class: 'tareas' },
            g.tareas.map((tarea) =>
              h(
                'li',
                { class: 'tarea' },
                h('span', { class: 'circulo lleno', html: ICONOS.palomita }),
                h('p', { class: 'texto-tarea' }, tarea.titulo),
                icono('revertir', `${t('revertir')}: ${tarea.titulo}`, () => revertir(L.restaurarTarea(estado, tarea.id)), 'revertir'),
              ),
            ),
            !g.tareas.length &&
              h(
                'li',
                { class: 'tarea' },
                h('span', { class: 'circulo lleno', html: ICONOS.palomita }),
                h('p', { class: 'texto-tarea' }, g.proyecto.nombre),
                icono('revertir', `${t('revertir')}: ${g.proyecto.nombre}`, () => revertir(L.restaurarProyecto(estado, g.proyecto.id)), 'revertir'),
              ),
          ),
        ])
      : h('p', { class: 'vacio' }, t('nadaFinalizado'));
    return [encabezado(t('finalizadas')), h('div', { class: 'cuerpo' }, cuerpo)];
  }

  // --- uso: límites y tokens de tus asistentes de código ---

  const hayUso = () => !!uso && uso.herramientas.length > 0;

  const VENTANAS = { '5h': 'ventana5h', '7d': 'ventana7d', gasto: 'ventanaGasto' };

  function filasUso() {
    if (!hayUso()) return [];
    return uso.herramientas.flatMap((h) =>
      h.limites.map((l) => ({ id: `${h.id}:${l.id}`, nombre: h.nombre, ventana: VENTANAS[l.id] ? t(VENTANAS[l.id]) : l.id, ...l })),
    );
  }

  function compacto(n) {
    if (n >= 1e6) return `${(n / 1e6).toLocaleString(undefined, { maximumFractionDigits: n >= 1e7 ? 0 : 1 })} M`;
    if (n >= 1e3) return `${Math.round(n / 1e3)} k`;
    return String(n);
  }

  function falta(epoch) {
    const min = Math.max(1, Math.round((epoch * 1000 - Date.now()) / 60000));
    if (min >= 2880) return `${Math.floor(min / 1440)} d ${Math.floor((min % 1440) / 60)} h`;
    if (min >= 60) return `${Math.floor(min / 60)} h ${min % 60} min`;
    return `${min} min`;
  }

  function vistaUso() {
    const filas = filasUso().map((f) =>
      h(
        'li',
        { class: 'limite' },
        h('b', null, `${f.nombre} · ${f.ventana}`),
        h('span', null, f.reinicia ? `${t('reinicia')} ${falta(f.reinicia)}` : t('sinUso')),
      ),
    );
    const consumo = h(
      'div',
      { class: 'tabla' },
      h('span', { class: 'rotulo' }, 'Tokens'),
      h('span', { class: 'rotulo' }, t('hoy')),
      h('span', { class: 'rotulo' }, t('sieteDias')),
      uso.herramientas.map((x) => [h('b', null, x.nombre), h('span', null, compacto(x.tokens.hoy)), h('span', null, compacto(x.tokens.semana))]),
    );
    const sinConectar = uso.herramientas.some((x) => x.id === 'claude' && !x.conectado);
    return [
      encabezado(t('uso')),
      h('ul', { class: 'proyectos limites' }, filas),
      h('div', { class: 'consumo' }, consumo, sinConectar && h('p', { class: 'nota' }, t('conectarClaude'))),
    ];
  }

  function recibirUso(nuevo) {
    const cambio = JSON.stringify(nuevo && nuevo.herramientas) !== JSON.stringify(uso && uso.herramientas);
    uso = nuevo && Array.isArray(nuevo.herramientas) ? nuevo : null;
    if (cambio && abierto && (vista.nombre === 'uso' || vista.nombre === 'lista') && !creando) pintar();
  }

  async function cargarUso() {
    if (!almacen) return;
    // En la app de iPhone/iPad lo pide la parte nativa (al servidor de tu Mac) y llega por recibirUso.
    if (almacen.modo === 'nativo') return movil.postMessage({ tipo: 'uso' });
    if (almacen.modo !== 'servidor') return;
    try {
      const r = await fetch('api/uso', { headers: { 'X-Flecha': '1' }, cache: 'no-store' });
      if (r.ok) recibirUso(await r.json());
    } catch (error) {
      /* sin servidor no hay sección de uso */
    }
  }

  // --- personalizar: como elegir la carátula de un reloj ---

  function vistaAjustes() {
    const a = estado.ajustes;
    const cambiar = (cambios) => {
      confirmar(L.cambiarAjustes(estado, cambios));
      aplicarAjustes();
      pintar();
    };
    const muestra = (clase, valor, etiqueta, estilo) =>
      h('button', {
        class: `muestra ${clase}`.trim(),
        type: 'button',
        style: estilo,
        'aria-label': etiqueta,
        title: etiqueta,
        'aria-pressed': String(a.color === valor),
        onclick: () => cambiar({ color: valor }),
      });
    const propio = /^#/.test(a.color) && !PALETA.includes(a.color);
    const segmento = (clave, opciones) =>
      h(
        'div',
        { class: 'segmento', role: 'group' },
        opciones.map(([valor, contenidoBoton, etiqueta]) =>
          h('button', { type: 'button', 'aria-pressed': String(a[clave] === valor), 'aria-label': etiqueta, title: etiqueta, onclick: () => cambiar({ [clave]: valor }) }, contenidoBoton),
        ),
      );
    const grupo = (rotulo, ...hijos) => h('section', { class: 'grupo' }, h('h3', { class: 'rotulo' }, rotulo), hijos);

    return [
      encabezado(t('personalizar')),
      h(
        'div',
        { class: 'cuerpo' },
        grupo(
          t('color'),
          h(
            'div',
            { class: 'muestras' },
            muestra('auto', 'auto', t('colorAuto')),
            PALETA.map((c) => muestra('', c, c, `--c:${c}`)),
            muestra('multi', 'multicolor', t('colorMulti')),
            h(
              'label',
              { class: 'muestra propio', style: propio ? `--c:${a.color}` : null, 'aria-pressed': String(propio), title: t('colorPropio') },
              h('span', { html: ICONOS.mas, style: 'display:grid' }),
              h('input', {
                type: 'color',
                value: propio ? a.color : '#0a84ff',
                'aria-label': t('colorPropio'),
                oninput: (e) => aplicarTinte(e.target.value),
                onchange: (e) => cambiar({ color: e.target.value }),
              }),
            ),
          ),
        ),
        grupo(
          t('forma'),
          segmento('forma', [
            ['redondeada', h('span', { class: 'mini redondeada' }), t('formaRedondeada')],
            ['pildora', h('span', { class: 'mini pildora' }), t('formaPildora')],
            ['fina', h('span', { class: 'mini fina' }), t('formaFina')],
          ]),
        ),
        grupo(t('lado'), segmento('lado', [['izquierda', t('izquierda')], ['derecha', t('derecha')]])),
        grupo(t('tema'), segmento('tema', [['auto', t('temaAuto')], ['claro', t('claro')], ['oscuro', t('oscuro')]])),
        grupo(
          t('datos'),
          h(
            'div',
            { class: 'acciones' },
            !puente && !movil && h('button', { class: 'boton', type: 'button', onclick: exportar }, t('exportar')),
            !puente && !movil && h('button', { class: 'boton', type: 'button', onclick: importar }, t('importar')),
            a.ejemplo && h('button', { class: 'boton', type: 'button', onclick: empezarDeCero }, t('empezarDeCero')),
          ),
          h('p', { class: 'nota' }, [a.ejemplo && t('notaEjemplo'), t(notaDeDatos())].filter(Boolean).join(' ')),
        ),
        movil &&
          grupo(
            t('tuMac'),
            h(
              'div',
              { class: 'acciones' },
              h('button', { class: 'boton', type: 'button', onclick: () => movil.postMessage({ tipo: conexion.servidor ? 'desconectar' : 'conectar' }) }, t(conexion.servidor ? 'desconectar' : 'conectar')),
            ),
            h('p', { class: 'nota' }, conexion.servidor ? `${t(conexion.enLinea ? 'macEnLinea' : 'macSinConexion')} ${conexion.servidor}` : t('notaConectar')),
          ),
      ),
    ];
  }

  function notaDeDatos() {
    if (almacen.modo === 'servidor') return 'notaServidor';
    if (almacen.modo === 'nativo') return conexion.servidor ? 'notaNativaMac' : 'notaNativa';
    return 'notaLocal';
  }

  function empezarDeCero() {
    const limpio = L.estadoVacio();
    limpio.ajustes = { ...estado.ajustes, iniciado: true };
    delete limpio.ajustes.ejemplo;
    confirmar(limpio, { recordar: true });
    volver();
    mostrarAviso(t('empezarDeCero'), true);
  }

  function exportar() {
    const archivo = new Blob([JSON.stringify(estado, null, 2)], { type: 'application/json' });
    const enlace = h('a', { href: URL.createObjectURL(archivo), download: `flecha-${new Date().toISOString().slice(0, 10)}.json` });
    document.body.append(enlace);
    enlace.click();
    enlace.remove();
    setTimeout(() => URL.revokeObjectURL(enlace.href), 1000);
  }

  function importar() {
    const selector = h('input', {
      type: 'file',
      accept: '.json,application/json',
      onchange: async () => {
        try {
          const crudo = JSON.parse(await selector.files[0].text());
          if (!crudo || !Array.isArray(crudo.proyectos)) throw new Error('formato');
          const nuevo = L.normalizar(crudo);
          nuevo.ajustes.iniciado = true;
          delete nuevo.ajustes.ejemplo;
          confirmar(nuevo, { recordar: true });
          aplicarAjustes();
          volver();
          mostrarAviso(t('avisoImportado'), true);
        } catch (error) {
          mostrarAviso(t('avisoImportMal'));
        }
      },
    });
    selector.click();
  }

  // ---------- abrir y cerrar la línea ----------

  function abrir(evento) {
    if (abierto) return;
    const conTeclado = !!evento && evento.detail === 0;
    abierto = true;
    asa.setAttribute('aria-expanded', 'true');
    nativo('expandir');
    cargarUso();
    // En la app nativa la ventana crece primero; se espera un instante a que termine.
    setTimeout(() => {
      if (!abierto) return;
      pintar(true);
      widget.classList.add('abierto');
      zonaNativa();
      if (conTeclado) contenido.querySelector('button')?.focus({ preventScroll: true });
    }, puente ? 70 : 0);
  }

  function cerrar() {
    if (!abierto) return;
    abierto = false;
    creando = false;
    ajustando = false;
    asa.setAttribute('aria-expanded', 'false');
    clearInterval(relojUso);
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
    nativo('cerrando');
    widget.classList.remove('abierto');
    setTimeout(() => {
      if (abierto) return;
      vista = { nombre: 'lista' };
      pintar();
      nativo('contraer');
    }, calmado.matches ? 0 : MORFOSIS_MS);
  }

  asa.setAttribute('aria-label', t('abrir'));
  asa.setAttribute('aria-expanded', 'false');
  asa.addEventListener('click', abrir);

  escena.addEventListener('pointerdown', (e) => {
    if (abierto && !e.target.closest('.nucleo, .asa')) cerrar();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || !abierto) return;
    if (creando) {
      creando = false;
      pintar();
    } else if (vista.nombre !== 'lista') volver();
    else {
      cerrar();
      asa.focus();
    }
  });

  window.addEventListener('resize', medir);

  // ---------- arranque ----------

  function escribiendo() {
    const el = document.activeElement;
    return !!el && (el.tagName === 'TEXTAREA' || (el.tagName === 'INPUT' && el.type !== 'range'));
  }

  // Parámetros de la URL para demos y capturas: ?abierto=1&vista=detalle&p=0&color=%230a84ff&forma=pildora&lado=derecha&tema=claro
  function aplicarDemo() {
    const q = new URLSearchParams(location.search);
    const cambios = {};
    for (const clave of ['color', 'forma', 'lado', 'tema']) if (q.has(clave)) cambios[clave] = q.get(clave);
    if (Object.keys(cambios).length) estado = L.cambiarAjustes(estado, cambios);
    if (!q.has('abierto')) return;
    const nombre = q.get('vista');
    const p = estado.proyectos[Number(q.get('p')) || 0];
    if (nombre === 'detalle' && p) vista = { nombre, id: p.id };
    else if (nombre === 'finalizadas' || nombre === 'ajustes' || nombre === 'uso') vista = { nombre };
    ajustando = q.has('ajustando');
    return true;
  }

  async function arrancar() {
    if (puente) html.classList.add('nativo');
    almacen = await window.Flecha.almacen.abrir({
      externo(nuevo) {
        if (escribiendo() || ajustando) return false;
        if (JSON.stringify(nuevo) === JSON.stringify(estado)) return true;
        estado = nuevo;
        anterior = null;
        if (vista.nombre === 'detalle' && !estado.proyectos.some((p) => p.id === vista.id)) vista = { nombre: 'lista' };
        aplicarAjustes();
        pintar();
        if (abierto) mostrarAviso(t('avisoExterno'));
        return true;
      },
      fallo: () => mostrarAviso(t('avisoNoGuardo')),
    });
    estado = almacen.estado;
    await cargarUso();
    const demo = aplicarDemo();
    aplicarAjustes();
    pintar();
    html.classList.add('lista');
    if (demo) abrir();

    if (almacen.modo === 'local' && 'serviceWorker' in navigator && location.protocol === 'https:') {
      navigator.serviceWorker.register('sw.js').catch(() => {});
    }
  }

  // Llega desde un toque en el widget: flecha://proyecto/<id>
  function abrirProyecto(id) {
    if (!estado.proyectos.some((p) => p.id === id)) return abrir();
    if (abierto) return ir({ nombre: 'detalle', id });
    vista = { nombre: 'detalle', id };
    abrir();
  }

  window.Flecha.cerrar = cerrar;
  window.Flecha.abrir = () => abrir();
  window.Flecha.abrirProyecto = abrirProyecto;
  window.Flecha.abrirUso = () => {
    if (!hayUso()) return abrir();
    if (abierto) return ir({ nombre: 'uso' });
    vista = { nombre: 'uso' };
    abrir();
  };
  window.Flecha.recibirUso = recibirUso;
  window.Flecha.recibirConexion = (nueva) => {
    conexion = nueva || { servidor: null, enLinea: false };
    if (!conexion.servidor) recibirUso(null);
    if (abierto && vista.nombre === 'ajustes') pintar();
  };
  arrancar();
})();
