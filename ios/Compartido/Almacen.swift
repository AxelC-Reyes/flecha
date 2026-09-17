// Dónde guarda Flecha sus archivos en iPhone y iPad: la carpeta compartida entre la
// app y el widget (App Group). Todo es JSON, igual que en la computadora.
//
//   local.json      tus datos cuando el teléfono va por su cuenta
//   mac.json        tu copia de trabajo de los datos de la Mac, si la conectaste
//   base.json       lo último que la Mac confirmó (mac.json = base.json + cola.json)
//   cola.json       cambios hechos sin conexión, por entregar
//   uso.json        lo último de GET /api/uso
//   conexion.json   dirección y clave del servidor de tu Mac

import Foundation

/// Español por defecto; inglés si el dispositivo está en inglés.
func texto(_ es: String, _ en: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("en") == true ? en : es
}

struct Conexion: Codable, Equatable {
    var base: URL
    var clave: String?

    /// Acepta el enlace que imprime `./flecha --red`: http://192.168.1.5:4747/?clave=abc
    init?(enlace: String) {
        let limpio = enlace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var partes = URLComponents(string: limpio.contains("://") ? limpio : "http://\(limpio)"),
              let esquema = partes.scheme?.lowercased(), ["http", "https"].contains(esquema),
              let anfitrion = partes.host, !anfitrion.isEmpty
        else { return nil }
        clave = partes.queryItems?.first { $0.name == "clave" }?.value
        partes.query = nil
        partes.fragment = nil
        partes.path = "/"
        guard let url = partes.url else { return nil }
        base = url
    }

    var legible: String { base.host.map { "\($0)\(base.port.map { ":\($0)" } ?? "")" } ?? base.absoluteString }
}

enum Almacen {
    static let grupo = Bundle.main.object(forInfoDictionaryKey: "FlechaGrupo") as? String

    static let carpeta: URL = {
        let archivos = FileManager.default
        if let grupo, let compartida = archivos.containerURL(forSecurityApplicationGroupIdentifier: grupo) {
            return compartida
        }
        // Sin App Group (firma incompleta) la app funciona igual, pero el widget no ve los datos.
        let propia = archivos.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Flecha")
        try? archivos.createDirectory(at: propia, withIntermediateDirectories: true)
        return propia
    }()

    enum Archivo: String {
        case local = "local.json", mac = "mac.json", base = "base.json", cola = "cola.json", uso = "uso.json", conexion = "conexion.json"
    }

    static func leer(_ archivo: Archivo) -> Data? {
        try? Data(contentsOf: carpeta.appendingPathComponent(archivo.rawValue))
    }

    static func escribir(_ datos: Data, en archivo: Archivo) {
        try? datos.write(to: carpeta.appendingPathComponent(archivo.rawValue), options: .atomic)
    }

    static func borrar(_ archivo: Archivo) {
        try? FileManager.default.removeItem(at: carpeta.appendingPathComponent(archivo.rawValue))
    }

    static var conexion: Conexion? {
        get { leer(.conexion).flatMap { try? JSONDecoder().decode(Conexion.self, from: $0) } }
        set {
            if let newValue, let datos = try? JSONEncoder().encode(newValue) {
                escribir(datos, en: .conexion)
            } else {
                borrar(.conexion)
            }
        }
    }

    /// Lo que debe mostrarse ahora: los datos de la Mac si hay conexión configurada, o los locales.
    static var estadoVigente: Data? {
        conexion != nil ? leer(.mac) : leer(.local)
    }

    /// Preferencias pequeñas compartidas entre la app y el widget.
    static var preferencias: UserDefaults { grupo.flatMap { UserDefaults(suiteName: $0) } ?? .standard }
}
