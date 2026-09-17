// Los widgets de Flecha para la pantalla de inicio de iPhone y iPad.
//
//   Línea    la idea original: solo una línea; la tocas y se abre el cuadro con las
//            barras, y se vuelve a cerrar sola. Todo ocurre dentro del widget.
//   Avance   tus proyectos y cuánto llevan, siempre a la vista
//   Uso      los límites de Claude, Codex... (necesita conectar la app con tu Mac)
//
// iOS no deja que una app dibuje sobre la pantalla de inicio ni que un widget cambie
// de tamaño: un widget vive en su casilla. Lo más cercano a la línea flotante de la
// Mac es el widget Línea, que usa un botón interactivo (iOS 17) para abrirse.

import AppIntents
import SwiftUI
import WidgetKit

struct Entrada: TimelineEntry {
    let date: Date
    let filas: [Fila]
    let apariencia: Apariencia
    var actualizado: Date? = nil
    var abierto = true
}

// MARK: widget Línea

/// Hasta cuándo está abierta la línea. Se guarda en la carpeta compartida.
enum EstadoLinea {
    static let duracion: TimeInterval = 30
    private static let clave = "lineaAbiertaHasta"
    private static var ajustes: UserDefaults { Almacen.grupo.flatMap { UserDefaults(suiteName: $0) } ?? .standard }

    static var abiertaHasta: Date? {
        let hasta = Date(timeIntervalSince1970: ajustes.double(forKey: clave))
        return hasta > Date() ? hasta : nil
    }

    static func alternar() {
        ajustes.set(abiertaHasta == nil ? Date().addingTimeInterval(duracion).timeIntervalSince1970 : 0, forKey: clave)
    }
}

struct AlternarLinea: AppIntent {
    static var title: LocalizedStringResource = "Abrir o cerrar la línea"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        EstadoLinea.alternar()
        return .result()
    }
}

struct ProveedorLinea: TimelineProvider {
    private func entradas() -> [Entrada] {
        let estado = Estado.leer(Almacen.estadoVigente)
        let filas = estado.filas.map { Fila(id: $0.id, nombre: $0.nombre, fraccion: $0.fraccion, porcentaje: $0.porcentaje) }
        let apariencia = Apariencia(estado.ajustes)
        guard let hasta = EstadoLinea.abiertaHasta else {
            return [Entrada(date: Date(), filas: filas, apariencia: apariencia, abierto: false)]
        }
        // Abierta ahora, y cerrada sola cuando se cumpla el tiempo.
        return [
            Entrada(date: Date(), filas: filas, apariencia: apariencia, abierto: true),
            Entrada(date: hasta, filas: filas, apariencia: apariencia, abierto: false),
        ]
    }

    func placeholder(in context: Context) -> Entrada {
        Entrada(date: Date(), filas: [], apariencia: Apariencia(), abierto: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entrada) -> Void) {
        completion(entradas()[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entrada>) -> Void) {
        Task {
            // Al abrirse no se espera a la red: primero se responde al toque.
            if EstadoLinea.abiertaHasta == nil { await refrescarDesdeLaMac() }
            completion(Timeline(entries: entradas(), policy: .after(Date().addingTimeInterval(siguienteVuelta))))
        }
    }
}

struct VistaLinea: View {
    let entrada: Entrada

    @Environment(\.widgetFamily) private var familia

    private var tamano: Tamano {
        switch familia {
        case .systemSmall: return .chico
        case .systemMedium: return .mediano
        default: return .grande
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(intent: AlternarLinea()) {
                ZStack(alignment: .leading) {
                    Color.clear
                    if entrada.abierto {
                        VistaBarras(filas: entrada.filas, apariencia: entrada.apariencia, tamano: tamano)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.04, anchor: .leading).combined(with: .opacity),
                                removal: .scale(scale: 0.04, anchor: .leading).combined(with: .opacity)))
                    } else {
                        Capsule()
                            .fill(entrada.apariencia.tinte(0))
                            .frame(width: 5, height: tamano == .grande ? 96 : 64)
                            .widgetAccentable()
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if entrada.abierto {
                // Una salida a la app, porque aquí tocar el cuadro lo cierra.
                Link(destination: URL(string: "flecha://abrir")!) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.quaternary))
                }
                .offset(x: 6, y: -6)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: entrada.abierto)
        .containerBackground(for: .widget) { Color.fondoFlecha }
    }
}

struct WidgetLinea: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlechaLinea", provider: ProveedorLinea()) { entrada in
            VistaLinea(entrada: entrada)
        }
        .configurationDisplayName(texto("Línea", "Line"))
        .description(texto("Una línea. La tocas y se abre en tus proyectos.", "A line. Tap it and it opens into your projects."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: widgets siempre abiertos

/// Si la app está conectada con tu Mac, trae lo más nuevo antes de dibujar.
/// Si la Mac no contesta (estás fuera de casa), se queda con lo último guardado.
private func refrescarDesdeLaMac() async {
    guard let conexion = Almacen.conexion else { return }
    let cliente = Cliente(conexion: conexion)
    if let nuevo = try? await cliente.estado() { Almacen.escribir(nuevo.datos, en: .mac) }
    if let uso = try? await cliente.uso() { Almacen.escribir(uso, en: .uso) }
}

private let siguienteVuelta: TimeInterval = 20 * 60

struct ProveedorAvance: TimelineProvider {
    private static let muestra = [
        Fila(id: "1", nombre: texto("Cafetería", "Coffee shop"), fraccion: 0.81, porcentaje: 81),
        Fila(id: "2", nombre: texto("Disco", "Album"), fraccion: 0.44, porcentaje: 44),
        Fila(id: "3", nombre: texto("Maratón", "Marathon"), fraccion: 0.71, porcentaje: 71),
        Fila(id: "4", nombre: texto("Huerto", "Garden"), fraccion: 0.17, porcentaje: 17),
    ]

    private func entrada() -> Entrada {
        let estado = Estado.leer(Almacen.estadoVigente)
        return Entrada(date: Date(), filas: estado.filas, apariencia: Apariencia(estado.ajustes))
    }

    func placeholder(in context: Context) -> Entrada {
        Entrada(date: Date(), filas: Self.muestra, apariencia: Apariencia())
    }

    func getSnapshot(in context: Context, completion: @escaping (Entrada) -> Void) {
        let real = entrada()
        completion(context.isPreview && real.filas.isEmpty ? placeholder(in: context) : real)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entrada>) -> Void) {
        Task {
            await refrescarDesdeLaMac()
            completion(Timeline(entries: [entrada()], policy: .after(Date().addingTimeInterval(siguienteVuelta))))
        }
    }
}

struct ProveedorUso: TimelineProvider {
    private static let muestra = [
        Fila(id: "1", nombre: "Claude · 5 h", fraccion: 0.64, porcentaje: 64),
        Fila(id: "2", nombre: "Claude · \(texto("semana", "week"))", fraccion: 0.27, porcentaje: 27),
        Fila(id: "3", nombre: "Codex · 5 h", fraccion: 0.38, porcentaje: 38),
        Fila(id: "4", nombre: "Codex · \(texto("semana", "week"))", fraccion: 0.92, porcentaje: 92, alerta: true),
    ]

    private func entrada() -> Entrada {
        let estado = Estado.leer(Almacen.estadoVigente)
        let uso = Almacen.conexion == nil ? nil : Uso.leer(Almacen.leer(.uso))
        return Entrada(
            date: Date(),
            filas: uso?.filas() ?? [],
            apariencia: Apariencia(estado.ajustes),
            actualizado: uso.map { Date(timeIntervalSince1970: $0.generado) }
        )
    }

    func placeholder(in context: Context) -> Entrada {
        Entrada(date: Date(), filas: Self.muestra, apariencia: Apariencia())
    }

    func getSnapshot(in context: Context, completion: @escaping (Entrada) -> Void) {
        let real = entrada()
        completion(context.isPreview && real.filas.isEmpty ? placeholder(in: context) : real)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entrada>) -> Void) {
        Task {
            await refrescarDesdeLaMac()
            completion(Timeline(entries: [entrada()], policy: .after(Date().addingTimeInterval(siguienteVuelta))))
        }
    }
}

struct VistaWidget: View {
    let entrada: Entrada
    var vacio: String? = nil
    var destino = "flecha://abrir"

    @Environment(\.widgetFamily) private var familia

    private var tamano: Tamano {
        switch familia {
        case .systemSmall: return .chico
        case .systemMedium: return .mediano
        default: return .grande
        }
    }

    var body: some View {
        Group {
            if let vacio {
                VistaBarras(filas: entrada.filas, apariencia: entrada.apariencia, tamano: tamano, vacio: vacio, actualizado: tamano == .chico ? nil : entrada.actualizado)
            } else {
                VistaBarras(filas: entrada.filas, apariencia: entrada.apariencia, tamano: tamano)
            }
        }
        .containerBackground(for: .widget) { Color.fondoFlecha }
        .widgetURL(URL(string: destino))
    }
}

struct WidgetAvance: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlechaAvance", provider: ProveedorAvance()) { entrada in
            VistaWidget(entrada: entrada)
        }
        .configurationDisplayName(texto("Avance", "Progress"))
        .description(texto("Tus proyectos y cuánto llevan.", "Your projects and how far along they are."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct WidgetUso: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlechaUso", provider: ProveedorUso()) { entrada in
            VistaWidget(
                entrada: entrada,
                vacio: texto("Conecta Flecha con tu Mac para ver tus límites", "Connect Flecha to your Mac to see your limits"),
                destino: "flecha://uso"
            )
        }
        .configurationDisplayName(texto("Uso", "Usage"))
        .description(texto("Los límites de tus asistentes de código.", "Your coding assistants' limits."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct WidgetsDeFlecha: WidgetBundle {
    var body: some Widget {
        WidgetLinea()
        WidgetAvance()
        WidgetUso()
    }
}
