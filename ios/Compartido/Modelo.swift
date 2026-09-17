// Lectura tolerante del estado de Flecha (el mismo JSON de ESQUEMA.md) y cálculo
// del avance. Lo usan la app y el widget; aquí nunca se escribe el estado: eso lo
// hace la interfaz web, que es la dueña del formato.

import Foundation

struct Tarea: Decodable {
    let peso: Double

    init(from decoder: Decoder) throws {
        // Una tarea puede venir como texto simple o como objeto con `peso` opcional.
        if (try? decoder.singleValueContainer().decode(String.self)) != nil {
            peso = 1
            return
        }
        let caja = try decoder.container(keyedBy: Claves.self)
        let leido = (try? caja.decode(Double.self, forKey: .peso)) ?? 1
        peso = leido > 0 ? leido : 1
    }

    private enum Claves: String, CodingKey { case peso }
}

struct Proyecto: Decodable {
    let id: String
    let nombre: String
    let previo: Double
    let tareas: [Tarea]

    init(from decoder: Decoder) throws {
        let caja = try decoder.container(keyedBy: Claves.self)
        id = (try? caja.decode(String.self, forKey: .id)) ?? UUID().uuidString
        nombre = (try? caja.decode(String.self, forKey: .nombre)) ?? ""
        previo = max(0, (try? caja.decode(Double.self, forKey: .previo)) ?? 0)
        tareas = (try? caja.decode([Tarea].self, forKey: .tareas)) ?? []
    }

    private enum Claves: String, CodingKey { case id, nombre, previo, tareas }
}

struct TareaFinalizada: Decodable {
    let proyectoId: String
    let peso: Double

    init(from decoder: Decoder) throws {
        let caja = try decoder.container(keyedBy: Claves.self)
        proyectoId = (try? caja.decode(String.self, forKey: .proyectoId)) ?? ""
        let leido = (try? caja.decode(Double.self, forKey: .peso)) ?? 1
        peso = leido > 0 ? leido : 1
    }

    private enum Claves: String, CodingKey { case proyectoId, peso }
}

struct Ajustes: Decodable {
    var color = "auto" // "auto" | "multicolor" | "#rrggbb"
    var forma = "redondeada" // "redondeada" | "pildora" | "fina"
    var fondoWidget: String? // "#rrggbb": para igualar el fondo de pantalla

    init() {}

    init(from decoder: Decoder) throws {
        let caja = try decoder.container(keyedBy: Claves.self)
        color = (try? caja.decode(String.self, forKey: .color)) ?? "auto"
        forma = (try? caja.decode(String.self, forKey: .forma)) ?? "redondeada"
        fondoWidget = try? caja.decode(String.self, forKey: .fondoWidget)
    }

    private enum Claves: String, CodingKey { case color, forma, fondoWidget }
}

struct Estado: Decodable {
    var ajustes = Ajustes()
    var proyectos: [Proyecto] = []
    var finalizadas: [TareaFinalizada] = []

    init() {}

    init(from decoder: Decoder) throws {
        let caja = try decoder.container(keyedBy: Claves.self)
        ajustes = (try? caja.decode(Ajustes.self, forKey: .ajustes)) ?? Ajustes()
        proyectos = ((try? caja.decode([Proyecto].self, forKey: .proyectos)) ?? []).filter { !$0.nombre.isEmpty }
        if let archivo = try? caja.nestedContainer(keyedBy: ClavesArchivo.self, forKey: .finalizadas) {
            finalizadas = (try? archivo.decode([TareaFinalizada].self, forKey: .tareas)) ?? []
        }
    }

    private enum Claves: String, CodingKey { case ajustes, proyectos, finalizadas }
    private enum ClavesArchivo: String, CodingKey { case tareas }

    static func leer(_ datos: Data?) -> Estado {
        guard let datos, let estado = try? JSONDecoder().decode(Estado.self, from: datos) else { return Estado() }
        return estado
    }
}

/// Una barra lista para dibujar: un proyecto con su avance, o un límite con su uso.
struct Fila: Identifiable {
    let id: String
    let nombre: String
    var detalle: String? = nil
    let fraccion: Double
    let porcentaje: Int
    var alerta = false
    var enlace: URL? = nil
}

extension Estado {
    /// Mismo cálculo que web/logica.js: hecho / (hecho + pendiente), y nunca 100 con pendientes.
    var filas: [Fila] {
        proyectos.map { proyecto in
            let hecho = proyecto.previo + finalizadas.filter { $0.proyectoId == proyecto.id }.reduce(0) { $0 + $1.peso }
            let pendiente = proyecto.tareas.reduce(0) { $0 + $1.peso }
            let total = hecho + pendiente
            let fraccion = total > 0 ? hecho / total : 0
            let redondeado = Int((fraccion * 100).rounded())
            return Fila(
                id: proyecto.id,
                nombre: proyecto.nombre,
                fraccion: fraccion,
                porcentaje: pendiente > 0 ? min(redondeado, 99) : redondeado,
                enlace: URL(string: "flecha://proyecto/\(proyecto.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")
            )
        }
    }
}

// MARK: uso de asistentes de código (GET /api/uso del servidor de la Mac)

struct Uso: Decodable {
    struct Limite: Decodable {
        let id: String
        let usado: Double
        let reinicia: Double?
    }

    struct Herramienta: Decodable {
        let id: String
        let nombre: String
        let limites: [Limite]
    }

    let generado: Double
    let herramientas: [Herramienta]

    static func leer(_ datos: Data?) -> Uso? {
        guard let datos else { return nil }
        return try? JSONDecoder().decode(Uso.self, from: datos)
    }

    func filas(ahora: Date = Date()) -> [Fila] {
        herramientas.flatMap { herramienta in
            herramienta.limites.map { limite in
                // Si la ventana ya se reinició desde la última lectura, el uso volvió a cero.
                let vencido = limite.reinicia.map { $0 <= ahora.timeIntervalSince1970 } ?? false
                let usado = vencido ? 0 : max(0, limite.usado)
                let ventana = ["5h": "5 h", "7d": texto("semana", "week")][limite.id] ?? limite.id
                return Fila(
                    id: "\(herramienta.id):\(limite.id)",
                    nombre: "\(herramienta.nombre) · \(ventana)",
                    fraccion: min(1, usado / 100),
                    porcentaje: Int(usado.rounded()),
                    alerta: usado >= 90,
                    enlace: URL(string: "flecha://uso")
                )
            }
        }
    }
}
