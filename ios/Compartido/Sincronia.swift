// Cómo conviven el teléfono y la Mac.
//
// Sin Mac conectada, todo vive en local.json y no hay más que hacer.
// Con Mac conectada, el teléfono trabaja sobre una copia (mac.json) y anota cada
// cambio en una cola. Sincronizar es: traer lo que tenga la Mac, volver a aplicar
// encima los cambios en cola y entregárselo. Si no hay red, la cola espera.
// Lo usan por igual la app y los botones de los widgets.

import Foundation
import WidgetKit

enum Sincronia {
    private static let claveHuella = "huellaMac"

    private static var huella: String? {
        get { Almacen.preferencias.string(forKey: claveHuella) }
        set { Almacen.preferencias.set(newValue, forKey: claveHuella) }
    }

    static var cola: [Operacion] {
        get { Almacen.leer(.cola).flatMap { try? JSONDecoder().decode([Operacion].self, from: $0) } ?? [] }
        set {
            if newValue.isEmpty { Almacen.borrar(.cola) } else if let datos = try? JSONEncoder().encode(newValue) { Almacen.escribir(datos, en: .cola) }
        }
    }

    /// Aplica un cambio de inmediato a lo que se ve. Con Mac conectada, además lo encola.
    static func aplicar(_ operacion: Operacion) {
        let conectado = Almacen.conexion != nil
        var documento = Documento(Almacen.estadoVigente)
        documento.aplicar(operacion)
        Almacen.escribir(documento.datos, en: conectado ? .mac : .local)
        if conectado { cola.append(operacion) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Solo despierta a los widgets si de verdad cambió lo que muestran (ellos también sincronizan).
    private static func mostrar(_ datos: Data) {
        guard Almacen.leer(.mac) != datos else { return }
        Almacen.escribir(datos, en: .mac)
        WidgetCenter.shared.reloadAllTimelines()
    }

    enum Resultado { case sinMac, alDia, sinRed, rechazado }

    /// Devuelve cómo quedó. Nunca pierde cambios: si algo falla, la cola se conserva.
    @discardableResult
    static func sincronizar() async -> Resultado {
        guard let conexion = Almacen.conexion else { return .sinMac }
        let cliente = Cliente(conexion: conexion)
        for _ in 0..<3 {
            let pendientes = cola
            do {
                // 1. ¿Qué tiene la Mac?
                var base = Almacen.leer(.base)
                if let nuevo = try await cliente.estado(huella: base == nil ? nil : huella) {
                    base = nuevo.datos
                    huella = nuevo.huella
                    Almacen.escribir(nuevo.datos, en: .base)
                }
                guard !pendientes.isEmpty else {
                    if let base { mostrar(base) }
                    return .alDia
                }
                // 2. Lo mío encima de lo suyo, y se lo entrego.
                var documento = Documento(base)
                pendientes.forEach { documento.aplicar($0) }
                let combinado = documento.datos
                huella = try await cliente.guardar(combinado, huella: huella)
                Almacen.escribir(combinado, en: .base)
                // Si mientras tanto se encoló algo más, se conserva para la siguiente vuelta.
                cola = Array(cola.dropFirst(pendientes.count))
                if cola.isEmpty {
                    mostrar(combinado)
                    return .alDia
                }
            } catch Cliente.Falla.conflicto {
                huella = nil // la Mac cambió justo en medio: otra vuelta
                Almacen.borrar(.base)
            } catch Cliente.Falla.rechazado {
                return .rechazado
            } catch {
                return .sinRed
            }
        }
        return .sinRed
    }

    static func traerUso() async {
        guard let conexion = Almacen.conexion, let datos = try? await Cliente(conexion: conexion).uso() else { return }
        Almacen.escribir(datos, en: .uso)
    }

    static func conectar(_ conexion: Conexion) async throws {
        guard let primero = try await Cliente(conexion: conexion).estado() else { return }
        Almacen.conexion = conexion
        Almacen.escribir(primero.datos, en: .base)
        Almacen.escribir(primero.datos, en: .mac)
        huella = primero.huella
        cola = []
        await traerUso()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func desconectar() {
        Almacen.conexion = nil
        let sobrantes: [Almacen.Archivo] = [.mac, .base, .cola, .uso]
        sobrantes.forEach(Almacen.borrar)
        huella = nil
        WidgetCenter.shared.reloadAllTimelines()
    }
}
