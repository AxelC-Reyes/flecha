// Encuentra las computadoras con Flecha compartido en tu red (Bonjour, _flecha._tcp)
// y averigua su dirección para poder emparejarse con un código.

import Network
import SwiftUI

struct MacEncontrada: Identifiable, Hashable {
    let nombre: String
    let punto: NWEndpoint
    var id: String { nombre }
}

@MainActor
final class Buscador: ObservableObject {
    @Published private(set) var macs: [MacEncontrada] = []
    private var navegador: NWBrowser?

    func empezar() {
        guard navegador == nil else { return }
        let navegador = NWBrowser(for: .bonjour(type: "_flecha._tcp", domain: nil), using: .tcp)
        navegador.browseResultsChangedHandler = { [weak self] resultados, _ in
            let lista = resultados.compactMap { resultado -> MacEncontrada? in
                guard case let .service(nombre, _, _, _) = resultado.endpoint else { return nil }
                return MacEncontrada(nombre: nombre, punto: resultado.endpoint)
            }
            Task { @MainActor in self?.macs = lista.sorted { $0.nombre < $1.nombre } }
        }
        navegador.start(queue: .main)
        self.navegador = navegador
    }

    func parar() {
        navegador?.cancel()
        navegador = nil
    }

    /// Abre una conexión solo para saber a qué dirección y puerto resolvió el servicio.
    static func direccion(de mac: MacEncontrada) async -> URL? {
        await withCheckedContinuation { continuacion in
            let conexion = NWConnection(to: mac.punto, using: .tcp)
            var entregado = false
            let terminar: (URL?) -> Void = { url in
                guard !entregado else { return }
                entregado = true
                conexion.cancel()
                continuacion.resume(returning: url)
            }
            conexion.stateUpdateHandler = { estado in
                switch estado {
                case .ready:
                    guard case let .hostPort(anfitrion, puerto)? = conexion.currentPath?.remoteEndpoint else { return terminar(nil) }
                    var nombre = "\(anfitrion)"
                    if let corte = nombre.firstIndex(of: "%") { nombre = String(nombre[..<corte]) } // quita la interfaz de IPv6
                    if nombre.contains(":") { nombre = "[\(nombre)]" }
                    terminar(URL(string: "http://\(nombre):\(puerto.rawValue)/"))
                case .failed, .cancelled:
                    terminar(nil)
                default:
                    break
                }
            }
            conexion.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { terminar(nil) }
        }
    }
}
