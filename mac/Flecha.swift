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

        // Detrás de la página, un desenfoque real de lo que haya en pantalla. Solo se
        // enciende al abrir. macOS no acepta máscaras con degradado para este efecto,
        // así que el desvanecido hacia dentro se arma con franjas cada vez más tenues.
        desenfoque = NSView()
        desenfoque.alphaValue = 0
        let fondo = NSView()
        for vista in [desenfoque!, web!] as [NSView] {
            vista.frame = fondo.bounds
            vista.autoresizingMask = [.width, .height]
            fondo.addSubview(vista)
        }
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
        let imagen = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: 2.5, width: 2.5, height: 13), xRadius: 1.25, yRadius: 1.25).fill()
            NSBezierPath(roundedRect: NSRect(x: 7.5, y: 11, width: 8, height: 3), xRadius: 1.2, yRadius: 1.2).fill()
            NSBezierPath(roundedRect: NSRect(x: 7.5, y: 6.5, width: 5, height: 3), xRadius: 1.2, yRadius: 1.2).fill()
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
        menu.addItem(withTitle: "Copiar enlace para el teléfono", action: #selector(copiarEnlace), keyEquivalent: "")
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
        if expandido { armarDesenfoque(destino.size) }
    }

    private func franja(_ area: NSRect, opacidad: CGFloat) -> NSVisualEffectView {
        let vista = NSVisualEffectView(frame: area)
        vista.material = .fullScreenUI
        vista.blendingMode = .behindWindow
        vista.state = .active
        vista.alphaValue = opacidad
        return vista
    }

    // Sólido junto al borde de la pantalla; de la mitad hacia dentro se va apagando.
    private func armarDesenfoque(_ tamano: NSSize) {
        desenfoque.subviews.forEach { $0.removeFromSuperview() }
        let derecha = lado == "derecha"
        let solido = (tamano.width * 0.5).rounded()
        let pasos = 28
        let ancho = (tamano.width - solido) / CGFloat(pasos)
        let x = { (desde: CGFloat, w: CGFloat) in derecha ? tamano.width - desde - w : desde }
        desenfoque.addSubview(franja(NSRect(x: x(0, solido), y: 0, width: solido, height: tamano.height), opacidad: 1))
        for i in 0..<pasos {
            let avance = (CGFloat(i) + 0.5) / CGFloat(pasos)
            let opacidad = pow(1 - avance, 1.6)
            let desde = solido + CGFloat(i) * ancho
            desenfoque.addSubview(franja(NSRect(x: x(desde, ancho), y: 0, width: ancho, height: tamano.height), opacidad: opacidad))
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
            desvanecer(a: 1, en: 0.45)
        case "cerrando":
            desvanecer(a: 0, en: 0.3)
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
        var pedido = URLRequest(url: base.appendingPathComponent("api/enlace"))
        pedido.timeoutInterval = 2
        URLSession.shared.dataTask(with: pedido) { datos, _, _ in
            let respuesta = datos.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let enlace = respuesta?["url"] as? String
            DispatchQueue.main.async {
                guard let enlace else {
                    return self.avisar("Todavía no hay enlace",
                                       "Activa primero \"Compartir con mi iPhone o iPad\" y revisa que esta Mac esté conectada a una red.")
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(enlace, forType: .string)
                self.avisar("Enlace copiado",
                            "Pégalo en la app de Flecha de tu iPhone o iPad (Personalizar → Conectar con mi Mac), o ábrelo en su navegador. Lleva una clave: compártelo solo con tus dispositivos.\n\n\(enlace)")
            }
        }.resume()
    }
}

let app = NSApplication.shared
let delegado = Delegado()
app.delegate = delegado
app.run()
