// Las piezas con que se arman las pantallas: secciones, renglones de tarea y de rutina.

import SwiftUI

struct Seccion<Contenido: View>: View {
    let titulo: String
    @ViewBuilder var contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            VStack(spacing: 0) { contenido }
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.cuadroFlecha))
        }
    }
}

/// Una tarea pendiente: círculo para terminarla, título y, debajo, proyecto y fecha.
struct RenglonTarea: View {
    @EnvironmentObject private var tienda: Tienda
    let pendiente: Pendiente
    var conProyecto = true

    private var atrasada: Bool { (pendiente.tarea.vence ?? "9999") < Fecha.hoy }

    private var nota: String {
        [conProyecto ? pendiente.proyecto.nombre : nil, pendiente.tarea.vence.map(Fecha.legible)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { tienda.terminar(pendiente) } label: { Circulo(tamano: 24) }
                .buttonStyle(.plain)
                .accessibilityLabel(texto("Terminar \(pendiente.tarea.titulo)", "Complete \(pendiente.tarea.titulo)"))
            Button { tienda.hoja = .tarea(proyecto: pendiente.proyecto.id, tarea: pendiente.tarea) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pendiente.tarea.titulo).font(.body).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    if !nota.isEmpty {
                        Text(nota).font(.footnote).foregroundStyle(atrasada ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contextMenu {
            Button(role: .destructive) {
                tienda.hacer(.eliminarTarea(proyecto: pendiente.proyecto.id, id: pendiente.tarea.id))
            } label: { Label(texto("Eliminar", "Delete"), systemImage: "trash") }
        }
    }
}

/// Una rutina en una fecha: la pastilla "2/3" suma una vez por toque.
struct RenglonRutina: View {
    @EnvironmentObject private var tienda: Tienda
    let proyecto: Proyecto
    let rutina: Rutina
    var fecha = Fecha.hoy
    var conProyecto = true

    private var nota: String {
        let racha = rutina.racha()
        return [
            conProyecto ? proyecto.nombre : nil,
            rutina.toca(fecha) ? nil : texto("descanso", "rest day"),
            racha > 0 ? texto("racha \(racha)", "streak \(racha)") : nil,
            rutina.meta.map { texto("\(rutina.diasCumplidos)/\($0) días", "\(rutina.diasCumplidos)/\($0) days") },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { tienda.sumar(rutina, de: proyecto, fecha: fecha) } label: {
                Contador(hechas: rutina.hechas(fecha), veces: rutina.veces, color: tienda.apariencia.tinte(), tamano: 13)
            }
            .buttonStyle(.plain)
            .disabled(fecha > Fecha.hoy)
            VStack(alignment: .leading, spacing: 2) {
                Text(rutina.titulo).font(.body)
                if !nota.isEmpty { Text(nota).font(.footnote).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contextMenu {
            if rutina.hechas(fecha) > 0 {
                Button {
                    tienda.hacer(.fijarRutina(proyecto: proyecto.id, id: rutina.id, fecha: fecha, cuenta: rutina.hechas(fecha) - 1))
                } label: { Label(texto("Quitar una", "Remove one"), systemImage: "minus.circle") }
            }
            Button(role: .destructive) {
                tienda.hacer(.eliminarRutina(proyecto: proyecto.id, id: rutina.id))
            } label: { Label(texto("Eliminar rutina", "Delete routine"), systemImage: "trash") }
        }
    }
}

/// Un proyecto con su barra, como en la computadora: solo el avance y la cifra al final.
struct RenglonProyecto: View {
    @EnvironmentObject private var tienda: Tienda
    let proyecto: Proyecto
    let posicion: Int

    var body: some View {
        let avance = tienda.estado.avance(proyecto)
        VStack(alignment: .leading, spacing: 5) {
            Text(proyecto.nombre).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
            BarraAvance(fraccion: avance.fraccion, porcentaje: avance.porcentaje, color: tienda.apariencia.tinte(posicion), apariencia: tienda.apariencia)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct Divisor: View {
    var body: some View { Divider().padding(.leading, 52).opacity(0.5) }
}
