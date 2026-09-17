// El dibujo de los widgets: el cuadro con los nombres y, por fuera, las barras con
// su porcentaje al final. Igual que en la app: nunca se ve la barra completa, solo
// el avance. Vive en Compartido para que la app pueda generar vistas previas.

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
    var fondoWidget: String?

    static let paleta = ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#63e6e2", "#64d2ff", "#0a84ff", "#5e5ce6", "#bf5af2", "#ff375f"]

    init() {}

    init(_ ajustes: Ajustes) {
        color = ajustes.color
        forma = ajustes.forma
        fondoWidget = ajustes.fondoWidget
    }

    /// El fondo del widget: el color que elegiste, o el negro/gris de siempre.
    var fondo: Color { fondoWidget.flatMap { Color(hex: $0) } ?? .fondoFlecha }

    /// Con fondo propio, las letras se deciden por lo claro u oscuro de ese color.
    var esquema: ColorScheme? {
        guard let hex = fondoWidget, hex.count == 7, let valor = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        let luz = 0.2126 * Double((valor >> 16) & 255) + 0.7152 * Double((valor >> 8) & 255) + 0.0722 * Double(valor & 255)
        return luz > 140 ? .light : .dark
    }

    func tinte(_ posicion: Int) -> Color {
        if color == "multicolor" { return Color(hex: Self.paleta[posicion % Self.paleta.count]) ?? .primary }
        return Color(hex: color) ?? .primary // "auto": blanco en oscuro, negro en claro
    }

    func grosor(_ tamano: Tamano) -> CGFloat {
        if forma == "fina" { return 3.5 }
        return tamano == .chico ? 6 : 9
    }

    func radio(_ grosor: CGFloat) -> CGFloat {
        switch forma {
        case "pildora": return grosor / 2
        case "fina": return grosor / 2
        default: return grosor * 0.38
        }
    }
}

extension Color {
    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7, let valor = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((valor >> 16) & 255) / 255,
            green: Double((valor >> 8) & 255) / 255,
            blue: Double(valor & 255) / 255
        )
    }

    /// Negro en oscuro, gris de sistema en claro: el mismo fondo que la app.
    static let fondoFlecha = Color(uiColor: UIColor { rasgos in
        rasgos.userInterfaceStyle == .dark ? .black : UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)
    })
}

struct VistaBarras: View {
    let filas: [Fila]
    let apariencia: Apariencia
    let tamano: Tamano
    var vacio = texto("Abre Flecha y crea tu primer proyecto", "Open Flecha and create your first project")
    var actualizado: Date? = nil

    @Environment(\.colorScheme) private var esquema

    private var visibles: [Fila] {
        filas.count > tamano.maximo ? Array(filas.prefix(tamano.maximo - 1)) : filas
    }

    private var sobrantes: Int { filas.count - visibles.count }

    var body: some View {
        if filas.isEmpty {
            sinDatos
        } else if tamano == .chico {
            compacto
        } else {
            conCuadro
        }
    }

    // MARK: mediano y grande: nombres dentro del cuadro, barras por fuera

    private var conCuadro: some View {
        GeometryReader { lienzo in
            let renglones = visibles.count + (sobrantes > 0 ? 1 : 0)
            let pie: CGFloat = actualizado == nil ? 0 : 16
            let alto = min(30, (lienzo.size.height - 12 - pie) / CGFloat(max(renglones, 1)))
            let anchoCuadro = (lienzo.size.width * 0.42).rounded()
            let anchoBarras = lienzo.size.width - anchoCuadro - 8

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
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(esquema == .dark ? Color.white.opacity(0.11) : Color.white)
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibles.enumerated()), id: \.element.id) { posicion, fila in
                            barra(fila, posicion: posicion, largo: anchoBarras - 40).frame(height: alto)
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

    private func barra(_ fila: Fila, posicion: Int, largo: CGFloat) -> some View {
        let grosor = apariencia.grosor(tamano)
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: apariencia.radio(grosor), style: .continuous)
                .fill(fila.alerta ? Color.red : apariencia.tinte(posicion))
                .opacity(fila.fraccion == 0 ? 0.3 : 1)
                .frame(width: max(grosor, CGFloat(fila.fraccion) * max(largo, grosor)), height: grosor)
                .widgetAccentable()
            cifra(fila.porcentaje, tamano: 12)
        }
    }

    private func cifra(_ porcentaje: Int, tamano: CGFloat) -> some View {
        (Text("\(porcentaje)").font(.system(size: tamano, weight: .semibold, design: .rounded))
            + Text("%").font(.system(size: tamano * 0.8, weight: .semibold, design: .rounded)).foregroundColor(.secondary))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: chico: nombre y cifra arriba, barra abajo

    private var compacto: some View {
        let grosor = apariencia.grosor(.chico)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibles.enumerated()), id: \.element.id) { posicion, fila in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(fila.nombre).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 2)
                        cifra(fila.porcentaje, tamano: 11)
                    }
                    GeometryReader { lienzo in
                        RoundedRectangle(cornerRadius: apariencia.radio(grosor), style: .continuous)
                            .fill(fila.alerta ? Color.red : apariencia.tinte(posicion))
                            .opacity(fila.fraccion == 0 ? 0.3 : 1)
                            .frame(width: max(grosor, CGFloat(fila.fraccion) * lienzo.size.width), height: grosor)
                            .widgetAccentable()
                    }
                    .frame(height: grosor)
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

    // MARK: sin datos: solo la línea

    private var sinDatos: some View {
        HStack(spacing: 12) {
            Capsule().fill(apariencia.tinte(0)).frame(width: 5, height: 56).widgetAccentable()
            Text(vacio)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
