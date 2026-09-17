// Flecha para iPhone y iPad. La interfaz es la misma carpeta web/ del repositorio
// dentro de un WKWebView; esta parte nativa guarda los datos donde el widget los
// pueda leer y, si quieres, los toma del servidor de Flecha que corre en tu Mac.

import SwiftUI
import WebKit
import WidgetKit

@main
struct FlechaApp: App {
    @StateObject private var puente = Puente()
    @Environment(\.scenePhase) private var fase

    var body: some Scene {
        WindowGroup {
            Pagina(puente: puente)
                .ignoresSafeArea()
                .background(Color.fondoFlecha)
                .onOpenURL { puente.abrir($0) }
                .onChange(of: fase) { _, nueva in puente.activa = nueva == .active }
                #if DEBUG
                .task { Capturas.generarSiSePide() }
                #endif
        }
    }
}

struct Pagina: UIViewRepresentable {
    let puente: Puente

    func makeUIView(context: Context) -> WKWebView { puente.vista }
    func updateUIView(_ vista: WKWebView, context: Context) {}
}

@MainActor
final class Puente: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    private(set) var vista: WKWebView!
    private var cargada = false
    private var pendiente: URL?
    private var huella: String?
    private var enLinea = false
    private var guardando = false
    private var sondeo: Timer?

    var activa = true {
        didSet {
            guard activa != oldValue else { return }
            activa ? reanudar() : pausar()
        }
    }

    override init() {
        super.init()
        let ajustes = WKWebViewConfiguration()
        ajustes.userContentController.add(self, name: "flechaDatos")
        ajustes.userContentController.addUserScript(
            WKUserScript(source: "window.__flechaInicial = \(inicial());", injectionTime: .atDocumentStart, forMainFrameOnly: true))

        #if DEBUG
        // Los errores de la página salen en la consola de Xcode.
        ajustes.userContentController.addUserScript(WKUserScript(
            source: "window.addEventListener('error', (e) => window.webkit.messageHandlers.flechaDatos.postMessage({ tipo: 'error', texto: e.message + ' @' + (e.filename || '').split('/').pop() + ':' + e.lineno }));",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #endif

        vista = WKWebView(frame: .zero, configuration: ajustes)
        vista.navigationDelegate = self
        vista.isOpaque = false
        vista.backgroundColor = .clear
        vista.scrollView.backgroundColor = .clear
        vista.scrollView.contentInsetAdjustmentBehavior = .never
        vista.scrollView.bounces = false
        vista.allowsLinkPreview = false
        #if DEBUG
        vista.isInspectable = true
        #endif

        if let pagina = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            vista.loadFileURL(pagina, allowingReadAccessTo: pagina.deletingLastPathComponent())
        }
        reanudar()
    }

    // MARK: estado inicial y mensajes hacia la página

    private func json(_ datos: Data?) -> String {
        datos.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    private var conexionJS: String {
        guard let conexion = Almacen.conexion else { return #"{"servidor":null,"enLinea":false}"# }
        let nombre = (try? JSONEncoder().encode(conexion.legible)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return #"{"servidor":\#(nombre),"enLinea":\#(enLinea)}"#
    }

    private func inicial() -> String {
        #"{"estado":\#(json(Almacen.estadoVigente)),"conexion":\#(conexionJS)}"#
    }

    private func avisar(_ llamada: String, entonces: ((Any?) -> Void)? = nil) {
        guard cargada else { return }
        vista.evaluateJavaScript("window.Flecha && window.Flecha.\(llamada)") { resultado, _ in entonces?(resultado) }
    }

    private func avisarConexion() { avisar("recibirConexion(\(conexionJS))") }

    private func refrescarWidgets() { WidgetCenter.shared.reloadAllTimelines() }

    // MARK: mensajes desde la página

    func userContentController(_ controlador: WKUserContentController, didReceive mensaje: WKScriptMessage) {
        guard let cuerpo = mensaje.body as? [String: Any], let tipo = cuerpo["tipo"] as? String else { return }
        switch tipo {
        case "guardar":
            guard let estado = cuerpo["estado"], JSONSerialization.isValidJSONObject(estado),
                  let datos = try? JSONSerialization.data(withJSONObject: estado)
            else { return }
            guardar(datos)
        case "uso":
            Task { await traerUso() }
        case "conectar":
            pedirEnlace()
        case "desconectar":
            desconectar()
        case "error":
            print("Error en la página:", cuerpo["texto"] ?? "")
        default:
            break
        }
    }

    private func guardar(_ datos: Data) {
        guard let conexion = Almacen.conexion else {
            Almacen.escribir(datos, en: .local)
            refrescarWidgets()
            return
        }
        guardando = true
        Task {
            defer { guardando = false }
            do {
                huella = try await Cliente(conexion: conexion).guardar(datos, huella: huella)
                Almacen.escribir(datos, en: .mac)
                marcar(enLinea: true)
                refrescarWidgets()
            } catch {
                // No llegó a la Mac: se avisa y la página regresa a lo último que sí está guardado.
                avisar("falloGuardar()")
                huella = nil
                await sincronizar(forzar: true)
            }
        }
    }

    // MARK: conexión con la Mac

    private func marcar(enLinea nuevo: Bool) {
        guard nuevo != enLinea else { return }
        enLinea = nuevo
        avisarConexion()
    }

    /// Lee el estado de la Mac y, si cambió, se lo entrega a la página y al widget.
    private func sincronizar(forzar: Bool = false) async {
        guard let conexion = Almacen.conexion, !guardando || forzar else { return }
        do {
            let nuevo = try await Cliente(conexion: conexion).estado(huella: forzar ? nil : huella)
            marcar(enLinea: true)
            guard let nuevo else { return }
            Almacen.escribir(nuevo.datos, en: .mac)
            refrescarWidgets()
            // Si la página aún no carga, no se anota la huella: así la siguiente vuelta se lo entrega.
            guard cargada else { return }
            // La página puede negarse si estás escribiendo; entonces se reintenta en la siguiente vuelta.
            avisar("recibir(\(json(nuevo.datos)))") { [weak self] aceptado in
                if (aceptado as? Bool) != false { self?.huella = nuevo.huella }
            }
        } catch {
            marcar(enLinea: false)
            if forzar, let ultimo = Almacen.leer(.mac) { avisar("recibir(\(json(ultimo)))") }
        }
    }

    private func traerUso() async {
        guard let conexion = Almacen.conexion else { return avisar("recibirUso(null)") }
        if let datos = try? await Cliente(conexion: conexion).uso() {
            Almacen.escribir(datos, en: .uso)
            refrescarWidgets()
        }
        avisar("recibirUso(\(json(Almacen.leer(.uso))))")
    }

    private func reanudar() {
        sondeo?.invalidate()
        guard Almacen.conexion != nil else { return }
        Task { await sincronizar() }
        sondeo = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sincronizar() }
        }
    }

    private func pausar() {
        sondeo?.invalidate()
        sondeo = nil
    }

    private func pedirEnlace() {
        let alerta = UIAlertController(
            title: texto("Conectar con tu Mac", "Connect to your Mac"),
            message: texto(
                "En tu Mac corre ./flecha --red y pega aquí el enlace que imprime. Los dos deben estar en la misma red wifi.",
                "On your Mac run ./flecha --red and paste the link it prints. Both devices must be on the same Wi-Fi."),
            preferredStyle: .alert)
        alerta.addTextField { campo in
            campo.placeholder = "http://192.168.1.5:4747/?clave=…"
            campo.keyboardType = .URL
            campo.autocapitalizationType = .none
            campo.autocorrectionType = .no
            campo.clearButtonMode = .whileEditing
            if let pegado = UIPasteboard.general.string, pegado.contains("clave="), Conexion(enlace: pegado) != nil {
                campo.text = pegado
            }
        }
        alerta.addAction(UIAlertAction(title: texto("Cancelar", "Cancel"), style: .cancel))
        alerta.addAction(UIAlertAction(title: texto("Conectar", "Connect"), style: .default) { [weak self, weak alerta] _ in
            self?.conectar(alerta?.textFields?.first?.text ?? "")
        })
        presentar(alerta)
    }

    private func conectar(_ enlace: String) {
        guard let conexion = Conexion(enlace: enlace) else {
            return informar(texto("Ese enlace no parece de Flecha.", "That doesn't look like a Flecha link."))
        }
        Task {
            do {
                guard let primero = try await Cliente(conexion: conexion).estado() else { return }
                Almacen.conexion = conexion
                Almacen.escribir(primero.datos, en: .mac)
                huella = primero.huella
                enLinea = true
                avisarConexion()
                avisar("recibir(\(json(primero.datos)))")
                await traerUso()
                refrescarWidgets()
                reanudar()
            } catch Cliente.Falla.rechazado(401) {
                informar(texto("La clave del enlace no es correcta.", "The key in the link is not correct."))
            } catch {
                informar(texto(
                    "No encontré tu Mac. Revisa que ./flecha --red esté corriendo y que los dos estén en la misma red.",
                    "Couldn't find your Mac. Check that ./flecha --red is running and both devices share the network."))
            }
        }
    }

    private func desconectar() {
        pausar()
        Almacen.conexion = nil
        Almacen.borrar(.mac)
        Almacen.borrar(.uso)
        huella = nil
        enLinea = false
        avisarConexion()
        avisar("recibir(\(json(Almacen.leer(.local))))")
        refrescarWidgets()
    }

    private func informar(_ mensaje: String) {
        let alerta = UIAlertController(title: nil, message: mensaje, preferredStyle: .alert)
        alerta.addAction(UIAlertAction(title: "OK", style: .default))
        presentar(alerta)
    }

    private func presentar(_ alerta: UIAlertController) {
        let escena = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var arriba = escena?.keyWindow?.rootViewController
        while let siguiente = arriba?.presentedViewController { arriba = siguiente }
        arriba?.present(alerta, animated: true)
    }

    // MARK: enlaces del widget (flecha://proyecto/<id>, flecha://uso, flecha://abrir)

    func abrir(_ url: URL) {
        guard cargada else {
            pendiente = url
            return
        }
        switch url.host {
        case "proyecto":
            let id = url.pathComponents.dropFirst().first ?? ""
            let seguro = (try? JSONEncoder().encode(id)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
            avisar("abrirProyecto(\(seguro))")
        case "uso":
            avisar("abrirUso()")
        default:
            avisar("abrir()")
        }
    }

    func webView(_ vista: WKWebView, didFinish navegacion: WKNavigation!) {
        cargada = true
        Task { await sincronizar(forzar: true) }
        // La página arranca sola; se espera un momento a que termine para entregarle el enlace.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            if let url = self.pendiente {
                self.pendiente = nil
                self.abrir(url)
            }
            if CommandLine.arguments.contains("--abierto") { self.avisar("abrir()") }
            if CommandLine.arguments.contains("--uso") { self.avisar("abrirUso()") }
        }
    }

    // Los enlaces externos se abren en Safari, no dentro de la app.
    func webView(_ vista: WKWebView, decidePolicyFor accion: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = accion.request.url, !url.isFileURL, accion.navigationType == .linkActivated {
            UIApplication.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }
}
