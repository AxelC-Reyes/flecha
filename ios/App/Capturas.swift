// Solo para desarrollo: `--capturas` dibuja los widgets a PNG dentro de Documents/capturas,
// con los datos guardados o con un ejemplo. Sirve para revisarlos sin ponerlos a mano
// en la pantalla de inicio:
//
//   xcrun simctl launch booted <id de la app> --capturas
//   open "$(xcrun simctl get_app_container booted <id de la app> data)/Documents/capturas"

#if DEBUG
import SwiftUI

@MainActor
enum Capturas {
    static func generarSiSePide() {
        guard CommandLine.arguments.contains("--capturas") else { return }
        let carpeta = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("capturas")
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)

        var estado = Estado.leer(Almacen.estadoVigente)
        if estado.proyectos.isEmpty { estado = Estado.leer(ejemplo) }
        let uso = Uso.leer(Almacen.leer(.uso)) ?? Uso.leer(usoDeEjemplo)

        let tamanos: [(String, Tamano, CGSize)] = [
            ("chico", .chico, CGSize(width: 170, height: 170)),
            ("mediano", .mediano, CGSize(width: 364, height: 170)),
            ("grande", .grande, CGSize(width: 364, height: 382)),
        ]
        for esquema in [ColorScheme.dark, .light] {
            for (nombre, tamano, medida) in tamanos {
                let sufijo = esquema == .dark ? "oscuro" : "claro"
                guardar(VistaBarras(filas: estado.filas, apariencia: Apariencia(estado.ajustes), tamano: tamano),
                        medida, esquema, carpeta.appendingPathComponent("avance-\(nombre)-\(sufijo).png"))
                guardar(VistaBarras(filas: uso?.filas() ?? [], apariencia: Apariencia(estado.ajustes), tamano: tamano,
                                    actualizado: tamano == .chico ? nil : Date()),
                        medida, esquema, carpeta.appendingPathComponent("uso-\(nombre)-\(sufijo).png"))
            }
        }
        print("Capturas en \(carpeta.path)")
    }

    private static func guardar(_ vista: some View, _ medida: CGSize, _ esquema: ColorScheme, _ destino: URL) {
        let marco = vista
            .padding(16)
            .frame(width: medida.width, height: medida.height)
            .background(Color.fondoFlecha)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .environment(\.colorScheme, esquema)
        let dibujante = ImageRenderer(content: marco)
        dibujante.scale = 3
        if let imagen = dibujante.uiImage, let png = imagen.pngData() { try? png.write(to: destino) }
    }

    private static let ejemplo = Data(#"""
    {"ajustes":{"color":"auto","forma":"redondeada"},
     "proyectos":[
      {"id":"a","nombre":"Cafetería","previo":11,"tareas":["1","2","3"]},
      {"id":"b","nombre":"Disco","previo":4,"tareas":["1","2","3","4","5"]},
      {"id":"c","nombre":"Maratón","previo":9,"tareas":["1","2","3","4"]},
      {"id":"d","nombre":"Huerto","previo":1,"tareas":["1","2","3","4","5"]},
      {"id":"e","nombre":"Tesis","previo":0,"tareas":["1","2","3"]}],
     "finalizadas":{"tareas":[{"proyectoId":"a"},{"proyectoId":"a"},{"proyectoId":"c"}],"proyectos":[]}}
    """#.utf8)

    private static let usoDeEjemplo = Data(#"""
    {"generado":0,"herramientas":[
      {"id":"claude","nombre":"Claude","limites":[{"id":"5h","usado":64,"reinicia":null},{"id":"7d","usado":27,"reinicia":null}]},
      {"id":"codex","nombre":"Codex","limites":[{"id":"5h","usado":38,"reinicia":null},{"id":"7d","usado":92,"reinicia":null}]}]}
    """#.utf8)
}
#endif
