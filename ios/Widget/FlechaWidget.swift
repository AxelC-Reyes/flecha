// Los widgets de Flecha para iPhone y iPad.
//
//   Hoy      el porcentaje del día, con botones para sumar a tus rutinas y terminar tareas
//   Avance   tus proyectos y cuánto llevan
//   Uso      los límites de Claude, Codex... (necesita conectar la app con tu Mac)

import SwiftUI
import WidgetKit

struct Entrada: TimelineEntry {
    let date: Date
    let estado: Estado
    var uso: Uso? = nil
}

struct Proveedor: TimelineProvider {
    private func entrada() -> Entrada {
        Entrada(date: Date(), estado: Estado.leer(Almacen.estadoVigente), uso: Almacen.conexion == nil ? nil : Uso.leer(Almacen.leer(.uso)))
    }

    func placeholder(in context: Context) -> Entrada { entrada() }

    func getSnapshot(in context: Context, completion: @escaping (Entrada) -> Void) { completion(entrada()) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entrada>) -> Void) {
        // Primero se dibuja lo que hay; la sincronización va por detrás y, si trae algo
        // distinto, ella misma pide que el widget se vuelva a dibujar.
        let ahora = Date()
        let medianoche = Calendar.current.startOfDay(for: ahora.addingTimeInterval(86400))
        completion(Timeline(entries: [entrada()], policy: .after(min(ahora.addingTimeInterval(20 * 60), medianoche))))
        Task {
            await Sincronia.sincronizar()
            await Sincronia.traerUso()
        }
    }
}

private struct Marco<Contenido: View>: View {
    let destino: String
    @ViewBuilder var contenido: (Tamano) -> Contenido

    @Environment(\.widgetFamily) private var familia

    var body: some View {
        let tamano: Tamano = familia == .systemSmall ? .chico : familia == .systemMedium ? .mediano : .grande
        contenido(tamano)
            .containerBackground(for: .widget) { Color.fondoFlecha }
            .widgetURL(URL(string: destino))
    }
}

struct WidgetHoy: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlechaHoy", provider: Proveedor()) { entrada in
            Marco(destino: "flecha://hoy") { tamano in
                VistaHoy(dia: entrada.estado.resumen(), apariencia: Apariencia(entrada.estado.ajustes), tamano: tamano, proximas: entrada.estado.proximas(dias: 14))
            }
        }
        .configurationDisplayName(texto("Hoy", "Today"))
        .description(texto("El avance de tu día: rutinas y entregas.", "Your day's progress: routines and deadlines."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetAvance: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlechaAvance", provider: Proveedor()) { entrada in
            Marco(destino: "flecha://proyectos") { tamano in
                VistaBarras(filas: entrada.estado.filas, apariencia: Apariencia(entrada.estado.ajustes), tamano: tamano)
            }
        }
        .configurationDisplayName(texto("Avance", "Progress"))
        .description(texto("Tus proyectos y cuánto llevan.", "Your projects and how far along they are."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetUso: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlechaUso", provider: Proveedor()) { entrada in
            Marco(destino: "flecha://hoy") { tamano in
                VistaBarras(
                    filas: entrada.uso?.filas() ?? [],
                    apariencia: Apariencia(entrada.estado.ajustes),
                    tamano: tamano,
                    vacio: texto("Conecta Flecha con tu Mac para ver tus límites", "Connect Flecha to your Mac to see your limits"),
                    actualizado: tamano == .chico ? nil : entrada.uso.map { Date(timeIntervalSince1970: $0.generado) }
                )
            }
        }
        .configurationDisplayName(texto("Uso", "Usage"))
        .description(texto("Los límites de tus asistentes de código.", "Your coding assistants' limits."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct WidgetsDeFlecha: WidgetBundle {
    var body: some Widget {
        WidgetHoy()
        WidgetAvance()
        WidgetUso()
    }
}
