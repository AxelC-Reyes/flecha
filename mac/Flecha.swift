// Flecha para macOS: la línea vive pegada al borde de tu pantalla, encima de todo.
//
// Es una ventana flotante y transparente que muestra la misma interfaz web
// (carpeta web/) y arranca por su cuenta el servidor local (servidor.py).
// Se compila con `mac/construir.sh`; no necesita proyecto de Xcode.

import Cocoa
import WebKit

let puerto = 4747
let base = URL(string: "http://127.0.0.1:\(puerto)/")!

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class Vista: WKWebView {
    // El primer clic sobre la línea debe abrirla aunque la ventana no esté activa.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class Delegado: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private var panel: Panel!
    private var web: Vista!
    private var desenfoque: NSView!
    private var icono: NSStatusItem!
    private var servidor: Process?
    private var expandido = false
    private let ajustes = UserDefaults.standard

    private var lado: String {
        get { ajustes.string(forKey: "lado") ?? "izquierda" }
        set { ajustes.set(newValue, forKey: "lado") }
    }
    private var encima: Bool {
        get { ajustes.object(forKey: "encima") as? Bool ?? true }
        set { ajustes.set(newValue, forKey: "encima") }
    }
    /// Arrancar el servidor con --red, para la app de iPhone y iPad.
    private var enRed: Bool {
        get { ajustes.bool(forKey: "enRed") }
        set { ajustes.set(newValue, forKey: "enRed") }
    }

    // MARK: arranque

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        crearPanel()
        crearIcono()
        NotificationCenter.default.addObserver(
            self, selector: #selector(recolocar),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let listo = self.asegurarServidor()
            DispatchQueue.main.async { listo ? self.cargar() : self.avisarSinServidor() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        servidor?.terminate()
    }

    private func crearPanel() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "flecha")
        web = Vista(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        web.allowsMagnification = false

        panel = Panel(
            contentRect: marco(expandido: false),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self

        // Detrás de la página va un solo panel de cristal, del tamaño exacto del cuadro
        // y sus barras (la página manda esa zona). Así todo se lee igual sobre una
        // ventana blanca que sobre una negra, sin franjas ni degradados sucios.
        desenfoque = crearCristal()
        desenfoque.alphaValue = 0
        let fondo = NSView()
        fondo.addSubview(desenfoque)
        web.frame = fondo.bounds
        web.autoresizingMask = [.width, .height]
        fondo.addSubview(web)
        panel.contentView = fondo
        aplicarNivel()
        panel.orderFrontRegardless()
    }

    private func aplicarNivel() {
        // Encima de todo, o al nivel del escritorio (detrás de tus ventanas).
        panel.level = encima ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private func crearIcono() {
        icono = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // El logo: tres proyectos, cada flecha es su avance. Dibujado a mano para que quede nítido a 18 px.
        let imagen = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            for y in [4.0, 9.0, 14.0] { NSBezierPath(ovalIn: NSRect(x: 2.5, y: y - 1.4, width: 2.8, height: 2.8)).fill() }
            NSColor.black.setStroke()
            for (y, largo) in [(4.0, 7.5), (9.0, 4.5)] {
                let flecha = NSBezierPath()
                flecha.lineWidth = 1.6
                flecha.lineCapStyle = .round
                flecha.lineJoinStyle = .round
                flecha.move(to: NSPoint(x: 7.5, y: y))
                flecha.line(to: NSPoint(x: 7.5 + largo, y: y))
                flecha.move(to: NSPoint(x: 7.5 + largo - 2.8, y: y - 2.8))
                flecha.line(to: NSPoint(x: 7.5 + largo, y: y))
                flecha.line(to: NSPoint(x: 7.5 + largo - 2.8, y: y + 2.8))
                flecha.stroke()
            }
            return true
        }
        imagen.isTemplate = true
        icono.button?.image = imagen
        icono.button?.toolTip = "Flecha"

        let menu = NSMenu()
        menu.addItem(withTitle: "Abrir o cerrar", action: #selector(alternar), keyEquivalent: "")
        let siempre = menu.addItem(withTitle: "Siempre encima", action: #selector(alternarEncima), keyEquivalent: "")
        siempre.state = encima ? .on : .off
        menu.addItem(withTitle: "Abrir en el navegador", action: #selector(abrirNavegador), keyEquivalent: "")
        menu.addItem(.separator())
        let compartir = menu.addItem(withTitle: "Compartir con mi iPhone o iPad", action: #selector(alternarRed), keyEquivalent: "")
        compartir.state = enRed ? .on : .off
        menu.addItem(withTitle: "Código para el teléfono", action: #selector(copiarEnlace), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de Flecha", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        icono.menu = menu
    }

    // MARK: servidor local

    private func responde() -> Bool {
        var pedido = URLRequest(url: base.appendingPathComponent("api/estado"))
        pedido.timeoutInterval = 0.6
        pedido.setValue("1", forHTTPHeaderField: "X-Flecha")
        let espera = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: pedido) { _, respuesta, _ in
            ok = (respuesta as? HTTPURLResponse)?.statusCode == 200
            espera.signal()
        }.resume()
        espera.wait()
        return ok
    }

    private func asegurarServidor() -> Bool {
        if responde() { return true } // ya había uno corriendo: se reutiliza
        guard let raiz = Bundle.main.object(forInfoDictionaryKey: "FlechaRaiz") as? String else { return false }
        let guion = URL(fileURLWithPath: raiz).appendingPathComponent("servidor.py").path
        guard FileManager.default.fileExists(atPath: guion) else { return false }

        let proceso = Process()
        proceso.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proceso.arguments = ["python3", guion, "--sin-abrir", "--con-padre", "--puerto", String(puerto)] + (enRed ? ["--red"] : [])
        proceso.standardOutput = FileHandle.nullDevice
        proceso.standardError = FileHandle.nullDevice
        do { try proceso.run() } catch { return false }
        servidor = proceso
        for _ in 0..<40 {
            if responde() { return true }
            if !proceso.isRunning { return false }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return false
    }

    private func cargar() {
        // `Flecha --abierto` arranca ya desplegado (útil para probar).
        let inicio = CommandLine.arguments.contains("--abierto") ? URL(string: "?abierto=1", relativeTo: base)! : base
        web.load(URLRequest(url: inicio, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    private func avisarSinServidor() {
        let alerta = NSAlert()
        alerta.messageText = "Flecha no pudo arrancar su servidor local"
        alerta.informativeText = "Revisa que exista python3 y que la carpeta del repositorio no se haya movido. Si la moviste, vuelve a correr mac/construir.sh."
        NSApp.activate(ignoringOtherApps: true)
        alerta.runModal()
        NSApp.terminate(nil)
    }

    // MARK: tamaño y posición

    private func marco(expandido: Bool) -> NSRect {
        let pantalla = (panel?.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let tamano = expandido
            ? NSSize(width: min(560, pantalla.width), height: pantalla.height)
            : NSSize(width: 44, height: 200)
        let x = lado == "derecha" ? pantalla.maxX - tamano.width : pantalla.minX
        return NSRect(x: x, y: (pantalla.midY - tamano.height / 2).rounded(), width: tamano.width, height: tamano.height)
    }

    @objc private func recolocar() {
        let destino = marco(expandido: expandido)
        panel.setFrame(destino, display: true)
    }

    private func crearCristal() -> NSView {
        if #available(macOS 26.0, *) {
            let cristal = NSGlassEffectView()
            cristal.cornerRadius = 38
            return cristal
        }
        let clasico = NSVisualEffectView()
        clasico.material = .hudWindow
        clasico.blendingMode = .behindWindow
        clasico.state = .active
        clasico.wantsLayer = true
        clasico.maskImage = Self.mascaraRedonda(radio: 38)
        return clasico
    }

    /// Máscara estirable con esquinas redondas para el efecto clásico (macOS 12 a 15).
    private static func mascaraRedonda(radio: CGFloat) -> NSImage {
        let lado = radio * 2 + 1
        let imagen = NSImage(size: NSSize(width: lado, height: lado), flipped: false) { area in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: area, xRadius: radio, yRadius: radio).fill()
            return true
        }
        imagen.capInsets = NSEdgeInsets(top: radio, left: radio, bottom: radio, right: radio)
        imagen.resizingMode = .stretch
        return imagen
    }

    /// En oscuro, un velo negro sobre el cristal para que las letras blancas conserven
    /// contraste aunque detrás haya una ventana blanca.
    private func entintarCristal() {
        guard #available(macOS 26.0, *), let cristal = desenfoque as? NSGlassEffectView else { return }
        let oscuro = panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        cristal.tintColor = oscuro ? NSColor.black.withAlphaComponent(0.32) : nil
    }

    /// La página avisa qué rectángulo ocupa (en sus coordenadas, con el origen arriba).
    private func acomodarCristal(_ cuerpo: [String: Any]) {
        guard expandido, let fondo = panel.contentView,
              let x = cuerpo["x"] as? Double, let y = cuerpo["y"] as? Double,
              let ancho = cuerpo["ancho"] as? Double, let alto = cuerpo["alto"] as? Double
        else { return }
        let marco = NSRect(x: x, y: Double(fondo.bounds.height) - y - alto, width: ancho, height: alto)
        if desenfoque.alphaValue == 0 {
            entintarCristal()
            desenfoque.frame = marco
            return desvanecer(a: 1, en: 0.35)
        }
        NSAnimationContext.runAnimationGroup { contexto in
            contexto.duration = 0.5
            contexto.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            contexto.allowsImplicitAnimation = true
            desenfoque.animator().frame = marco
        }
    }

    private func desvanecer(a opacidad: CGFloat, en segundos: TimeInterval) {
        NSAnimationContext.runAnimationGroup { contexto in
            contexto.duration = segundos
            desenfoque.animator().alphaValue = opacidad
        }
    }

    // MARK: mensajes desde la página

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let cuerpo = message.body as? [String: Any], let tipo = cuerpo["tipo"] as? String else { return }
        switch tipo {
        case "expandir":
            expandido = true
            recolocar()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        case "zona":
            acomodarCristal(cuerpo)
        case "cerrando":
            desvanecer(a: 0, en: 0.18)
        case "contraer":
            expandido = false
            desenfoque.alphaValue = 0
            recolocar()
        case "tema":
            let tema = cuerpo["tema"] as? String
            panel.appearance = tema == "claro" ? NSAppearance(named: .aqua) : tema == "oscuro" ? NSAppearance(named: .darkAqua) : nil
        case "lado":
            guard let nuevo = cuerpo["lado"] as? String, nuevo != lado else { return }
            lado = nuevo
            recolocar()
        default:
            break
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if expandido { web.evaluateJavaScript("window.Flecha && window.Flecha.cerrar()") }
    }

    // Los enlaces externos se abren en el navegador, no dentro del panel.
    func webView(_ webView: WKWebView, decidePolicyFor accion: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = accion.request.url, url.host != base.host {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    // MARK: menú

    @objc private func alternar() {
        web.evaluateJavaScript("window.Flecha && (document.getElementById('widget').classList.contains('abierto') ? window.Flecha.cerrar() : window.Flecha.abrir())")
    }

    @objc private func alternarEncima(_ item: NSMenuItem) {
        encima.toggle()
        item.state = encima ? .on : .off
        aplicarNivel()
    }

    @objc private func abrirNavegador() {
        NSWorkspace.shared.open(base)
    }

    // MARK: compartir con el teléfono

    private func avisar(_ titulo: String, _ detalle: String) {
        let alerta = NSAlert()
        alerta.messageText = titulo
        alerta.informativeText = detalle
        NSApp.activate(ignoringOtherApps: true)
        alerta.runModal()
    }

    @objc private func alternarRed(_ item: NSMenuItem) {
        guard let propio = servidor else {
            return avisar("Flecha ya estaba corriendo por fuera",
                          "El servidor lo arrancó otra ventana (./flecha), así que no puedo reiniciarlo. Ciérralo, vuelve a abrir esta app y activa la opción; o arráncalo tú con ./flecha --red.")
        }
        enRed.toggle()
        item.state = enRed ? .on : .off
        propio.terminate()
        servidor = nil
        DispatchQueue.global(qos: .userInitiated).async {
            propio.waitUntilExit()
            let listo = self.asegurarServidor()
            DispatchQueue.main.async {
                guard listo else { return self.avisarSinServidor() }
                self.cargar()
                if self.enRed { self.copiarEnlace() }
            }
        }
    }

    @objc private func copiarEnlace() {
        var pedido = URLRequest(url: base.appendingPathComponent("api/emparejar"))
        pedido.timeoutInterval = 2
        URLSession.shared.dataTask(with: pedido) { datos, _, _ in
            let respuesta = datos.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let codigo = respuesta?["codigo"] as? String
            let enlace = respuesta?["url"] as? String
            DispatchQueue.main.async {
                guard let codigo else {
                    return self.avisar("Todavía no se puede",
                                       "Activa primero \"Compartir con mi iPhone o iPad\" y revisa que esta Mac esté conectada a una red.")
                }
                if let enlace {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(enlace, forType: .string)
                }
                self.avisar("Código: \(codigo.prefix(3)) \(codigo.suffix(3))",
                            "En el iPhone o iPad: Flecha → engrane → toca esta Mac y escribe el código. Vale 10 minutos. Los dos deben estar en la misma red wifi.\n\nSi la app no encuentra la Mac, el enlace con clave ya quedó copiado para pegarlo ahí.")
            }
        }.resume()
    }
}

let app = NSApplication.shared
let delegado = Delegado()
app.delegate = delegado
app.run()
