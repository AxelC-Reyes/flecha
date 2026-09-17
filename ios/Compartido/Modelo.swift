// Lectura tolerante del estado de Flecha (el mismo JSON de ESQUEMA.md) y los mismos
// cálculos que web/logica.js: avance, rachas y el resumen del día. Solo lectura:
// los cambios se hacen sobre el JSON crudo en Documento.swift para no perder campos.

import Foundation

// MARK: fechas como texto "AAAA-MM-DD", en hora local

enum Fecha {
    private static let formato: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func texto(_ dia: Date) -> String { formato.string(from: dia) }
    static func dia(_ texto: String) -> Date? { formato.date(from: texto) }
    static var hoy: String { texto(Date()) }

    /// 1 = lunes ... 7 = domingo.
    static func diaSemana(_ texto: String) -> Int {
        guard let dia = dia(texto) else { return 1 }
        return (Calendar(identifier: .gregorian).component(.weekday, from: dia) + 5) % 7 + 1
    }

    static func sumar(_ dias: Int, a texto: String) -> String {
        guard let dia = dia(texto), let otro = Calendar(identifier: .gregorian).date(byAdding: .day, value: dias, to: dia) else { return texto }
        return self.texto(otro)
    }

    /// El día local de un instante ISO 8601 (así guarda la web el campo `fin`).
    static func deInstante(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let lector = ISO8601DateFormatter()
        lector.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let instante = lector.date(from: iso) { return texto(instante) }
        lector.formatOptions = [.withInternetDateTime]
        return lector.date(from: iso).map(texto)
    }

    static func instante(_ momento: Date = Date()) -> String {
        let escritor = ISO8601DateFormatter()
        escritor.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return escritor.string(from: momento)
    }

    static func legible(_ texto: String) -> String {
        guard let dia = dia(texto) else { return texto }
        let f = DateFormatter()
        let otroAnio = !texto.hasPrefix(String(hoy.prefix(4)))
        f.setLocalizedDateFormatFromTemplate(otroAnio ? "d MMM yyyy" : "EEE d MMM")
        return f.string(from: dia)
    }
}

// MARK: modelo

private func pesoValido(_ leido: Double?) -> Double { (leido ?? 1) > 0 ? (leido ?? 1) : 1 }

struct Tarea: Decodable, Identifiable, Hashable {
    let id: String
    let titulo: String
    let peso: Double
    let vence: String?

    init(from decoder: Decoder) throws {
        // Escrita a mano puede venir como texto simple.
        if let soloTexto = try? decoder.singleValueContainer().decode(String.self) {
            (id, titulo, peso, vence) = (soloTexto, soloTexto, 1, nil)
            return
        }
        let caja = try decoder.container(keyedBy: Claves.self)
        titulo = (try? caja.decode(String.self, forKey: .titulo)) ?? ""
        id = (try? caja.decode(String.self, forKey: .id)) ?? titulo
        peso = pesoValido(try? caja.decode(Double.self, forKey: .peso))
        vence = try? caja.decode(String.self, forKey: .vence)
    }

    private enum Claves: String, CodingKey { case id, titulo, peso, vence }
}

struct Rutina: Decodable, Identifiable, Hashable {
    let id: String
    let titulo: String
    let veces: Int
    let dias: [Int]? // nil = todos los días
    let meta: Int?
    let peso: Double
    let registro: [String: Int]

    init(from decoder: Decoder) throws {
        let caja = try decoder.container(keyedBy: Claves.self)
        titulo = (try? caja.decode(String.self, forKey: .titulo)) ?? ""
        id = (try? caja.decode(String.self, forKey: .id)) ?? titulo
        veces = max(1, (try? caja.decode(Int.self, forKey: .veces)) ?? 1)
        let leidos = (try? caja.decode([Int].self, forKey: .dias)) ?? []
        dias = leidos.isEmpty || leidos.count >= 7 ? nil : leidos
        meta = (try? caja.decode(Int.self, forKey: .meta)).flatMap { $0 >= 1 ? $0 : nil }
        peso = pesoValido(try? caja.decode(Double.self, forKey: .peso))
        registro = (try? caja.decode([String: Int].self, forKey: .registro)) ?? [:]
    }

    private enum Claves: String, CodingKey { case id, titulo, veces, dias, meta, peso, registro }

    func toca(_ fecha: String) -> Bool { dias?.contains(Fecha.diaSemana(fecha)) ?? true }
    func hechas(_ fecha: String) -> Int { min(registro[fecha] ?? 0, veces) }
    func cumplida(_ fecha: String) -> Bool { hechas(fecha) >= veces }
    var diasCumplidos: Int { registro.keys.filter(cumplida).count }

    /// De 0 a 1 si tiene meta; nil si es una rutina sin fin.
    var avance: Double? { meta.map { min(1, Double(diasCumplidos) / Double($0)) } }

    /// Días seguidos cumplidos. El descanso no cuenta ni rompe; hoy no rompe si aún no lo haces.
    func racha(hoy: String = Fecha.hoy) -> Int {
        var seguidos = 0
        var fecha = hoy
        for _ in 0..<3660 {
            if toca(fecha) {
                if cumplida(fecha) { seguidos += 1 } else if fecha != hoy { break }
            }
            fecha = Fecha.sumar(-1, a: fecha)
        }
        return seguidos
    }
}

struct Proyecto: Decodable, Identifiable, Hashable {
    let id: String
    let nombre: String
    let previo: Double
    let tareas: [Tarea]
    let rutinas: [Rutina]

    init(from decoder: Decoder) throws {
        let caja = try decoder.container(keyedBy: Claves.self)
        nombre = (try? caja.decode(String.self, forKey: .nombre)) ?? ""
        id = (try? caja.decode(String.self, forKey: .id)) ?? nombre
        previo = max(0, (try? caja.decode(Double.self, forKey: .previo)) ?? 0)
        tareas = ((try? caja.decode([Tarea].self, forKey: .tareas)) ?? []).filter { !$0.titulo.isEmpty }
        rutinas = ((try? caja.decode([Rutina].self, forKey: .rutinas)) ?? []).filter { !$0.titulo.isEmpty }
    }

    private enum Claves: String, CodingKey { case id, nombre, previo, tareas, rutinas }
}

struct TareaFinalizada: Decodable, Identifiable, Hashable {
    let id: String
    let titulo: String
    let proyectoId: String
    let peso: Double
    let vence: String?
    let fin: String?

    init(from decoder: Decoder) throws {
        let caja = try decoder.container(keyedBy: Claves.self)
        titulo = (try? caja.decode(String.self, forKey: .titulo)) ?? ""
        id = (try? caja.decode(String.self, forKey: .id)) ?? UUID().uuidString
        proyectoId = (try? caja.decode(String.self, forKey: .proyectoId)) ?? ""
        peso = pesoValido(try? caja.decode(Double.self, forKey: .peso))
        vence = try? caja.decode(String.self, forKey: .vence)
        fin = try? caja.decode(String.self, forKey: .fin)
    }

    private enum Claves: String, CodingKey { case id, titulo, proyectoId, peso, vence, fin }
}

struct Ajustes: Decodable {
    var color = "auto" // "auto" | "multicolor" | "#rrggbb"
    var forma = "redondeada" // "redondeada" | "pildora" | "fina"

    init() {}

    init(from decoder: Decoder) throws {
        let caja = try decoder.container(keyedBy: Claves.self)
        color = (try? caja.decode(String.self, forKey: .color)) ?? "auto"
        forma = (try? caja.decode(String.self, forKey: .forma)) ?? "redondeada"
    }

    private enum Claves: String, CodingKey { case color, forma }
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

// MARK: avance

/// Una barra lista para dibujar: un proyecto con su avance, o un límite con su uso.
struct Fila: Identifiable {
    let id: String
    let nombre: String
    let fraccion: Double
    let porcentaje: Int
    var alerta = false
    var enlace: URL? = nil
}

extension Estado {
    /// Mismo cálculo que web/logica.js. Una rutina con meta pesa como una tarea que se va llenando.
    func avance(_ proyecto: Proyecto) -> (fraccion: Double, porcentaje: Int) {
        var hecho = proyecto.previo + finalizadas.filter { $0.proyectoId == proyecto.id }.reduce(0) { $0 + $1.peso }
        var pendiente = proyecto.tareas.reduce(0) { $0 + $1.peso }
        for rutina in proyecto.rutinas {
            guard let f = rutina.avance else { continue }
            hecho += rutina.peso * f
            pendiente += rutina.peso * (1 - f)
        }
        let total = hecho + pendiente
        let fraccion = total > 0 ? hecho / total : 0
        let redondeado = Int((fraccion * 100).rounded())
        // Nunca 100 mientras quede algo pendiente.
        return (fraccion, pendiente > 1e-9 ? min(redondeado, 99) : redondeado)
    }

    var filas: [Fila] {
        proyectos.map { proyecto in
            let (fraccion, porcentaje) = avance(proyecto)
            let ruta = proyecto.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            return Fila(id: proyecto.id, nombre: proyecto.nombre, fraccion: fraccion, porcentaje: porcentaje, enlace: URL(string: "flecha://proyecto/\(ruta)"))
        }
    }
}

// MARK: el día

struct Pendiente: Identifiable, Hashable {
    let proyecto: Proyecto
    let tarea: Tarea
    var id: String { tarea.id }
}

struct RutinaDelDia: Identifiable, Hashable {
    let proyecto: Proyecto
    let rutina: Rutina
    var id: String { rutina.id }
}

struct ResumenDelDia {
    let fecha: String
    var rutinas: [RutinaDelDia] = []
    var vencen: [Pendiente] = [] // vencen ese día
    var atrasadas: [Pendiente] = [] // vencieron antes (solo para hoy)
    var terminadas: [TareaFinalizada] = [] // con fecha límite, terminadas ese día
    var hechas = 0
    var total = 0

    /// nil cuando no hay nada que hacer ese día.
    var fraccion: Double? { total > 0 ? Double(hechas) / Double(total) : nil }
    var porcentaje: Int? { fraccion.map { Int(($0 * 100).rounded()) } }
}

extension Estado {
    /// Lo que toca un día: rutinas de ese día de la semana y tareas que vencen (o ya vencieron).
    /// Cada vez de una rutina y cada tarea cuentan como una unidad del porcentaje del día.
    func resumen(de fecha: String = Fecha.hoy) -> ResumenDelDia {
        var dia = ResumenDelDia(fecha: fecha)
        let esHoy = fecha == Fecha.hoy
        for proyecto in proyectos {
            for rutina in proyecto.rutinas where rutina.toca(fecha) {
                dia.rutinas.append(RutinaDelDia(proyecto: proyecto, rutina: rutina))
                dia.total += rutina.veces
                dia.hechas += rutina.hechas(fecha)
            }
            for tarea in proyecto.tareas {
                guard let vence = tarea.vence else { continue }
                if vence == fecha {
                    dia.vencen.append(Pendiente(proyecto: proyecto, tarea: tarea))
                } else if esHoy, vence < fecha {
                    dia.atrasadas.append(Pendiente(proyecto: proyecto, tarea: tarea))
                }
            }
        }
        dia.atrasadas.sort { ($0.tarea.vence ?? "") < ($1.tarea.vence ?? "") }
        dia.terminadas = finalizadas.filter { hecha in
            guard let vence = hecha.vence, Fecha.deInstante(hecha.fin) == fecha else { return false }
            return esHoy ? vence <= fecha : vence == fecha
        }
        dia.total += dia.vencen.count + dia.atrasadas.count + dia.terminadas.count
        dia.hechas += dia.terminadas.count
        return dia
    }

    /// Tareas con fecha en los próximos días (sin contar hoy), ordenadas.
    func proximas(dias: Int = 7) -> [Pendiente] {
        let hoy = Fecha.hoy
        let limite = Fecha.sumar(dias, a: hoy)
        return proyectos
            .flatMap { proyecto in proyecto.tareas.map { Pendiente(proyecto: proyecto, tarea: $0) } }
            .filter { ($0.tarea.vence ?? "") > hoy && ($0.tarea.vence ?? "") <= limite }
            .sorted { ($0.tarea.vence ?? "") < ($1.tarea.vence ?? "") }
    }

    func nombreDelProyecto(_ id: String) -> String { proyectos.first { $0.id == id }?.nombre ?? "" }
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
                    enlace: URL(string: "flecha://hoy")
                )
            }
        }
    }
}
