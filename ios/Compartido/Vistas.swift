// El dibujo que comparten la app y los widgets: la barra que solo muestra el avance
// (nunca la pista completa) con su porcentaje al final, el cuadro con los nombres y
// las barras por fuera, y el resumen de hoy.

import AppIntents
import SwiftUI
import WidgetKit

enum Tamano {
    case chico, mediano, grande

    var maximo: Int {
        switch self {
        case .chico: return 4
        case .mediano: return 5
        case .grande: return 13
        }
    }
}

struct Apariencia {
    var color = "auto"
    var forma = "redondeada"

    static let paleta = ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#63e6e2", "#64d2ff", "#0a84ff", "#5e5ce6", "#bf5af2", "#ff375f"]

    init() {}

    init(_ ajustes: Ajustes) {
        color = ajustes.color
        forma = ajustes.forma
    }

    func tinte(_ posicion: Int = 0) -> Color {
        if color == "multicolor" { return Color(hex: Self.paleta[posicion % Self.paleta.count]) ?? .primary }
        return Color(hex: color) ?? .primary // "auto": blanco en oscuro, negro en claro
    }

    /// Para botones y acentos de la app: el color elegido, o azul de sistema si es "auto".
    var acento: Color { Color(hex: color) ?? .primary }

    func radio(_ grosor: CGFloat) -> CGFloat {
        forma == "redondeada" ? grosor * 0.38 : grosor / 2
    }

    func grosor(_ base: CGFloat) -> CGFloat { forma == "fina" ? max(3, base * 0.4) : base }
}

extension Color {
    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7, let valor = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(.sRGB, red: Double((valor >> 16) & 255) / 255, green: Double((valor >> 8) & 255) / 255, blue: Double(valor & 255) / 255)
    }

    /// Negro en oscuro, gris de sistema en claro: el mismo fondo que en la computadora.
    static let fondoFlecha = Color(uiColor: UIColor { rasgos in
        rasgos.userInterfaceStyle == .dark ? .black : UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)
    })

    /// El "cuadro": gris translúcido en oscuro, blanco en claro.
    static let cuadroFlecha = Color(uiColor: UIColor { rasgos in
        rasgos.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.11) : .white
    })
}

/// "81%" con el signo más chico y apagado, como en la computadora.
struct Cifra: View {
    let valor: Int?
    var tamano: CGFloat = 12

    var body: some View {
        (Text(valor.map(String.init) ?? "–").font(.system(size: tamano, weight: .semibold, design: .rounded))
            + Text(valor == nil ? "" : "%").font(.system(size: tamano * 0.78, weight: .semibold, design: .rounded)).foregroundColor(.secondary))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}

/// Solo el avance, sin pista, con la cifra pegada al final de la barra.
struct BarraAvance: View {
    let fraccion: Double
    let porcentaje: Int?
    var color: Color = .primary
    var apariencia = Apariencia()
    var grosor: CGFloat = 10
    var cifra: CGFloat = 13

    var body: some View {
        let alto = apariencia.grosor(grosor)
        GeometryReader { lienzo in
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: apariencia.radio(alto), style: .continuous)
                    .fill(color)
                    .opacity(fraccion <= 0 ? 0.3 : 1)
                    .frame(width: max(alto, CGFloat(min(1, max(0, fraccion))) * max(alto, lienzo.size.width - cifra * 3.2)), height: alto)
                    .widgetAccentable()
                if cifra > 0 { Cifra(valor: porcentaje, tamano: cifra) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraccion)
        }
        .frame(height: max(alto, cifra * 1.25))
    }
}

// MARK: cuadro con nombres y barras por fuera (widgets Avance y Uso)

struct VistaBarras: View {
    let filas: [Fila]
    let apariencia: Apariencia
    let tamano: Tamano
    var vacio = texto("Abre Flecha y crea tu primer proyecto", "Open Flecha and create your first project")
    var actualizado: Date? = nil

    private var visibles: [Fila] {
        filas.count > tamano.maximo ? Array(filas.prefix(tamano.maximo - 1)) : filas
    }

    private var sobrantes: Int { filas.count - visibles.count }

    var body: some View {
        if filas.isEmpty {
            SinDatos(mensaje: vacio, color: apariencia.tinte())
        } else if tamano == .chico {
            compacto
        } else {
            conCuadro
        }
    }

    private var conCuadro: some View {
        GeometryReader { lienzo in
            let renglones = visibles.count + (sobrantes > 0 ? 1 : 0)
            let pie: CGFloat = actualizado == nil ? 0 : 16
            let alto = min(30, (lienzo.size.height - 12 - pie) / CGFloat(max(renglones, 1)))
            let anchoCuadro = (lienzo.size.width * 0.42).rounded()
            let anchoBarras = lienzo.size.width - anchoCuadro - 8
            let grosor = apariencia.grosor(9)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(visibles) { fila in
                            nombre(fila).frame(height: alto)
                        }
                        if sobrantes > 0 {
                            Text(texto("+\(sobrantes) más", "+\(sobrantes) more"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(height: alto)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .frame(width: anchoCuadro, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.cuadroFlecha))

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibles.enumerated()), id: \.element.id) { posicion, fila in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: apariencia.radio(grosor), style: .continuous)
                                    .fill(fila.alerta ? Color.red : apariencia.tinte(posicion))
                                    .opacity(fila.fraccion == 0 ? 0.3 : 1)
                                    .frame(width: max(grosor, CGFloat(fila.fraccion) * max(anchoBarras - 40, grosor)), height: grosor)
                                    .widgetAccentable()
                                Cifra(valor: fila.porcentaje)
                            }
                            .frame(height: alto)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(width: anchoBarras, alignment: .leading)
                }
                if let actualizado {
                    (Text(texto("Actualizado ", "Updated ")) + Text(actualizado, style: .time))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 12)
                        .frame(height: 12)
                }
            }
            .frame(width: lienzo.size.width, height: lienzo.size.height, alignment: .center)
        }
    }

    @ViewBuilder
    private func nombre(_ fila: Fila) -> some View {
        let etiqueta = Text(fila.nombre)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let enlace = fila.enlace {
            Link(destination: enlace) { etiqueta }.buttonStyle(.plain)
        } else {
            etiqueta
        }
    }

    private var compacto: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibles.enumerated()), id: \.element.id) { posicion, fila in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(fila.nombre).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 2)
                        Cifra(valor: fila.porcentaje, tamano: 11)
                    }
                    GeometryReader { lienzo in
                        let grosor = apariencia.grosor(6)
                        RoundedRectangle(cornerRadius: apariencia.radio(grosor), style: .continuous)
                            .fill(fila.alerta ? Color.red : apariencia.tinte(posicion))
                            .opacity(fila.fraccion == 0 ? 0.3 : 1)
                            .frame(width: max(grosor, CGFloat(fila.fraccion) * lienzo.size.width), height: grosor)
                            .widgetAccentable()
                    }
                    .frame(height: 6)
                }
                .frame(maxHeight: .infinity)
            }
            if sobrantes > 0 {
                Text(texto("+\(sobrantes) más", "+\(sobrantes) more"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

struct SinDatos: View {
    let mensaje: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Capsule().fill(color).frame(width: 5, height: 56).widgetAccentable()
            Text(mensaje)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: botones que sirven igual en la app y en los widgets

/// La pastilla "2/3" de una rutina. Cada toque suma una vez.
struct Contador: View {
    let hechas: Int
    let veces: Int
    var color: Color = .primary
    var tamano: CGFloat = 12

    var body: some View {
        let lleno = hechas >= veces
        Text("\(hechas)/\(veces)")
            .font(.system(size: tamano, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(lleno ? AnyShapeStyle(Color.fondoFlecha) : AnyShapeStyle(.secondary))
            .padding(.horizontal, tamano * 0.7)
            .frame(minWidth: tamano * 3.2, minHeight: tamano * 2)
            .background(Capsule().fill(lleno ? color : .clear))
            .overlay(Capsule().strokeBorder(.tertiary, lineWidth: lleno ? 0 : 1.5))
            .contentShape(Capsule())
    }
}

struct Circulo: View {
    var tamano: CGFloat = 22

    var body: some View {
        Circle().strokeBorder(.tertiary, lineWidth: 1.5).frame(width: tamano, height: tamano).contentShape(Circle())
    }
}

// MARK: widget Hoy

struct VistaHoy: View {
    let dia: ResumenDelDia
    let apariencia: Apariencia
    let tamano: Tamano
    var proximas: [Pendiente] = [] // solo se usan en el tamaño grande, si sobra espacio

    private enum Renglon: Identifiable {
        case rutina(RutinaDelDia)
        case tarea(Pendiente, atrasada: Bool)
        case proxima(Pendiente)

        var id: String {
            switch self {
            case let .rutina(r): return "r:\(r.id)"
            case let .tarea(t, _): return "t:\(t.id)"
            case let .proxima(t): return "p:\(t.id)"
            }
        }
    }

    private var renglones: [Renglon] {
        dia.rutinas.filter { !$0.rutina.cumplida(dia.fecha) }.map(Renglon.rutina)
            + dia.atrasadas.map { .tarea($0, atrasada: true) }
            + dia.vencen.map { .tarea($0, atrasada: false) }
            + dia.rutinas.filter { $0.rutina.cumplida(dia.fecha) }.map(Renglon.rutina)
            + (tamano == .grande ? proximas.map(Renglon.proxima) : [])
    }

    var body: some View {
        if dia.total == 0 {
            SinDatos(mensaje: texto("Nada para hoy. Ponle fecha a una tarea o crea una rutina.", "Nothing for today. Give a task a date or create a routine."), color: apariencia.tinte())
        } else if tamano == .chico {
            VStack(alignment: .leading, spacing: 6) {
                encabezado
                Spacer(minLength: 0)
                ForEach(renglones.prefix(2)) { renglon($0) }
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    encabezado
                    Spacer(minLength: 0)
                    Text(texto("\(dia.hechas) de \(dia.total)", "\(dia.hechas) of \(dia.total)"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 118, alignment: .leading)

                VStack(alignment: .leading, spacing: tamano == .grande ? 10 : 7) {
                    ForEach(renglones.prefix(tamano == .grande ? 9 : 4)) { renglon($0) }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.cuadroFlecha))
            }
        }
    }

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(texto("Hoy", "Today")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Cifra(valor: dia.porcentaje, tamano: tamano == .chico ? 30 : 34)
            BarraAvance(fraccion: dia.fraccion ?? 0, porcentaje: nil, color: apariencia.tinte(), apariencia: apariencia, grosor: 8, cifra: 0)
        }
    }

    @ViewBuilder
    private func renglon(_ renglon: Renglon) -> some View {
        switch renglon {
        case let .rutina(r):
            HStack(spacing: 8) {
                Button(intent: SumarRutina(proyecto: r.proyecto.id, rutina: r.rutina.id)) {
                    Contador(hechas: r.rutina.hechas(dia.fecha), veces: r.rutina.veces, color: apariencia.tinte(), tamano: 11)
                }
                .buttonStyle(.plain)
                Text(r.rutina.titulo).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    .foregroundStyle(r.rutina.cumplida(dia.fecha) ? .secondary : .primary)
            }
        case let .tarea(t, atrasada):
            HStack(spacing: 8) {
                Button(intent: TerminarTarea(proyecto: t.proyecto.id, tarea: t.tarea.id)) { Circulo(tamano: 20) }
                    .buttonStyle(.plain)
                Text(t.tarea.titulo).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    .foregroundStyle(atrasada ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
            }
        case let .proxima(t):
            HStack(spacing: 8) {
                Button(intent: TerminarTarea(proyecto: t.proyecto.id, tarea: t.tarea.id)) { Circulo(tamano: 20) }
                    .buttonStyle(.plain)
                Text(t.tarea.titulo).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Text(t.tarea.vence.map(Fecha.legible) ?? "").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
        }
    }
}
