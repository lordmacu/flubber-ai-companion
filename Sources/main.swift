import Cocoa
import UserNotifications
import ServiceManagement

// ============================================================================
// SlimePet — pixel-art slime pet + Tamagotchi for macOS.
// 100% code-drawn art. It has needs (hunger, happiness, energy,
// cleanliness, health) that decay in real time; it eats, plays, bathes, takes
// medicine, sleeps, poops, grows (egg→baby→child→adult), gets sick and
// can die. Stat bars HUD + floating buttons on mouse hover.
// ============================================================================

// MARK: - Color palette

struct Skin { let body, bodyDark, bodyLight, shine: NSColor }

enum Pal {
    static var skins: [Skin] = [
        Skin(body:      NSColor(srgbRed: 0.36, green: 0.85, blue: 0.55, alpha: 1),  // green
             bodyDark:  NSColor(srgbRed: 0.20, green: 0.62, blue: 0.40, alpha: 1),
             bodyLight: NSColor(srgbRed: 0.62, green: 0.96, blue: 0.72, alpha: 1),
             shine:     NSColor(srgbRed: 0.92, green: 1.00, blue: 0.95, alpha: 1)),
        Skin(body:      NSColor(srgbRed: 0.42, green: 0.66, blue: 0.98, alpha: 1),  // blue
             bodyDark:  NSColor(srgbRed: 0.24, green: 0.42, blue: 0.78, alpha: 1),
             bodyLight: NSColor(srgbRed: 0.68, green: 0.84, blue: 1.00, alpha: 1),
             shine:     NSColor(srgbRed: 0.94, green: 0.98, blue: 1.00, alpha: 1)),
        Skin(body:      NSColor(srgbRed: 0.78, green: 0.55, blue: 0.96, alpha: 1),  // purple
             bodyDark:  NSColor(srgbRed: 0.55, green: 0.34, blue: 0.74, alpha: 1),
             bodyLight: NSColor(srgbRed: 0.90, green: 0.76, blue: 1.00, alpha: 1),
             shine:     NSColor(srgbRed: 0.99, green: 0.96, blue: 1.00, alpha: 1)),
        Skin(body:      NSColor(srgbRed: 0.99, green: 0.62, blue: 0.78, alpha: 1),  // pink
             bodyDark:  NSColor(srgbRed: 0.85, green: 0.40, blue: 0.58, alpha: 1),
             bodyLight: NSColor(srgbRed: 1.00, green: 0.80, blue: 0.89, alpha: 1),
             shine:     NSColor(srgbRed: 1.00, green: 0.96, blue: 0.98, alpha: 1)),
    ]
    static var index = 0
    static var skin: Skin { skins[min(index, skins.count - 1)] }

    /// Applies an AI-generated skin into a single "slot" (index 4) and activates it.
    static func setAISkin(_ s: Skin) {
        if skins.count > 4 { skins[4] = s } else { skins.append(s) }
        index = 4
    }

    /// NSColor from hex "#RRGGBB".
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

    // stat bar colors
    static let barHunger = NSColor(srgbRed: 1.00, green: 0.60, blue: 0.25, alpha: 1)
    static let barHappy  = heart
    static let barEnergy = NSColor(srgbRed: 1.00, green: 0.82, blue: 0.20, alpha: 1)
    static let barClean  = NSColor(srgbRed: 0.40, green: 0.78, blue: 1.00, alpha: 1)
    static let barHealth = NSColor(srgbRed: 0.40, green: 0.85, blue: 0.50, alpha: 1)
}

// MARK: - Animation states

enum PetState {
    case idle, looking, walking, dragging, falling, reacting
    case happy, chasing, dancing, rolling, dizzy, yawning, sleeping
    case eating, bathing, takingMedicine    // care actions
    case egg, hatching, dead                 // life cycle
    case stuckWall                           // stuck to a side, oozing down
    case wiggling, stretching                // spontaneous animations (wiggle / stretch)
}

// MARK: - Particles

struct Particle {
    var x, y, vx, vy, life: CGFloat
    var kind: Int   // 0 heart,1 note,2 star,3 Z,4 sweat,5 fly,6 bubble,7 crumb,8 spark
}

// MARK: - HUD button

struct HudButton { let id: String; let icon: String; var rect: NSRect }

// MARK: - Pet view

final class PetView: NSView {

    let GW = 32, GH = 32
    let PX: CGFloat = 4                                   // size of each slime pixel
    var slimeOX: CGFloat { (bounds.width - CGFloat(GW) * PX) / 2 }

    // animation state
    var state: PetState = .egg
    var tick = 0, stateTimer = 0, idleFrames = 0
    var facing: CGFloat = 1

    // physics
    var vx: CGFloat = 0, vy: CGFloat = 0
    var walkSpeed: CGFloat = 1.4
    var targetX: CGFloat = 0
    var wallSide: CGFloat = 0      // -1 left, +1 right (when oozing)

    // eyes
    var blinkUntil = 0
    var lookX: CGFloat = 0, lookY: CGFloat = 0
    var lookTX: CGFloat = 0, lookTY: CGFloat = 0
    var lookChanges = 0

    // input
    var dragOffset: NSPoint = .zero
    var mouseDownAt: NSPoint = .zero
    var didDrag = false
    var consumedByButton = false
    var grabbedSlime = false        // the mousedown started on the slime's body
    var loveClicks = 0, lastClickTick = -999

    // particles / squash
    var particles: [Particle] = []
    var squashLanding: CGFloat = 0
    var eatingFood: Food = .meat

    // Tamagotchi
    var stats = PetStats()

    // AI / dialogue
    var client: AIBackend?
    var convo: [(String, String)] = []          // chat history (role, content)
    var bubbleText: String? = nil
    var bubbleUntil = Date.distantPast
    var bubbleThinking = false
    var lastSpontaneous = Date.distantPast
    var lastClickTalk = Date.distantPast
    var onChatRequested: (() -> Void)?
    var onToggleListen: (() -> Void)?     // 👂 system audio
    var onToggleMic: (() -> Void)?        // 🎤 microphone
    var listening = false                 // 👂 listening to the system (for the icon)
    var micOn = false                     // 🎤 microphone active (for the icon)

    // integrated chat (pixel panel over the slime)
    var chatActive = false
    var chatStore = ConversationStore.load()
    var convIndex = 0
    var chatInput = ""
    var chatScroll: CGFloat = 0
    var chatBusy = false
    var listOpen = false
    var stepLines: [String] = []        // ephemeral tool steps (not saved)
    var agent: Agent?
    var chatButtons: [HudButton] = []   // panel buttons (close/new/list)
    var listRowRects: [NSRect] = []     // rows of the conversation list
    var chatStick = true                // stuck to the bottom (autoscroll)
    var chatScrollToBottom = false      // on opening/switching conversation: jump to the absolute end
    // --- meeting listening: rolling summaries in batches ---
    var meetingConvId: String? = nil           // dedicated conversation (created on the fly, new per session)
    var meetingSummarizedLen = 0               // how much transcript has already been summarized
    var meetingRollingSummaries: [String] = [] // accumulated mini-summaries
    var meetingRollTimer: Timer?               // fires a mini-summary every X time
    var meetingStartedAt = Date()              // to decide whether it was a "meeting" (>1 min) or a "talk"
    static let meetingThreshold: TimeInterval = 60   // ≥60s = meeting; otherwise a talk
    var chatContentH: CGFloat = 0       // content height (for clamping the scroll)
    var chatAreaH: CGFloat = 0
    var chatMouse: NSPoint = .zero       // mouse position inside the chat (for hover)
    var copyButtons: [(rect: NSRect, text: String)] = []
    var pendingShot: String? = nil       // screenshot ready to attach
    var pendingShotPath: String? = nil   // path of that capture's PNG
    var thumbRects: [(rect: NSRect, path: String)] = []
    var fileButtons: [(rect: NSRect, path: String)] = []   // clickable links to files (transcript)
    var imgCache: [String: NSImage] = [:]
    var attrCache: [String: NSAttributedString] = [:]   // rendered markdown (cache)
    var sendRect: NSRect = .zero                         // send button (little arrow)
    var detachRect: NSRect = .zero                       // attached capture chip (click = remove)
    var streamLive: String? = nil                        // text arriving via streaming (token by token)
    var inputFont: NSFont { NSFont.systemFont(ofSize: 12) }
    var chatActivity = 0                  // 0 thinking, 1 searching, 2 looking at screen
    var turnT: CGFloat = 0               // 0 facing front .. 1 facing away (looking at the screen)
    var lookingAtScreen: Bool { chatActive && chatBusy && chatActivity == 2 }
    var talking: Bool { chatActive && chatBusy && !(streamLive ?? "").isEmpty }   // talking (text arriving)
    var chatOpen: Bool { chatActive }   // while chatting, it doesn't wander

    // "scrub" gesture to wash
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
    // Mouse tracking to show/hide the HUD
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

    /// Detects the scrubbing gesture (horizontal back-and-forth) over the slime → wash it.
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
        if scrubDir != 0 && dir != scrubDir {                 // there was a direction change
            if now.timeIntervalSince(lastScrubTime) < 1.2 { scrubCount += 1 } else { scrubCount = 1 }
            lastScrubTime = now
            if scrubCount >= 4 {                              // enough back-and-forths → time to wash!
                scrubCount = 0
                if stats.poops > 0 || stats.cleanliness < 0.99 { doClean() }
            }
        }
        scrubDir = dir
    }

    // ------------------------------------------------------------------
    // Per-frame loop. realDt = real seconds elapsed.
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
        // sync the visual state with the life cycle
        if stats.isDead {
            if state != .dead { enter(.dead) }
        } else if stats.stage == .egg {
            if state != .egg { enter(.egg) }
        } else if state == .egg {
            enter(.idle)                       // in case it loads already hatched
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

    /// Range of origin.x so the slime's BODY doesn't go off the screen.
    func originXBounds(_ vf: NSRect) -> (CGFloat, CGFloat) {
        (vf.minX - slimeOX, vf.maxX - bounds.width + slimeOX)
    }

    func ambientFx() {
        guard !stats.isDead, stats.stage != .egg else { return }
        if stats.isSick && tick % 28 == 0 { spawn(kind: 4, n: 1, at: CGPoint(x: 22, y: 20)) }   // sweat
        if stats.poops > 0 && stats.cleanliness < 0.6 && tick % 24 == 0 {
            spawn(kind: 5, n: 1, at: CGPoint(x: 25, y: 3))                                       // fly
        }
    }

    // ------------------------------------------------------------------
    // State machine (movement + actions)
    // ------------------------------------------------------------------
    func update() {
        guard let win = petWindow, let screen = win.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let floor = vf.minY

        lookX += (lookTX - lookX) * 0.25
        lookY += (lookTY - lookY) * 0.25

        // turn toward the screen when it looks at it
        turnT += ((lookingAtScreen ? 1 : 0) - turnT) * 0.15

        // "working" animation (works in any state)
        if chatActive && chatBusy {
            if chatActivity == 1 {       // searching: eyes scan
                if stateTimer % 10 == 0 { lookTX = CGFloat(Int.random(in: -1...1)); lookTY = CGFloat(Int.random(in: -1...1)) }
            } else {                     // looking/thinking: looks up
                lookTX = 0; lookTY = 1
            }
        }

        switch state {

        case .egg:
            // the egg just wobbles; near hatching it shakes more
            break

        case .hatching:
            if stateTimer > 45 { enter(.idle) }

        case .dead:
            break

        case .eating:
            if stateTimer % 12 == 0 { spawn(kind: 7, n: 2, at: CGPoint(x: 16, y: 11)) }  // crumbs
            if stateTimer > 55 { enter(.idle) }

        case .bathing:
            if stateTimer % 6 == 0 { spawn(kind: 6, n: 1, at: CGPoint(x: 16, y: 12)) }   // bubbles
            if stateTimer > 55 { enter(.idle) }

        case .takingMedicine:
            if stateTimer == 6 { spawn(kind: 8, n: 6, at: CGPoint(x: 16, y: 14)) }       // sparks
            if stateTimer > 40 { enter(.idle) }

        case .idle:
            idleFrames += 1
            if chatActive && chatBusy {                      // animation depending on the action
                if chatActivity == 1 {                       // searching: eyes scan
                    if stateTimer % 10 == 0 { lookTX = CGFloat(Int.random(in: -1...1)); lookTY = CGFloat(Int.random(in: -1...1)) }
                } else { lookTX = 0; lookTY = 1 }            // looking/thinking: looks up
            } else {
                lookAtMouse(win)
            }
            // if the mouse is over it, the chat is open, or it's listening, it stays still and attentive.
            // Variety of spontaneous animations depending on mood/energy.
            if stateTimer > 50 && !hovering && !chatOpen && !listening {
                switch Int.random(in: 0..<150) {
                case 0..<3:  if stats.energy > 0.3 { startWalking(in: screen) }      // wander
                case 3:      if stats.mood > 0.6 { enter(.dancing) }                 // dance
                case 4...6:  enter(.looking)                                         // look around
                case 7:      enter(.wiggling)                                        // wiggle
                case 8:      if stats.energy < 0.55 { enter(.stretching) }           // stretch
                case 9:      if stats.energy > 0.4 { enter(.rolling) }               // roll
                case 10:     if stats.mood > 0.7 { enter(.happy) }                   // hop happily
                case 11:     if stats.mood > 0.5 { enter(.chasing) }                 // chase the cursor
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
            if hovering || chatOpen { enter(.idle); break }   // doesn't walk on hover or with the chat open
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
            // stuck to the side; oozes downward with viscosity
            idleFrames = 0
            vy -= 0.18                                   // slow gravity (viscous)
            vy = max(vy, -3.2)                           // limited ooze speed
            var f = win.frame
            let (wminX, wmaxX) = originXBounds(vf)
            f.origin.x = wallSide < 0 ? wminX : wmaxX    // stays hugging the wall
            f.origin.y += vy
            if f.origin.y <= floor {
                f.origin.y = floor; win.setFrameOrigin(f.origin)
                vy = 0; squashLanding = 0.8; wallSide = 0; enter(.idle)
            } else {
                win.setFrameOrigin(f.origin)
                if stateTimer % 16 == 0 { spawn(kind: 6, n: 1, at: CGPoint(x: 16, y: 4)) }  // dripping droplet
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
            // wiggle in place; happy eyes
            if stateTimer == 4 { spawn(kind: 0, n: 1) }     // a little heart
            if stateTimer > 38 { enter(.idle) }

        case .stretching:
            // stretch like a cat and come back
            if stateTimer > 42 { enter(.idle) }
        }

        if squashLanding > 0 { squashLanding = max(0, squashLanding - 0.08) }
    }

    func enter(_ s: PetState) {
        // with the chat open, don't allow states that MOVE the window (they move the dialogue)
        if chatActive, [.dancing, .walking, .rolling, .chasing, .happy, .reacting, .falling].contains(s) { return }
        // getting active wakes the slime up
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
    // Care actions (called by the buttons / menu)
    // ------------------------------------------------------------------
    func doFeed(_ food: Food) { wakeUp(); guard stats.stage != .egg, !stats.isDead else { return }; stats.feed(food); eatingFood = food; enter(.eating) }
    func doPlay()    { wakeUp(); guard stats.stage != .egg, !stats.isDead, !stats.isAsleep else { return }; stats.play(); enter(.happy) }
    func doClean()   { wakeUp(); guard !stats.isDead else { return }; stats.clean(); enter(.bathing) }
    func doMedicine(){ wakeUp(); guard !stats.isDead else { return }; let was = stats.isSick; stats.medicine(); if was { enter(.takingMedicine) } }
    func doSleep()   { guard stats.stage != .egg, !stats.isDead else { return }; stats.toggleSleep() }
    func doRestart() { stats.restart(); enter(.egg) }

    // ------------------------------------------------------------------
    // Particles
    // ------------------------------------------------------------------
    func spawn(kind: Int, n: Int, at p: CGPoint? = nil) {
        let base = p ?? CGPoint(x: CGFloat(GW)/2, y: CGFloat(GH) * 0.6)
        for _ in 0..<n {
            let spread: CGFloat = kind == 2 ? 0.6 : 0.2
            particles.append(Particle(
                x: base.x + CGFloat.random(in: -3...3),
                y: base.y,
                vx: CGFloat.random(in: -spread...spread),
                vy: kind == 7 ? CGFloat.random(in: -0.5 ... -0.2)            // crumbs fall
                    : kind == 5 ? CGFloat.random(in: -0.15...0.15)          // flies float
                    : kind == 3 ? 0.45
                    : CGFloat.random(in: 0.4...0.7),
                life: 1.0, kind: kind))
        }
    }
    func updateParticles() {
        for i in particles.indices {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            if particles[i].kind == 5 {                                    // flies: zigzag
                particles[i].x += sin(CGFloat(tick) * 0.4 + particles[i].y) * 0.3
                particles[i].life -= 0.01
            } else {
                particles[i].life -= 0.018
            }
        }
        particles.removeAll { $0.life <= 0 || $0.y > CGFloat(GH) + 2 || $0.y < -2 }
    }

    // ------------------------------------------------------------------
    // DRAWING
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
            drawChat(ctx)      // pixel conversation panel over the slime
        } else {
            drawBubble(ctx)    // the bubble/animation is drawn behind…
            drawHUD(ctx)       // …and the buttons stay in front
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
        case .stuckWall: sx = 0.74 + sin(CGFloat(tick)*0.3)*0.03   // squashed against the wall
        case .reacting: sx = 0.92
        case .yawning:  sx = 1 - min(1,CGFloat(stateTimer)/20)*0.12
        case .wiggling: sx = 1 + sin(CGFloat(stateTimer)*0.6)*0.06
        case .stretching:                                    // stretches upward (thins out)
            let p = sin(min(1, CGFloat(stateTimer)/42) * .pi)
            sx = 1 - p*0.18
        default:        sx = 1 + sin(CGFloat(tick)*0.08)*0.04
        }
        if chatActive && chatBusy {
            switch chatActivity {
            case 1: sx = 1 - abs(sin(CGFloat(tick)*0.32))*0.10    // searching: bounce
            case 2: sx = max(0.12, abs(cos(turnT * .pi)))         // looking: turns toward the screen
            default: sx = 1 + sin(CGFloat(tick)*0.2)*0.08         // thinking: pulses
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
        case .stuckWall: sy = 1.30                                  // stretched vertically while oozing
        case .reacting: sy = 1.10
        case .yawning:  sy = 1 + min(1,CGFloat(stateTimer)/20)*0.20
        case .wiggling: sy = 1 - sin(CGFloat(stateTimer)*0.6)*0.05
        case .stretching:                                    // stretches upward
            let p = sin(min(1, CGFloat(stateTimer)/42) * .pi)
            sy = 1 + p*0.28
        default:        sy = 1 - sin(CGFloat(tick)*0.08)*0.04
        }
        if chatActive && chatBusy {
            switch chatActivity {
            case 1: sy = 1 + abs(sin(CGFloat(tick)*0.32))*0.10    // searching: bounce
            case 2: sy = 1.10 + sin(CGFloat(tick)*0.2)*0.05       // looking: attentive bobbing
            default: sy = 1 - sin(CGFloat(tick)*0.2)*0.08         // thinking: pulses
            }
        }
        return (sy - squashLanding*0.35) * CGFloat(stats.sizeScale)
    }

    func fill(_ ctx: CGContext, _ gx: Int, _ gy: Int, _ c: NSColor) {
        guard gx >= 0, gx < GW, gy >= 0, gy < GH else { return }
        ctx.setFillColor(c.cgColor)
        ctx.fill(CGRect(x: slimeOX + CGFloat(gx) * PX, y: CGFloat(gy) * PX, width: PX + 0.5, height: PX + 0.5))
    }

    // Expression based on mood (for calm states)
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
            drawBackPeek(ctx, cx: Int(cx), height: height, footY: footY)   // facing away, looking at the screen
        } else {
            drawFace(ctx, cx: Int(cx), height: height, footY: footY)
        }

        // food in front of the mouth while eating
        if state == .eating && stateTimer < 48 {
            let fy = footY + Int(height * 0.30)
            drawPattern(ctx, foodSprite(eatingFood), Int(cx) + 5, fy, eatingFood == .candy ? Pal.heart : Pal.crumb)
        }

        // listening to the meeting: little ears that move + sound waves
        if listening { drawListening(ctx, cx: Int(cx), height: height, footY: footY) }
    }

    /// "Listening" decoration: two little ears that tilt (twitch) and sound
    /// waves that pulse beside the head.
    func drawListening(_ ctx: CGContext, cx: Int, height: CGFloat, footY: Int) {
        let skin = stats.isSick ? Pal.sick : Pal.skin
        let topY = footY + Int(height) - 1
        // twitch: the ear tips move a tiny bit over time
        let tw = (tick / 9) % 2 == 0 ? 0 : 1

        // 2x4 ear: body + pink inner + dark border, leans at the tip
        func ear(_ x0: Int, _ lean: Int) {
            for oy in 0..<4 {
                let lx = x0 + (oy >= 2 ? lean : 0)
                fill(ctx, lx,     topY + oy, skin.bodyDark)            // outer border
                fill(ctx, lx + 1, topY + oy, oy >= 1 && oy <= 2 ? Pal.heart : skin.body)
            }
        }
        ear(cx - 6, -tw)     // left ear (leans to the left)
        ear(cx + 4,  tw)     // right ear

        // pulsing sound waves to the right of the head ")))"
        let wx = cx + 9
        let wy = footY + Int(height * 0.52)
        let arc = ["1", "01", "1"]                       // a simple ")" arc
        let phase = (tick / 7) % 3                        // how many waves are shown (1..3)
        for i in 0...phase {
            let a = 0.9 - Double(i) * 0.22
            drawPattern(ctx, arc, wx + i * 2, wy - 1, Pal.note.withAlphaComponent(max(0.25, a)))
        }
    }

    /// Back view: two little eyes peeking over the top (looking at the screen).
    func drawBackPeek(_ ctx: CGContext, cx: Int, height: CGFloat, footY: Int) {
        let skin = stats.isSick ? Pal.sick : Pal.skin
        let topY = footY + Int(height * 0.80)
        for dx in [-3, -2, 2, 3] { fill(ctx, cx + dx, topY, Pal.eye) }       // peeking little eyes
        // a faint central shine on the "back of the head"
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
        func eyeSad(_ ex: Int) {   // upper eyelid + pupil at the bottom
            for ox in 0..<3 { fill(ctx, ex+ox, faceY+3, Pal.eye) }
            for ox in 0..<2 { fill(ctx, ex+ox, faceY+1, Pal.eye) }
        }

        // eyes based on state / mood
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

        // mouth
        let openStates: [PetState] = [.reacting, .falling, .dragging, .yawning, .eating]
        if talking {
            // mouth that opens and closes (simulates talking)
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
            // no mouth
        } else if expr == .sad || expr == .sick {
            fill(ctx, cx, faceY-3, Pal.mouth); fill(ctx, cx-1, faceY-4, Pal.mouth); fill(ctx, cx+1, faceY-4, Pal.mouth)  // ∩ sad
        } else {
            fill(ctx, cx-1, faceY-3, Pal.mouth); fill(ctx, cx, faceY-4, Pal.mouth); fill(ctx, cx+1, faceY-3, Pal.mouth)  // ∪ smile
        }

        // happy cheeks
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

    // ---- Egg ----
    func drawEgg(_ ctx: CGContext) {
        let cx = GW/2
        let wob = (state == .hatching) ? sin(CGFloat(stateTimer)*0.9)*2.5 : sin(CGFloat(tick)*0.06)*1.0
        let chh = 11, cw = 8, baseY = 3
        for gy in 0..<(2*chh) {
            let t = (CGFloat(gy) - CGFloat(chh)) / CGFloat(chh)
            let w = CGFloat(cw) * sqrt(max(0, 1 - t*t)) * (gy < chh ? 1.05 : 0.92) // a bit of "egg" shape
            let xw = Int(w.rounded())
            for dx in -xw...xw {
                let gx = cx + dx + Int(wob)
                let edge = dx <= -xw+1 || dx >= xw-1
                fill(ctx, gx, baseY+gy, edge ? Pal.egg2 : Pal.egg1)
            }
        }
        // spots
        for (sx, sy) in [(-3, 6), (2, 10), (-1, 14), (4, 9)] {
            fill(ctx, cx+sx+Int(wob), baseY+sy, Pal.egg2)
        }
        // cracks when hatching
        if state == .hatching {
            let cyl = baseY + chh
            for (gx, gy) in [(0,2),(1,1),(-1,1),(1,-1),(2,0),(-2,0)] {
                fill(ctx, cx+gx+Int(wob), cyl+gy, Pal.eye)
            }
        }
    }

    // ---- Ghost (dead) ----
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
                // wavy bottom edge (ghost tail)
                if gy == 0 && (dx % 2 == 0) { continue }
                let edge = dx <= -xw+1 || dx >= xw-1
                fill(ctx, gx, gy+floatY, edge ? skin.bodyDark : skin.body)
            }
        }
        // X eyes and sad mouth
        let faceY = floatY + Int(baseHeight*0.45)
        for ex in [cx-4, cx+2] {
            fill(ctx, ex, faceY+2, Pal.eye); fill(ctx, ex+2, faceY+2, Pal.eye)
            fill(ctx, ex+1, faceY+1, Pal.eye); fill(ctx, ex, faceY, Pal.eye); fill(ctx, ex+2, faceY, Pal.eye)
        }
        // angel halo
        let haloY = floatY + Int(baseHeight) + 2
        for dx in -3...3 { fill(ctx, cx+dx, haloY, Pal.halo) }
        fill(ctx, cx-4, haloY, Pal.halo); fill(ctx, cx+4, haloY, Pal.halo)
    }

    // ---- Poop ----
    func drawPoops(_ ctx: CGContext) {
        guard stats.poops > 0 else { return }
        let pat = ["00100","01110","11111"]
        for i in 0..<min(stats.poops, 3) {
            drawPattern(ctx, pat, GW/2 + 8 + i*5, 1, Pal.poop)
        }
    }

    // ---- Particles ----
    func drawParticles(_ ctx: CGContext) {
        for p in particles {
            let bx = Int(p.x.rounded()), by = Int(p.y.rounded())
            let a = max(0, min(1, p.life))
            switch p.kind {
            case 0: drawPattern(ctx, ["01010","11111","11111","01110","00100"], bx, by, Pal.heart.withAlphaComponent(a))
            case 1: drawPattern(ctx, ["00110","00010","00010","11010","11000"], bx, by, Pal.note.withAlphaComponent(a))
            case 2: drawPattern(ctx, ["00100","01110","00100"], bx, by, Pal.star.withAlphaComponent(a))
            case 3: drawPattern(ctx, ["1110","0100","1110"], bx, by, Pal.skin.bodyDark.withAlphaComponent(a))
            case 4: drawPattern(ctx, ["010","010","111","010"], bx, by, Pal.sweat.withAlphaComponent(a))   // sweat
            case 5: drawPattern(ctx, ["101","010"], bx, by, Pal.eye.withAlphaComponent(a))                  // fly
            case 6: drawPattern(ctx, ["010","101","010"], bx, by, Pal.bubble.withAlphaComponent(a))         // bubble
            case 7: fill(ctx, bx, by, Pal.crumb.withAlphaComponent(a))                                      // crumb
            default: drawPattern(ctx, ["00100","01110","00100"], bx, by, Pal.star.withAlphaComponent(a))    // spark
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
    // HUD: stat bars + action buttons
    // ------------------------------------------------------------------
    func layoutButtons() {
        let bw: CGFloat = 26
        let cx = bounds.width / 2
        if stats.isDead {
            buttons = [HudButton(id: "restart", icon: "🥚", rect: NSRect(x: cx - 13, y: 108, width: bw, height: bw))]
            return
        }
        // Contextual buttons: 🍖 only if hungry, 💊 only if sick.
        // (play = double click, wash = scrub, sleep = automatic)
        // The chat is smaller and sits next to the slime, on the left.
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

    /// Draws a tinted SF Symbol, centered in `rect`. Crisp at any size.
    func drawSymbol(_ name: String, in rect: NSRect, _ color: NSColor, size: CGFloat = 13, weight: NSFont.Weight = .regular) {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return }
        let s = base.size
        let tinted = NSImage(size: s, flipped: false) { r in
            base.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2,
                               width: s.width, height: s.height))
    }

    /// Draws a pixel-art icon centered in `rect`. Each char of `rows` maps to
    /// a color in `palette` ('0' = transparent). Row 0 = top.
    func drawPixelIcon(_ ctx: CGContext, _ rows: [String], in rect: NSRect, _ palette: [Character: NSColor]) {
        let cols = rows.map { $0.count }.max() ?? 0
        let n = rows.count
        guard cols > 0, n > 0 else { return }
        let cell = max(1, floor(min(rect.width, rect.height) / CGFloat(max(cols, n))))
        let gw = cell * CGFloat(cols), gh = cell * CGFloat(n)
        let ox = rect.minX + (rect.width - gw) / 2
        let oy = rect.minY + (rect.height - gh) / 2
        for (r, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() {
                guard let c = palette[ch] else { continue }
                ctx.setFillColor(c.cgColor)
                ctx.fill(CGRect(x: ox + CGFloat(i) * cell,
                                y: oy + CGFloat(n - 1 - r) * cell,
                                width: cell + 0.4, height: cell + 0.4))
            }
        }
    }

    // Pixel-art icons for the chat header (matching the slime).
    static let eyeIcon = [
        "000000000",
        "00EEEEE00",
        "0EE000EE0",
        "EE0WWW0EE",
        "0EE000EE0",
        "00EEEEE00",
        "000000000",
    ]
    static let earIcon = [
        "00BBB00",
        "0BBBBB0",
        "BBPPPBB",
        "BBPP0BB",
        "BBPP00B",
        "BBPP0B0",
        "0BBPB00",
        "00BBB00",
        "000B000",
    ]
    static let micIcon = [
        "0011100",
        "0MMMMM0",
        "0MMMMM0",
        "0MMMMM0",
        "0MMMMM0",
        "M0MMM0M",
        "M01110M",
        "0001000",
        "0011100",
    ]
    static let stopIcon = [
        "0000000",
        "0RRRRR0",
        "0RRRRR0",
        "0RRRRR0",
        "0RRRRR0",
        "0RRRRR0",
        "0000000",
    ]
    static let chatAccent = NSColor(srgbRed: 0.62, green: 0.96, blue: 0.72, alpha: 1)
    static let chatRecRed = NSColor(srgbRed: 0.96, green: 0.36, blue: 0.40, alpha: 1)

    /// Icon that works as a gauge: the background stays dimmed (empty) and the
    /// lower portion "fills up" with the emoji's own color based on `value`.
    func drawStatIcon(_ ctx: CGContext, _ icon: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, value: Double) {
        let v = CGFloat(max(0, min(1, value)))
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size)]
        let p = NSPoint(x: x, y: y)

        // dimmed base (the "spent" part)
        ctx.saveGState()
        ctx.setAlpha(hudAlpha * (v < 0.25 ? 0.12 : 0.20))
        (icon as NSString).draw(at: p, withAttributes: attrs)
        ctx.restoreGState()

        // filled portion, from bottom to top
        if v > 0.001 {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x - 3, y: y - 2, width: size + 8, height: (size + 4) * v))
            ctx.setAlpha(hudAlpha)
            (icon as NSString).draw(at: p, withAttributes: attrs)
            // red alert tint when critical
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

        // --- buttons (the background fills like an indicator based on its stat) ---
        let statFor: [String: (Double, NSColor)] = [
            "feed":  (stats.hunger,      Pal.barHunger),
            "play":  (stats.happiness,   Pal.barHappy),
            "clean": (stats.cleanliness, Pal.barClean),
            "med":   (stats.health,      Pal.barHealth),
            "sleep": (stats.energy,      Pal.barEnergy),
        ]
        for b in buttons {
            let path = NSBezierPath(roundedRect: b.rect, xRadius: 6, yRadius: 6)
            // empty background (dark)
            NSColor(white: 0.12, alpha: 0.80).setFill(); path.fill()
            // indicator fill, from bottom to top
            if let (value, color) = statFor[b.id] {
                let v = CGFloat(max(0, min(1, value)))
                if v > 0.001 {
                    ctx.saveGState()
                    path.addClip()                                   // clip to the rounded rectangle
                    let c = v < 0.25 ? NSColor.systemRed : color
                    c.withAlphaComponent(0.9).setFill()
                    NSBezierPath(rect: NSRect(x: b.rect.minX, y: b.rect.minY,
                                              width: b.rect.width, height: b.rect.height * v)).fill()
                    ctx.restoreGState()
                }
            }
            // border + icon on top (always visible), scaled to the button size
            NSColor(white: 1, alpha: 0.30).setStroke(); path.lineWidth = 1; path.stroke()
            drawText(b.icon, b.rect.minX + b.rect.width * 0.15, b.rect.minY + b.rect.height * 0.15,
                     size: b.rect.width * 0.58)
        }
        ctx.restoreGState()
    }

    // ------------------------------------------------------------------
    // Dialogue bubble + AI
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
        let by: CGFloat = 88                                    // right above the slime's head
        let rect = NSRect(x: bx, y: by, width: bw, height: bh)

        // little tail pointing downward (to the head)
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

    /// Contextual reaction: asks the LLM for a phrase (if there's a key) or uses a canned one.
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

    /// Spontaneous reaction (events): with a cooldown to avoid spamming.
    func reactSpontaneous(_ sit: Situation) {
        guard !stats.isAsleep, state != .sleeping else { return }   // quiet while sleeping
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
        let history = Array(convo.suffix(8))         // recent context for the LLM
        let snapshot = stats
        client.chat(system: Personality.systemPrompt(snapshot), history: history, user: t, maxTokens: 1000) { [weak self] reply in
            guard let self = self else { return }
            let r = reply.flatMap(Personality.sanitize) ?? "Uy, no pude pensar 😵‍💫"
            self.convo.append(("user", t)); self.convo.append(("assistant", r))   // full history
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
    // Integrated chat (pixel panel over the slime)
    // ------------------------------------------------------------------
    override var acceptsFirstResponder: Bool { true }

    func toggleChat() {
        chatActive.toggle()
        if chatActive {
            if chatStore.conversations.isEmpty { chatStore.conversations.append(.new()); chatStore.save() }
            convIndex = min(convIndex, chatStore.conversations.count - 1)
            ensureAgent(); listOpen = false; chatStick = true; chatScrollToBottom = true
            persistActiveConversation()
            // if it was moving, stay still so the dialogue doesn't move
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

    /// On startup: opens the conversation that was active last time.
    func restoreActiveConversation() {
        if let id = chatStore.activeId,
           let idx = chatStore.conversations.firstIndex(where: { $0.id == id }) {
            convIndex = idx
        } else {
            convIndex = max(0, chatStore.conversations.count - 1)   // lacking data, the most recent one
        }
    }

    /// Remembers which conversation is active (to restore it when reopening the app).
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

    /// Attaches a capture (its path) to the user's last message, for the thumbnail.
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
        wakeUp()                                  // if it was asleep, talking to it wakes it up
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

        if let shot = shot {                       // question about the screen → vision
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
    // Meeting listening: dedicated conversation + rolling summaries in
    // batches + final synthesis + saved transcript with a clickable link.
    // ==================================================================

    /// When starting to listen: does NOT create a conversation yet (it's created at the end
    /// depending on the duration). Forces a new session (meetingConvId = nil) so it doesn't attach to the
    /// previous meeting, and starts the partial-summary timer.
    func beginMeeting() {
        guard #available(macOS 13.0, *) else { return }
        meetingConvId = nil                    // ← each listen is a NEW session
        meetingSummarizedLen = 0
        meetingRollingSummaries = []
        meetingStartedAt = Date()

        meetingRollTimer?.invalidate()
        meetingRollTimer = Timer.scheduledTimer(withTimeInterval: 240, repeats: true) { [weak self] _ in
            self?.rollMeetingSummary()
        }
        Log.write("📝 listening started")
    }

    /// Creates (only once per session) the dedicated conversation, with a title depending on
    /// whether it's a meeting (🎧) or a talk (💬).
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

    /// Adds a message from the slime to the meeting conversation (by id).
    func appendToMeetingConversation(_ text: String, filePath: String? = nil) {
        guard let id = meetingConvId,
              let idx = chatStore.conversations.firstIndex(where: { $0.id == id }) else { return }
        chatStore.conversations[idx].messages.append(Msg(role: "assistant", content: text, filePath: filePath))
        chatStore.save()
        if chatActive && convIndex == idx { chatStick = true; chatScrollToBottom = true }
        needsDisplay = true
    }

    /// Mini-summary of the NEW chunk of transcript since last time.
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
                    Log.write("📝 partial summary #\(self.meetingRollingSummaries.count): \(mini.prefix(60))")
                    self.ensureMeetingConversation(isMeeting: true)       // by now (>4min) it's already a meeting
                    self.appendToMeetingConversation("🎧 " + mini)        // live partial (in its conversation)
                    self.say(Loc.t("🎧 anoté algo de la reunión…", "🎧 jotted down something…"))
                }
                completion?()
            }
        }
    }

    /// On stop: closes the last chunk, synthesizes the final summary in the
    /// chat (streaming), and attaches the full transcript as a clickable link.
    func finishMeeting() {
        guard #available(macOS 13.0, *) else { return }
        meetingRollTimer?.invalidate(); meetingRollTimer = nil
        rollMeetingSummary { [weak self] in self?.finalizeMeetingSummary() }
    }

    private func finalizeMeetingSummary() {
        let transcript = MeetingListener.shared.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filePath = saveTranscriptFile(transcript)
        let elapsed = Date().timeIntervalSince(meetingStartedAt)
        let isMeeting = elapsed >= PetView.meetingThreshold     // ≥1 min = meeting; otherwise a talk
        Log.write("📝 finalize — \(Int(elapsed))s, \(isMeeting ? "meeting" : "talk"), transcript=\(transcript.count) chars, partials=\(meetingRollingSummaries.count)")

        // Creates the dedicated conversation (title based on meeting/talk) and opens the chat.
        ensureMeetingConversation(isMeeting: isMeeting)
        if !chatActive { toggleChat() }
        chatScrollToBottom = true

        guard !transcript.isEmpty else {
            appendToMeetingConversation(Loc.t("No escuché nada claro 👂", "Didn't catch anything clear 👂")); return
        }
        // No AI configured: fallback → shows what it heard WITHOUT processing.
        guard let client = client, client.config.isConfigured else {
            Log.write("📝 no AI → fallback: showing the raw transcript")
            appendToMeetingConversation(
                Loc.t("🎧 Esto fue lo que escuché (sin IA para resumir):\n\n", "🎧 Here's what I heard (no AI to summarize):\n\n") + transcript)
            if let fp = filePath { appendToMeetingConversation(Loc.t("📄 Ver transcripción completa", "📄 View full transcript"), filePath: fp) }
            return
        }

        // Basis of the synthesis: if there were rolling summaries, use them (short); otherwise the transcript.
        let basis = meetingRollingSummaries.isEmpty
            ? transcript
            : meetingRollingSummaries.map { "- \($0)" }.joined(separator: "\n")

        // Meeting (≥1min): closing phrase + structured summary. Talk (<1min):
        // just a short summary, no closing phrase or structure.
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

    /// Saves the full transcript to a .txt and returns its path.
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
        catch { Log.write("📝 couldn't save the transcript: \(error.localizedDescription)"); return nil }
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
        case .alertSecondButtonReturn: cb(true, true)     // always
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

    /// Horizontal offset of the body (sway while searching).
    func bodyOffsetX() -> CGFloat {
        if state == .wiggling { return sin(CGFloat(stateTimer) * 0.6) * 3.0 }   // sideways wiggle
        guard chatActive && chatBusy else { return 0 }
        if chatActivity == 1 { return sin(CGFloat(tick) * 0.32) * 3.5 }   // searching: sway
        if chatActivity == 2 { return sin(CGFloat(tick) * 0.2) * 1.5 }    // looking: slight
        return 0
    }

    // ---- chat panel drawing ----
    struct ChatItem { let text: String; let kind: Int; var imagePath: String? = nil; var filePath: String? = nil }   // 0 slime, 1 user, 2 step

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
        if chatBusy && !live.isEmpty {               // text arriving via streaming
            items.append(ChatItem(text: live + "▌", kind: 0))
        }
        return items
    }

    func drawChat(_ ctx: CGContext) {
        chatButtons.removeAll(); listRowRects.removeAll(); copyButtons.removeAll(); thumbRects.removeAll(); fileButtons.removeAll()
        let W = bounds.width, H = bounds.height
        let pad: CGFloat = 8
        let panel = NSRect(x: pad, y: 96, width: W - 2 * pad, height: H - 96 - pad)
        // panel background
        let bg = NSBezierPath(roundedRect: panel, xRadius: 8, yRadius: 8)
        NSColor(white: 0.16, alpha: 0.95).setFill(); bg.fill()
        NSColor(srgbRed: 0.36, green: 0.85, blue: 0.55, alpha: 0.9).setStroke(); bg.lineWidth = 2; bg.stroke()

        let header = NSRect(x: panel.minX, y: panel.maxY - 28, width: panel.width, height: 28)
        // dynamic-height input (grows with the lines) + attachment row if there's a capture
        let sendW: CGFloat = 30
        let chipH: CGFloat = pendingShot != nil ? 24 : 0
        let inputInnerW = panel.width - 18 - sendW
        let th = attrSize(inputDisplayAttr(), inputInnerW).height
        let inputH = max(28, min(120, th + 10)) + chipH
        let inputR = NSRect(x: panel.minX, y: panel.minY, width: panel.width, height: inputH)
        let area = NSRect(x: panel.minX + 4, y: inputR.maxY + 4,
                          width: panel.width - 8, height: header.minY - inputR.maxY - 8)
        chatAreaH = area.height

        // --- header: name + buttons ---
        drawText("\(stats.displayName) 💬", header.minX + 8, header.minY + 7, size: 12,
                 color: NSColor(srgbRed: 0.62, green: 0.96, blue: 0.72, alpha: 1))
        let bs: CGFloat = 20, gapb: CGFloat = 4
        var bxr = header.maxX - 8 - bs
        var headerBtns: [(String, String)] = [("close", "✕"), ("new", "＋"), ("list", "☰")]
        if client?.config.supportsVision == true { headerBtns.append(("eye", "👁️")) }   // vision only on paid image-capable APIs
        headerBtns += [("ear", listening ? "⏹️" : "👂"), ("mic", micOn ? "⏹️" : "🎤")]
        for (id, icon) in headerBtns {
            let r = NSRect(x: bxr, y: header.minY + 4, width: bs, height: bs)
            let p = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            NSColor(white: 1, alpha: 0.12).setFill(); p.fill()
            switch id {
            case "eye": drawSymbol("eye", in: r, Self.chatAccent)
            case "ear": listening ? drawSymbol("stop.fill", in: r, Self.chatRecRed)
                                   : drawSymbol("ear", in: r, Self.chatAccent)
            case "mic": micOn ? drawSymbol("stop.fill", in: r, Self.chatRecRed)
                              : drawSymbol("mic.fill", in: r, Self.chatAccent)
            default:    drawText(icon, r.minX + 4, r.minY + 3, size: 12)
            }
            chatButtons.append(HudButton(id: id, icon: icon, rect: r))
            bxr -= bs + gapb
        }
        // separator line under the header
        NSColor(white: 1, alpha: 0.12).setFill()
        ctx.fill(CGRect(x: panel.minX + 4, y: header.minY - 1, width: panel.width - 8, height: 1))

        // --- conversation list (overlay) ---
        if listOpen { drawChatList(ctx, area); return }

        // --- messages ---
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let items = chatItems()
        let maxBW = area.width * 0.82
        // measure (same width as the drawing, so the text isn't cut off)
        let heights = items.map { bubbleHeight($0, maxBW, area.width) }
        let spacing: CGFloat = 6
        let total = heights.reduce(0, +) + spacing * CGFloat(max(0, items.count - 1)) + 8
        chatContentH = total
        let maxScroll = max(0, total - area.height)
        if chatScrollToBottom {
            // on opening/switching conversation: see the END (last complete message)
            chatScroll = maxScroll
            chatScrollToBottom = false
        } else if chatStick {
            // show the START of the last message (not the end), so the top isn't cut off
            let lastTop = heights.dropLast().reduce(0, +) + spacing * CGFloat(max(0, items.count - 1))
            chatScroll = min(lastTop, maxScroll)
        }
        chatScroll = max(0, min(maxScroll, chatScroll))

        ctx.saveGState(); NSBezierPath(rect: area).addClip()
        // draw from top (content) downward
        var cy: CGFloat = 0     // content coord from the top
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

        // --- attached capture chip (click = remove) ---
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

        // --- input (visible field, multiline) + send button ---
        let fieldR = NSRect(x: inputR.minX + 2, y: inputR.minY + 2, width: inputR.width - 4 - sendW, height: inputR.height - 4 - chipH)
        let ip = NSBezierPath(roundedRect: fieldR, xRadius: 5, yRadius: 5)
        NSColor(white: 0.95, alpha: 0.95).setFill(); ip.fill()
        NSColor(white: 0.4, alpha: 1).setStroke(); ip.lineWidth = 1; ip.stroke()
        drawAttr(inputDisplayAttr(), in: fieldR.insetBy(dx: 7, dy: 5))

        // send button (little arrow)
        sendRect = NSRect(x: fieldR.maxX + 4, y: fieldR.minY, width: sendW - 4, height: fieldR.height)
        let active = !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatBusy
        let sp = NSBezierPath(roundedRect: sendRect, xRadius: 6, yRadius: 6)
        (active ? NSColor(srgbRed: 0.30, green: 0.66, blue: 0.98, alpha: 1) : NSColor(white: 0.5, alpha: 0.6)).setFill(); sp.fill()
        let arrow = "➤" as NSString
        let asz = arrow.size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
        drawText("➤", sendRect.midX - asz.width / 2, sendRect.midY - asz.height / 2, size: 13)
    }

    func drawChatItem(_ it: ChatItem, font: NSFont, area: NSRect, top: CGFloat, height: CGFloat, maxBW: CGFloat) {
        if it.kind == 2 {   // tool step / thinking (gray, no bubble)
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
        // message with an attached file (transcript): the whole bubble is clickable
        if let path = it.filePath {
            NSColor(srgbRed: 0.62, green: 0.96, blue: 0.72, alpha: 0.9).setStroke()
            let bp = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5); bp.lineWidth = 1; bp.stroke()
            fileButtons.append((rect, path))
        }
        // capture thumbnail (clickable)
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

        // copy button when hovering over the bubble
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
            listRowRects.append(r)   // in draw order (reversed)
            y -= 28
            if y < area.minY { break }
        }
    }

    var chatFont: NSFont { NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) }
    var chatPara: NSParagraphStyle { let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping; return p }

    /// Converts Markdown to formatted text (bold, italic, code, lists, headings).
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
        return NSSize(width: ceil(r.width), height: ceil(r.height) + 6)   // extra margin so it's not cut off
    }

    /// Draws text TOP-aligned in our non-flipped view, using a flipped image.
    func drawAttr(_ a: NSAttributedString, in rect: NSRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        let img = NSImage(size: rect.size, flipped: true) { b in
            a.draw(with: b, options: [.usesLineFragmentOrigin, .usesFontLeading]); return true
        }
        img.draw(in: rect)
    }

    /// Bubble width for a message (text or with an image).
    func bubbleWidth(_ it: ChatItem, _ maxBW: CGFloat) -> CGFloat {
        let w = attrSize(chatAttr(it), maxBW - 12).width
        return max(it.imagePath != nil ? 116 : 0, min(maxBW, w + 14))
    }
    /// Bubble height measured at the SAME width the text is drawn with.
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
        if detachRect != .zero && detachRect.contains(p) {           // remove the attached capture
            pendingShot = nil; pendingShotPath = nil; needsDisplay = true; return true
        }
        if sendRect.contains(p) { sendChatMessage(); return true }   // send button
        for t in thumbRects where t.rect.contains(p) {          // open the capture
            NSWorkspace.shared.open(URL(fileURLWithPath: t.path))
            return true
        }
        for f in fileButtons where f.rect.contains(p) {         // open the full transcript
            NSWorkspace.shared.open(URL(fileURLWithPath: f.path))
            return true
        }
        for cb in copyButtons where cb.rect.contains(p) {       // copy text from a bubble
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
            case "mic": onToggleMic?()
            default: break
            }
            return true
        }
        if listOpen {
            // the rows were drawn in reverse(enumerate) order
            let order = Array(chatStore.conversations.indices.reversed())
            for (k, r) in listRowRects.enumerated() where r.contains(p) {
                if k < order.count { selectConversation(order[k]) }
                return true
            }
            return true   // click inside the list: consume
        }
        return false
    }

    // ------------------------------------------------------------------
    // Context menu (right click)
    // ------------------------------------------------------------------
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        // Feed (food submenu)
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
            window?.makeFirstResponder(self)        // regain focus to type
            let p = convert(event.locationInWindow, from: nil)
            if handleChatTap(p) { consumedByButton = true; return }
            if p.y > 88 { consumedByButton = true; return }   // click on the panel: neither drags nor jumps
        }
        let p = convert(event.locationInWindow, from: nil)
        consumedByButton = false
        // click on a HUD button?
        if hudAlpha > 0.4 {
            for b in buttons where b.rect.insetBy(dx: -3, dy: -3).contains(p) {
                consumedByButton = true; handleButton(b.id, at: event); return
            }
        }
        mouseDownAt = NSEvent.mouseLocation
        didDrag = false
        grabbedSlime = slimeHitRect().contains(p)       // only counts if you touched the slime
        if grabbedSlime && stats.isAsleep {             // moving it wakes it up
            stats.isAsleep = false
            stats.energy = max(stats.energy, 0.12)
            if state == .sleeping { enter(.idle) }
        }
        if let win = petWindow {
            let m = NSEvent.mouseLocation
            dragOffset = NSPoint(x: m.x - win.frame.origin.x, y: m.y - win.frame.origin.y)
        }
    }

    /// "Grabbable" zone: the slime's body (bottom-center).
    func slimeHitRect() -> NSRect {
        NSRect(x: slimeOX + 4 * PX, y: 0, width: 24 * PX, height: 22 * PX)
    }

    override func mouseDragged(with event: NSEvent) {
        if consumedByButton || chatActive || !grabbedSlime { return }   // only drags if you grabbed the slime
        guard !stats.isDead, state != .egg else { return }
        let m = NSEvent.mouseLocation
        if hypot(m.x - mouseDownAt.x, m.y - mouseDownAt.y) > 4 { didDrag = true }
        if didDrag, let win = petWindow {
            enter(.dragging)
            let vf = (win.screen ?? NSScreen.main)?.visibleFrame ?? win.frame
            var newOrigin = NSPoint(x: m.x - dragOffset.x, y: m.y - dragOffset.y)
            // don't let it leave the screen
            let (minX, maxX) = originXBounds(vf)
            newOrigin.x = max(minX, min(maxX, newOrigin.x))
            newOrigin.y = max(vf.minY, min(vf.maxY - bounds.height, newOrigin.y))
            vx = (newOrigin.x - win.frame.origin.x) * 0.5
            win.setFrameOrigin(newOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if consumedByButton { consumedByButton = false; return }
        if chatActive { return }        // with the chat open, the slime doesn't jump
        if !grabbedSlime { return }     // only reacts if you touched the slime, not the bubble/empty space
        if stats.isDead || state == .egg { return }
        if didDrag {
            vy = 0
            // dropped stuck to a side? -> it oozes down the wall
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
        if loveClicks >= 2 { loveClicks = 0; doPlay() }            // double click = play
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

// MARK: - Transparent floating window

final class PetWindow: NSWindow {
    init() {
        let size = NSSize(width: 160, height: 140)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        sharingType = .none          // default: don't appear in recordings / screen sharing
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

    /// `hidden=true` => the window doesn't appear in captures/recordings/screen sharing.
    func applyCapturePrivacy(_ hidden: Bool) { sharingType = hidden ? .none : .readOnly }
}

// MARK: - Menu bar icon (same slime pixel-art)

/// Draws the green slime (body + shine + happy face) in a small NSImage,
/// using the same grid logic as `PetView.drawSlime` / `drawFace`.
/// It's the same art as the app icon, but without a background, for the status item.
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
        let cell = S * 0.94 / 23.0                 // fits the slime's width (~23 cells)
        let originX = S / 2 - CGFloat(cx) * cell
        let originY = S / 2 - 11.5 * cell           // centers the vertical bbox (grid y ≈ 3..20)
        func fill(_ gx: Int, _ gy: Int, _ c: NSColor) {
            ctx.setShouldAntialias(false)
            ctx.setFillColor(c.cgColor)
            ctx.fill(CGRect(x: originX + CGFloat(gx) * cell, y: originY + CGFloat(gy) * cell,
                            width: cell + 0.4, height: cell + 0.4))
        }
        // body (same elliptical formula + border + highlight)
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
        // happy face looking forward
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
    img.isTemplate = false      // in color (not monochrome), like the app icon
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

    // alert rate-limit
    var alerted: [String: Date] = [:]

    func applicationDidFinishLaunching(_ note: Notification) {
        // Startup log: binary path + screen permission state (TCC).
        // If CGPreflight changes true→false between launches, the signature isn't stable.
        Log.write("🚀 Flubber started — bin=\(Bundle.main.executablePath ?? "?") · screen permission(preflight)=\(CGPreflightScreenCaptureAccess())")

        // Prevents macOS from "sleeping" the app in the background (we need to keep animating).
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "SlimePet animation loop")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        window = PetWindow()
        view = PetView(frame: window.contentRect(forFrameRect: window.frame))
        view.petWindow = window
        view.stats = PetStats.load()
        Pal.index = min(max(0, view.stats.skinIndex), Pal.skins.count - 1)
        view.state = view.stats.isDead ? .dead : (view.stats.stage == .egg ? .egg : .idle)
        view.restoreActiveConversation()             // opens the last conversation you were using

        // AI
        let cfg = AIConfig.load()
        Loc.override = cfg.lang                      // saved language (nil = system)
        view.client = makeBackend(cfg)
        window.applyCapturePrivacy(cfg.hideFromCaptureValue)   // hidden by default
        if let spec = cfg.customSkin, let skin = Pal.skin(from: spec) { Pal.setAISkin(skin) }
        view.onChatRequested = { [weak self] in self?.openChat() }
        view.onToggleListen = { [weak self] in self?.toggleListen() }
        view.onToggleMic = { [weak self] in self?.toggleMic() }

        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        // greeting on open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let v = self?.view else { return }
            if v.stats.isDead {                                   // it died while closed
                self?.notify("💀 \(v.stats.displayName) " + Loc.t("ha muerto", "has died"),
                             Loc.t("Lo descuidaste demasiado… toca 🥚 para empezar de nuevo.",
                                   "Too neglected… tap 🥚 to start over."))
                return
            }
            guard v.stats.stage != .egg else { return }
            v.react(.greeting)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = slimeStatusImage()      // same slime pixel-art as the icon
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
        if frame % 300 == 0 { view.stats.save() }     // saves every ~10 s
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
                if let last = alerted[key], Date().timeIntervalSince(last) < 600 { return }   // max 1 every 10 min
                alerted[key] = Date(); notify(title, body)
            } else { alerted[key] = nil }
        }
        let n = s.displayName
        maybe("hunger", s.hunger < Tuning.lowThreshold, Loc.t("🍖 ¡Tengo hambre!", "🍖 I'm hungry!"), Loc.t("\(n) necesita comer.", "\(n) needs to eat."))
        maybe("energy", s.energy < Tuning.lowThreshold, Loc.t("😴 Estoy agotado", "😴 I'm exhausted"), Loc.t("\(n) necesita dormir.", "\(n) needs to sleep."))
        maybe("clean",  s.cleanliness < Tuning.lowThreshold, Loc.t("🛁 ¡Qué sucio!", "🛁 So dirty!"), Loc.t("Hay que limpiar a \(n).", "\(n) needs a clean."))

        // also say it in the bubble, at the same threshold the button appears
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
            let micTitle = l.micOn
                ? Loc.t("Apagar micrófono ⏹️", "Turn off microphone ⏹️")
                : Loc.t("Incluir mi micrófono 🎤", "Include my microphone 🎤")
            menu.addItem(NSMenuItem(title: micTitle, action: #selector(toggleMic), keyEquivalent: ""))
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
        // Submenu with all the animations
        let animItem = NSMenuItem(title: Loc.t("Animaciones 🎭", "Animations 🎭"), action: nil, keyEquivalent: "")
        let animMenu = NSMenu()
        let anims: [(String, String, Selector, String)] = [
            ("¡Pasea! 🚶", "Walk! 🚶", #selector(walkNow), "w"),
            ("Persíguelo 🏃", "Chase cursor 🏃", #selector(chaseNow), "c"),
            ("¡Baila! 💃", "Dance! 💃", #selector(danceNow), "d"),
            ("¡Rueda! 🤸", "Roll! 🤸", #selector(rollNow), "r"),
            ("¡Salta! ⤴️", "Jump! ⤴️", #selector(jumpNow), ""),
            ("Contonéate 🪩", "Wiggle 🪩", #selector(wiggleNow), ""),
            ("Estírate 🙆", "Stretch 🙆", #selector(stretchNow), ""),
            ("Maréate 😵‍💫", "Spin 😵‍💫", #selector(spinNow), ""),
            ("Bosteza 🥱", "Yawn 🥱", #selector(yawnNow), ""),
        ]
        for (es, en, sel, key) in anims {
            let it = NSMenuItem(title: Loc.t(es, en), action: sel, keyEquivalent: key)
            it.target = self; animMenu.addItem(it)
        }
        animItem.submenu = animMenu
        menu.addItem(animItem)
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
        let next = Loc.lang == .es ? "en" : "es"     // toggles relative to the effective language
        Loc.override = next
        view.client?.config.lang = next
        view.client?.config.save()
        view.agent = nil                              // re-seeds prompts in the new language
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
    @objc func jumpNow()    { view.wakeUp(); view.enter(.happy) }
    @objc func wiggleNow()  { view.wakeUp(); view.enter(.wiggling) }
    @objc func stretchNow() { view.wakeUp(); view.enter(.stretching) }
    @objc func spinNow()    { view.wakeUp(); view.enter(.dizzy) }
    @objc func yawnNow()    { view.enter(.yawning) }
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

    // --- AI: integrated chat ---
    @objc func openChat() {
        if view.client?.config.isConfigured != true { showNeedConfig(); return }
        view.toggleChat()
    }

    // --- Listen to meeting (system audio → on-device transcription) ---
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
            // Wait for the last speech segment to flush, then close/summarize.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                Log.write("📝 stop → finalizing meeting (synthesis + transcript)")
                self?.view.finishMeeting()
            }
        } else {
            l.start { [weak self] ok, err in
                DispatchQueue.main.async {
                    Log.write("🎧 toggleListen.start callback ok=\(ok) err=\(err ?? "-")")
                    if ok {
                        self?.view.listening = true
                        self?.view.beginMeeting()                  // new session + rolling summaries
                        self?.view.say(Loc.t("Escuchando… 🎧", "Listening… 🎧"))
                    } else {
                        self?.notify("Flubber", err ?? Loc.t("No pude escuchar.", "Couldn't listen."))
                    }
                    self?.rebuildMenu()
                }
            }
        }
    }

    @objc func toggleMic() {
        guard #available(macOS 13.0, *) else {
            notify("Flubber", Loc.t("El micrófono requiere macOS 13+.", "Mic requires macOS 13+.")); return
        }
        let l = MeetingListener.shared
        if l.micOn {
            l.stopMic()
            view.micOn = false
            view.say(Loc.t("Apagué el micrófono 🎤", "Mic off 🎤"))
            rebuildMenu()
        } else {
            l.startMic { [weak self] ok, err in
                DispatchQueue.main.async {
                    if ok {
                        self?.view.micOn = true
                        self?.view.say(Loc.t("Te escucho 🎤", "I can hear you 🎤"))
                    } else {
                        self?.notify("Flubber", err ?? Loc.t("No pude usar el micrófono.", "Couldn't use the mic."))
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

    // --- AI: create skin ---
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

    // --- AI: configuration ---
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

// MARK: - Text fields that accept ⌘V/⌘C/⌘X/⌘A in apps without a menu bar

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

// MARK: - AI settings window

final class ConfigController: NSObject, NSWindowDelegate {
    var window: NSWindow!
    var config: AIConfig
    let onSave: (AIConfig) -> Void

    private var providerPopup: NSPopUpButton!
    private var kiBox: NSView!, mmBox: NSView!, clBox: NSView!, oaBox: NSView!, dsBox: NSView!, orBox: NSView!
    private var kiKeyField: NSSecureTextField!, mmKeyField: NSSecureTextField!, clKeyField: NSSecureTextField!
    private var oaKeyField: NSSecureTextField!, dsKeyField: NSSecureTextField!, orKeyField: NSSecureTextField!
    private var kiModelPopup: NSPopUpButton!, mmModelPopup: NSPopUpButton!, clModelPopup: NSPopUpButton!
    private var oaModelPopup: NSPopUpButton!, dsModelPopup: NSPopUpButton!, orModelPopup: NSPopUpButton!
    private var statusLabel: NSTextField!

    // provider order in the popup (Kilo first = free default)
    private let providers = ["kilo", "minimax", "claude", "openai", "deepseek", "openrouter"]
    private let kiTitles = ["Laguna (gratis, recomendado)", "Laguna XS (gratis)", "Auto (variable)"]
    private let kiValues = ["poolside/laguna-m.1:free", "poolside/laguna-xs.2:free", "kilo-auto/free"]
    private let mmTitles = ["MiniMax-M2.7", "MiniMax-M2.5", "MiniMax-M2.1", "MiniMax-M2"]
    private let clTitles = ["Haiku 4.5 (económico)", "Sonnet 4.6", "Opus 4.8"]
    private let clValues = ["claude-haiku-4-5-20251001", "claude-sonnet-4-6", "claude-opus-4-8"]
    private let oaModels = ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini"]
    private let dsModels = ["deepseek-chat", "deepseek-reasoner"]
    private let orTitles = ["MiniMax M2.5 (gratis)", "MiniMax M2.5 (de pago)", "MiniMax M2.7 (de pago)"]
    private let orValues = ["minimax/minimax-m2.5:free", "minimax/minimax-m2.5", "minimax/minimax-m2.7"]
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
        providerPopup.addItems(withTitles: ["Kilo (gratis, sin clave)", "MiniMax", "Claude (Anthropic)", "ChatGPT (OpenAI)", "DeepSeek", "OpenRouter (gratis)"])
        providerPopup.target = self; providerPopup.action = #selector(providerChanged)
        c.addSubview(providerPopup)

        let console = NSButton(title: "Abrir consola ↗", target: self, action: #selector(openConsole))
        console.frame = NSRect(x: W-160, y: H-69, width: 140, height: 28); c.addSubview(console)

        // The sections occupy the same space; only the active provider's is visible.
        let boxFrame = NSRect(x: 20, y: 110, width: W-40, height: 110)
        kiBox = NSView(frame: boxFrame); mmBox = NSView(frame: boxFrame); clBox = NSView(frame: boxFrame)
        oaBox = NSView(frame: boxFrame); dsBox = NSView(frame: boxFrame); orBox = NSView(frame: boxFrame)
        c.addSubview(kiBox); c.addSubview(mmBox); c.addSubview(clBox); c.addSubview(oaBox); c.addSubview(dsBox); c.addSubview(orBox)

        func boxLabel(_ s: String, _ y: CGFloat, bold: Bool = false) -> NSTextField {
            let l = NSTextField(labelWithString: s); l.frame = NSRect(x: 0, y: y, width: boxFrame.width, height: 18)
            if bold { l.font = NSFont.boldSystemFont(ofSize: 12) }; l.textColor = .secondaryLabelColor; return l
        }

        // Kilo Gateway (gratis, sin clave). Clave opcional para más límites.
        kiBox.addSubview(boxLabel("Gratis sin clave (~200 mensajes/hora). Opcional: pega tu clave de Kilo para más.", 88, bold: true))
        kiKeyField = PastableSecureTextField(frame: NSRect(x: 0, y: 58, width: boxFrame.width, height: 24))
        kiKeyField.placeholderString = "clave de Kilo (opcional, ⌘V para pegar)"; kiBox.addSubview(kiKeyField)
        let kiModelLbl = boxLabel("Modelo:", 26); kiModelLbl.frame.size.width = 64; kiBox.addSubview(kiModelLbl)
        kiModelPopup = NSPopUpButton(frame: NSRect(x: 70, y: 22, width: 220, height: 26))
        kiModelPopup.addItems(withTitles: kiTitles); kiBox.addSubview(kiModelPopup)
        let kiNote = boxLabel("⚠︎ Gratis puede registrar tus mensajes; no envíes datos sensibles. (Sin visión de imágenes.)", 2)
        kiNote.font = NSFont.systemFont(ofSize: 10); kiBox.addSubview(kiNote)

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

        // OpenRouter (modelos gratis; agregador OpenAI-compatible)
        orBox.addSubview(boxLabel("Clave de OpenRouter (sk-or-…) — modelos :free gratis:", 88, bold: true))
        orKeyField = PastableSecureTextField(frame: NSRect(x: 0, y: 58, width: boxFrame.width, height: 24))
        orKeyField.placeholderString = "clave de OpenRouter (⌘V para pegar)"; orBox.addSubview(orKeyField)
        let orModelLbl = boxLabel("Modelo:", 26); orModelLbl.frame.size.width = 64; orBox.addSubview(orModelLbl)
        orModelPopup = NSPopUpButton(frame: NSRect(x: 70, y: 22, width: 280, height: 26))
        orModelPopup.addItems(withTitles: orTitles); orBox.addSubview(orModelPopup)

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
        kiBox.isHidden = i != 0; mmBox.isHidden = i != 1; clBox.isHidden = i != 2
        oaBox.isHidden = i != 3; dsBox.isHidden = i != 4; orBox.isHidden = i != 5
    }

    @objc private func providerChanged() { updateVisibility() }

    func show() {
        providerPopup.selectItem(at: max(0, providers.firstIndex(of: config.provider) ?? 0))
        kiKeyField.stringValue = config.kiloKeyValue
        kiModelPopup.selectItem(at: kiValues.firstIndex(of: config.kiloModelValue) ?? 0)
        mmKeyField.stringValue = config.apiKey
        mmModelPopup.selectItem(withTitle: config.model); if mmModelPopup.indexOfSelectedItem < 0 { mmModelPopup.selectItem(at: 1) }
        clKeyField.stringValue = config.claudeKeyValue
        clModelPopup.selectItem(at: clValues.firstIndex(of: config.claudeModelValue) ?? 0)
        oaKeyField.stringValue = config.openaiKeyValue
        oaModelPopup.selectItem(withTitle: config.openaiModelValue); if oaModelPopup.indexOfSelectedItem < 0 { oaModelPopup.selectItem(at: 0) }
        dsKeyField.stringValue = config.deepseekKeyValue
        dsModelPopup.selectItem(withTitle: config.deepseekModelValue); if dsModelPopup.indexOfSelectedItem < 0 { dsModelPopup.selectItem(at: 0) }
        orKeyField.stringValue = config.openrouterKeyValue
        orModelPopup.selectItem(at: orValues.firstIndex(of: config.openrouterModelValue) ?? 0)
        statusLabel.stringValue = config.isConfigured ? "Configurado ✅" : "Falta la clave del proveedor elegido."
        updateVisibility()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func current() -> AIConfig {
        var c = config
        c.provider = providers[min(provIndex(), providers.count - 1)]
        c.kiloKey = kiKeyField.stringValue.isEmpty ? nil : kiKeyField.stringValue
        c.kiloModel = kiValues[min(max(0, kiModelPopup.indexOfSelectedItem), kiValues.count - 1)]
        c.apiKey = mmKeyField.stringValue
        c.model = mmModelPopup.titleOfSelectedItem ?? "MiniMax-M2.5"
        c.claudeKey = clKeyField.stringValue.isEmpty ? nil : clKeyField.stringValue
        c.claudeModel = clValues[min(max(0, clModelPopup.indexOfSelectedItem), clValues.count - 1)]
        c.openaiKey = oaKeyField.stringValue.isEmpty ? nil : oaKeyField.stringValue
        c.openaiModel = oaModelPopup.titleOfSelectedItem
        c.deepseekKey = dsKeyField.stringValue.isEmpty ? nil : dsKeyField.stringValue
        c.deepseekModel = dsModelPopup.titleOfSelectedItem
        c.openrouterKey = orKeyField.stringValue.isEmpty ? nil : orKeyField.stringValue
        c.openrouterModel = orValues[min(max(0, orModelPopup.indexOfSelectedItem), orValues.count - 1)]
        return c
    }

    @objc private func openConsole() {
        let url: String
        switch provIndex() {
        case 0: url = "https://app.kilo.ai/api-keys"
        case 2: url = "https://console.anthropic.com/settings/keys"
        case 3: url = "https://platform.openai.com/api-keys"
        case 4: url = "https://platform.deepseek.com/api_keys"
        case 5: url = "https://openrouter.ai/keys"
        default: url = "https://platform.minimax.io/user-center/basic-information/interface-key"
        }
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    @objc private func testConn() {
        persist()                      // saves before testing, so it isn't lost
        let c = config
        statusLabel.stringValue = "Probando…"
        makeBackend(c).test { [weak self] _, msg in self?.statusLabel.stringValue = msg }
    }

    /// Reads the fields, saves to Keychain/disk, and updates the live client.
    private func persist() {
        config = current()
        config.save()                  // key → Keychain, rest → config.json
        onSave(config)
    }

    @objc private func saveCfg() {
        persist()
        statusLabel.stringValue = config.isConfigured ? "Guardado ✅" : "Guardado (sin clave)"
    }

    @objc private func closeWin() { persist(); window.orderOut(nil) }

    // Also saves if closed with the red button / ⌘W.
    func windowWillClose(_ notification: Notification) { persist() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
