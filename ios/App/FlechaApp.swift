// Flecha para iPhone y iPad: tus proyectos como lista de deberes. Hoy primero, con el
// porcentaje del día; después los proyectos con sus barras y un calendario de entregas.
// Los datos son los mismos de la computadora (si conectas tu Mac) o viven en el teléfono.

import SwiftUI

@main
struct FlechaApp: App {
    @StateObject private var tienda = Tienda()
    @Environment(\.scenePhase) private var fase

    var body: some Scene {
        WindowGroup {
            Raiz()
                .environmentObject(tienda)
                .tint(tienda.apariencia.acento)
                .onOpenURL { tienda.abrir($0) }
                .onChange(of: fase) { _, nueva in tienda.activa = nueva == .active }
                #if DEBUG
                .task { Capturas.generarSiSePide(tienda) }
                #endif
        }
    }
}

enum Pestana: Hashable { case hoy, proyectos, calendario }

struct Raiz: View {
    @EnvironmentObject private var tienda: Tienda

    var body: some View {
        TabView(selection: $tienda.pestana) {
            HoyView()
                .tabItem { Label(texto("Hoy", "Today"), systemImage: "sun.max") }
                .tag(Pestana.hoy)
            ProyectosView()
                .tabItem { Label(texto("Proyectos", "Projects"), systemImage: "chart.bar.xaxis") }
                .tag(Pestana.proyectos)
            CalendarioView()
                .tabItem { Label(texto("Calendario", "Calendar"), systemImage: "calendar") }
                .tag(Pestana.calendario)
        }
        .overlay(alignment: .bottom) { AvisoDeshacer().padding(.bottom, 62) }
        .sheet(item: $tienda.hoja) { hoja in
            switch hoja {
            case let .tarea(proyecto, tarea): FormularioTarea(proyectoId: proyecto, tarea: tarea)
            case let .rutina(proyecto): FormularioRutina(proyectoId: proyecto)
            case .ajustes: AjustesView()
            }
        }
    }
}

// MARK: estado de la app

enum Hoja: Identifiable {
    case tarea(proyecto: String, tarea: Tarea?)
    case rutina(proyecto: String)
    case ajustes

    var id: String {
        switch self {
        case let .tarea(proyecto, tarea): return "t:\(proyecto):\(tarea?.id ?? "nueva")"
        case let .rutina(proyecto): return "r:\(proyecto)"
        case .ajustes: return "ajustes"
        }
    }
}

struct Deshacer: Equatable {
    let mensaje: String
    let operacion: Operacion
}

@MainActor
final class Tienda: ObservableObject {
    @Published private(set) var estado = Estado()
    @Published private(set) var uso: Uso?
    @Published private(set) var conexion: Conexion?
    @Published private(set) var enLinea = false
    @Published private(set) var porEntregar = 0
    @Published var pestana = Pestana.hoy
    @Published var ruta: [String] = [] // ids de proyecto abiertos en la pestaña Proyectos
    @Published var hoja: Hoja?
    @Published var deshacer: Deshacer?

    private var reloj: Timer?
    private var vueltas = 0

    var apariencia: Apariencia { Apariencia(estado.ajustes) }

    var activa = true {
        didSet {
            guard activa != oldValue else { return }
            activa ? reanudar() : reloj?.invalidate()
        }
    }

    init() {
        recargar()
        reanudar()
    }

    func recargar() {
        estado = Estado.leer(Almacen.estadoVigente)
        conexion = Almacen.conexion
        uso = conexion == nil ? nil : Uso.leer(Almacen.leer(.uso))
        porEntregar = Sincronia.cola.count
        // Si el proyecto abierto ya no existe (se terminó o se borró), se regresa a la lista.
        ruta.removeAll { id in !estado.proyectos.contains { $0.id == id } }
    }

    // MARK: cambios

    func hacer(_ operacion: Operacion) {
        Sincronia.aplicar(operacion)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { recargar() }
        Task { await sincronizar() }
    }

    func terminar(_ pendiente: Pendiente) {
        hacer(.completarTarea(proyecto: pendiente.proyecto.id, id: pendiente.tarea.id, fin: Fecha.instante()))
        ofrecerDeshacer(texto("Tarea terminada", "Task completed"), .restaurarTarea(id: pendiente.tarea.id))
    }

    /// Un toque suma una vez; al llegar al total, otro toque la regresa a cero.
    func sumar(_ rutina: Rutina, de proyecto: Proyecto, fecha: String = Fecha.hoy) {
        let cuenta = rutina.cumplida(fecha) ? 0 : rutina.hechas(fecha) + 1
        hacer(.fijarRutina(proyecto: proyecto.id, id: rutina.id, fecha: fecha, cuenta: cuenta))
    }

    private func ofrecerDeshacer(_ mensaje: String, _ operacion: Operacion) {
        let oferta = Deshacer(mensaje: mensaje, operacion: operacion)
        deshacer = oferta
        Task {
            try? await Task.sleep(for: .seconds(5))
            if deshacer == oferta { withAnimation { deshacer = nil } }
        }
    }

    func aceptarDeshacer() {
        guard let oferta = deshacer else { return }
        deshacer = nil
        hacer(oferta.operacion)
    }

    // MARK: la Mac

    func sincronizar() async {
        guard Almacen.conexion != nil else { return }
        let resultado = await Sincronia.sincronizar()
        enLinea = resultado == .alDia
        recargar()
    }

    private func reanudar() {
        reloj?.invalidate()
        recargar()
        Task { await sincronizar() }
        reloj = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.conexion != nil else { return }
                await self.sincronizar()
                self.vueltas += 1
                if self.vueltas % 5 == 1 {
                    await Sincronia.traerUso()
                    self.recargar()
                }
            }
        }
    }

    func conectar(_ enlace: String) async -> String? {
        guard let nueva = Conexion(enlace: enlace) else { return texto("Ese enlace no parece de Flecha.", "That doesn't look like a Flecha link.") }
        do {
            try await Sincronia.conectar(nueva)
            enLinea = true
            recargar()
            return nil
        } catch Cliente.Falla.rechazado(401) {
            return texto("La clave del enlace no es correcta.", "The key in the link is not correct.")
        } catch {
            return texto("No encontré tu Mac. Revisa que esté compartiendo y que los dos estén en la misma red wifi.",
                         "Couldn't find your Mac. Check that it is sharing and both devices are on the same Wi-Fi.")
        }
    }

    func desconectar() {
        Sincronia.desconectar()
        enLinea = false
        recargar()
    }

    // MARK: enlaces de los widgets (flecha://hoy, flecha://proyectos, flecha://proyecto/<id>)

    func abrir(_ url: URL) {
        hoja = nil
        switch url.host {
        case "proyecto":
            let id = url.pathComponents.dropFirst().first ?? ""
            pestana = .proyectos
            ruta = estado.proyectos.contains { $0.id == id } ? [id] : []
        case "proyectos":
            pestana = .proyectos
        default:
            pestana = .hoy
        }
    }
}

struct AvisoDeshacer: View {
    @EnvironmentObject private var tienda: Tienda

    var body: some View {
        if let oferta = tienda.deshacer {
            HStack(spacing: 14) {
                Text(oferta.mensaje).font(.subheadline)
                Button(texto("Deshacer", "Undo")) { tienda.aceptarDeshacer() }.font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .frame(height: 42)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
