// Cliente del servidor de Flecha que corre en tu Mac con `./flecha --red`.

import Foundation

struct Cliente {
    enum Falla: Error { case conflicto, rechazado(Int), sinRespuesta }

    let conexion: Conexion

    private static let sesion: URLSession = {
        let ajustes = URLSessionConfiguration.ephemeral
        ajustes.timeoutIntervalForRequest = 4
        ajustes.timeoutIntervalForResource = 8
        ajustes.waitsForConnectivity = false
        return URLSession(configuration: ajustes)
    }()

    private func pedido(_ ruta: String, metodo: String = "GET") -> URLRequest {
        var pedido = URLRequest(url: conexion.base.appendingPathComponent(ruta))
        pedido.httpMethod = metodo
        pedido.cachePolicy = .reloadIgnoringLocalCacheData
        pedido.setValue("1", forHTTPHeaderField: "X-Flecha")
        if let clave = conexion.clave { pedido.setValue(clave, forHTTPHeaderField: "X-Flecha-Clave") }
        return pedido
    }

    private func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (datos, respuesta) = try await Self.sesion.data(for: pedido)
        guard let http = respuesta as? HTTPURLResponse else { throw Falla.sinRespuesta }
        return (datos, http)
    }

    /// Devuelve nil si no cambió desde `huella`.
    func estado(huella: String? = nil) async throws -> (datos: Data, huella: String?)? {
        var pedido = pedido("api/estado")
        if let huella { pedido.setValue(huella, forHTTPHeaderField: "If-None-Match") }
        let (datos, http) = try await enviar(pedido)
        if http.statusCode == 304 { return nil }
        guard http.statusCode == 200 else { throw Falla.rechazado(http.statusCode) }
        return (datos, http.value(forHTTPHeaderField: "ETag"))
    }

    /// Devuelve la huella nueva.
    func guardar(_ estado: Data, huella: String?) async throws -> String? {
        var pedido = pedido("api/estado", metodo: "PUT")
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let huella { pedido.setValue(huella, forHTTPHeaderField: "If-Match") }
        pedido.httpBody = estado
        let (_, http) = try await enviar(pedido)
        if http.statusCode == 409 { throw Falla.conflicto }
        guard http.statusCode == 200 else { throw Falla.rechazado(http.statusCode) }
        return http.value(forHTTPHeaderField: "ETag")
    }

    func uso() async throws -> Data {
        let (datos, http) = try await enviar(pedido("api/uso"))
        guard http.statusCode == 200 else { throw Falla.rechazado(http.statusCode) }
        return datos
    }
}
