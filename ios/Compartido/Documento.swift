// Los cambios que el teléfono puede hacer, aplicados sobre el JSON crudo para no
// perder nada que la versión de computadora haya guardado (ajustes, campos nuevos).
//
// Cada cambio es una Operacion que se puede repetir sin daño. Eso permite trabajar
// sin conexión: las operaciones se guardan en una cola y, al volver a ver la Mac,
// se vuelven a aplicar sobre lo que ella tenga en ese momento (ver Sincronia.swift).

import Foundation

enum Operacion: Codable, Equatable {
    case crearProyecto(id: String, nombre: String)
    case eliminarProyecto(id: String)
    case crearTarea(proyecto: String, id: String, titulo: String, vence: String?)
    case editarTarea(proyecto: String, id: String, titulo: String, vence: String?)
    case eliminarTarea(proyecto: String, id: String)
    case completarTarea(proyecto: String, id: String, fin: String)
    case restaurarTarea(id: String)
    case crearRutina(proyecto: String, id: String, titulo: String, veces: Int, dias: [Int]?, meta: Int?)
    case eliminarRutina(proyecto: String, id: String)
    /// Deja en `cuenta` las veces hechas ese día. Absoluto (no "+1") para poder repetirse.
    case fijarRutina(proyecto: String, id: String, fecha: String, cuenta: Int)
}

func nuevoId() -> String { String(UUID().uuidString.lowercased().prefix(8)) }

struct Documento {
    private(set) var raiz: [String: Any]

    init(_ datos: Data?) {
        let leido = datos.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        raiz = leido ?? [:]
        normalizar()
    }

    var datos: Data {
        (try? JSONSerialization.data(withJSONObject: raiz, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    // MARK: acceso

    private typealias Objeto = [String: Any]

    private var proyectos: [Objeto] {
        get { raiz["proyectos"] as? [Objeto] ?? [] }
        set { raiz["proyectos"] = newValue }
    }

    private var archivo: Objeto {
        get { raiz["finalizadas"] as? Objeto ?? [:] }
        set { raiz["finalizadas"] = newValue }
    }

    private var tareasFinalizadas: [Objeto] {
        get { archivo["tareas"] as? [Objeto] ?? [] }
        set { archivo["tareas"] = newValue }
    }

    private var proyectosFinalizados: [Objeto] {
        get { archivo["proyectos"] as? [Objeto] ?? [] }
        set { archivo["proyectos"] = newValue }
    }

    /// Completa lo mínimo para que todo tenga forma e identificador.
    private mutating func normalizar() {
        if raiz["version"] == nil { raiz["version"] = 1 }
        if raiz["ajustes"] as? Objeto == nil { raiz["ajustes"] = Objeto() }
        proyectos = (raiz["proyectos"] as? [Any] ?? []).compactMap { crudo in
            guard var proyecto = crudo as? Objeto, let nombre = proyecto["nombre"] as? String, !nombre.isEmpty else { return nil }
            if (proyecto["id"] as? String ?? "").isEmpty { proyecto["id"] = nuevoId() }
            proyecto["tareas"] = (proyecto["tareas"] as? [Any] ?? []).compactMap { tarea -> Objeto? in
                if let titulo = tarea as? String { return titulo.isEmpty ? nil : ["id": nuevoId(), "titulo": titulo] }
                guard var objeto = tarea as? Objeto, let titulo = objeto["titulo"] as? String, !titulo.isEmpty else { return nil }
                if (objeto["id"] as? String ?? "").isEmpty { objeto["id"] = nuevoId() }
                return objeto
            }
            return proyecto
        }
        var limpio = archivo
        limpio["tareas"] = tareasFinalizadas
        limpio["proyectos"] = proyectosFinalizados
        archivo = limpio
        // Al crear algo aquí, la versión de computadora ya no debe mostrar sus proyectos de ejemplo.
    }

    private mutating func conProyecto(_ id: String, _ cambio: (inout Objeto) -> Void) {
        var lista = proyectos
        guard let i = lista.firstIndex(where: { $0["id"] as? String == id }) else { return }
        cambio(&lista[i])
        proyectos = lista
    }

    // MARK: reglas (las mismas de web/logica.js)

    private static func cumplidos(_ rutina: Objeto) -> Int {
        let veces = max(1, rutina["veces"] as? Int ?? 1)
        return (rutina["registro"] as? [String: Int] ?? [:]).values.filter { $0 >= veces }.count
    }

    /// Sin tareas pendientes y con todas sus rutinas cumplidas. Una rutina sin meta nunca termina.
    private static func sinPendientes(_ proyecto: Objeto) -> Bool {
        guard (proyecto["tareas"] as? [Objeto] ?? []).isEmpty else { return false }
        return (proyecto["rutinas"] as? [Objeto] ?? []).allSatisfy { rutina in
            guard let meta = rutina["meta"] as? Int, meta >= 1 else { return false }
            return cumplidos(rutina) >= meta
        }
    }

    private mutating func archivarSiTermino(_ id: String, fin: String) {
        guard let proyecto = proyectos.first(where: { $0["id"] as? String == id }), Self.sinPendientes(proyecto) else { return }
        let algoHecho = (proyecto["previo"] as? Double ?? 0) > 0
            || tareasFinalizadas.contains { $0["proyectoId"] as? String == id }
            || !(proyecto["rutinas"] as? [Objeto] ?? []).isEmpty
        guard algoHecho else { return }
        proyectos.removeAll { $0["id"] as? String == id }
        var archivado = proyecto
        archivado["fin"] = fin
        proyectosFinalizados.append(archivado)
    }

    // MARK: aplicar

    mutating func aplicar(_ operacion: Operacion) {
        switch operacion {
        case let .crearProyecto(id, nombre):
            guard !proyectos.contains(where: { $0["id"] as? String == id }) else { return }
            proyectos.append(["id": id, "nombre": nombre, "previo": 0, "tareas": [Objeto](), "creado": Fecha.instante()])
            marcarIniciado()

        case let .eliminarProyecto(id):
            proyectos.removeAll { $0["id"] as? String == id }
            proyectosFinalizados.removeAll { $0["id"] as? String == id }
            tareasFinalizadas.removeAll { $0["proyectoId"] as? String == id }

        case let .crearTarea(proyecto, id, titulo, vence):
            conProyecto(proyecto) { p in
                var tareas = p["tareas"] as? [Objeto] ?? []
                guard !tareas.contains(where: { $0["id"] as? String == id }) else { return }
                var tarea: Objeto = ["id": id, "titulo": titulo]
                if let vence { tarea["vence"] = vence }
                tareas.append(tarea)
                p["tareas"] = tareas
            }

        case let .editarTarea(proyecto, id, titulo, vence):
            conProyecto(proyecto) { p in
                var tareas = p["tareas"] as? [Objeto] ?? []
                guard let i = tareas.firstIndex(where: { $0["id"] as? String == id }) else { return }
                tareas[i]["titulo"] = titulo
                tareas[i]["vence"] = vence
                p["tareas"] = tareas
            }

        case let .eliminarTarea(proyecto, id):
            conProyecto(proyecto) { p in
                p["tareas"] = (p["tareas"] as? [Objeto] ?? []).filter { $0["id"] as? String != id }
            }

        case let .completarTarea(proyecto, id, fin):
            var terminada: Objeto?
            conProyecto(proyecto) { p in
                var tareas = p["tareas"] as? [Objeto] ?? []
                guard let i = tareas.firstIndex(where: { $0["id"] as? String == id }) else { return }
                terminada = tareas.remove(at: i)
                p["tareas"] = tareas
            }
            guard var tarea = terminada else { return }
            tarea["proyectoId"] = proyecto
            tarea["fin"] = fin
            tareasFinalizadas.append(tarea)
            archivarSiTermino(proyecto, fin: fin)

        case let .restaurarTarea(id):
            guard let i = tareasFinalizadas.firstIndex(where: { $0["id"] as? String == id }) else { return }
            var tarea = tareasFinalizadas.remove(at: i)
            guard let proyecto = tarea["proyectoId"] as? String else { return }
            tarea["proyectoId"] = nil
            tarea["fin"] = nil
            // Si el proyecto ya se había archivado, regresa con ella.
            if let j = proyectosFinalizados.firstIndex(where: { $0["id"] as? String == proyecto }) {
                var revivido = proyectosFinalizados.remove(at: j)
                revivido["fin"] = nil
                revivido["tareas"] = [Objeto]()
                proyectos.append(revivido)
            }
            conProyecto(proyecto) { p in p["tareas"] = (p["tareas"] as? [Objeto] ?? []) + [tarea] }

        case let .crearRutina(proyecto, id, titulo, veces, dias, meta):
            conProyecto(proyecto) { p in
                var rutinas = p["rutinas"] as? [Objeto] ?? []
                guard !rutinas.contains(where: { $0["id"] as? String == id }) else { return }
                var rutina: Objeto = ["id": id, "titulo": titulo, "veces": max(1, veces), "registro": [String: Int](), "creado": Fecha.instante()]
                if let dias, !dias.isEmpty, dias.count < 7 { rutina["dias"] = dias.sorted() }
                if let meta, meta >= 1 { rutina["meta"] = meta }
                rutinas.append(rutina)
                p["rutinas"] = rutinas
            }

        case let .eliminarRutina(proyecto, id):
            conProyecto(proyecto) { p in
                let quedan = (p["rutinas"] as? [Objeto] ?? []).filter { $0["id"] as? String != id }
                p["rutinas"] = quedan.isEmpty ? nil : quedan
            }

        case let .fijarRutina(proyecto, id, fecha, cuenta):
            conProyecto(proyecto) { p in
                var rutinas = p["rutinas"] as? [Objeto] ?? []
                guard let i = rutinas.firstIndex(where: { $0["id"] as? String == id }) else { return }
                let veces = max(1, rutinas[i]["veces"] as? Int ?? 1)
                var registro = rutinas[i]["registro"] as? [String: Int] ?? [:]
                let limpia = max(0, min(veces, cuenta))
                registro[fecha] = limpia > 0 ? limpia : nil
                rutinas[i]["registro"] = registro
                p["rutinas"] = rutinas
            }
            archivarSiTermino(proyecto, fin: Fecha.instante())
        }
    }

    private mutating func marcarIniciado() {
        var ajustes = raiz["ajustes"] as? Objeto ?? [:]
        ajustes["iniciado"] = true
        ajustes["ejemplo"] = nil
        raiz["ajustes"] = ajustes
    }
}
