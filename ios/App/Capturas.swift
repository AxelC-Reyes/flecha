// Solo para desarrollo: `--capturas` dibuja los widgets a PNG en Documents/capturas y
// `--ejemplo` carga datos ficticios (sin tocar los tuyos si ya hay), para revisar la app
// y los widgets sin ponerlos a mano en la pantalla de inicio.

#if DEBUG
import SwiftUI

@MainActor
enum Capturas {
    static func generarSiSePide(_ tienda: Tienda) {
        let argumentos = CommandLine.arguments
        if argumentos.contains("--ejemplo"), Estado.leer(Almacen.estadoVigente).proyectos.isEmpty, Almacen.conexion == nil {
            Almacen.escribir(ejemplo(), en: .local)
            tienda.recargar()
        }
        if let i = argumentos.firstIndex(of: "--pestana"), argumentos.count > i + 1 {
            tienda.pestana = ["proyectos": .proyectos, "calendario": .calendario][argumentos[i + 1]] ?? .hoy
            if argumentos[i + 1] == "proyecto" {
                tienda.pestana = .proyectos
                tienda.ruta = tienda.estado.proyectos.first.map { [$0.id] } ?? []
            }
        }
        if argumentos.contains("--sumar") {
            // Prueba de punta a punta: sincroniza, suma una vez a la primera rutina de hoy y entrega el cambio.
            Task {
                await tienda.sincronizar()
                if let primera = tienda.estado.resumen().rutinas.first { tienda.sumar(primera.rutina, de: primera.proyecto) }
            }
        }
        if let i = argumentos.firstIndex(of: "--emparejar"), argumentos.count > i + 1 {
            // Prueba de punta a punta del emparejamiento: busca la computadora por Bonjour y usa el código.
            let codigo = argumentos[i + 1]
            let buscador = Buscador()
            buscador.empezar()
            Task {
                for _ in 0..<40 where buscador.macs.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
                guard let mac = buscador.macs.first else { return print("Emparejar: no se encontró ninguna computadora") }
                guard let base = await Buscador.direccion(de: mac) else { return print("Emparejar: sin dirección para \(mac.nombre)") }
                do {
                    let conexion = try await Cliente.emparejar(base, codigo: codigo)
                    try await Sincronia.conectar(conexion)
                    tienda.recargar()
                    print("Emparejar: conectado con \(mac.nombre) en \(base)")
                } catch {
                    print("Emparejar: falló \(error)")
                }
            }
        }
        guard argumentos.contains("--capturas") else { return }
        let carpeta = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("capturas")
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let estado = tienda.estado
        let apariencia = Apariencia(estado.ajustes)
        let tamanos: [(String, Tamano, CGSize)] = [("chico", .chico, CGSize(width: 170, height: 170)), ("mediano", .mediano, CGSize(width: 364, height: 170)), ("grande", .grande, CGSize(width: 364, height: 382))]
        for (nombre, tamano, medida) in tamanos {
            guardar(VistaHoy(dia: estado.resumen(), apariencia: apariencia, tamano: tamano, proximas: estado.proximas(dias: 14)), medida, carpeta.appendingPathComponent("hoy-\(nombre).png"))
            guardar(VistaBarras(filas: estado.filas, apariencia: apariencia, tamano: tamano), medida, carpeta.appendingPathComponent("avance-\(nombre).png"))
        }
        print("Capturas en \(carpeta.path)")
    }

    private static func guardar(_ vista: some View, _ medida: CGSize, _ destino: URL) {
        let marco = vista
            .padding(16)
            .frame(width: medida.width, height: medida.height)
            .background(Color.fondoFlecha)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .environment(\.colorScheme, .dark)
        let dibujante = ImageRenderer(content: marco)
        dibujante.scale = 3
        if let png = dibujante.uiImage?.pngData() { try? png.write(to: destino) }
    }

    /// Un estudiante con su maestría, su gimnasio y una mudanza, con fechas relativas a hoy.
    private static func ejemplo() -> Data {
        let hoy = Fecha.hoy
        var ejercicios: [String: Int] = [hoy: 2]
        var gimnasio: [String: Int] = [:]
        for atras in 1...20 {
            let fecha = Fecha.sumar(-atras, a: hoy)
            if Fecha.diaSemana(fecha) <= 5 { ejercicios[fecha] = 3 }
            if [1, 3, 5].contains(Fecha.diaSemana(fecha)), atras < 16 { gimnasio[fecha] = 1 }
        }
        let raiz: [String: Any] = [
            "version": 1,
            "ajustes": ["color": "auto", "forma": "redondeada", "iniciado": true],
            "proyectos": [
                ["id": "m", "nombre": texto("Maestría", "Master's"), "previo": 2, "tareas": [
                    ["id": "m1", "titulo": texto("Registro al examen", "Exam registration"), "vence": Fecha.sumar(-1, a: hoy)],
                    ["id": "m2", "titulo": texto("Guía de álgebra lineal, cap. 4", "Linear algebra guide, ch. 4"), "vence": hoy],
                    ["id": "m3", "titulo": texto("Constancia de inglés", "English certificate"), "vence": Fecha.sumar(5, a: hoy)],
                    ["id": "m4", "titulo": texto("Exámenes de práctica", "Practice exams")],
                ], "rutinas": [["id": "r1", "titulo": texto("Ejercicios diarios", "Daily exercises"), "veces": 3, "dias": [1, 2, 3, 4, 5], "meta": 120, "registro": ejercicios]]],
                ["id": "g", "nombre": texto("Gimnasio", "Gym"), "previo": 0, "tareas": [], "rutinas": [["id": "r2", "titulo": texto("Entrenar", "Work out"), "veces": 1, "dias": [1, 3, 5], "meta": 100, "registro": gimnasio]]],
                ["id": "d", "nombre": texto("Mudanza", "Moving"), "previo": 5, "tareas": [
                    ["id": "d1", "titulo": texto("Contratar la mudanza", "Book the movers"), "vence": Fecha.sumar(2, a: hoy)],
                    ["id": "d2", "titulo": texto("Cambio de domicilio", "Change of address")],
                    ["id": "d3", "titulo": texto("Entregar llaves", "Hand over keys"), "vence": Fecha.sumar(12, a: hoy)],
                ]],
            ],
            "finalizadas": ["tareas": [], "proyectos": []],
        ]
        return (try? JSONSerialization.data(withJSONObject: raiz)) ?? Data()
    }
}
#endif
