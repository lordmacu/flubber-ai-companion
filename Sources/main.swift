import Cocoa
import UserNotifications
import ServiceManagement

// ============================================================================
// SlimePet — mascota slime pixel-art + Tamagotchi para macOS.
// Arte 100% por código. Tiene necesidades (hambre, felicidad, energía,
// limpieza, salud) que decaen en tiempo real; come, juega, se baña, toma
// medicina, duerme, hace popó, crece (huevo→bebé→niño→adulto), enferma y
// puede morir. HUD de barras + botones flotantes al pasar el mouse.
// ============================================================================

// MARK: - Paleta de color

struct Skin { let body, bodyDark, bodyLight, shine: NSColor }

enum Pal {
    static var skins: [Skin] = [
        Skin(body:      NSColor(srgbRed: 0.36, green: 0.85, blue: 0.55, alpha: 1),  // verde
             bodyDark:  NSColor(srgbRed: 0.20, green: 0.62, blue: 0.40, alpha: 1),
             bodyLight: NSColor(srgbRed: 0.62, green: 0.96, blue: 0.72, alpha: 1),
             shine:     NSColor(srgbRed: 0.92, green: 1.00, blue: 0.95, alpha: 1)),
        Skin(body:      NSColor(srgbRed: 0.42, green: 0.66, blue: 0.98, alpha: 1),  // azul
             bodyDark:  NSColor(srgbRed: 0.24, green: 0.42, blue: 0.78, alpha: 1),
             bodyLight: NSColor(srgbRed: 0.68, green: 0.84, blue: 1.00, alpha: 1),
             shine:     NSColor(srgbRed: 0.94, green: 0.98, blue: 1.00, alpha: 1)),
        Skin(body:      NSColor(srgbRed: 0.78, green: 0.55, blue: 0.96, alpha: 1),  // morado
             bodyDark:  NSColor(srgbRed: 0.55, green: 0.34, blue: 0.74, alpha: 1),
             bodyLight: NSColor(srgbRed: 0.90, green: 0.76, blue: 1.00, alpha: 1),
             shine:     NSColor(srgbRed: 0.99, green: 0.96, blue: 1.00, alpha: 1)),
        Skin(body:      NSColor(srgbRed: 0.99, green: 0.62, blue: 0.78, alpha: 1),  // rosa
             bodyDark:  NSColor(srgbRed: 0.85, green: 0.40, blue: 0.58, alpha: 1),
             bodyLight: NSColor(srgbRed: 1.00, green: 0.80, blue: 0.89, alpha: 1),
             shine:     NSColor(srgbRed: 1.00, green: 0.96, blue: 0.98, alpha: 1)),
    ]
    static var index = 0
    static var skin: Skin { skins[min(index, skins.count - 1)] }

    /// Aplica un skin generado por IA en un único "slot" (índice 4) y lo activa.
    static func setAISkin(_ s: Skin) {
        if skins.count > 4 { skins[4] = s } else { skins.append(s) }
        index = 4
    }

    /// NSColor desde hex "#RRGGBB".
    static func color(_ hex: String) -> NSColor? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xff)/255, green: CGFloat((v >> 8) & 0xff)/255,
                       blue: CGFloat(v & 0xff)/255, alpha: 1)
    }
    static func skin(from spec: SkinSpec) -> Skin? {
        guard let b = color(spec.body), let d = color(spec.dark),
              let l = color(spec.light), let s = color(spec.shine) else { return nil }
        return Skin(body: b, bodyDark: d, bodyLight: l, shine: s)
    }

    static let ghost = Skin(body:      NSColor(white: 0.82, alpha: 0.85),
                            bodyDark:  NSColor(white: 0.55, alpha: 0.85),
                            bodyLight: NSColor(white: 0.95, alpha: 0.85),
                            shine:     NSColor(white: 1.00, alpha: 0.9))
    static let sick = Skin(body:      NSColor(srgbRed: 0.62, green: 0.74, blue: 0.45, alpha: 1),
                           bodyDark:  NSColor(srgbRed: 0.42, green: 0.54, blue: 0.30, alpha: 1),
                           bodyLight: NSColor(srgbRed: 0.78, green: 0.86, blue: 0.60, alpha: 1),
                           shine:     NSColor(srgbRed: 0.90, green: 0.95, blue: 0.80, alpha: 1))

    static let eye      = NSColor(srgbRed: 0.10, green: 0.16, blue: 0.18, alpha: 1)
    static let eyeWhite = NSColor.white
    static let mouth    = NSColor(srgbRed: 0.15, green: 0.40, blue: 0.28, alpha: 1)
    static let blush    = NSColor(srgbRed: 1.00, green: 0.62, blue: 0.62, alpha: 0.55)
    static let heart    = NSColor(srgbRed: 1.00, green: 0.36, blue: 0.52, alpha: 1)
    static let note     = NSColor(srgbRed: 0.30, green: 0.50, blue: 0.95, alpha: 1)
    static let star     = NSColor(srgbRed: 1.00, green: 0.85, blue: 0.25, alpha: 1)
    static let poop     = NSColor(srgbRed: 0.45, green: 0.30, blue: 0.15, alpha: 1)
    static let sweat    = NSColor(srgbRed: 0.55, green: 0.80, blue: 1.00, alpha: 1)
    static let bubble   = NSColor(srgbRed: 0.75, green: 0.92, blue: 1.00, alpha: 0.95)
    static let crumb    = NSColor(srgbRed: 0.60, green: 0.40, blue: 0.20, alpha: 1)
    static let halo     = NSColor(srgbRed: 1.00, green: 0.88, blue: 0.35, alpha: 1)
    static let egg1     = NSColor(srgbRed: 0.96, green: 0.93, blue: 0.84, alpha: 1)
    static let egg2     = NSColor(srgbRed: 0.85, green: 0.80, blue: 0.68, alpha: 1)

    // colores de barras de stats
    static let barHunger = NSColor(srgbRed: 1.00, green: 0.60, blue: 0.25, alpha: 1)
    static let barHappy  = heart
    static let barEnergy = NSColor(srgbRed: 1.00, green: 0.82, blue: 0.20, alpha: 1)
    static let barClean  = NSColor(srgbRed: 0.40, green: 0.78, blue: 1.00, alpha: 1)
    static let barHealth = NSColor(srgbRed: 0.40, green: 0.85, blue: 0.50, alpha: 1)
}

// MARK: - Estados de animación

enum PetState {
    case idle, looking, walking, dragging, falling, reacting
    case happy, chasing, dancing, rolling, dizzy, yawning, sleeping
    case eating, bathing, takingMedicine    // acciones de cuidado
    case egg, hatching, dead                 // ciclo de vida
    case stuckWall                           // pegado a un costado, escurriéndose
    case wiggling, stretching                // animaciones espontáneas (contoneo / estirarse)
}

// MARK: - Partículas

struct Particle {
    var x, y, vx, vy, life: CGFloat
    var kind: Int   // 0 corazón,1 nota,2 estrella,3 Z,4 sudor,5 mosca,6 burbuja,7 miga,8 chispa
}

// MARK: - Botón del HUD

struct HudButton { let id: String; let icon: String; var rect: NSRect }

// MARK: - Vista de la mascota

final class PetView: NSView {

    let GW = 32, GH = 32
    let PX: CGFloat = 4                                   // tamaño de cada pixel del slime
    var slimeOX: CGFloat { (bounds.width - CGFloat(GW) * PX) / 2 }

    // estado de animación
    var state: PetState = .egg
    var tick = 0, stateTimer = 0, idleFrames = 0
    var facing: CGFloat = 1

    // física
    var vx: CGFloat = 0, vy: CGFloat = 0
    var walkSpeed: CGFloat = 1.4
    var targetX: CGFloat = 0
    var wallSide: CGFloat = 0      // -1 izquierda, +1 derecha (al escurrirse)

    // ojos
    var blinkUntil = 0
    var lookX: CGFloat = 0, lookY: CGFloat = 0
    var lookTX: CGFloat = 0, lookTY: CGFloat = 0
    var lookChanges = 0

    // input
    var dragOffset: NSPoint = .zero
    var mouseDownAt: NSPoint = .zero
    var didDrag = false
    var consumedByButton = false
    var grabbedSlime = false        // el mousedown empezó sobre el cuerpo del slime
    var loveClicks = 0, lastClickTick = -999

    // partículas / squash
    var particles: [Particle] = []
    var squashLanding: CGFloat = 0
    var eatingFood: Food = .meat

    // Tamagotchi
    var stats = PetStats()

    // IA / diálogo
    var client: AIBackend?
    var convo: [(String, String)] = []          // historial de chat (role, content)
    var bubbleText: String? = nil
    var bubbleUntil = Date.distantPast
    var bubbleThinking = false
    var lastSpontaneous = Date.distantPast
    var lastClickTalk = Date.distantPast
    var onChatRequested: (() -> Void)?
    var onToggleListen: (() -> Void)?
    var listening = false                 // escuchando la reunión (para el indicador 👂)

    // chat integrado (panel pixel sobre el slime)
    var chatActive = false
    var chatStore = ConversationStore.load()
    var convIndex = 0
    var chatInput = ""
    var chatScroll: CGFloat = 0
    var chatBusy = false
    var listOpen = false
    var stepLines: [String] = []        // pasos de herramienta efímeros (no se guardan)
    var agent: Agent?
    var chatButtons: [HudButton] = []   // botones del panel (close/new/list)
    var listRowRects: [NSRect] = []     // filas de la lista de conversaciones
    var chatStick = true                // pegado al fondo (autoscroll)
    var chatScrollToBottom = false      // al abrir/cambiar de conversación: salta al final absoluto
    // --- escucha de reunión: resúmenes rodantes por lotes ---
    var meetingConvId: String? = nil           // conversación dedicada (se crea al vuelo, nueva por sesión)
    var meetingSummarizedLen = 0               // cuánto transcript ya se resumió
    var meetingRollingSummaries: [String] = [] // mini-resúmenes acumulados
    var meetingRollTimer: Timer?               // dispara un mini-resumen cada X tiempo
    var meetingStartedAt = Date()              // para decidir si fue "reunión" (>1 min) o "charla"
    static let meetingThreshold: TimeInterval = 60   // ≥60s = reunión; si no, charla
    var chatContentH: CGFloat = 0       // alto del contenido (para clamping del scroll)
    var chatAreaH: CGFloat = 0
    var chatMouse: NSPoint = .zero       // posición del mouse dentro del chat (para hover)
    var copyButtons: [(rect: NSRect, text: String)] = []
    var pendingShot: String? = nil       // captura de pantalla lista para adjuntar
    var pendingShotPath: String? = nil   // ruta del PNG de esa captura
    var thumbRects: [(rect: NSRect, path: String)] = []
    var fileButtons: [(rect: NSRect, path: String)] = []   // links clicables a archivos (transcripción)
    var imgCache: [String: NSImage] = [:]
    var attrCache: [String: NSAttributedString] = [:]   // markdown renderizado (cache)
    var sendRect: NSRect = .zero                         // botón de enviar (flechita)
    var detachRect: NSRect = .zero                       // chip de captura adjunta (clic = quitar)
    var streamLive: String? = nil                        // texto que llega en streaming (token a token)
    var inputFont: NSFont { NSFont.systemFont(ofSize: 12) }
    var chatActivity = 0                  // 0 pensando, 1 buscando, 2 mirando pantalla
    var turnT: CGFloat = 0               // 0 de frente .. 1 de espaldas (mirando la pantalla)
    var lookingAtScreen: Bool { chatActive && chatBusy && chatActivity == 2 }
    var talking: Bool { chatActive && chatBusy && !(streamLive ?? "").isEmpty }   // hablando (texto llegando)
    var chatOpen: Bool { chatActive }   // mientras chateamos, no deambula

    // gesto de "frotar" para lavar
    var lastScrubX: CGFloat = 0
    var scrubDir = 0
    var scrubCount = 0
    var lastScrubTime = Date.distantPast

    // HUD
    var hovering = false
    var hudAlpha: CGFloat = 0
    var buttons: [HudButton] = []
    var trackingArea: NSTrackingArea?

    weak var petWindow: PetWindow?
    override var isFlipped: Bool { false }

    // ------------------------------------------------------------------
    // Tracking del mouse para mostrar/ocultar el HUD
    // ------------------------------------------------------------------
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent)  { hovering = false; scrubDir = 0; scrubCount = 0 }

    /// Detecta el gesto de frotar (vaivén horizontal) sobre el slime → lavarlo.
    override func mouseMoved(with event: NSEvent) {
        if chatActive {
            chatMouse = convert(event.locationInWindow, from: nil)
            needsDisplay = true
            return
        }
        guard !stats.isDead, state != .egg else { return }
        let x = event.locationInWindow.x
        let dx = x - lastScrubX
        lastScrubX = x
        guard abs(dx) > 3 else { return }
        let dir = dx > 0 ? 1 : -1
        let now = Date()
        if scrubDir != 0 && dir != scrubDir {                 // hubo un cambio de dirección
            if now.timeIntervalSince(lastScrubTime) < 1.2 { scrubCount += 1 } else { scrubCount = 1 }
            lastScrubTime = now
            if scrubCount >= 4 {                              // suficientes vaivenes → ¡a lavar!
                scrubCount = 0
                if stats.poops > 0 || stats.cleanliness < 0.99 { doClean() }
            }
        }
        scrubDir = dir
    }

    // ------------------------------------------------------------------
    // Bucle por frame. realDt = segundos reales transcurridos.
    // ------------------------------------------------------------------
    func advance(realDt: TimeInterval) -> [PetEvent] {
        let events = stats.tick(dt: realDt)
        for e in events {
            switch e {
            case .hatched: enter(.hatching)
            case .died:    enter(.dead)
            default: break
            }
        }
        // sincroniza el estado visual con la vida
        if stats.isDead {
            if state != .dead { enter(.dead) }
        } else if stats.stage == .egg {
            if state != .egg { enter(.egg) }
        } else if state == .egg {
            enter(.idle)                       // por si carga directo ya nacido
        } else {
            if stats.isAsleep && interruptible() && state != .sleeping { enter(.sleeping) }
            if !stats.isAsleep && state == .sleeping { enter(.idle) }
        }

        tick += 1; stateTimer += 1
        // HUD fade
        let target: CGFloat = hovering ? 1.0 : (stats.needsAttention && !stats.isDead ? 0.55 : 0.0)
        hudAlpha += (target - hudAlpha) * 0.2

        update()
        ambientFx()
        updateParticles()
        needsDisplay = true
        return events
    }

    func interruptible() -> Bool {
        ![.eating, .bathing, .takingMedicine, .hatching, .dragging, .falling, .stuckWall].contains(state)
    }

    /// Rango de origin.x para que el CUERPO del slime no salga de la pantalla.
    func originXBounds(_ vf: NSRect) -> (CGFloat, CGFloat) {
        (vf.minX - slimeOX, vf.maxX - bounds.width + slimeOX)
    }

    func ambientFx() {
        guard !stats.isDead, stats.stage != .egg else { return }
        if stats.isSick && tick % 28 == 0 { spawn(kind: 4, n: 1, at: CGPoint(x: 22, y: 20)) }   // sudor
        if stats.poops > 0 && stats.cleanliness < 0.6 && tick % 24 == 0 {
            spawn(kind: 5, n: 1, at: CGPoint(x: 25, y: 3))                                       // mosca
        }
    }

    // ------------------------------------------------------------------
    // Máquina de estados (movimiento + acciones)
    // ------------------------------------------------------------------
    func update() {
        guard let win = petWindow, let screen = win.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let floor = vf.minY

        lookX += (lookTX - lookX) * 0.25
        lookY += (lookTY - lookY) * 0.25

        // giro hacia la pantalla cuando la mira
        turnT += ((lookingAtScreen ? 1 : 0) - turnT) * 0.15

        // animación de "trabajando" (funciona en cualquier estado)
        if chatActive && chatBusy {
            if chatActivity == 1 {       // buscando: ojos escanean
                if stateTimer % 10 == 0 { lookTX = CGFloat(Int.random(in: -1...1)); lookTY = CGFloat(Int.random(in: -1...1)) }
            } else {                     // mirando/pensando: mira arriba
                lookTX = 0; lookTY = 1
            }
        }

        switch state {

        case .egg:
            // el huevo solo se bambolea; cerca de eclosionar tiembla más
            break

        case .hatching:
            if stateTimer > 45 { enter(.idle) }

        case .dead:
            break

        case .eating:
            if stateTimer % 12 == 0 { spawn(kind: 7, n: 2, at: CGPoint(x: 16, y: 11)) }  // migas
            if stateTimer > 55 { enter(.idle) }

        case .bathing:
            if stateTimer % 6 == 0 { spawn(kind: 6, n: 1, at: CGPoint(x: 16, y: 12)) }   // burbujas
            if stateTimer > 55 { enter(.idle) }

        case .takingMedicine:
            if stateTimer == 6 { spawn(kind: 8, n: 6, at: CGPoint(x: 16, y: 14)) }       // chispas
            if stateTimer > 40 { enter(.idle) }

        case .idle:
            idleFrames += 1
            if chatActive && chatBusy {                      // animación según la acción
                if chatActivity == 1 {                       // buscando: ojos escanean
                    if stateTimer % 10 == 0 { lookTX = CGFloat(Int.random(in: -1...1)); lookTY = CGFloat(Int.random(in: -1...1)) }
                } else { lookTX = 0; lookTY = 1 }            // mirando/pensando: mira arriba
            } else {
                lookAtMouse(win)
            }
            // si el mouse está encima, el chat abierto o está escuchando, se queda quieto y atento.
            // Variedad de animaciones espontáneas según ánimo/energía.
            if stateTimer > 50 && !hovering && !chatOpen && !listening {
                switch Int.random(in: 0..<150) {
                case 0..<3:  if stats.energy > 0.3 { startWalking(in: screen) }      // pasear
                case 3:      if stats.mood > 0.6 { enter(.dancing) }                 // bailar
                case 4...6:  enter(.looking)                                         // mirar alrededor
                case 7:      enter(.wiggling)                                        // contonearse
                case 8:      if stats.energy < 0.55 { enter(.stretching) }           // estirarse
                case 9:      if stats.energy > 0.4 { enter(.rolling) }               // rodar
                case 10:     if stats.mood > 0.7 { enter(.happy) }                   // brincar contento
                case 11:     if stats.mood > 0.5 { enter(.chasing) }                 // perseguir el cursor
                default:     break
                }
            }
            maybeBlink()

        case .looking:
            if stateTimer % 22 == 0 {
                lookTX = CGFloat(Int.random(in: -1...1)); lookTY = CGFloat(Int.random(in: -1...1)); lookChanges += 1
            }
            if lookChanges > 3 { lookTX = 0; lookTY = 0; lookChanges = 0; enter(.idle) }
            maybeBlink()

        case .walking:
            idleFrames = 0
            if hovering || chatOpen { enter(.idle); break }   // no camina al hover o con el chat abierto
            var f = win.frame
            f.origin.x += vx
            let (minX, maxX) = originXBounds(vf)
            if f.origin.x < minX { f.origin.x = minX; flip() }
            if f.origin.x > maxX { f.origin.x = maxX; flip() }
            win.setFrameOrigin(f.origin)
            lookAtMouse(win)
            if abs(f.origin.x - targetX) < 4 || stateTimer > 240 { enter(.idle) }
            maybeBlink()

        case .chasing:
            idleFrames = 0
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - win.frame.midX
            facing = dx >= 0 ? 1 : -1
            lookTX = facing; lookTY = 0.4
            var f = win.frame
            f.origin.x += max(-5, min(5, dx * 0.12))
            f.origin.y = floor + abs(sin(CGFloat(stateTimer) * 0.4)) * 10
            let (cminX, cmaxX) = originXBounds(vf)
            f.origin.x = max(cminX, min(cmaxX, f.origin.x))
            win.setFrameOrigin(f.origin)
            if abs(dx) < 20 && abs(mouse.y - f.midY) < 120 { f.origin.y = floor; win.setFrameOrigin(f.origin); enter(.happy) }
            if stateTimer > 300 { var g = win.frame; g.origin.y = floor; win.setFrameOrigin(g.origin); enter(.idle) }

        case .dancing:
            idleFrames = 0
            var f = win.frame
            f.origin.x += sin(CGFloat(stateTimer) * 0.25) * 2.2
            f.origin.y = floor + abs(sin(CGFloat(stateTimer) * 0.5)) * 6
            f.origin.x = max(vf.minX, min(vf.maxX - bounds.width, f.origin.x))
            facing = sin(CGFloat(stateTimer) * 0.25) >= 0 ? 1 : -1
            win.setFrameOrigin(f.origin)
            if stateTimer % 16 == 0 { spawn(kind: 1, n: 1) }
            if stateTimer > 200 { var g = win.frame; g.origin.y = floor; win.setFrameOrigin(g.origin); enter(.idle) }

        case .rolling:
            idleFrames = 0
            var f = win.frame
            f.origin.x += vx
            let (minX, maxX) = originXBounds(vf)
            if f.origin.x <= minX || f.origin.x >= maxX { vx = -vx; facing = -facing }
            f.origin.x = max(minX, min(maxX, f.origin.x))
            f.origin.y = floor + abs(sin(CGFloat(stateTimer) * 0.5)) * 8
            win.setFrameOrigin(f.origin)
            if stateTimer > 150 { var g = win.frame; g.origin.y = floor; win.setFrameOrigin(g.origin); enter(.dizzy) }

        case .dizzy:
            idleFrames = 0
            if stateTimer % 10 == 0 { spawn(kind: 2, n: 1) }
            if stateTimer > 75 { enter(.idle) }

        case .happy:
            idleFrames = 0
            vy -= 1.4
            var f = win.frame
            f.origin.y += vy
            if f.origin.y <= floor {
                f.origin.y = floor
                if stateTimer < 90 { vy = 8; squashLanding = 0.6 } else { vy = 0 }
            }
            win.setFrameOrigin(f.origin)
            if stateTimer % 8 == 0 { spawn(kind: 0, n: 1) }
            if stateTimer > 90 && win.frame.minY <= floor + 0.5 { enter(.idle) }

        case .dragging:
            idleFrames = 0

        case .falling:
            vy -= 1.6
            var f = win.frame
            f.origin.y += vy; f.origin.x += vx; vx *= 0.96
            let (fminX, fmaxX) = originXBounds(vf)
            f.origin.x = max(fminX, min(fmaxX, f.origin.x))
            if f.origin.y <= floor {
                f.origin.y = floor; win.setFrameOrigin(f.origin); vy = 0; vx = 0; squashLanding = 1.0; enter(.idle)
            } else { win.setFrameOrigin(f.origin) }

        case .stuckWall:
            // pegado al costado; se escurre hacia abajo con viscosidad
            idleFrames = 0
            vy -= 0.18                                   // gravedad lenta (viscoso)
            vy = max(vy, -3.2)                           // velocidad de escurrido limitada
            var f = win.frame
            let (wminX, wmaxX) = originXBounds(vf)
            f.origin.x = wallSide < 0 ? wminX : wmaxX    // se mantiene hugueado a la pared
            f.origin.y += vy
            if f.origin.y <= floor {
                f.origin.y = floor; win.setFrameOrigin(f.origin)
                vy = 0; squashLanding = 0.8; wallSide = 0; enter(.idle)
            } else {
                win.setFrameOrigin(f.origin)
                if stateTimer % 16 == 0 { spawn(kind: 6, n: 1, at: CGPoint(x: 16, y: 4)) }  // gotita que gotea
            }

        case .reacting:
            vy -= 1.6
            var f = win.frame
            f.origin.y += vy
            if f.origin.y <= floor {
                f.origin.y = floor; win.setFrameOrigin(f.origin); vy = 0; squashLanding = 1.0; enter(.idle)
            } else { win.setFrameOrigin(f.origin) }

        case .yawning:
            if stateTimer > 40 { enter(.sleeping) }

        case .sleeping:
            idleFrames += 1
            if stateTimer % 26 == 0 { spawn(kind: 3, n: 1) }

        case .wiggling:
            // contoneo en el sitio; ojos felices
            if stateTimer == 4 { spawn(kind: 0, n: 1) }     // un corazoncito
            if stateTimer > 38 { enter(.idle) }

        case .stretching:
            // estirarse como gato y volver
            if stateTimer > 42 { enter(.idle) }
        }

        if squashLanding > 0 { squashLanding = max(0, squashLanding - 0.08) }
    }

    func enter(_ s: PetState) {
        // con el chat abierto no permitir estados que MUEVAN la ventana (mueven el diálogo)
        if chatActive, [.dancing, .walking, .rolling, .chasing, .happy, .reacting, .falling].contains(s) { return }
        // animarse despierta al slime
        if [.dancing, .walking, .rolling, .chasing, .happy].contains(s) { wakeUp() }
        state = s
        stateTimer = 0
        if s == .idle { idleFrames = 0 }
        if s == .looking { lookChanges = 0 }
        if s == .rolling { vx = 4.5 * facing }
    }

    func startWalking(in screen: NSScreen) {
        let vf = screen.visibleFrame
        targetX = CGFloat.random(in: vf.minX...(vf.maxX - bounds.width))
        guard let win = petWindow else { return }
        facing = targetX > win.frame.origin.x ? 1 : -1
        vx = walkSpeed * facing
        enter(.walking)
    }

    func flip() {
        facing *= -1; vx = walkSpeed * facing
        if let screen = petWindow?.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            targetX = facing > 0 ? vf.maxX - bounds.width : vf.minX
        }
    }

    func maybeBlink() { if tick > blinkUntil && Int.random(in: 0..<100) < 2 { blinkUntil = tick + 6 } }
    var isBlinking: Bool { tick < blinkUntil }

    func lookAtMouse(_ win: PetWindow) {
        let m = NSEvent.mouseLocation
        let dx = m.x - win.frame.midX, dy = m.y - (win.frame.minY + 40)
        lookTX = abs(dx) < 12 ? 0 : (dx > 0 ? 1 : -1)
        lookTY = abs(dy) < 12 ? 0 : (dy > 0 ? 1 : -1)
    }

    // ------------------------------------------------------------------
    // Acciones de cuidado (las llaman los botones / menú)
    // ------------------------------------------------------------------
    func doFeed(_ food: Food) { wakeUp(); guard stats.stage != .egg, !stats.isDead else { return }; stats.feed(food); eatingFood = food; enter(.eating) }
    func doPlay()    { wakeUp(); guard stats.stage != .egg, !stats.isDead, !stats.isAsleep else { return }; stats.play(); enter(.happy) }
    func doClean()   { wakeUp(); guard !stats.isDead else { return }; stats.clean(); enter(.bathing) }
    func doMedicine(){ wakeUp(); guard !stats.isDead else { return }; let was = stats.isSick; stats.medicine(); if was { enter(.takingMedicine) } }
    func doSleep()   { guard stats.stage != .egg, !stats.isDead else { return }; stats.toggleSleep() }
    func doRestart() { stats.restart(); enter(.egg) }

    // ------------------------------------------------------------------
    // Partículas
    // ------------------------------------------------------------------
    func spawn(kind: Int, n: Int, at p: CGPoint? = nil) {
        let base = p ?? CGPoint(x: CGFloat(GW)/2, y: CGFloat(GH) * 0.6)
        for _ in 0..<n {
            let spread: CGFloat = kind == 2 ? 0.6 : 0.2
            particles.append(Particle(
                x: base.x + CGFloat.random(in: -3...3),
                y: base.y,
                vx: CGFloat.random(in: -spread...spread),
                vy: kind == 7 ? CGFloat.random(in: -0.5 ... -0.2)            // migas caen
                    : kind == 5 ? CGFloat.random(in: -0.15...0.15)          // moscas flotan
                    : kind == 3 ? 0.45
                    : CGFloat.random(in: 0.4...0.7),
                life: 1.0, kind: kind))
        }
    }
    func updateParticles() {
        for i in particles.indices {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            if particles[i].kind == 5 {                                    // moscas: zigzag
                particles[i].x += sin(CGFloat(tick) * 0.4 + particles[i].y) * 0.3
                particles[i].life -= 0.01
            } else {
                particles[i].life -= 0.018
            }
        }
        particles.removeAll { $0.life <= 0 || $0.y > CGFloat(GH) + 2 || $0.y < -2 }
    }

    // ------------------------------------------------------------------
    // DIBUJO
    // ------------------------------------------------------------------
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.interpolationQuality = .none

        if state == .egg || state == .hatching {
            drawEgg(ctx)
        } else if stats.isDead {
            drawGhost(ctx)
        } else {
            drawSlime(ctx, scaleX: bodyScaleX(), scaleY: bodyScaleY())
            drawPoops(ctx)
        }
        drawParticles(ctx)
        if chatActive {
            drawChat(ctx)      // panel de conversación pixel sobre el slime
        } else {
            drawBubble(ctx)    // el globo/animación nace por detrás…
            drawHUD(ctx)       // …y los botones quedan al frente
        }
    }

    func bodyScaleX() -> CGFloat {
        var sx: CGFloat = 1
        switch state {
        case .walking:  sx = 1 - abs(sin(CGFloat(stateTimer)*0.35))*0.10
        case .happy, .chasing: sx = 1 - abs(sin(CGFloat(stateTimer)*0.4))*0.12
        case .dancing:  sx = 1 - abs(sin(CGFloat(stateTimer)*0.5))*0.08
        case .rolling:  sx = 1 + sin(CGFloat(stateTimer)*0.5)*0.18
        case .eating:   sx = 1 + abs(sin(CGFloat(stateTimer)*0.6))*0.10
        case .dizzy:    sx = 1.05
        case .dragging: sx = 0.86
        case .falling:  sx = 0.88
        case .stuckWall: sx = 0.74 + sin(CGFloat(tick)*0.3)*0.03   // aplastado contra la pared
        case .reacting: sx = 0.92
        case .yawning:  sx = 1 - min(1,CGFloat(stateTimer)/20)*0.12
        case .wiggling: sx = 1 + sin(CGFloat(stateTimer)*0.6)*0.06
        case .stretching:                                    // se estira hacia arriba (se adelgaza)
            let p = sin(min(1, CGFloat(stateTimer)/42) * .pi)
            sx = 1 - p*0.18
        default:        sx = 1 + sin(CGFloat(tick)*0.08)*0.04
        }
        if chatActive && chatBusy {
            switch chatActivity {
            case 1: sx = 1 - abs(sin(CGFloat(tick)*0.32))*0.10    // buscando: rebote
            case 2: sx = max(0.12, abs(cos(turnT * .pi)))         // mirando: se gira hacia la pantalla
            default: sx = 1 + sin(CGFloat(tick)*0.2)*0.08         // pensando: pulsa
            }
        }
        return (sx + squashLanding*0.30) * CGFloat(stats.sizeScale)
    }
    func bodyScaleY() -> CGFloat {
        var sy: CGFloat = 1
        switch state {
        case .walking:  sy = 1 + abs(sin(CGFloat(stateTimer)*0.35))*0.12
        case .happy, .chasing: sy = 1 + abs(sin(CGFloat(stateTimer)*0.4))*0.14
        case .dancing:  sy = 1 + abs(sin(CGFloat(stateTimer)*0.5))*0.10
        case .rolling:  sy = 1 - sin(CGFloat(stateTimer)*0.5)*0.18
        case .eating:   sy = 1 - abs(sin(CGFloat(stateTimer)*0.6))*0.08
        case .dizzy:    sy = 0.95
        case .dragging: sy = 1.18
        case .falling:  sy = 1.14
        case .stuckWall: sy = 1.30                                  // estirado verticalmente al escurrir
        case .reacting: sy = 1.10
        case .yawning:  sy = 1 + min(1,CGFloat(stateTimer)/20)*0.20
        case .wiggling: sy = 1 - sin(CGFloat(stateTimer)*0.6)*0.05
        case .stretching:                                    // se estira hacia arriba
            let p = sin(min(1, CGFloat(stateTimer)/42) * .pi)
            sy = 1 + p*0.28
        default:        sy = 1 - sin(CGFloat(tick)*0.08)*0.04
        }
        if chatActive && chatBusy {
            switch chatActivity {
            case 1: sy = 1 + abs(sin(CGFloat(tick)*0.32))*0.10    // buscando: rebote
            case 2: sy = 1.10 + sin(CGFloat(tick)*0.2)*0.05       // mirando: bobeo atento
            default: sy = 1 - sin(CGFloat(tick)*0.2)*0.08         // pensando: pulsa
            }
        }
        return (sy - squashLanding*0.35) * CGFloat(stats.sizeScale)
    }

    func fill(_ ctx: CGContext, _ gx: Int, _ gy: Int, _ c: NSColor) {
        guard gx >= 0, gx < GW, gy >= 0, gy < GH else { return }
        ctx.setFillColor(c.cgColor)
        ctx.fill(CGRect(x: slimeOX + CGFloat(gx) * PX, y: CGFloat(gy) * PX, width: PX + 0.5, height: PX + 0.5))
    }

    // Expresión según el ánimo (para estados tranquilos)
    enum Expr { case normal, sad, sick }
    var expr: Expr {
        if stats.isSick { return .sick }
        if stats.hunger < 0.25 || stats.mood < 0.4 { return .sad }
        return .normal
    }

    func drawSlime(_ ctx: CGContext, scaleX: CGFloat, scaleY: CGFloat) {
        let skin = stats.isSick ? Pal.sick : Pal.skin
        let baseHalf: CGFloat = 11, baseHeight: CGFloat = 17
        let halfW = baseHalf * scaleX, height = baseHeight * scaleY
        let cx = CGFloat(GW) / 2 + bodyOffsetX()
        let footY = 3
        let jig: CGFloat = [.walking, .falling, .rolling, .chasing].contains(state) ? 2.0 : 1.0

        for gy in 0..<max(1, Int(height)) {
            let t = CGFloat(gy) / height
            var w = halfW * sqrt(max(0, 1 - pow(t, 2.2)))
            w += sin(CGFloat(tick) * 0.12 + t * 3) * 0.25 * jig
            let xw = Int(w.rounded()); let y = footY + gy
            for dx in -xw...xw {
                let gx = Int(cx) + dx
                let edge = dx <= -xw + 1 || dx >= xw - 1 || gy == 0 || gy >= Int(height) - 1
                if edge { fill(ctx, gx, y, skin.bodyDark) }
                else if dx < 0 && t > 0.45 && t < 0.85 && dx > -xw + 3 { fill(ctx, gx, y, skin.bodyLight) }
                else { fill(ctx, gx, y, skin.body) }
            }
        }

        let shineY = footY + Int(height * 0.72)
        fill(ctx, Int(cx)-4, shineY, skin.shine); fill(ctx, Int(cx)-5, shineY, skin.shine); fill(ctx, Int(cx)-4, shineY-1, skin.shine)

        if lookingAtScreen && turnT > 0.5 {
            drawBackPeek(ctx, cx: Int(cx), height: height, footY: footY)   // de espaldas, mirando la pantalla
        } else {
            drawFace(ctx, cx: Int(cx), height: height, footY: footY)
        }

        // comida frente a la boca al comer
        if state == .eating && stateTimer < 48 {
            let fy = footY + Int(height * 0.30)
            drawPattern(ctx, foodSprite(eatingFood), Int(cx) + 5, fy, eatingFood == .candy ? Pal.heart : Pal.crumb)
        }

        // escuchando la reunión: orejitas que se mueven + ondas de sonido
        if listening { drawListening(ctx, cx: Int(cx), height: height, footY: footY) }
    }

    /// Decoración de "escuchando": dos orejitas que se inclinan (twitch) y ondas
    /// de sonido que pulsan al lado de la cabeza.
    func drawListening(_ ctx: CGContext, cx: Int, height: CGFloat, footY: Int) {
        let skin = stats.isSick ? Pal.sick : Pal.skin
        let topY = footY + Int(height) - 1
        // twitch: la punta de las orejas se mueve un pelín con el tiempo
        let tw = (tick / 9) % 2 == 0 ? 0 : 1

        // oreja de 2x4: cuerpo + interior rosita + borde oscuro, se inclina a la punta
        func ear(_ x0: Int, _ lean: Int) {
            for oy in 0..<4 {
                let lx = x0 + (oy >= 2 ? lean : 0)
                fill(ctx, lx,     topY + oy, skin.bodyDark)            // borde exterior
                fill(ctx, lx + 1, topY + oy, oy >= 1 && oy <= 2 ? Pal.heart : skin.body)
            }
        }
        ear(cx - 6, -tw)     // oreja izquierda (se inclina a la izquierda)
        ear(cx + 4,  tw)     // oreja derecha

        // ondas de sonido pulsantes a la derecha de la cabeza ")))"
        let wx = cx + 9
        let wy = footY + Int(height * 0.52)
        let arc = ["1", "01", "1"]                       // un arco ")" simple
        let phase = (tick / 7) % 3                        // cuántas ondas se ven (1..3)
        for i in 0...phase {
            let a = 0.9 - Double(i) * 0.22
            drawPattern(ctx, arc, wx + i * 2, wy - 1, Pal.note.withAlphaComponent(max(0.25, a)))
        }
    }

    /// Vista de espaldas: dos ojitos asomándose por arriba (mirando la pantalla).
    func drawBackPeek(_ ctx: CGContext, cx: Int, height: CGFloat, footY: Int) {
        let skin = stats.isSick ? Pal.sick : Pal.skin
        let topY = footY + Int(height * 0.80)
        for dx in [-3, -2, 2, 3] { fill(ctx, cx + dx, topY, Pal.eye) }       // ojitos asomados
        // un brillo central tenue en la "nuca"
        fill(ctx, cx, footY + Int(height * 0.6), skin.bodyLight)
        fill(ctx, cx + 1, footY + Int(height * 0.6), skin.bodyLight)
    }

    func drawFace(_ ctx: CGContext, cx: Int, height: CGFloat, footY: Int) {
        let faceY = footY + Int(height * 0.45)
        let eyeDX = 4
        let leftX = cx - eyeDX + (facing < 0 ? -1 : 0)
        let rightX = cx + eyeDX + (facing < 0 ? -1 : 0)
        let lx = Int(lookX.rounded()), ly = Int(lookY.rounded())

        func eyeOpen(_ ex: Int) {
            for oy in 0..<4 { for ox in 0..<3 { fill(ctx, ex+ox, faceY+oy, Pal.eyeWhite) } }
            let pxp = max(0, min(1, 1+lx)), pyp = max(0, min(2, 1+ly))
            for oy in 0..<2 { for ox in 0..<2 { fill(ctx, ex+pxp+ox, faceY+pyp+oy, Pal.eye) } }
        }
        func eyeClosed(_ ex: Int) { for ox in 0..<3 { fill(ctx, ex+ox, faceY+1, Pal.eye) } }
        func eyeHappy(_ ex: Int) { fill(ctx, ex+1, faceY+2, Pal.eye); fill(ctx, ex, faceY+1, Pal.eye); fill(ctx, ex+2, faceY+1, Pal.eye) }
        func eyeSurprised(_ ex: Int) {
            for oy in 0..<5 { for ox in 0..<3 { fill(ctx, ex+ox, faceY+oy, Pal.eyeWhite) } }
            for oy in 0..<2 { for ox in 0..<2 { fill(ctx, ex+ox, faceY+2+oy, Pal.eye) } }
        }
        func eyeDizzy(_ ex: Int) {
            fill(ctx, ex, faceY+2, Pal.eye); fill(ctx, ex+2, faceY+2, Pal.eye)
            fill(ctx, ex+1, faceY+1, Pal.eye); fill(ctx, ex, faceY, Pal.eye); fill(ctx, ex+2, faceY, Pal.eye)
        }
        func eyeSad(_ ex: Int) {   // párpado superior + pupila abajo
            for ox in 0..<3 { fill(ctx, ex+ox, faceY+3, Pal.eye) }
            for ox in 0..<2 { fill(ctx, ex+ox, faceY+1, Pal.eye) }
        }

        // ojos según estado / ánimo
        switch state {
        case .sleeping, .yawning, .takingMedicine: eyeClosed(leftX); eyeClosed(rightX)
        case .happy, .wiggling: eyeHappy(leftX); eyeHappy(rightX)
        case .stretching: eyeClosed(leftX); eyeClosed(rightX)
        case .dizzy: eyeDizzy(leftX); eyeDizzy(rightX)
        case .eating: eyeHappy(leftX); eyeHappy(rightX)
        case .reacting, .falling, .dragging: eyeSurprised(leftX); eyeSurprised(rightX)
        case .dancing:
            if (stateTimer/14) % 2 == 0 { eyeHappy(leftX); eyeHappy(rightX) } else { eyeOpen(leftX); eyeOpen(rightX) }
        default:
            if isBlinking { eyeClosed(leftX); eyeClosed(rightX) }
            else if expr == .sad { eyeSad(leftX); eyeSad(rightX) }
            else if expr == .sick { eyeClosed(leftX); eyeClosed(rightX) }
            else { eyeOpen(leftX); eyeOpen(rightX) }
        }

        // boca
        let openStates: [PetState] = [.reacting, .falling, .dragging, .yawning, .eating]
        if talking {
            // boca que se abre y cierra (simula que habla)
            let open = 1 + Int((abs(sin(CGFloat(tick) * 0.7)) * 3).rounded())   // 1..4 px
            for oy in 0..<open { for ox in 0..<2 { fill(ctx, cx - 1 + ox, faceY - 3 - oy, Pal.mouth) } }
            return
        }
        if openStates.contains(state) {
            let mw = state == .yawning ? 3 : 2
            for oy in 0..<3 { for ox in 0..<mw { fill(ctx, cx-1+ox, faceY-4+oy, Pal.mouth) } }
        } else if [.happy, .chasing, .dancing].contains(state) {
            for ox in -2...2 { fill(ctx, cx+ox, faceY-3, Pal.mouth) }
            for ox in -1...1 { fill(ctx, cx+ox, faceY-4, Pal.mouth) }
        } else if state == .sleeping {
            // sin boca
        } else if expr == .sad || expr == .sick {
            fill(ctx, cx, faceY-3, Pal.mouth); fill(ctx, cx-1, faceY-4, Pal.mouth); fill(ctx, cx+1, faceY-4, Pal.mouth)  // ∩ triste
        } else {
            fill(ctx, cx-1, faceY-3, Pal.mouth); fill(ctx, cx, faceY-4, Pal.mouth); fill(ctx, cx+1, faceY-3, Pal.mouth)  // ∪ sonrisa
        }

        // mejillas felices
        if [.idle, .looking, .walking, .happy, .dancing, .chasing].contains(state) && expr == .normal {
            fill(ctx, leftX-1, faceY-2, Pal.blush); fill(ctx, rightX+2, faceY-2, Pal.blush)
        }
    }

    func foodSprite(_ f: Food) -> [String] {
        switch f {
        case .apple: return ["00100","01110","11111","11111","01110"]
        case .meat:  return ["01110","11111","11111","00100","00100"]
        case .candy: return ["10001","01110","11111","01110","10001"]
        }
    }

    // ---- Huevo ----
    func drawEgg(_ ctx: CGContext) {
        let cx = GW/2
        let wob = (state == .hatching) ? sin(CGFloat(stateTimer)*0.9)*2.5 : sin(CGFloat(tick)*0.06)*1.0
        let chh = 11, cw = 8, baseY = 3
        for gy in 0..<(2*chh) {
            let t = (CGFloat(gy) - CGFloat(chh)) / CGFloat(chh)
            let w = CGFloat(cw) * sqrt(max(0, 1 - t*t)) * (gy < chh ? 1.05 : 0.92) // un poco de "huevo"
            let xw = Int(w.rounded())
            for dx in -xw...xw {
                let gx = cx + dx + Int(wob)
                let edge = dx <= -xw+1 || dx >= xw-1
                fill(ctx, gx, baseY+gy, edge ? Pal.egg2 : Pal.egg1)
            }
        }
        // manchas
        for (sx, sy) in [(-3, 6), (2, 10), (-1, 14), (4, 9)] {
            fill(ctx, cx+sx+Int(wob), baseY+sy, Pal.egg2)
        }
        // grietas al eclosionar
        if state == .hatching {
            let cyl = baseY + chh
            for (gx, gy) in [(0,2),(1,1),(-1,1),(1,-1),(2,0),(-2,0)] {
                fill(ctx, cx+gx+Int(wob), cyl+gy, Pal.eye)
            }
        }
    }

    // ---- Fantasma (muerto) ----
    func drawGhost(_ ctx: CGContext) {
        let skin = Pal.ghost
        let baseHalf: CGFloat = 10, baseHeight: CGFloat = 16
        let floatY = Int(sin(CGFloat(tick)*0.06) * 2) + 4
        let cx = GW/2
        for gy in 0..<Int(baseHeight) {
            let t = CGFloat(gy)/baseHeight
            let w = baseHalf * sqrt(max(0, 1 - pow(t, 2.0)))
            let xw = Int(w.rounded())
            for dx in -xw...xw {
                let gx = cx + dx
                // borde ondulado abajo (cola de fantasma)
                if gy == 0 && (dx % 2 == 0) { continue }
                let edge = dx <= -xw+1 || dx >= xw-1
                fill(ctx, gx, gy+floatY, edge ? skin.bodyDark : skin.body)
            }
        }
        // ojos X y boca triste
        let faceY = floatY + Int(baseHeight*0.45)
        for ex in [cx-4, cx+2] {
            fill(ctx, ex, faceY+2, Pal.eye); fill(ctx, ex+2, faceY+2, Pal.eye)
            fill(ctx, ex+1, faceY+1, Pal.eye); fill(ctx, ex, faceY, Pal.eye); fill(ctx, ex+2, faceY, Pal.eye)
        }
        // halo de ángel
        let haloY = floatY + Int(baseHeight) + 2
        for dx in -3...3 { fill(ctx, cx+dx, haloY, Pal.halo) }
        fill(ctx, cx-4, haloY, Pal.halo); fill(ctx, cx+4, haloY, Pal.halo)
    }

    // ---- Popó ----
    func drawPoops(_ ctx: CGContext) {
        guard stats.poops > 0 else { return }
        let pat = ["00100","01110","11111"]
        for i in 0..<min(stats.poops, 3) {
            drawPattern(ctx, pat, GW/2 + 8 + i*5, 1, Pal.poop)
        }
    }

    // ---- Partículas ----
    func drawParticles(_ ctx: CGContext) {
        for p in particles {
            let bx = Int(p.x.rounded()), by = Int(p.y.rounded())
            let a = max(0, min(1, p.life))
            switch p.kind {
            case 0: drawPattern(ctx, ["01010","11111","11111","01110","00100"], bx, by, Pal.heart.withAlphaComponent(a))
            case 1: drawPattern(ctx, ["00110","00010","00010","11010","11000"], bx, by, Pal.note.withAlphaComponent(a))
            case 2: drawPattern(ctx, ["00100","01110","00100"], bx, by, Pal.star.withAlphaComponent(a))
            case 3: drawPattern(ctx, ["1110","0100","1110"], bx, by, Pal.skin.bodyDark.withAlphaComponent(a))
            case 4: drawPattern(ctx, ["010","010","111","010"], bx, by, Pal.sweat.withAlphaComponent(a))   // sudor
            case 5: drawPattern(ctx, ["101","010"], bx, by, Pal.eye.withAlphaComponent(a))                  // mosca
            case 6: drawPattern(ctx, ["010","101","010"], bx, by, Pal.bubble.withAlphaComponent(a))         // burbuja
            case 7: fill(ctx, bx, by, Pal.crumb.withAlphaComponent(a))                                      // miga
            default: drawPattern(ctx, ["00100","01110","00100"], bx, by, Pal.star.withAlphaComponent(a))    // chispa
            }
        }
    }

    func drawPattern(_ ctx: CGContext, _ rows: [String], _ ox: Int, _ oy: Int, _ c: NSColor) {
        for (r, row) in rows.enumerated() {
            for (cIdx, ch) in row.enumerated() where ch == "1" {
                fill(ctx, ox + cIdx, oy + (rows.count - 1 - r), c)
            }
        }
    }

    // ------------------------------------------------------------------
    // HUD: barras de stats + botones de acción
    // ------------------------------------------------------------------
    func layoutButtons() {
        let bw: CGFloat = 26
        let cx = bounds.width / 2
        if stats.isDead {
            buttons = [HudButton(id: "restart", icon: "🥚", rect: NSRect(x: cx - 13, y: 108, width: bw, height: bw))]
            return
        }
        // Botones contextuales: 🍖 solo si tiene hambre, 💊 solo si está enfermo.
        // (jugar = doble clic, lavar = frotar, dormir = automático)
        // El chat es más pequeño y va pegado al slime, a la izquierda.
        let chatSz: CGFloat = 19
        buttons = [HudButton(id: "chat", icon: "💬", rect: NSRect(x: cx - 42, y: 62, width: chatSz, height: chatSz))]
        if stats.hunger < Tuning.careShow {
            buttons.append(HudButton(id: "feed", icon: "🍖", rect: NSRect(x: cx - 72, y: 54, width: bw, height: bw)))
        }
        if stats.isSick {
            buttons.append(HudButton(id: "med", icon: "💊", rect: NSRect(x: cx + 46, y: 54, width: bw, height: bw)))
        }
    }

    func drawText(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, color: NSColor = .white) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color]
        (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }

    /// Icono que funciona como medidor: el fondo va apagado (vacío) y la
    /// porción inferior se "llena" con el color del propio emoji según `value`.
    func drawStatIcon(_ ctx: CGContext, _ icon: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, value: Double) {
        let v = CGFloat(max(0, min(1, value)))
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size)]
        let p = NSPoint(x: x, y: y)

        // base apagada (lo "gastado")
        ctx.saveGState()
        ctx.setAlpha(hudAlpha * (v < 0.25 ? 0.12 : 0.20))
        (icon as NSString).draw(at: p, withAttributes: attrs)
        ctx.restoreGState()

        // porción llena, de abajo hacia arriba
        if v > 0.001 {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x - 3, y: y - 2, width: size + 8, height: (size + 4) * v))
            ctx.setAlpha(hudAlpha)
            (icon as NSString).draw(at: p, withAttributes: attrs)
            // tinte rojo de alerta cuando está crítico
            if v < 0.25 {
                ctx.setBlendMode(.sourceAtop)
                ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.5).cgColor)
                ctx.fill(CGRect(x: x - 3, y: y - 2, width: size + 8, height: size + 6))
            }
            ctx.restoreGState()
        }
    }

    func drawHUD(_ ctx: CGContext) {
        layoutButtons()
        guard hudAlpha > 0.02 else { return }
        ctx.saveGState()
        ctx.setAlpha(hudAlpha)

        if stats.isDead {
            drawText("R.I.P.  ·  toca 🥚 para revivir", (bounds.width - 150)/2, 244, size: 11)
        }

        // --- botones (el fondo se llena como un indicador según su stat) ---
        let statFor: [String: (Double, NSColor)] = [
            "feed":  (stats.hunger,      Pal.barHunger),
            "play":  (stats.happiness,   Pal.barHappy),
            "clean": (stats.cleanliness, Pal.barClean),
            "med":   (stats.health,      Pal.barHealth),
            "sleep": (stats.energy,      Pal.barEnergy),
        ]
        for b in buttons {
            let path = NSBezierPath(roundedRect: b.rect, xRadius: 6, yRadius: 6)
            // fondo vacío (oscuro)
            NSColor(white: 0.12, alpha: 0.80).setFill(); path.fill()
            // relleno indicador, de abajo hacia arriba
            if let (value, color) = statFor[b.id] {
                let v = CGFloat(max(0, min(1, value)))
                if v > 0.001 {
                    ctx.saveGState()
                    path.addClip()                                   // recorta al rectángulo redondeado
                    let c = v < 0.25 ? NSColor.systemRed : color
                    c.withAlphaComponent(0.9).setFill()
                    NSBezierPath(rect: NSRect(x: b.rect.minX, y: b.rect.minY,
                                              width: b.rect.width, height: b.rect.height * v)).fill()
                    ctx.restoreGState()
                }
            }
            // borde + icono encima (siempre visible), escalado al tamaño del botón
            NSColor(white: 1, alpha: 0.30).setStroke(); path.lineWidth = 1; path.stroke()
            drawText(b.icon, b.rect.minX + b.rect.width * 0.15, b.rect.minY + b.rect.height * 0.15,
                     size: b.rect.width * 0.58)
        }
        ctx.restoreGState()
    }

    // ------------------------------------------------------------------
    // Globo de diálogo + IA
    // ------------------------------------------------------------------
    var bubbleVisible: Bool { bubbleThinking || (bubbleText != nil && Date() < bubbleUntil) }

    func drawBubble(_ ctx: CGContext) {
        guard bubbleVisible, !stats.isDead, state != .egg, state != .sleeping, !stats.isAsleep else { return }
        let text = bubbleThinking ? thinkingDots() : (bubbleText ?? "")
        guard !text.isEmpty else { return }

        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.12, alpha: 1), .paragraphStyle: para]
        let maxW = bounds.width - 30
        let tr = (text as NSString).boundingRect(with: NSSize(width: maxW, height: 120),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        let bw = min(maxW, ceil(tr.width)) + 18, bh = ceil(tr.height) + 12
        let bx = (bounds.width - bw) / 2
        let by: CGFloat = 88                                    // pegado a la cabeza del slime
        let rect = NSRect(x: bx, y: by, width: bw, height: bh)

        // colita apuntando hacia abajo (a la cabeza)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bounds.width/2 - 6, y: by + 1))
        tail.line(to: NSPoint(x: bounds.width/2, y: by - 9))
        tail.line(to: NSPoint(x: bounds.width/2 + 6, y: by + 1))
        tail.close()

        let bubble = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor(white: 1, alpha: 0.97).setFill()
        bubble.fill(); tail.fill()
        NSColor(white: 0.20, alpha: 1).setStroke()
        bubble.lineWidth = 2; bubble.stroke(); tail.stroke()

        (text as NSString).draw(with: NSRect(x: bx + 9, y: by + 6, width: bw - 18, height: bh - 12),
                                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
    }

    func thinkingDots() -> String {
        let n = (tick / 12) % 3 + 1
        return String(repeating: "•", count: n)
    }

    func duration(for text: String) -> TimeInterval { min(8, max(2.5, Double(text.count) * 0.09)) }

    func say(_ text: String) {
        bubbleThinking = false
        bubbleText = text
        bubbleUntil = Date().addingTimeInterval(duration(for: text))
    }

    /// Reacción contextual: pide frase al LLM (si hay clave) o usa enlatada.
    func react(_ sit: Situation) {
        if let client = client, client.config.isConfigured {
            bubbleThinking = true
            bubbleUntil = Date().addingTimeInterval(20)
            let snapshot = stats
            client.chat(system: Personality.systemPrompt(snapshot), history: [], user: Personality.prompt(for: sit), maxTokens: 800) { [weak self] reply in
                let clean = reply.flatMap(Personality.sanitize)
                self?.say(clean ?? Personality.canned(sit))
            }
        } else {
            say(Personality.canned(sit))
        }
    }

    /// Reacción espontánea (eventos): con enfriamiento para no spamear.
    func reactSpontaneous(_ sit: Situation) {
        guard !stats.isAsleep, state != .sleeping else { return }   // callado mientras duerme
        guard Date().timeIntervalSince(lastSpontaneous) > 45 else { return }
        lastSpontaneous = Date()
        react(sit)
    }

    func sendChat(_ userText: String, onReply: ((String) -> Void)? = nil) {
        let t = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard let client = client, client.config.isConfigured else {
            let m = "Configúrame con MiniMax para charlar 🔌"; say(m); onReply?(m); return
        }
        bubbleThinking = true
        bubbleUntil = Date().addingTimeInterval(20)
        let history = Array(convo.suffix(8))         // contexto reciente para el LLM
        let snapshot = stats
        client.chat(system: Personality.systemPrompt(snapshot), history: history, user: t, maxTokens: 1000) { [weak self] reply in
            guard let self = self else { return }
            let r = reply.flatMap(Personality.sanitize) ?? "Uy, no pude pensar 😵‍💫"
            self.convo.append(("user", t)); self.convo.append(("assistant", r))   // historial completo
            self.say(r)
            onReply?(r)
        }
    }

    func applyAISkin(_ spec: SkinSpec) {
        guard let skin = Pal.skin(from: spec) else { return }
        Pal.setAISkin(skin)
        say("¡Mira mi nuevo look! ✨")
    }

    // ------------------------------------------------------------------
    // Chat integrado (panel pixel sobre el slime)
    // ------------------------------------------------------------------
    override var acceptsFirstResponder: Bool { true }

    func toggleChat() {
        chatActive.toggle()
        if chatActive {
            if chatStore.conversations.isEmpty { chatStore.conversations.append(.new()); chatStore.save() }
            convIndex = min(convIndex, chatStore.conversations.count - 1)
            ensureAgent(); listOpen = false; chatStick = true; chatScrollToBottom = true
            persistActiveConversation()
            // si venía moviéndose, quédate quieto para que el diálogo no se mueva
            if [.dancing, .walking, .rolling, .chasing, .happy, .reacting, .falling].contains(state) { state = .idle; stateTimer = 0 }
            resizeForChat(true)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window?.makeFirstResponder(self)
        } else {
            resizeForChat(false)
        }
        needsDisplay = true
    }

    func resizeForChat(_ on: Bool) {
        guard let win = petWindow, let screen = win.screen ?? NSScreen.main else { return }
        let target = on ? NSSize(width: 300, height: 360) : NSSize(width: 160, height: 140)
        let vf = screen.visibleFrame
        let centerX = win.frame.midX
        var origin = NSPoint(x: centerX - target.width / 2, y: vf.minY)
        origin.x = max(vf.minX, min(vf.maxX - target.width, origin.x))
        win.setFrame(NSRect(origin: origin, size: target), display: true)
        updateTrackingAreas()
    }

    func ensureAgent() {
        guard let client = client else { return }
        let a = Agent(view: self, client: client)
        a.confirm = { [weak self] title, detail, cb in self?.confirmAction(title, detail, cb) }
        var msgs: [AIMessage] = [AIMessage(role: "system", content: Personality.agentSystem(stats))]
        for m in chatStore.conversations[convIndex].messages { msgs.append(AIMessage(role: m.role, content: m.content)) }
        a.messages = msgs
        agent = a
    }

    func newConversation() {
        chatStore.conversations.append(.new())
        convIndex = chatStore.conversations.count - 1
        chatStore.save(); ensureAgent(); listOpen = false; chatStick = true; chatScroll = 0
        persistActiveConversation()
        needsDisplay = true
    }

    func selectConversation(_ i: Int) {
        guard i >= 0, i < chatStore.conversations.count else { return }
        convIndex = i; ensureAgent(); listOpen = false; chatStick = true; chatScrollToBottom = true
        persistActiveConversation()
        needsDisplay = true
    }

    /// Al arrancar: abre la conversación que estaba activa la última vez.
    func restoreActiveConversation() {
        if let id = chatStore.activeId,
           let idx = chatStore.conversations.firstIndex(where: { $0.id == id }) {
            convIndex = idx
        } else {
            convIndex = max(0, chatStore.conversations.count - 1)   // a falta de dato, la más reciente
        }
    }

    /// Recuerda cuál es la conversación activa (para restaurarla al reabrir la app).
    func persistActiveConversation() {
        guard convIndex >= 0, convIndex < chatStore.conversations.count else { return }
        chatStore.activeId = chatStore.conversations[convIndex].id
        chatStore.save()
    }

    func captureScreen() {
        stepLines = ["📸 capturando pantalla…"]; needsDisplay = true
        ScreenCapture.grab(excluding: window) { [weak self] b64, path in
            guard let self = self else { return }
            if let b64 = b64 {
                self.pendingShot = b64; self.pendingShotPath = path
                self.stepLines = ["📸 pantalla adjunta — escribe tu pregunta"]
            } else {
                self.stepLines = [Loc.t("⚠️ Activa Grabación de pantalla para Flubber (te abrí Ajustes) y REINICIA la app.",
                                        "⚠️ Enable Screen Recording for Flubber (I opened Settings) and RESTART the app.")]
            }
            self.needsDisplay = true
        }
    }

    /// Adjunta una captura (su ruta) al último mensaje del usuario, para el thumbnail.
    func attachShot(_ path: String) {
        guard convIndex < chatStore.conversations.count else { return }
        if let idx = chatStore.conversations[convIndex].messages.lastIndex(where: { $0.role == "user" }) {
            chatStore.conversations[convIndex].messages[idx].imagePath = path
            chatStore.save(); chatStick = true; needsDisplay = true
        }
    }

    func wakeUp() {
        guard stats.isAsleep || state == .sleeping else { return }
        stats.isAsleep = false
        stats.energy = max(stats.energy, 0.12)
        if state == .sleeping { state = .idle; stateTimer = 0 }
    }

    func setName(_ n: String) {
        let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
        stats.name = t.isEmpty ? nil : t
        stats.save(); needsDisplay = true
    }

    func sendChatMessage() {
        let t = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !chatBusy else { return }
        wakeUp()                                  // si estaba dormido, despierta al hablarle
        chatInput = ""
        let shotPath = pendingShotPath; pendingShotPath = nil
        chatStore.conversations[convIndex].messages.append(Msg(role: "user", content: t, imagePath: shotPath))
        if chatStore.conversations[convIndex].title == "Nueva conversación" {
            chatStore.conversations[convIndex].title = String(t.prefix(26))
        }
        chatStore.save()
        let shot = pendingShot; pendingShot = nil
        chatBusy = true; chatStick = true; needsDisplay = true

        func finish(_ reply: String) {
            stepLines = []; chatBusy = false; chatActivity = 0; streamLive = nil
            chatStore.conversations[convIndex].messages.append(Msg(role: "assistant", content: reply))
            chatStore.save(); chatStick = true; needsDisplay = true
        }

        if let shot = shot {                       // pregunta sobre la pantalla → visión
            stepLines = ["👁️ mirando tu pantalla…"]; chatActivity = 2
            client?.vision(prompt: t, imageBase64: shot) { reply in
                finish(reply ?? "No pude analizar la pantalla 😅 (revisa el permiso de grabación o usa un modelo con visión).")
            }
            return
        }
        guard let agent = agent else { finish("Configúrame con IA para charlar 🔌"); return }
        stepLines = []; chatActivity = 0; streamLive = ""
        agent.run(t, onStep: { step in
            self.stepLines.append(step)
            if step.contains("buscando") { self.chatActivity = 1 }
            else if step.contains("pantalla") || step.contains("leyendo") { self.chatActivity = 2 }
            else { self.chatActivity = 0 }
            self.chatStick = true; self.needsDisplay = true
        }, onToken: { chunk in
            self.streamLive = (self.streamLive ?? "") + chunk
            self.stepLines = []; self.chatStick = true; self.needsDisplay = true
        }, completion: { reply in finish(reply) })
    }

    // ==================================================================
    // Escucha de reunión: conversación dedicada + resúmenes rodantes por
    // lotes + síntesis final + transcripción guardada con link clicable.
    // ==================================================================

    /// Al empezar a escuchar: NO crea conversación todavía (se crea al final según
    /// la duración). Fuerza sesión nueva (meetingConvId = nil) para no adjuntar a la
    /// reunión anterior, y arranca el timer de resúmenes parciales.
    func beginMeeting() {
        guard #available(macOS 13.0, *) else { return }
        meetingConvId = nil                    // ← cada escucha es una sesión NUEVA
        meetingSummarizedLen = 0
        meetingRollingSummaries = []
        meetingStartedAt = Date()

        meetingRollTimer?.invalidate()
        meetingRollTimer = Timer.scheduledTimer(withTimeInterval: 240, repeats: true) { [weak self] _ in
            self?.rollMeetingSummary()
        }
        Log.write("📝 escucha iniciada")
    }

    /// Crea (una sola vez por sesión) la conversación dedicada, con título según
    /// sea reunión (🎧) o charla (💬).
    private func ensureMeetingConversation(isMeeting: Bool) {
        guard meetingConvId == nil else { return }
        let df = DateFormatter(); df.dateFormat = "HH:mm"
        let stamp = df.string(from: Date())
        let title = isMeeting
            ? Loc.t("🎧 Reunión \(stamp)", "🎧 Meeting \(stamp)")
            : Loc.t("💬 Charla \(stamp)", "💬 Talk \(stamp)")
        let conv = Conversation(id: UUID().uuidString, title: title, messages: [])
        chatStore.conversations.append(conv)
        meetingConvId = conv.id
        convIndex = chatStore.conversations.count - 1
        chatStore.save(); persistActiveConversation(); ensureAgent()
    }

    /// Añade un mensaje del slime a la conversación de la reunión (por id).
    func appendToMeetingConversation(_ text: String, filePath: String? = nil) {
        guard let id = meetingConvId,
              let idx = chatStore.conversations.firstIndex(where: { $0.id == id }) else { return }
        chatStore.conversations[idx].messages.append(Msg(role: "assistant", content: text, filePath: filePath))
        chatStore.save()
        if chatActive && convIndex == idx { chatStick = true; chatScrollToBottom = true }
        needsDisplay = true
    }

    /// Mini-resumen del trozo NUEVO de transcript desde la última vez.
    func rollMeetingSummary(completion: (() -> Void)? = nil) {
        guard #available(macOS 13.0, *) else { completion?(); return }
        let full = MeetingListener.shared.transcript
        let start = min(meetingSummarizedLen, full.count)
        let new = String(full.dropFirst(start)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard new.count >= 40, let client = client, client.config.isConfigured else { completion?(); return }
        meetingSummarizedLen = full.count
        let sys = Loc.t(
            "Anota en UNA sola frase corta y neutral SOLO de qué se está hablando ahora. NO saludes, NO te presentes, NO uses emojis ni opiniones. Solo el tema o dato. Español.",
            "Note in ONE short neutral sentence ONLY what is being talked about now. NO greetings, NO introducing yourself, NO emojis or opinions. Just the topic or fact. English.")
        client.chat(system: sys, history: [], user: new, maxTokens: 220) { [weak self] reply in
            DispatchQueue.main.async {
                guard let self = self else { completion?(); return }
                let mini = (reply.map { Agent.cleanFinal($0) } ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !mini.isEmpty {
                    self.meetingRollingSummaries.append(mini)
                    Log.write("📝 resumen parcial #\(self.meetingRollingSummaries.count): \(mini.prefix(60))")
                    self.ensureMeetingConversation(isMeeting: true)       // a estas alturas (>4min) ya es reunión
                    self.appendToMeetingConversation("🎧 " + mini)        // partial en vivo (en su conversación)
                    self.say(Loc.t("🎧 anoté algo de la reunión…", "🎧 jotted down something…"))
                }
                completion?()
            }
        }
    }

    /// Al hacer stop: cierra el último trozo, sintetiza el resumen final en el
    /// chat (streaming) y adjunta la transcripción completa como link clicable.
    func finishMeeting() {
        guard #available(macOS 13.0, *) else { return }
        meetingRollTimer?.invalidate(); meetingRollTimer = nil
        rollMeetingSummary { [weak self] in self?.finalizeMeetingSummary() }
    }

    private func finalizeMeetingSummary() {
        let transcript = MeetingListener.shared.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filePath = saveTranscriptFile(transcript)
        let elapsed = Date().timeIntervalSince(meetingStartedAt)
        let isMeeting = elapsed >= PetView.meetingThreshold     // ≥1 min = reunión; si no, charla
        Log.write("📝 finalize — \(Int(elapsed))s, \(isMeeting ? "reunión" : "charla"), transcript=\(transcript.count) chars, partials=\(meetingRollingSummaries.count)")

        // Crea la conversación dedicada (título según reunión/charla) y abre el chat.
        ensureMeetingConversation(isMeeting: isMeeting)
        if !chatActive { toggleChat() }
        chatScrollToBottom = true

        guard !transcript.isEmpty else {
            appendToMeetingConversation(Loc.t("No escuché nada claro 👂", "Didn't catch anything clear 👂")); return
        }
        // Sin IA configurada: fallback → muestra lo que escuchó SIN procesar.
        guard let client = client, client.config.isConfigured else {
            Log.write("📝 sin IA → fallback: muestro la transcripción en crudo")
            appendToMeetingConversation(
                Loc.t("🎧 Esto fue lo que escuché (sin IA para resumir):\n\n", "🎧 Here's what I heard (no AI to summarize):\n\n") + transcript)
            if let fp = filePath { appendToMeetingConversation(Loc.t("📄 Ver transcripción completa", "📄 View full transcript"), filePath: fp) }
            return
        }

        // Base de la síntesis: si hubo resúmenes rodantes, úsalos (corto); si no, el transcript.
        let basis = meetingRollingSummaries.isEmpty
            ? transcript
            : meetingRollingSummaries.map { "- \($0)" }.joined(separator: "\n")

        // Reunión (≥1min): frase de cierre + resumen estructurado. Charla (<1min):
        // solo un resumen corto, sin frase de cierre ni estructura.
        if isMeeting {
            appendToMeetingConversation(Loc.t("✅ Ya terminé de escuchar. Este fue tu resumen:", "✅ Done listening. Here's your summary:"))
        }
        chatBusy = true; chatStick = true; chatScrollToBottom = true; streamLive = ""; stepLines = []; chatActivity = 0; needsDisplay = true
        let sys = isMeeting
            ? Loc.t(
                "Resume lo que se dijo en una reunión, directo y claro. NO saludes ni te presentes ni hables de ti. Estructura: 1) resumen breve, 2) puntos clave (viñetas), 3) tareas/acuerdos si los hay. Solo español.",
                "Summarize what was said in a meeting, direct and clear. Do NOT greet or introduce yourself. Structure: 1) short summary, 2) key points (bullets), 3) action items if any. English only.")
            : Loc.t(
                "Resume en 1-2 frases lo que se habló, directo. NO saludes ni te presentes ni hables de ti. Solo el resumen. Español.",
                "Summarize in 1-2 sentences what was talked about, direct. Do NOT greet or introduce yourself. Just the summary. English only.")
        let userMsg = isMeeting
            ? Loc.t("Esto es lo que escuché en la reunión (puede tener errores):\n\n",
                    "Here's what I heard in the meeting (may have errors):\n\n") + basis
            : Loc.t("Esto es lo que escuché en la conversación (puede tener errores):\n\n",
                    "Here's what I heard in the conversation (may have errors):\n\n") + basis
        let msgs = [AIMessage(role: "system", content: sys), AIMessage(role: "user", content: userMsg)]

        client.completeStream(messages: msgs, tools: nil, maxTokens: 1200, onDelta: { [weak self] chunk in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.streamLive = (self.streamLive ?? "") + chunk
                self.stepLines = []; self.chatStick = true; self.needsDisplay = true
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let reply = (result?.content ?? self.streamLive ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let final = reply.isEmpty ? Loc.t("No pude resumir lo que escuché 😅", "Couldn't summarize what I heard 😅") : reply
                self.streamLive = nil; self.chatBusy = false; self.chatActivity = 0
                self.appendToMeetingConversation(final)
                if let fp = filePath {
                    self.appendToMeetingConversation(Loc.t("📄 Ver transcripción completa", "📄 View full transcript"), filePath: fp)
                }
            }
        })
    }

    /// Guarda la transcripción completa a un .txt y devuelve su ruta.
    private func saveTranscriptFile(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlimePet/transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd_HH-mm"
        let url = dir.appendingPathComponent("reunion-\(df.string(from: Date())).txt")
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let header = Loc.t("Transcripción de reunión — ", "Meeting transcript — ") + stamp + "\n\n"
        do { try (header + text).write(to: url, atomically: true, encoding: .utf8); return url.path }
        catch { Log.write("📝 no pude guardar la transcripción: \(error.localizedDescription)"); return nil }
    }

    func confirmAction(_ title: String, _ detail: String, _ cb: @escaping (Bool, Bool) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "\(title)?"
        a.informativeText = detail + Loc.t("\n\n\(stats.displayName) quiere hacer esto. ¿Lo permites?",
                                           "\n\n\(stats.displayName) wants to do this. Allow it?")
        a.alertStyle = .warning
        a.addButton(withTitle: Loc.t("Aprobar", "Approve"))
        a.addButton(withTitle: Loc.t("Permitir siempre", "Always allow"))
        a.addButton(withTitle: Loc.t("Denegar", "Deny"))
        switch a.runModal() {
        case .alertFirstButtonReturn:  cb(true, false)
        case .alertSecondButtonReturn: cb(true, true)     // siempre
        default:                       cb(false, false)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard chatActive else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 53: toggleChat()                                   // Esc
        case 36, 76: sendChatMessage()                          // Return / Enter
        case 51: if !chatInput.isEmpty { chatInput.removeLast() }   // Backspace
        default:
            if event.modifierFlags.isDisjoint(with: [.command, .control]),
               let ch = event.characters, !ch.isEmpty {
                chatInput += ch.filter { !$0.isNewline && $0 != "\u{7f}" }
            }
        }
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if chatActive, event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            if let s = NSPasteboard.general.string(forType: .string) { chatInput += s; needsDisplay = true }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard chatActive else { super.scrollWheel(with: event); return }
        chatScroll = max(0, min(chatContentH - chatAreaH, chatScroll - event.scrollingDeltaY))
        chatStick = false
        needsDisplay = true
    }

    /// Desplazamiento horizontal del cuerpo (vaivén al buscar).
    func bodyOffsetX() -> CGFloat {
        if state == .wiggling { return sin(CGFloat(stateTimer) * 0.6) * 3.0 }   // contoneo lateral
        guard chatActive && chatBusy else { return 0 }
        if chatActivity == 1 { return sin(CGFloat(tick) * 0.32) * 3.5 }   // buscando: vaivén
        if chatActivity == 2 { return sin(CGFloat(tick) * 0.2) * 1.5 }    // mirando: leve
        return 0
    }

    // ---- dibujo del panel de chat ----
    struct ChatItem { let text: String; let kind: Int; var imagePath: String? = nil; var filePath: String? = nil }   // 0 slime, 1 user, 2 paso

    func chatItems() -> [ChatItem] {
        var items: [ChatItem] = []
        for m in chatStore.conversations[convIndex].messages {
            items.append(ChatItem(text: m.content, kind: m.role == "user" ? 1 : 0, imagePath: m.imagePath, filePath: m.filePath))
        }
        for s in stepLines { items.append(ChatItem(text: s, kind: 2)) }
        let live = streamLive ?? ""
        if chatBusy && stepLines.isEmpty && live.isEmpty {
            items.append(ChatItem(text: Loc.t("pensando…", "thinking…"), kind: 2))
        }
        if chatBusy && !live.isEmpty {               // texto llegando en streaming
            items.append(ChatItem(text: live + "▌", kind: 0))
        }
        return items
    }

    func drawChat(_ ctx: CGContext) {
        chatButtons.removeAll(); listRowRects.removeAll(); copyButtons.removeAll(); thumbRects.removeAll(); fileButtons.removeAll()
        let W = bounds.width, H = bounds.height
        let pad: CGFloat = 8
        let panel = NSRect(x: pad, y: 96, width: W - 2 * pad, height: H - 96 - pad)
        // fondo del panel
        let bg = NSBezierPath(roundedRect: panel, xRadius: 8, yRadius: 8)
        NSColor(white: 0.16, alpha: 0.95).setFill(); bg.fill()
        NSColor(srgbRed: 0.36, green: 0.85, blue: 0.55, alpha: 0.9).setStroke(); bg.lineWidth = 2; bg.stroke()

        let header = NSRect(x: panel.minX, y: panel.maxY - 28, width: panel.width, height: 28)
        // input de altura dinámica (crece con las líneas) + fila de adjunto si hay captura
        let sendW: CGFloat = 30
        let chipH: CGFloat = pendingShot != nil ? 24 : 0
        let inputInnerW = panel.width - 18 - sendW
        let th = attrSize(inputDisplayAttr(), inputInnerW).height
        let inputH = max(28, min(120, th + 10)) + chipH
        let inputR = NSRect(x: panel.minX, y: panel.minY, width: panel.width, height: inputH)
        let area = NSRect(x: panel.minX + 4, y: inputR.maxY + 4,
                          width: panel.width - 8, height: header.minY - inputR.maxY - 8)
        chatAreaH = area.height

        // --- header: nombre + botones ---
        drawText("\(stats.displayName) 💬", header.minX + 8, header.minY + 7, size: 12,
                 color: NSColor(srgbRed: 0.62, green: 0.96, blue: 0.72, alpha: 1))
        let bs: CGFloat = 20, gapb: CGFloat = 4
        var bxr = header.maxX - 8 - bs
        for (id, icon) in [("close", "✕"), ("new", "＋"), ("list", "☰"), ("eye", "👁️"), ("ear", listening ? "⏹️" : "👂")] {
            let r = NSRect(x: bxr, y: header.minY + 4, width: bs, height: bs)
            let p = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            NSColor(white: 1, alpha: 0.12).setFill(); p.fill()
            drawText(icon, r.minX + 4, r.minY + 3, size: 12)
            chatButtons.append(HudButton(id: id, icon: icon, rect: r))
            bxr -= bs + gapb
        }
        // línea separadora bajo el header
        NSColor(white: 1, alpha: 0.12).setFill()
        ctx.fill(CGRect(x: panel.minX + 4, y: header.minY - 1, width: panel.width - 8, height: 1))

        // --- lista de conversaciones (overlay) ---
        if listOpen { drawChatList(ctx, area); return }

        // --- mensajes ---
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let items = chatItems()
        let maxBW = area.width * 0.82
        // medir (misma anchura que el dibujo, para no cortar el texto)
        let heights = items.map { bubbleHeight($0, maxBW, area.width) }
        let spacing: CGFloat = 6
        let total = heights.reduce(0, +) + spacing * CGFloat(max(0, items.count - 1)) + 8
        chatContentH = total
        let maxScroll = max(0, total - area.height)
        if chatScrollToBottom {
            // al abrir/cambiar de conversación: ver el FINAL (último mensaje completo)
            chatScroll = maxScroll
            chatScrollToBottom = false
        } else if chatStick {
            // mostrar el INICIO del último mensaje (no el final), para no cortar arriba
            let lastTop = heights.dropLast().reduce(0, +) + spacing * CGFloat(max(0, items.count - 1))
            chatScroll = min(lastTop, maxScroll)
        }
        chatScroll = max(0, min(maxScroll, chatScroll))

        ctx.saveGState(); NSBezierPath(rect: area).addClip()
        // dibujar de arriba (contenido) hacia abajo
        var cy: CGFloat = 0     // coord contenido desde arriba
        for (i, it) in items.enumerated() {
            let hi = heights[i]
            let screenTop = area.maxY - (cy - chatScroll)
            let rectTop = screenTop, rectBottom = screenTop - hi
            if rectBottom < area.maxY && rectTop > area.minY {     // visible
                drawChatItem(it, font: font, area: area, top: screenTop, height: hi, maxBW: maxBW)
            }
            cy += hi + spacing
        }
        ctx.restoreGState()

        // --- chip de captura adjunta (clic = quitar) ---
        if pendingShot != nil {
            let chip = NSRect(x: inputR.minX + 4, y: inputR.maxY - 22, width: 96, height: 20)
            NSColor(white: 0.92, alpha: 0.95).setFill(); NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
            if let path = pendingShotPath, let img = imgCache[path] ?? NSImage(contentsOfFile: path) {
                imgCache[path] = img; img.draw(in: NSRect(x: chip.minX + 3, y: chip.minY + 3, width: 22, height: 14))
            }
            drawText(Loc.t("captura", "capture"), chip.minX + 28, chip.minY + 4, size: 10, color: NSColor(white: 0.2, alpha: 1))
            drawText("✕", chip.maxX - 14, chip.minY + 3, size: 12, color: NSColor.systemRed)
            detachRect = chip
        } else { detachRect = .zero }

        // --- input (campo visible, multilínea) + botón enviar ---
        let fieldR = NSRect(x: inputR.minX + 2, y: inputR.minY + 2, width: inputR.width - 4 - sendW, height: inputR.height - 4 - chipH)
        let ip = NSBezierPath(roundedRect: fieldR, xRadius: 5, yRadius: 5)
        NSColor(white: 0.95, alpha: 0.95).setFill(); ip.fill()
        NSColor(white: 0.4, alpha: 1).setStroke(); ip.lineWidth = 1; ip.stroke()
        drawAttr(inputDisplayAttr(), in: fieldR.insetBy(dx: 7, dy: 5))

        // botón enviar (flechita)
        sendRect = NSRect(x: fieldR.maxX + 4, y: fieldR.minY, width: sendW - 4, height: fieldR.height)
        let active = !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatBusy
        let sp = NSBezierPath(roundedRect: sendRect, xRadius: 6, yRadius: 6)
        (active ? NSColor(srgbRed: 0.30, green: 0.66, blue: 0.98, alpha: 1) : NSColor(white: 0.5, alpha: 0.6)).setFill(); sp.fill()
        let arrow = "➤" as NSString
        let asz = arrow.size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
        drawText("➤", sendRect.midX - asz.width / 2, sendRect.midY - asz.height / 2, size: 13)
    }

    func drawChatItem(_ it: ChatItem, font: NSFont, area: NSRect, top: CGFloat, height: CGFloat, maxBW: CGFloat) {
        if it.kind == 2 {   // paso de herramienta / pensando (gris, sin burbuja)
            drawAttr(chatAttr(it), in: NSRect(x: area.minX + 6, y: top - height, width: area.width - 12, height: height))
            return
        }
        let isUser = it.kind == 1
        let hasImg = it.imagePath != nil
        let bw = bubbleWidth(it, maxBW)
        let bx = isUser ? area.maxX - bw : area.minX
        let rect = NSRect(x: bx, y: top - height, width: bw, height: height)
        let fill = isUser ? NSColor(srgbRed: 0.20, green: 0.42, blue: 0.78, alpha: 0.95)
                          : NSColor(srgbRed: 0.20, green: 0.55, blue: 0.38, alpha: 0.95)
        let p = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        fill.setFill(); p.fill()
        let imgH: CGFloat = hasImg ? 66 : 0
        let textRect = NSRect(x: rect.minX + 6, y: rect.minY + 6 + imgH, width: rect.width - 12, height: rect.height - 12 - imgH)
        drawAttr(chatAttr(it), in: textRect)
        // mensaje con archivo adjunto (transcripción): toda la burbuja es clicable
        if let path = it.filePath {
            NSColor(srgbRed: 0.62, green: 0.96, blue: 0.72, alpha: 0.9).setStroke()
            let bp = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5); bp.lineWidth = 1; bp.stroke()
            fileButtons.append((rect, path))
        }
        // thumbnail de la captura (clicable)
        if let path = it.imagePath {
            let thumb = NSRect(x: rect.minX + 6, y: rect.minY + 5, width: rect.width - 12, height: imgH - 4)
            let img = imgCache[path] ?? NSImage(contentsOfFile: path)
            if let img = img {
                imgCache[path] = img
                NSColor(white: 0, alpha: 0.3).setFill(); NSBezierPath(rect: thumb).fill()
                img.draw(in: thumb, from: .zero, operation: .sourceOver, fraction: 1.0,
                         respectFlipped: true, hints: [.interpolation: NSImageInterpolation.medium.rawValue])
                NSColor(white: 1, alpha: 0.4).setStroke(); NSBezierPath(rect: thumb).stroke()
                thumbRects.append((thumb, path))
            }
        }

        // botón de copiar al pasar el mouse sobre la burbuja
        if rect.insetBy(dx: -4, dy: -4).contains(chatMouse) {
            let cb = NSRect(x: rect.maxX - 22, y: rect.maxY - 16, width: 20, height: 14)
            let pb = NSBezierPath(roundedRect: cb, xRadius: 3, yRadius: 3)
            NSColor(white: 0.96, alpha: 0.97).setFill(); pb.fill()
            drawText("⧉", cb.minX + 4, cb.minY + 1, size: 10, color: NSColor(white: 0.12, alpha: 1))
            copyButtons.append((cb, it.text))
        }
    }

    func drawChatList(_ ctx: CGContext, _ area: NSRect) {
        drawText("Conversaciones:", area.minX + 4, area.maxY - 16, size: 11)
        var y = area.maxY - 38
        for (i, conv) in chatStore.conversations.enumerated().reversed() {
            let r = NSRect(x: area.minX + 2, y: y, width: area.width - 4, height: 24)
            let sel = i == convIndex
            let p = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            NSColor(white: sel ? 0.30 : 0.16, alpha: 0.9).setFill(); p.fill()
            drawText(String(conv.title.prefix(34)), r.minX + 8, r.minY + 5, size: 11)
            listRowRects.append(r)   // en orden de dibujo (reversed)
            y -= 28
            if y < area.minY { break }
        }
    }

    var chatFont: NSFont { NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) }
    var chatPara: NSParagraphStyle { let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping; return p }

    /// Convierte Markdown a texto con formato (negrita, itálica, código, listas, encabezados).
    func renderMarkdown(_ raw: String, color: NSColor) -> NSAttributedString {
        let pre = raw.components(separatedBy: "\n").map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") { return "**" + t.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) + "**" }
            if t.hasPrefix("- ") || t.hasPrefix("* ") { return "• " + t.dropFirst(2) }
            return line
        }.joined(separator: "\n")
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                           failurePolicy: .returnPartiallyParsedIfPossible)
        guard let m = try? NSMutableAttributedString(markdown: pre, options: opts) else {
            return NSAttributedString(string: raw, attributes: [.font: chatFont, .foregroundColor: color, .paragraphStyle: chatPara])
        }
        let full = NSRange(location: 0, length: m.length)
        m.addAttribute(.foregroundColor, value: color, range: full)
        m.addAttribute(.paragraphStyle, value: chatPara, range: full)
        m.enumerateAttribute(.font, in: full) { val, range, _ in
            var nf = chatFont
            if let f = val as? NSFont {
                let sym = f.fontDescriptor.symbolicTraits
                if sym.contains(.bold) { nf = NSFontManager.shared.convert(nf, toHaveTrait: .boldFontMask) }
                if sym.contains(.italic) { nf = NSFontManager.shared.convert(nf, toHaveTrait: .italicFontMask) }
            }
            m.addAttribute(.font, value: nf, range: range)
        }
        return m
    }

    func chatAttr(_ it: ChatItem) -> NSAttributedString {
        if it.kind == 2 {
            return NSAttributedString(string: it.text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor(white: 0.7, alpha: 0.9), .paragraphStyle: chatPara])
        }
        let key = "\(it.kind)|\(it.text)"
        if let c = attrCache[key] { return c }
        let a = renderMarkdown(it.text, color: .white)
        attrCache[key] = a
        return a
    }

    func inputDisplayAttr() -> NSAttributedString {
        let placeholder = chatInput.isEmpty && !chatBusy
        let cursor = (tick / 15) % 2 == 0 ? "▌" : ""
        let text = placeholder
            ? (pendingShot != nil ? Loc.t("pregunta sobre la captura…", "ask about the capture…") : Loc.t("escribe aquí…", "type here…"))
            : chatInput + cursor
        let color = placeholder ? NSColor(white: 0.5, alpha: 1) : NSColor(white: 0.1, alpha: 1)
        return NSAttributedString(string: text, attributes: [.font: inputFont, .foregroundColor: color, .paragraphStyle: chatPara])
    }

    func attrSize(_ a: NSAttributedString, _ maxW: CGFloat) -> NSSize {
        let r = a.boundingRect(with: NSSize(width: maxW, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return NSSize(width: ceil(r.width), height: ceil(r.height) + 6)   // margen extra para no cortar
    }

    /// Dibuja texto alineado ARRIBA en nuestra vista no-invertida, usando una imagen volteada.
    func drawAttr(_ a: NSAttributedString, in rect: NSRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        let img = NSImage(size: rect.size, flipped: true) { b in
            a.draw(with: b, options: [.usesLineFragmentOrigin, .usesFontLeading]); return true
        }
        img.draw(in: rect)
    }

    /// Ancho de burbuja para un mensaje (texto o con imagen).
    func bubbleWidth(_ it: ChatItem, _ maxBW: CGFloat) -> CGFloat {
        let w = attrSize(chatAttr(it), maxBW - 12).width
        return max(it.imagePath != nil ? 116 : 0, min(maxBW, w + 14))
    }
    /// Altura de burbuja medida al MISMO ancho con el que se dibuja el texto.
    func bubbleHeight(_ it: ChatItem, _ maxBW: CGFloat, _ areaW: CGFloat) -> CGFloat {
        if it.kind == 2 { return attrSize(chatAttr(it), areaW - 12).height + 4 }
        let bw = bubbleWidth(it, maxBW)
        return attrSize(chatAttr(it), bw - 12).height + 12 + (it.imagePath != nil ? 70 : 0)
    }

    func textSize(_ s: String, font: NSFont, maxW: CGFloat) -> NSSize {
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
        let r = (s as NSString).boundingRect(with: NSSize(width: maxW, height: 4000),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading],
                                             attributes: [.font: font, .paragraphStyle: para])
        return NSSize(width: ceil(r.width), height: ceil(r.height))
    }

    func handleChatTap(_ p: NSPoint) -> Bool {
        if detachRect != .zero && detachRect.contains(p) {           // quitar la captura adjunta
            pendingShot = nil; pendingShotPath = nil; needsDisplay = true; return true
        }
        if sendRect.contains(p) { sendChatMessage(); return true }   // botón enviar
        for t in thumbRects where t.rect.contains(p) {          // abrir la captura
            NSWorkspace.shared.open(URL(fileURLWithPath: t.path))
            return true
        }
        for f in fileButtons where f.rect.contains(p) {         // abrir la transcripción completa
            NSWorkspace.shared.open(URL(fileURLWithPath: f.path))
            return true
        }
        for cb in copyButtons where cb.rect.contains(p) {       // copiar texto de una burbuja
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cb.text, forType: .string)
            stepLines = ["✓ copiado al portapapeles"]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if self?.stepLines == ["✓ copiado al portapapeles"] { self?.stepLines = []; self?.needsDisplay = true }
            }
            needsDisplay = true
            return true
        }
        for b in chatButtons where b.rect.contains(p) {
            switch b.id {
            case "close": toggleChat()
            case "new": newConversation()
            case "list": listOpen.toggle(); needsDisplay = true
            case "eye": captureScreen()
            case "ear": onToggleListen?()
            default: break
            }
            return true
        }
        if listOpen {
            // las filas se dibujaron en orden reverse(enumerate)
            let order = Array(chatStore.conversations.indices.reversed())
            for (k, r) in listRowRects.enumerated() where r.contains(p) {
                if k < order.count { selectConversation(order[k]) }
                return true
            }
            return true   // clic dentro de la lista: consumir
        }
        return false
    }

    // ------------------------------------------------------------------
    // Menú contextual (clic derecho)
    // ------------------------------------------------------------------
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        // Alimentar (submenú de comidas)
        let feed = NSMenuItem(title: Loc.t("Alimentar 🍖", "Feed 🍖"), action: nil, keyEquivalent: "")
        let fm = NSMenu()
        for food in Food.allCases {
            let it = NSMenuItem(title: "\(food.emoji)  \(food.name)", action: #selector(feedFromMenu(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = food.rawValue; fm.addItem(it)
        }
        feed.submenu = fm; menu.addItem(feed)

        func add(_ t: String, _ sel: Selector) {
            let it = NSMenuItem(title: t, action: sel, keyEquivalent: ""); it.target = self; menu.addItem(it)
        }
        add(Loc.t("Jugar 🎮", "Play 🎮"), #selector(ctxPlay))
        add(Loc.t("Limpiar 🛁", "Clean 🛁"), #selector(ctxClean))
        add(Loc.t("Medicina 💊", "Medicine 💊"), #selector(ctxMed))
        add(Loc.t("Dormir / Despertar 💤", "Sleep / Wake 💤"), #selector(ctxSleep))
        menu.addItem(.separator())
        add(Loc.t("Pasear 🚶", "Walk 🚶"), #selector(ctxWalk))
        add(Loc.t("Bailar 💃", "Dance 💃"), #selector(ctxDance))
        add(Loc.t("Rodar 🤸", "Roll 🤸"), #selector(ctxRoll))
        add(Loc.t("Perseguir 🏃", "Chase 🏃"), #selector(ctxChase))
        menu.addItem(.separator())
        add(Loc.t("Hablar 💬", "Chat 💬"), #selector(ctxChat))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func ctxPlay()  { doPlay() }
    @objc func ctxClean() { doClean() }
    @objc func ctxMed()   { doMedicine() }
    @objc func ctxSleep() { doSleep() }
    @objc func ctxWalk()  { if let s = window?.screen ?? NSScreen.main { startWalking(in: s) } }
    @objc func ctxDance() { enter(.dancing) }
    @objc func ctxRoll()  { enter(.rolling) }
    @objc func ctxChase() { enter(.chasing) }
    @objc func ctxChat()  { onChatRequested?() }

    // ------------------------------------------------------------------
    // Mouse
    // ------------------------------------------------------------------
    override func mouseDown(with event: NSEvent) {
        if chatActive {
            window?.makeFirstResponder(self)        // recuperar foco para escribir
            let p = convert(event.locationInWindow, from: nil)
            if handleChatTap(p) { consumedByButton = true; return }
            if p.y > 88 { consumedByButton = true; return }   // clic en el panel: ni arrastra ni salta
        }
        let p = convert(event.locationInWindow, from: nil)
        consumedByButton = false
        // ¿clic en un botón del HUD?
        if hudAlpha > 0.4 {
            for b in buttons where b.rect.insetBy(dx: -3, dy: -3).contains(p) {
                consumedByButton = true; handleButton(b.id, at: event); return
            }
        }
        mouseDownAt = NSEvent.mouseLocation
        didDrag = false
        grabbedSlime = slimeHitRect().contains(p)       // solo cuenta si tocaste al slime
        if grabbedSlime && stats.isAsleep {             // moverlo lo despierta
            stats.isAsleep = false
            stats.energy = max(stats.energy, 0.12)
            if state == .sleeping { enter(.idle) }
        }
        if let win = petWindow {
            let m = NSEvent.mouseLocation
            dragOffset = NSPoint(x: m.x - win.frame.origin.x, y: m.y - win.frame.origin.y)
        }
    }

    /// Zona "agarrable": el cuerpo del slime (abajo-centro).
    func slimeHitRect() -> NSRect {
        NSRect(x: slimeOX + 4 * PX, y: 0, width: 24 * PX, height: 22 * PX)
    }

    override func mouseDragged(with event: NSEvent) {
        if consumedByButton || chatActive || !grabbedSlime { return }   // solo arrastra si agarraste al slime
        guard !stats.isDead, state != .egg else { return }
        let m = NSEvent.mouseLocation
        if hypot(m.x - mouseDownAt.x, m.y - mouseDownAt.y) > 4 { didDrag = true }
        if didDrag, let win = petWindow {
            enter(.dragging)
            let vf = (win.screen ?? NSScreen.main)?.visibleFrame ?? win.frame
            var newOrigin = NSPoint(x: m.x - dragOffset.x, y: m.y - dragOffset.y)
            // no dejar salir de la pantalla
            let (minX, maxX) = originXBounds(vf)
            newOrigin.x = max(minX, min(maxX, newOrigin.x))
            newOrigin.y = max(vf.minY, min(vf.maxY - bounds.height, newOrigin.y))
            vx = (newOrigin.x - win.frame.origin.x) * 0.5
            win.setFrameOrigin(newOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if consumedByButton { consumedByButton = false; return }
        if chatActive { return }        // con el chat abierto, el slime no salta
        if !grabbedSlime { return }     // solo reacciona si tocaste al slime, no la burbuja/vacío
        if stats.isDead || state == .egg { return }
        if didDrag {
            vy = 0
            // ¿soltado pegado a un costado? -> se escurre por la pared
            if let win = petWindow, let vf = (win.screen ?? NSScreen.main)?.visibleFrame {
                let (minX, maxX) = originXBounds(vf)
                let thresh: CGFloat = 6
                if win.frame.origin.x <= minX + thresh && win.frame.minY > vf.minY + 4 {
                    wallSide = -1; enter(.stuckWall); return
                }
                if win.frame.origin.x >= maxX - thresh && win.frame.minY > vf.minY + 4 {
                    wallSide = 1; enter(.stuckWall); return
                }
            }
            enter(.falling); return
        }
        if tick - lastClickTick < 25 { loveClicks += 1 } else { loveClicks = 1 }
        lastClickTick = tick
        if loveClicks >= 2 { loveClicks = 0; doPlay() }            // doble clic = jugar
        else {
            vy = 12; enter(.reacting)
            if Date().timeIntervalSince(lastClickTalk) > 5 { lastClickTalk = Date(); react(.clicked) }
        }
    }

    func handleButton(_ id: String, at event: NSEvent) {
        switch id {
        case "feed": showFoodMenu(at: event)
        case "play": doPlay()
        case "clean": doClean()
        case "med": doMedicine()
        case "sleep": doSleep()
        case "restart": doRestart()
        case "chat": onChatRequested?()
        default: break
        }
    }

    func showFoodMenu(at event: NSEvent) {
        let menu = NSMenu()
        for food in Food.allCases {
            let item = NSMenuItem(title: "\(food.emoji)  \(food.name)", action: #selector(feedFromMenu(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = food.rawValue
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }
    @objc func feedFromMenu(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let f = Food(rawValue: raw) { doFeed(f) }
    }
}

// MARK: - Ventana flotante transparente

final class PetWindow: NSWindow {
    init() {
        let size = NSSize(width: 160, height: 140)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        sharingType = .none          // por defecto: no aparecer en grabaciones / compartir pantalla
        acceptsMouseMovedEvents = true
        level = .floating; ignoresMouseEvents = false; isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY))
        }
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// `hidden=true` => la ventana no aparece en capturas/grabaciones/compartir pantalla.
    func applyCapturePrivacy(_ hidden: Bool) { sharingType = hidden ? .none : .readOnly }
}

// MARK: - Ícono de la barra de menús (mismo pixel-art del slime)

/// Dibuja el slime verde (cuerpo + brillo + cara feliz) en una NSImage pequeña,
/// usando la misma lógica de grilla que `PetView.drawSlime` / `drawFace`.
/// Es el mismo arte del ícono de la app, pero sin fondo, para el status item.
func slimeStatusImage(size S: CGFloat = 18) -> NSImage {
    let body  = NSColor(srgbRed: 0.36, green: 0.85, blue: 0.55, alpha: 1)
    let dark  = NSColor(srgbRed: 0.20, green: 0.62, blue: 0.40, alpha: 1)
    let light = NSColor(srgbRed: 0.62, green: 0.96, blue: 0.72, alpha: 1)
    let shine = NSColor(srgbRed: 0.92, green: 1.00, blue: 0.95, alpha: 1)
    let eye      = NSColor(srgbRed: 0.10, green: 0.16, blue: 0.18, alpha: 1)
    let eyeWhite = NSColor.white
    let mouth    = NSColor(srgbRed: 0.15, green: 0.40, blue: 0.28, alpha: 1)

    let img = NSImage(size: NSSize(width: S, height: S), flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        let cx = 16.0, footY = 3
        let halfW = 11.0, height = 17.0
        let cell = S * 0.94 / 23.0                 // encaja el ancho del slime (~23 celdas)
        let originX = S / 2 - CGFloat(cx) * cell
        let originY = S / 2 - 11.5 * cell           // centra el bbox vertical (grid y ≈ 3..20)
        func fill(_ gx: Int, _ gy: Int, _ c: NSColor) {
            ctx.setShouldAntialias(false)
            ctx.setFillColor(c.cgColor)
            ctx.fill(CGRect(x: originX + CGFloat(gx) * cell, y: originY + CGFloat(gy) * cell,
                            width: cell + 0.4, height: cell + 0.4))
        }
        // cuerpo (misma fórmula elíptica + borde + highlight)
        for gy in 0..<Int(height) {
            let t = Double(gy) / height
            var w = halfW * (max(0, 1 - pow(t, 2.2))).squareRoot()
            w += sin(t * 3) * 0.25
            let xw = Int(w.rounded()); let y = footY + gy
            for dx in -xw...xw {
                let gx = Int(cx) + dx
                let edge = dx <= -xw + 1 || dx >= xw - 1 || gy == 0 || gy >= Int(height) - 1
                if edge { fill(gx, y, dark) }
                else if dx < 0 && t > 0.45 && t < 0.85 && dx > -xw + 3 { fill(gx, y, light) }
                else { fill(gx, y, body) }
            }
        }
        let shineY = footY + Int(height * 0.72)
        fill(Int(cx) - 4, shineY, shine); fill(Int(cx) - 5, shineY, shine); fill(Int(cx) - 4, shineY - 1, shine)
        // cara feliz mirando al frente
        let faceY = footY + Int(height * 0.45)
        let leftX = Int(cx) - 4, rightX = Int(cx) + 4
        func eyeOpen(_ ex: Int) {
            for oy in 0..<4 { for ox in 0..<3 { fill(ex + ox, faceY + oy, eyeWhite) } }
            for oy in 0..<2 { for ox in 0..<2 { fill(ex + 1 + ox, faceY + 1 + oy, eye) } }
        }
        eyeOpen(leftX); eyeOpen(rightX)
        for ox in -2...2 { fill(Int(cx) + ox, faceY - 3, mouth) }
        for ox in -1...1 { fill(Int(cx) + ox, faceY - 4, mouth) }
        return true
    }
    img.isTemplate = false      // a color (no monocromo), como el ícono de la app
    return img
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: PetWindow!
    var view: PetView!
    var timer: Timer?
    var statusItem: NSStatusItem?
    var lastTick = Date()
    var frame = 0
    var activity: NSObjectProtocol?

    // rate-limit de avisos
    var alerted: [String: Date] = [:]

    func applicationDidFinishLaunching(_ note: Notification) {
        // Log de arranque: ruta del binario + estado del permiso de pantalla (TCC).
        // Si CGPreflight cambia de true→false entre lanzamientos, la firma no es estable.
        Log.write("🚀 Flubber arrancó — bin=\(Bundle.main.executablePath ?? "?") · permiso pantalla(preflight)=\(CGPreflightScreenCaptureAccess())")

        // Evita que macOS "duerma" la app en segundo plano (necesitamos seguir animando).
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "SlimePet animation loop")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        window = PetWindow()
        view = PetView(frame: window.contentRect(forFrameRect: window.frame))
        view.petWindow = window
        view.stats = PetStats.load()
        Pal.index = min(max(0, view.stats.skinIndex), Pal.skins.count - 1)
        view.state = view.stats.isDead ? .dead : (view.stats.stage == .egg ? .egg : .idle)
        view.restoreActiveConversation()             // abre la última conversación que usabas

        // IA
        let cfg = AIConfig.load()
        Loc.override = cfg.lang                      // idioma guardado (nil = sistema)
        view.client = makeBackend(cfg)
        window.applyCapturePrivacy(cfg.hideFromCaptureValue)   // oculto por defecto
        if let spec = cfg.customSkin, let skin = Pal.skin(from: spec) { Pal.setAISkin(skin) }
        view.onChatRequested = { [weak self] in self?.openChat() }
        view.onToggleListen = { [weak self] in self?.toggleListen() }

        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        // saludo al abrir
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let v = self?.view else { return }
            if v.stats.isDead {                                   // murió mientras estuvo cerrado
                self?.notify("💀 \(v.stats.displayName) " + Loc.t("ha muerto", "has died"),
                             Loc.t("Lo descuidaste demasiado… toca 🥚 para empezar de nuevo.",
                                   "Too neglected… tap 🥚 to start over."))
                return
            }
            guard v.stats.stage != .egg else { return }
            v.react(.greeting)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = slimeStatusImage()      // mismo slime pixel-art que el ícono
        statusItem?.button?.title = ""
        rebuildMenu()

        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tickLoop() }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func tickLoop() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        let events = view.advance(realDt: dt)
        handleEvents(events)
        checkAttentionAlerts()
        frame += 1
        if frame % 300 == 0 { view.stats.save() }     // guarda cada ~10 s
    }

    func handleEvents(_ events: [PetEvent]) {
        let n = view.stats.displayName
        for e in events {
            switch e {
            case .gotSick: notify("🤒 \(n) " + Loc.t("se enfermó", "got sick"), Loc.t("Dale medicina 💊 para que se recupere.", "Give it medicine 💊 to recover.")); view.reactSpontaneous(.sick)
            case .died:    notify("💀 \(n) " + Loc.t("ha muerto", "has died"), Loc.t("Lo descuidaste demasiado… toca 🥚 para empezar de nuevo.", "Too neglected… tap 🥚 to start over.")); view.say(Personality.canned(.died)); view.stats.save()
            case .evolved:  notify("✨ ¡\(n) " + Loc.t("creció!", "grew up!"), Loc.t("Sigue cuidándolo.", "Keep taking care of it.")); view.react(.evolved); view.stats.save()
            case .hatched: notify("🐣 " + Loc.t("¡Nació \(n)!", "\(n) was born!"), Loc.t("Cuídalo bien para que crezca sano.", "Take good care of it.")); view.react(.hatched); view.stats.save()
            case .pooped: break
            }
        }
    }

    func checkAttentionAlerts() {
        let s = view.stats
        guard !s.isDead, s.stage != .egg else { return }
        func maybe(_ key: String, _ cond: Bool, _ title: String, _ body: String) {
            if cond {
                if let last = alerted[key], Date().timeIntervalSince(last) < 600 { return }   // máx 1 cada 10 min
                alerted[key] = Date(); notify(title, body)
            } else { alerted[key] = nil }
        }
        let n = s.displayName
        maybe("hunger", s.hunger < Tuning.lowThreshold, Loc.t("🍖 ¡Tengo hambre!", "🍖 I'm hungry!"), Loc.t("\(n) necesita comer.", "\(n) needs to eat."))
        maybe("energy", s.energy < Tuning.lowThreshold, Loc.t("😴 Estoy agotado", "😴 I'm exhausted"), Loc.t("\(n) necesita dormir.", "\(n) needs to sleep."))
        maybe("clean",  s.cleanliness < Tuning.lowThreshold, Loc.t("🛁 ¡Qué sucio!", "🛁 So dirty!"), Loc.t("Hay que limpiar a \(n).", "\(n) needs a clean."))

        // que también lo diga en el globo, al mismo umbral que aparece el botón
        if s.isSick { view.reactSpontaneous(.sick) }
        else if s.hunger < Tuning.careShow { view.reactSpontaneous(.hungry) }
        else if s.energy < Tuning.careShow { view.reactSpontaneous(.tired) }
        else if s.cleanliness < Tuning.careShow { view.reactSpontaneous(.dirty) }
    }

    func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: Loc.t("Alimentar 🍖", "Feed 🍖"), action: #selector(mFeed), keyEquivalent: "f"))
        menu.addItem(NSMenuItem(title: Loc.t("Jugar 🎮", "Play 🎮"), action: #selector(mPlay), keyEquivalent: "g"))
        menu.addItem(NSMenuItem(title: Loc.t("Limpiar 🛁", "Clean 🛁"), action: #selector(mClean), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: Loc.t("Medicina 💊", "Medicine 💊"), action: #selector(mMed), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: Loc.t("Dormir / Despertar 💤", "Sleep / Wake 💤"), action: #selector(mSleep), keyEquivalent: "s"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Loc.t("Hablar con \(view.stats.displayName)… 💬", "Chat with \(view.stats.displayName)… 💬"), action: #selector(openChat), keyEquivalent: "t"))
        if #available(macOS 13.0, *) {
            let l = MeetingListener.shared
            let title = l.isListening
                ? Loc.t("Dejar de escuchar la reunión ⏹️", "Stop listening to meeting ⏹️")
                : Loc.t("Escuchar la reunión 🎧", "Listen to meeting 🎧")
            menu.addItem(NSMenuItem(title: title, action: #selector(toggleListen), keyEquivalent: ""))
            if !l.fullText.isEmpty {
                menu.addItem(NSMenuItem(title: Loc.t("Resumir la reunión 📝", "Summarize meeting 📝"), action: #selector(summarizeMeeting), keyEquivalent: ""))
            }
        }
        menu.addItem(NSMenuItem(title: Loc.t("Crear skin con IA… 🎨✨", "Create AI skin… 🎨✨"), action: #selector(makeSkin), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: Loc.t("Configurar IA… ⚙️", "AI settings… ⚙️"), action: #selector(showConfig), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: Loc.t("Restablecer permisos 🔒", "Reset permissions 🔒"), action: #selector(resetPerms), keyEquivalent: ""))
        let hideItem = NSMenuItem(title: Loc.t("Ocultar en capturas/grabaciones 🕵️", "Hide from captures/recordings 🕵️"), action: #selector(toggleHideFromCapture), keyEquivalent: "")
        hideItem.state = (view.client?.config.hideFromCaptureValue ?? true) ? .on : .off
        menu.addItem(hideItem)
        menu.addItem(NSMenuItem(title: Loc.t("Idioma: English 🌐", "Language: Español 🌐"), action: #selector(toggleLang), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Loc.t("¡Pasea!", "Walk!"), action: #selector(walkNow), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: Loc.t("Persíguelo", "Chase cursor"), action: #selector(chaseNow), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: Loc.t("¡Baila! 💃", "Dance! 💃"), action: #selector(danceNow), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: Loc.t("¡Rueda! 🤸", "Roll! 🤸"), action: #selector(rollNow), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Loc.t("Ponerle nombre 🏷️", "Set name 🏷️"), action: #selector(setNameDialog), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: Loc.t("Cambiar color 🎨", "Change color 🎨"), action: #selector(cycleColor), keyEquivalent: "k"))
        menu.addItem(NSMenuItem(title: Loc.t("Nuevo huevo 🥚 (reiniciar)", "New egg 🥚 (restart)"), action: #selector(restart), keyEquivalent: ""))
        menu.addItem(.separator())
        let li = NSMenuItem(title: Loc.t("Iniciar al encender el Mac 🔌", "Launch at login 🔌"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        if #available(macOS 13, *) { li.state = SMAppService.mainApp.status == .enabled ? .on : .off }
        menu.addItem(li)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Loc.t("Salir de Flubber", "Quit Flubber"), action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func toggleLang() {
        let next = Loc.lang == .es ? "en" : "es"     // alterna respecto al idioma efectivo
        Loc.override = next
        view.client?.config.lang = next
        view.client?.config.save()
        view.agent = nil                              // re-siembra prompts en el nuevo idioma
        rebuildMenu()
        view.needsDisplay = true
    }

    @objc func mFeed()  { view.doFeed(.meat) }
    @objc func mPlay()  { view.doPlay() }
    @objc func mClean() { view.doClean() }
    @objc func mMed()   { view.doMedicine() }
    @objc func mSleep() { view.doSleep() }
    @objc func walkNow()  { if let s = NSScreen.main { view.startWalking(in: s) } }
    @objc func chaseNow() { view.enter(.chasing) }
    @objc func danceNow() { view.enter(.dancing) }
    @objc func rollNow()  { view.enter(.rolling) }
    @objc func cycleColor() { Pal.index = (Pal.index + 1) % Pal.skins.count; view.stats.skinIndex = Pal.index }
    @objc func restart() { view.doRestart() }
    @objc func toggleLaunchAtLogin() {
        guard #available(macOS 13, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSLog("login item: \(error)") }
        rebuildMenu()
    }
    @objc func resetPerms() {
        guard var c = view.client?.config else { return }
        c.allowBrowser = nil; c.allowCommand = nil; c.allowOpen = nil
        view.client?.config = c; c.save()
    }
    @objc func toggleHideFromCapture() {
        guard var c = view.client?.config else { return }
        let next = !c.hideFromCaptureValue
        c.hideFromCapture = next
        view.client?.config = c; c.save()
        window.applyCapturePrivacy(next)
        rebuildMenu()
    }
    @objc func setNameDialog() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Ponerle nombre a tu slime 🏷️"
        a.informativeText = "¿Cómo quieres llamarlo?"
        let tf = PastableTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.stringValue = view.stats.name ?? ""
        a.accessoryView = tf
        a.addButton(withTitle: "Guardar"); a.addButton(withTitle: "Cancelar")
        if a.runModal() == .alertFirstButtonReturn { view.setName(tf.stringValue) }
    }

    // --- IA: chat integrado ---
    @objc func openChat() {
        if view.client?.config.isConfigured != true { showNeedConfig(); return }
        view.toggleChat()
    }

    // --- Escuchar reunión (audio del sistema → transcripción on-device) ---
    @objc func toggleListen() {
        guard #available(macOS 13.0, *) else {
            notify("Flubber", Loc.t("La escucha requiere macOS 13+.", "Listening requires macOS 13+.")); return
        }
        let l = MeetingListener.shared
        Log.write("🎧 toggleListen — isListening=\(l.isListening)")
        if l.isListening {
            l.stop()
            view.listening = false
            view.say(Loc.t("Listo, déjame contarte lo que escuché… 📝", "Done, let me tell you what I heard… 📝"))
            rebuildMenu()
            // Espera a que el último segmento de voz se vuelque y cierra/resume.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                Log.write("📝 stop → finalizando reunión (síntesis + transcripción)")
                self?.view.finishMeeting()
            }
        } else {
            l.start { [weak self] ok, err in
                DispatchQueue.main.async {
                    Log.write("🎧 toggleListen.start callback ok=\(ok) err=\(err ?? "-")")
                    if ok {
                        self?.view.listening = true
                        self?.view.beginMeeting()                  // nueva sesión + resúmenes rodantes
                        self?.view.say(Loc.t("Escuchando… 🎧", "Listening… 🎧"))
                    } else {
                        self?.notify("Flubber", err ?? Loc.t("No pude escuchar.", "Couldn't listen."))
                    }
                    self?.rebuildMenu()
                }
            }
        }
    }

    @objc func summarizeMeeting() {
        guard #available(macOS 13.0, *) else { return }
        let text = MeetingListener.shared.fullText
        guard !text.isEmpty else { notify("Flubber", Loc.t("Aún no hay nada transcrito.", "Nothing transcribed yet.")); return }
        guard let client = view.client, client.isConfigured else { showNeedConfig(); return }
        view.say(Loc.t("Resumiendo… 📝", "Summarizing… 📝"))
        let sys = Loc.t("Eres un asistente que resume reuniones. Devuelve: 1) resumen breve, 2) puntos clave, 3) tareas/acuerdos. Solo en español.",
                        "You summarize meetings. Return: 1) short summary, 2) key points, 3) action items. English only.")
        let prompt = Loc.t("Transcripción (audio del sistema, puede tener errores):\n\n",
                           "Transcript (system audio, may contain errors):\n\n") + text
        client.chat(system: sys, history: [], user: prompt, maxTokens: 1200) { [weak self] reply in
            DispatchQueue.main.async {
                let s = reply.map { Agent.cleanFinal($0) } ?? ""
                self?.showSummary(s.isEmpty ? Loc.t("No pude generar el resumen.", "Couldn't generate the summary.") : s)
            }
        }
    }

    private func showSummary(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = Loc.t("Resumen de la reunión", "Meeting summary")
        a.informativeText = text
        a.addButton(withTitle: Loc.t("Copiar", "Copy"))
        a.addButton(withTitle: "OK")
        if a.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    // --- IA: crear skin ---
    @objc func makeSkin() {
        guard view.client?.config.isConfigured == true else { showNeedConfig(); return }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Crear skin con IA 🎨"
        a.informativeText = "Describe un tema (ej: lava, galaxia, arcoíris, ninja):"
        let tf = PastableTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        a.accessoryView = tf
        a.addButton(withTitle: "Generar"); a.addButton(withTitle: "Cancelar")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let theme = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !theme.isEmpty else { return }
        view.bubbleThinking = true; view.bubbleUntil = Date().addingTimeInterval(25)
        view.client?.chat(system: "Eres un diseñador de paletas de color. Responde SOLO con JSON, sin texto extra.",
                          history: [], user: Personality.skinPrompt(theme: theme), maxTokens: 800) { [weak self] reply in
            guard let self = self else { return }
            if let r = reply, let spec = Personality.parseSkin(r) {
                self.view.applyAISkin(spec)
                var cfg = self.view.client!.config; cfg.customSkin = spec; cfg.save()
                self.view.client!.config = cfg
                self.view.stats.skinIndex = Pal.index
            } else {
                self.view.say("No pude crear ese skin 😅")
            }
        }
    }

    func showNeedConfig() {
        let a = NSAlert()
        a.messageText = "Necesitas configurar la IA"
        a.informativeText = "Agrega tu clave de MiniMax en «Configurar IA… ⚙️» para usar esta función."
        a.runModal()
    }

    // --- IA: configuración ---
    var configController: ConfigController?
    @objc func showConfig() {
        if configController == nil {
            configController = ConfigController(config: view.client?.config ?? AIConfig()) { [weak self] newCfg in
                self?.view.client = makeBackend(newCfg)
            }
        }
        configController?.config = view.client?.config ?? AIConfig()
        configController?.show()
    }

    @objc func quit() { view.stats.save(); NSApp.terminate(nil) }

    func applicationWillTerminate(_ n: Notification) { view.stats.save() }
}

// MARK: - Campos de texto que aceptan ⌘V/⌘C/⌘X/⌘A en apps sin barra de menús

private func handleEditingShortcut(_ event: NSEvent, _ sender: NSView) -> Bool {
    guard event.modifierFlags.contains(.command),
          let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }
    let sel: Selector?
    switch chars {
    case "v": sel = #selector(NSText.paste(_:))
    case "c": sel = #selector(NSText.copy(_:))
    case "x": sel = #selector(NSText.cut(_:))
    case "a": sel = #selector(NSText.selectAll(_:))
    case "z": sel = Selector(("undo:"))
    default:  sel = nil
    }
    if let sel = sel { return NSApp.sendAction(sel, to: nil, from: sender) }
    return false
}

final class PastableTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event, self) || super.performKeyEquivalent(with: event)
    }
}
final class PastableSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event, self) || super.performKeyEquivalent(with: event)
    }
}

// MARK: - Ventana de configuración de IA

final class ConfigController: NSObject, NSWindowDelegate {
    var window: NSWindow!
    var config: AIConfig
    let onSave: (AIConfig) -> Void

    private var providerPopup: NSPopUpButton!
    private var mmBox: NSView!, clBox: NSView!, oaBox: NSView!, dsBox: NSView!
    private var mmKeyField: NSSecureTextField!, clKeyField: NSSecureTextField!
    private var oaKeyField: NSSecureTextField!, dsKeyField: NSSecureTextField!
    private var mmModelPopup: NSPopUpButton!, clModelPopup: NSPopUpButton!
    private var oaModelPopup: NSPopUpButton!, dsModelPopup: NSPopUpButton!
    private var statusLabel: NSTextField!

    // orden de proveedores en el popup
    private let providers = ["minimax", "claude", "openai", "deepseek"]
    private let mmTitles = ["MiniMax-M2.7", "MiniMax-M2.5", "MiniMax-M2.1", "MiniMax-M2"]
    private let clTitles = ["Haiku 4.5 (económico)", "Sonnet 4.6", "Opus 4.8"]
    private let clValues = ["claude-haiku-4-5-20251001", "claude-sonnet-4-6", "claude-opus-4-8"]
    private let oaModels = ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini"]
    private let dsModels = ["deepseek-chat", "deepseek-reasoner"]
    private func provIndex() -> Int { providerPopup.indexOfSelectedItem }

    init(config: AIConfig, onSave: @escaping (AIConfig) -> Void) {
        self.config = config; self.onSave = onSave
        super.init(); build()
    }

    private func label(_ s: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.frame = NSRect(x: x, y: y, width: w, height: 18)
        if bold { l.font = NSFont.boldSystemFont(ofSize: 12) }
        l.textColor = .secondaryLabelColor
        return l
    }

    private func build() {
        let W: CGFloat = 470, H: CGFloat = 300
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = Loc.t("Configuración de IA — Flubber", "AI Settings — Flubber")
        w.isReleasedWhenClosed = false; w.delegate = self
        let c = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))

        c.addSubview(label("Elige el proveedor y pega tu clave. Se guarda en un archivo local protegido (solo tú).", 20, H-30, W-40, bold: true))

        c.addSubview(label("Proveedor:", 20, H-64, 90))
        providerPopup = NSPopUpButton(frame: NSRect(x: 110, y: H-68, width: 200, height: 26))
        providerPopup.addItems(withTitles: ["MiniMax", "Claude (Anthropic)", "ChatGPT (OpenAI)", "DeepSeek"])
        providerPopup.target = self; providerPopup.action = #selector(providerChanged)
        c.addSubview(providerPopup)

        let console = NSButton(title: "Abrir consola ↗", target: self, action: #selector(openConsole))
        console.frame = NSRect(x: W-160, y: H-69, width: 140, height: 28); c.addSubview(console)

        // Las secciones ocupan el mismo espacio; solo se ve la del proveedor activo.
        let boxFrame = NSRect(x: 20, y: 110, width: W-40, height: 110)
        mmBox = NSView(frame: boxFrame); clBox = NSView(frame: boxFrame)
        oaBox = NSView(frame: boxFrame); dsBox = NSView(frame: boxFrame)
        c.addSubview(mmBox); c.addSubview(clBox); c.addSubview(oaBox); c.addSubview(dsBox)

        func boxLabel(_ s: String, _ y: CGFloat, bold: Bool = false) -> NSTextField {
            let l = NSTextField(labelWithString: s); l.frame = NSRect(x: 0, y: y, width: boxFrame.width, height: 18)
            if bold { l.font = NSFont.boldSystemFont(ofSize: 12) }; l.textColor = .secondaryLabelColor; return l
        }

        // MiniMax
        mmBox.addSubview(boxLabel("Clave de MiniMax (Token Plan):", 88, bold: true))
        mmKeyField = PastableSecureTextField(frame: NSRect(x: 0, y: 58, width: boxFrame.width, height: 24))
        mmKeyField.placeholderString = "clave de MiniMax (⌘V para pegar)"; mmBox.addSubview(mmKeyField)
        let mmModelLbl = boxLabel("Modelo:", 26); mmModelLbl.frame.size.width = 64; mmBox.addSubview(mmModelLbl)
        mmModelPopup = NSPopUpButton(frame: NSRect(x: 70, y: 22, width: 220, height: 26))
        mmModelPopup.addItems(withTitles: mmTitles); mmBox.addSubview(mmModelPopup)

        // Claude
        clBox.addSubview(boxLabel("Clave API de Claude (sk-ant-…):", 88, bold: true))
        clKeyField = PastableSecureTextField(frame: NSRect(x: 0, y: 58, width: boxFrame.width, height: 24))
        clKeyField.placeholderString = "clave de Anthropic (⌘V para pegar)"; clBox.addSubview(clKeyField)
        let clModelLbl = boxLabel("Modelo:", 26); clModelLbl.frame.size.width = 64; clBox.addSubview(clModelLbl)
        clModelPopup = NSPopUpButton(frame: NSRect(x: 70, y: 22, width: 220, height: 26))
        clModelPopup.addItems(withTitles: clTitles); clBox.addSubview(clModelPopup)

        // ChatGPT (OpenAI)
        oaBox.addSubview(boxLabel("Clave API de OpenAI (sk-…):", 88, bold: true))
        oaKeyField = PastableSecureTextField(frame: NSRect(x: 0, y: 58, width: boxFrame.width, height: 24))
        oaKeyField.placeholderString = "clave de OpenAI (⌘V para pegar)"; oaBox.addSubview(oaKeyField)
        let oaModelLbl = boxLabel("Modelo:", 26); oaModelLbl.frame.size.width = 64; oaBox.addSubview(oaModelLbl)
        oaModelPopup = NSPopUpButton(frame: NSRect(x: 70, y: 22, width: 220, height: 26))
        oaModelPopup.addItems(withTitles: oaModels); oaBox.addSubview(oaModelPopup)

        // DeepSeek
        dsBox.addSubview(boxLabel("Clave API de DeepSeek (sk-…):", 88, bold: true))
        dsKeyField = PastableSecureTextField(frame: NSRect(x: 0, y: 58, width: boxFrame.width, height: 24))
        dsKeyField.placeholderString = "clave de DeepSeek (⌘V para pegar)"; dsBox.addSubview(dsKeyField)
        let dsModelLbl = boxLabel("Modelo:", 26); dsModelLbl.frame.size.width = 64; dsBox.addSubview(dsModelLbl)
        dsModelPopup = NSPopUpButton(frame: NSRect(x: 70, y: 22, width: 220, height: 26))
        dsModelPopup.addItems(withTitles: dsModels); dsBox.addSubview(dsModelPopup)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 20, y: 60, width: W-40, height: 40)
        statusLabel.textColor = .secondaryLabelColor; statusLabel.maximumNumberOfLines = 2
        c.addSubview(statusLabel)

        let test = NSButton(title: "Probar conexión", target: self, action: #selector(testConn))
        test.frame = NSRect(x: 20, y: 18, width: 150, height: 30); c.addSubview(test)
        let cancel = NSButton(title: "Cerrar", target: self, action: #selector(closeWin))
        cancel.frame = NSRect(x: W-230, y: 18, width: 100, height: 30); c.addSubview(cancel)
        let save = NSButton(title: "Guardar", target: self, action: #selector(saveCfg))
        save.frame = NSRect(x: W-120, y: 18, width: 100, height: 30); save.keyEquivalent = "\r"; c.addSubview(save)

        w.contentView = c; w.center(); window = w
    }

    private func updateVisibility() {
        let i = provIndex()
        mmBox.isHidden = i != 0; clBox.isHidden = i != 1; oaBox.isHidden = i != 2; dsBox.isHidden = i != 3
    }

    @objc private func providerChanged() { updateVisibility() }

    func show() {
        providerPopup.selectItem(at: max(0, providers.firstIndex(of: config.provider) ?? 0))
        mmKeyField.stringValue = config.apiKey
        mmModelPopup.selectItem(withTitle: config.model); if mmModelPopup.indexOfSelectedItem < 0 { mmModelPopup.selectItem(at: 1) }
        clKeyField.stringValue = config.claudeKeyValue
        clModelPopup.selectItem(at: clValues.firstIndex(of: config.claudeModelValue) ?? 0)
        oaKeyField.stringValue = config.openaiKeyValue
        oaModelPopup.selectItem(withTitle: config.openaiModelValue); if oaModelPopup.indexOfSelectedItem < 0 { oaModelPopup.selectItem(at: 0) }
        dsKeyField.stringValue = config.deepseekKeyValue
        dsModelPopup.selectItem(withTitle: config.deepseekModelValue); if dsModelPopup.indexOfSelectedItem < 0 { dsModelPopup.selectItem(at: 0) }
        statusLabel.stringValue = config.isConfigured ? "Configurado ✅" : "Falta la clave del proveedor elegido."
        updateVisibility()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func current() -> AIConfig {
        var c = config
        c.provider = providers[min(provIndex(), providers.count - 1)]
        c.apiKey = mmKeyField.stringValue
        c.model = mmModelPopup.titleOfSelectedItem ?? "MiniMax-M2.5"
        c.claudeKey = clKeyField.stringValue.isEmpty ? nil : clKeyField.stringValue
        c.claudeModel = clValues[min(max(0, clModelPopup.indexOfSelectedItem), clValues.count - 1)]
        c.openaiKey = oaKeyField.stringValue.isEmpty ? nil : oaKeyField.stringValue
        c.openaiModel = oaModelPopup.titleOfSelectedItem
        c.deepseekKey = dsKeyField.stringValue.isEmpty ? nil : dsKeyField.stringValue
        c.deepseekModel = dsModelPopup.titleOfSelectedItem
        return c
    }

    @objc private func openConsole() {
        let url: String
        switch provIndex() {
        case 1: url = "https://console.anthropic.com/settings/keys"
        case 2: url = "https://platform.openai.com/api-keys"
        case 3: url = "https://platform.deepseek.com/api_keys"
        default: url = "https://platform.minimax.io/user-center/basic-information/interface-key"
        }
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    @objc private func testConn() {
        persist()                      // guarda antes de probar, así no se pierde
        let c = config
        statusLabel.stringValue = "Probando…"
        makeBackend(c).test { [weak self] _, msg in self?.statusLabel.stringValue = msg }
    }

    /// Lee los campos, guarda en Keychain/disco y actualiza el cliente vivo.
    private func persist() {
        config = current()
        config.save()                  // clave → Keychain, resto → config.json
        onSave(config)
    }

    @objc private func saveCfg() {
        persist()
        statusLabel.stringValue = config.isConfigured ? "Guardado ✅" : "Guardado (sin clave)"
    }

    @objc private func closeWin() { persist(); window.orderOut(nil) }

    // Guarda también si cierran con el botón rojo / ⌘W.
    func windowWillClose(_ notification: Notification) { persist() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
