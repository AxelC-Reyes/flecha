// Las tres pantallas: Hoy, Proyectos (con el detalle de cada uno) y Calendario.

import SwiftUI

extension String {
    /// Solo la primera letra: "jueves 17 de septiembre" -> "Jueves 17 de septiembre".
    var conMayuscula: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: Hoy

struct HoyView: View {
    @EnvironmentObject private var tienda: Tienda

    private var fechaLarga: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return f.string(from: Date()).conMayuscula
    }

    var body: some View {
        let dia = tienda.estado.resumen()
        let proximas = tienda.estado.proximas()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(fechaLarga).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Text(texto("Hoy", "Today")).font(.largeTitle.bold())
                        if dia.total > 0 {
                            BarraAvance(fraccion: dia.fraccion ?? 0, porcentaje: dia.porcentaje, color: tienda.apariencia.tinte(), apariencia: tienda.apariencia, grosor: 14, cifra: 22)
                            Text(texto("\(dia.hechas) de \(dia.total) hechas", "\(dia.hechas) of \(dia.total) done"))
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text(texto("Nada para hoy. Ponle fecha a una tarea o crea una rutina dentro de un proyecto.",
                                       "Nothing for today. Give a task a date or create a routine inside a project."))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)

                    if !dia.rutinas.isEmpty {
                        Seccion(titulo: texto("Rutinas", "Routines")) {
                            ForEach(dia.rutinas) { RenglonRutina(proyecto: $0.proyecto, rutina: $0.rutina) }
                        }
                    }
                    if !dia.atrasadas.isEmpty {
                        Seccion(titulo: texto("Atrasadas", "Overdue")) { ForEach(dia.atrasadas) { RenglonTarea(pendiente: $0) } }
                    }
                    if !dia.vencen.isEmpty {
                        Seccion(titulo: texto("Vence hoy", "Due today")) { ForEach(dia.vencen) { RenglonTarea(pendiente: $0) } }
                    }
                    if !proximas.isEmpty {
                        Seccion(titulo: texto("Próximos 7 días", "Next 7 days")) { ForEach(proximas) { RenglonTarea(pendiente: $0) } }
                    }
                    if !tienda.estado.proyectos.isEmpty {
                        Seccion(titulo: texto("Proyectos", "Projects")) {
                            ForEach(Array(tienda.estado.proyectos.enumerated()), id: \.element.id) { posicion, proyecto in
                                Button {
                                    tienda.pestana = .proyectos
                                    tienda.ruta = [proyecto.id]
                                } label: { RenglonProyecto(proyecto: proyecto, posicion: posicion) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if let filas = tienda.uso?.filas(), !filas.isEmpty {
                        Seccion(titulo: texto("Uso de tus asistentes", "Assistant usage")) {
                            ForEach(filas) { fila in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(fila.nombre).font(.subheadline.weight(.semibold))
                                    BarraAvance(fraccion: fila.fraccion, porcentaje: fila.porcentaje, color: fila.alerta ? .red : tienda.apariencia.tinte(), apariencia: tienda.apariencia, grosor: 8)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 90)
            }
            .background(Color.fondoFlecha)
            .refreshable { await tienda.sincronizar() }
            .toolbar { BotonAjustes() }
        }
    }
}

struct BotonAjustes: ToolbarContent {
    @EnvironmentObject private var tienda: Tienda

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { tienda.hoja = .ajustes } label: {
                Image(systemName: tienda.conexion == nil ? "gearshape" : tienda.enLinea ? "desktopcomputer" : "desktopcomputer.trianglebadge.exclamationmark")
            }
            .accessibilityLabel(texto("Ajustes", "Settings"))
        }
    }
}

// MARK: Proyectos

struct ProyectosView: View {
    @EnvironmentObject private var tienda: Tienda
    @State private var creando = false
    @State private var nombre = ""

    var body: some View {
        NavigationStack(path: $tienda.ruta) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(texto("Proyectos", "Projects")).font(.largeTitle.bold()).padding(.horizontal, 6)
                    if tienda.estado.proyectos.isEmpty {
                        Text(texto("Aún no hay proyectos. Crea el primero con el botón +.", "No projects yet. Create the first one with the + button."))
                            .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 6)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(tienda.estado.proyectos.enumerated()), id: \.element.id) { posicion, proyecto in
                                NavigationLink(value: proyecto.id) { RenglonProyecto(proyecto: proyecto, posicion: posicion) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.cuadroFlecha))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 90)
            }
            .background(Color.fondoFlecha)
            .refreshable { await tienda.sincronizar() }
            .navigationDestination(for: String.self) { ProyectoView(id: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { creando = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(texto("Nuevo proyecto", "New project"))
                }
                BotonAjustes()
            }
            .alert(texto("Nuevo proyecto", "New project"), isPresented: $creando) {
                TextField(texto("Nombre", "Name"), text: $nombre)
                Button(texto("Cancelar", "Cancel"), role: .cancel) { nombre = "" }
                Button(texto("Crear", "Create")) {
                    let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
                    nombre = ""
                    guard !limpio.isEmpty else { return }
                    let id = nuevoId()
                    tienda.hacer(.crearProyecto(id: id, nombre: limpio))
                    tienda.ruta = [id]
                }
            }
        }
    }
}

struct ProyectoView: View {
    @EnvironmentObject private var tienda: Tienda
    let id: String
    @State private var nueva = ""
    @State private var confirmandoBorrar = false
    @FocusState private var escribiendo: Bool

    var body: some View {
        if let proyecto = tienda.estado.proyectos.first(where: { $0.id == id }) {
            let posicion = tienda.estado.proyectos.firstIndex { $0.id == id } ?? 0
            let avance = tienda.estado.avance(proyecto)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(proyecto.nombre).font(.largeTitle.bold())
                        BarraAvance(fraccion: avance.fraccion, porcentaje: avance.porcentaje, color: tienda.apariencia.tinte(posicion), apariencia: tienda.apariencia, grosor: 14, cifra: 22)
                    }
                    .padding(.horizontal, 6)

                    Seccion(titulo: texto("Rutinas", "Routines")) {
                        ForEach(proyecto.rutinas) { RenglonRutina(proyecto: proyecto, rutina: $0, conProyecto: false) }
                        Button { tienda.hoja = .rutina(proyecto: proyecto.id) } label: {
                            Label(texto("Nueva rutina", "New routine"), systemImage: "plus")
                                .font(.body).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Seccion(titulo: texto("Faltantes", "To do")) {
                        ForEach(proyecto.tareas) { RenglonTarea(pendiente: Pendiente(proyecto: proyecto, tarea: $0), conProyecto: false) }
                        HStack(spacing: 12) {
                            Image(systemName: "plus").foregroundStyle(.tertiary).frame(width: 24)
                            TextField(texto("Nueva tarea", "New task"), text: $nueva)
                                .focused($escribiendo)
                                .submitLabel(.done)
                                .onSubmit { agregar(a: proyecto) }
                            // Para ponerle fecha antes de crearla.
                            Button {
                                tienda.hoja = .tarea(proyecto: proyecto.id, tarea: nil)
                            } label: { Image(systemName: "calendar.badge.plus").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(texto("Nueva tarea con fecha", "New task with a date"))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 90)
            }
            .background(Color.fondoFlecha)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { confirmandoBorrar = true } label: {
                            Label(texto("Eliminar proyecto", "Delete project"), systemImage: "trash")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog(texto("¿Eliminar \(proyecto.nombre) y todo su avance?", "Delete \(proyecto.nombre) and all its progress?"),
                                isPresented: $confirmandoBorrar, titleVisibility: .visible) {
                Button(texto("Eliminar", "Delete"), role: .destructive) { tienda.hacer(.eliminarProyecto(id: proyecto.id)) }
            }
        } else {
            Color.fondoFlecha.ignoresSafeArea()
        }
    }

    private func agregar(a proyecto: Proyecto) {
        let limpio = nueva.trimmingCharacters(in: .whitespacesAndNewlines)
        nueva = ""
        guard !limpio.isEmpty else { return }
        tienda.hacer(.crearTarea(proyecto: proyecto.id, id: nuevoId(), titulo: limpio, vence: nil))
        escribiendo = true // para capturar varias seguidas, como en Recordatorios
    }
}

// MARK: Calendario

struct CalendarioView: View {
    @EnvironmentObject private var tienda: Tienda
    @State private var mes = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var seleccion = Fecha.hoy

    private var calendario: Calendar { Calendar.current }

    private var tituloDelMes: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: mes).conMayuscula
    }

    /// Las casillas del mes, con huecos al inicio para cuadrar con el primer día de la semana.
    private var casillas: [String?] {
        guard let rango = calendario.range(of: .day, in: .month, for: mes) else { return [] }
        let primero = calendario.component(.weekday, from: mes)
        let huecos = (primero - calendario.firstWeekday + 7) % 7
        let dias = rango.compactMap { calendario.date(byAdding: .day, value: $0 - 1, to: mes) }.map(Fecha.texto)
        return Array(repeating: nil, count: huecos) + dias
    }

    private var iniciales: [String] {
        let simbolos = calendario.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { simbolos[($0 + calendario.firstWeekday - 1) % 7] }
    }

    var body: some View {
        // Qué días tienen entregas pendientes, para los puntitos.
        let entregas = Dictionary(grouping: tienda.estado.proyectos.flatMap(\.tareas).compactMap(\.vence)) { $0 }.mapValues(\.count)
        let dia = tienda.estado.resumen(de: seleccion)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(tituloDelMes).font(.largeTitle.bold())
                        Spacer()
                        Button { mover(-1) } label: { Image(systemName: "chevron.left") }
                        Button { mover(1) } label: { Image(systemName: "chevron.right") }.padding(.leading, 14)
                    }
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 6)

                    VStack(spacing: 6) {
                        HStack(spacing: 0) {
                            ForEach(Array(iniciales.enumerated()), id: \.offset) { _, letra in
                                Text(letra).font(.caption.weight(.semibold)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                            }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                            ForEach(Array(casillas.enumerated()), id: \.offset) { _, fecha in
                                if let fecha { casilla(fecha, entregas: entregas[fecha] ?? 0) } else { Color.clear.frame(height: 46) }
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.cuadroFlecha))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(seleccion == Fecha.hoy ? texto("Hoy", "Today") : Fecha.legible(seleccion).conMayuscula)
                            .font(.title3.bold())
                        if dia.total > 0 {
                            BarraAvance(fraccion: dia.fraccion ?? 0, porcentaje: dia.porcentaje, color: tienda.apariencia.tinte(), apariencia: tienda.apariencia)
                        } else {
                            Text(texto("Sin deberes este día.", "Nothing due this day.")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)

                    if !dia.rutinas.isEmpty {
                        Seccion(titulo: texto("Rutinas", "Routines")) {
                            ForEach(dia.rutinas) { RenglonRutina(proyecto: $0.proyecto, rutina: $0.rutina, fecha: seleccion) }
                        }
                    }
                    if !dia.atrasadas.isEmpty {
                        Seccion(titulo: texto("Atrasadas", "Overdue")) { ForEach(dia.atrasadas) { RenglonTarea(pendiente: $0) } }
                    }
                    if !dia.vencen.isEmpty {
                        Seccion(titulo: texto("Vencen", "Due")) { ForEach(dia.vencen) { RenglonTarea(pendiente: $0) } }
                    }
                    if !dia.terminadas.isEmpty {
                        Seccion(titulo: texto("Terminadas", "Completed")) {
                            ForEach(dia.terminadas) { hecha in
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(tienda.apariencia.tinte())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hecha.titulo).foregroundStyle(.secondary)
                                        Text(tienda.estado.nombreDelProyecto(hecha.proyectoId)).font(.footnote).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 90)
            }
            .background(Color.fondoFlecha)
            .toolbar { BotonAjustes() }
        }
    }

    private func mover(_ meses: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { mes = calendario.date(byAdding: .month, value: meses, to: mes) ?? mes }
    }

    private func casilla(_ fecha: String, entregas: Int) -> some View {
        let elegida = fecha == seleccion
        let esHoy = fecha == Fecha.hoy
        let rutinas = tienda.estado.proyectos.flatMap(\.rutinas).filter { $0.toca(fecha) }
        let cumplidas = !rutinas.isEmpty && rutinas.allSatisfy { $0.cumplida(fecha) }
        return Button { seleccion = fecha } label: {
            VStack(spacing: 3) {
                Text(String(Int(fecha.suffix(2)) ?? 0))
                    .font(.system(size: 16, weight: esHoy || elegida ? .bold : .regular, design: .rounded))
                    .foregroundStyle(elegida ? AnyShapeStyle(Color.fondoFlecha) : AnyShapeStyle(.primary))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(elegida ? AnyShapeStyle(tienda.apariencia.tinte()) : AnyShapeStyle(.clear)))
                    .overlay(Circle().strokeBorder(.tertiary, lineWidth: esHoy && !elegida ? 1.5 : 0))
                HStack(spacing: 3) {
                    // Punto: hay entregas ese día (rojo si ya pasó). Raya: rutinas cumplidas.
                    if entregas > 0 { Circle().fill(fecha < Fecha.hoy ? Color.red : Color.primary).frame(width: 5, height: 5) }
                    if cumplidas { Capsule().fill(tienda.apariencia.tinte()).frame(width: 10, height: 4) }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
