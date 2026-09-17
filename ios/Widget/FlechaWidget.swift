// Los widgets de Flecha para la pantalla de inicio de iPhone y iPad.
//
//   Avance   tus proyectos y cuánto llevan
//   Uso      los límites de Claude, Codex... (necesita conectar la app con tu Mac)
//
// Los widgets del sistema son estáticos: no pueden hacer la animación de la línea
// que se abre. Muestran el cuadro ya abierto; al tocarlos se abre la app.

import SwiftUI
import WidgetKit

struct Entrada: TimelineEntry {
    let date: Date
    let filas: [Fila]
    let apariencia: Apariencia
    var actualizado: Date? = nil
}

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
        WidgetAvance()
        WidgetUso()
    }
}
