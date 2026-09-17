// Las hojas para crear o editar: una tarea (con fecha límite opcional), una rutina
// (veces por día, días de descanso, meta opcional) y los ajustes (conectar con la Mac).

import SwiftUI

struct FormularioTarea: View {
    @EnvironmentObject private var tienda: Tienda
    @Environment(\.dismiss) private var cerrar
    let proyectoId: String
    let tarea: Tarea?

    @State private var titulo = ""
    @State private var conFecha = false
    @State private var fecha = Date()
    @FocusState private var enfocado: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(texto("Qué hay que hacer", "What needs doing"), text: $titulo, axis: .vertical).focused($enfocado)
                }
                Section {
                    Toggle(texto("Fecha límite", "Due date"), isOn: $conFecha.animation())
                    if conFecha {
                        DatePicker(texto("Vence", "Due"), selection: $fecha, displayedComponents: .date).datePickerStyle(.graphical)
                    }
                } footer: {
                    Text(texto("Sin fecha, la tarea vive en su proyecto y no aparece en Hoy ni en el calendario.",
                               "Without a date the task lives in its project and doesn't show up in Today or the calendar."))
                }
                if let tarea {
                    Section {
                        Button(texto("Eliminar tarea", "Delete task"), role: .destructive) {
                            tienda.hacer(.eliminarTarea(proyecto: proyectoId, id: tarea.id))
                            cerrar()
                        }
                    }
                }
            }
            .navigationTitle(tarea == nil ? texto("Nueva tarea", "New task") : texto("Tarea", "Task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(texto("Cancelar", "Cancel")) { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(texto("Guardar", "Save")) { guardar() }
                        .disabled(titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                titulo = tarea?.titulo ?? ""
                if let vence = tarea?.vence, let dia = Fecha.dia(vence) {
                    conFecha = true
                    fecha = dia
                }
                enfocado = tarea == nil
            }
        }
        .presentationDetents([.large])
    }

    private func guardar() {
        let limpio = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        let vence = conFecha ? Fecha.texto(fecha) : nil
        if let tarea {
            tienda.hacer(.editarTarea(proyecto: proyectoId, id: tarea.id, titulo: limpio, vence: vence))
        } else {
            tienda.hacer(.crearTarea(proyecto: proyectoId, id: nuevoId(), titulo: limpio, vence: vence))
        }
        cerrar()
    }
}

struct FormularioRutina: View {
    @EnvironmentObject private var tienda: Tienda
    @Environment(\.dismiss) private var cerrar
    let proyectoId: String

    @State private var titulo = ""
    @State private var veces = 1
    @State private var dias: Set<Int> = Set(1...7)
    @State private var conMeta = false
    @State private var meta = 30
    @FocusState private var enfocado: Bool

    /// Letras de lunes a domingo (1...7), en el idioma del teléfono.
    private var letras: [String] {
        let simbolos = Calendar.current.veryShortStandaloneWeekdaySymbols // empieza en domingo
        return (1...7).map { simbolos[$0 % 7] }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(texto("Ejercicios de la maestría, gimnasio…", "Study exercises, gym…"), text: $titulo).focused($enfocado)
                    Stepper(texto("\(veces) \(veces == 1 ? "vez" : "veces") al día", "\(veces) \(veces == 1 ? "time" : "times") a day"), value: $veces, in: 1...20)
                }
                Section {
                    HStack(spacing: 0) {
                        ForEach(1...7, id: \.self) { dia in
                            let activo = dias.contains(dia)
                            Button {
                                if activo, dias.count > 1 { dias.remove(dia) } else { dias.insert(dia) }
                            } label: {
                                Text(letras[dia - 1])
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(activo ? AnyShapeStyle(Color.fondoFlecha) : AnyShapeStyle(.secondary))
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(activo ? AnyShapeStyle(tienda.apariencia.tinte()) : AnyShapeStyle(.quaternary)))
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                    Toggle(texto("Descansar el fin de semana", "Rest on weekends"), isOn: Binding(
                        get: { dias == Set(1...5) },
                        set: { dias = $0 ? Set(1...5) : Set(1...7) }
                    ))
                } header: {
                    Text(texto("Días que toca", "Days it applies"))
                } footer: {
                    Text(texto("Los días de descanso no cuentan ni rompen tu racha.", "Rest days neither count nor break your streak."))
                }
                Section {
                    Toggle(texto("Tiene meta", "Has a goal"), isOn: $conMeta.animation())
                    if conMeta {
                        Stepper(texto("\(meta) días cumplidos", "\(meta) completed days"), value: $meta, in: 1...3650, step: meta >= 60 ? 10 : 5)
                    }
                } footer: {
                    Text(conMeta
                        ? texto("Cada día cumplido suma al avance del proyecto, hasta llegar a la meta.", "Each completed day adds to the project's progress until the goal is reached.")
                        : texto("Sin meta, la rutina solo lleva tu avance del día y tu racha.", "Without a goal the routine only tracks your day and your streak."))
                }
            }
            .navigationTitle(texto("Nueva rutina", "New routine"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(texto("Cancelar", "Cancel")) { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(texto("Crear", "Create")) {
                        tienda.hacer(.crearRutina(
                            proyecto: proyectoId, id: nuevoId(),
                            titulo: titulo.trimmingCharacters(in: .whitespacesAndNewlines),
                            veces: veces, dias: dias.count == 7 ? nil : dias.sorted(), meta: conMeta ? meta : nil))
                        cerrar()
                    }
                    .disabled(titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { enfocado = true }
        }
    }
}

struct AjustesView: View {
    @EnvironmentObject private var tienda: Tienda
    @Environment(\.dismiss) private var cerrar
    @State private var enlace = ""
    @State private var conectando = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let conexion = tienda.conexion {
                    Section {
                        LabeledContent(texto("Conectada a", "Connected to"), value: conexion.legible)
                        LabeledContent(texto("Estado", "Status"), value: tienda.enLinea ? texto("Al día", "Up to date") : texto("Sin conexión ahora", "Offline right now"))
                        if tienda.porEntregar > 0 {
                            LabeledContent(texto("Cambios por entregar", "Changes to deliver"), value: String(tienda.porEntregar))
                        }
                        Button(texto("Desconectar", "Disconnect"), role: .destructive) { tienda.desconectar() }
                    } header: {
                        Text(texto("Tu Mac", "Your Mac"))
                    } footer: {
                        Text(texto("Ves y editas los mismos proyectos que en tu computadora. Fuera de casa puedes seguir palomeando: los cambios se entregan cuando vuelvas a su red.",
                                   "You see and edit the same projects as on your computer. Away from home you can keep checking things off: changes are delivered when you're back on its network."))
                    }
                } else {
                    Section {
                        TextField("http://192.168.1.5:4747/?clave=…", text: $enlace)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button(conectando ? texto("Buscando tu Mac…", "Looking for your Mac…") : texto("Conectar", "Connect")) {
                            conectando = true
                            Task {
                                error = await tienda.conectar(enlace)
                                conectando = false
                                if error == nil { enlace = "" }
                            }
                        }
                        .disabled(conectando || enlace.isEmpty)
                        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    } header: {
                        Text(texto("Conectar con tu Mac", "Connect to your Mac"))
                    } footer: {
                        Text(texto("En tu Mac: ícono de Flecha en la barra de menús → Compartir con mi iPhone o iPad (o corre ./flecha --red). Pega aquí el enlace que te da. Deben estar en la misma red wifi. Sin conectar, tus datos viven solo en este dispositivo.",
                                   "On your Mac: Flecha's menu bar icon → Share with my iPhone or iPad (or run ./flecha --red). Paste the link here. Both must be on the same Wi-Fi. Without connecting, your data lives only on this device."))
                    }
                }
                Section {
                    Text(texto("El color y la forma de las barras se eligen en la versión de computadora (Personalizar) y aquí se respetan.",
                               "Bar color and shape are chosen in the computer version (Customize) and respected here."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(texto("Ajustes", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(texto("Listo", "Done")) { cerrar() } } }
            .onAppear {
                if let pegado = UIPasteboard.general.string, pegado.contains("clave="), Conexion(enlace: pegado) != nil { enlace = pegado }
            }
        }
    }
}
