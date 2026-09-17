// Los botones de los widgets: sumar una vez a una rutina y terminar una tarea,
// sin abrir la app. El cambio se ve al instante; si la Mac está conectada, se le
// entrega en la siguiente sincronización.

import AppIntents

struct SumarRutina: AppIntent {
    static var title: LocalizedStringResource = "Sumar a una rutina"
    static var isDiscoverable = false

    @Parameter(title: "Proyecto") var proyecto: String
    @Parameter(title: "Rutina") var rutina: String

    init() {}

    init(proyecto: String, rutina: String) {
        self.proyecto = proyecto
        self.rutina = rutina
    }

    func perform() async throws -> some IntentResult {
        let estado = Estado.leer(Almacen.estadoVigente)
        guard let actual = estado.proyectos.first(where: { $0.id == proyecto })?.rutinas.first(where: { $0.id == rutina }) else { return .result() }
        let hoy = Fecha.hoy
        // Al llegar al total, otro toque la regresa a cero (por si fue un error).
        let cuenta = actual.cumplida(hoy) ? 0 : actual.hechas(hoy) + 1
        Sincronia.aplicar(.fijarRutina(proyecto: proyecto, id: rutina, fecha: hoy, cuenta: cuenta))
        return .result()
    }
}

struct TerminarTarea: AppIntent {
    static var title: LocalizedStringResource = "Terminar una tarea"
    static var isDiscoverable = false

    @Parameter(title: "Proyecto") var proyecto: String
    @Parameter(title: "Tarea") var tarea: String

    init() {}

    init(proyecto: String, tarea: String) {
        self.proyecto = proyecto
        self.tarea = tarea
    }

    func perform() async throws -> some IntentResult {
        Sincronia.aplicar(.completarTarea(proyecto: proyecto, id: tarea, fin: Fecha.instante()))
        return .result()
    }
}
