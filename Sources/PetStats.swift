import Foundation

// ============================================================================
// PetStats — the slime's Tamagotchi "soul".
// Pure model (no UI): needs that decay in real time, care actions,
// health/sickness, age/evolution, death, and persistence to disk.
// ============================================================================

// MARK: - Settings (everything tunable from here)

enum Tuning {
    // Decay rates PER MINUTE (over a 0..1 range). Lower = slower.
    static let hungerDecay      = 0.0035
    static let happyDecay       = 0.0025
    static let energyDecay      = 0.0025  // awake
    static let energyRegen      = 0.020   // asleep
    static let cleanDecayPerPoop = 0.0015 // for each poop present, per minute
    static let healthDecay      = 0.005   // when something is wrong
    static let healthRegen      = 0.004   // when everything is fine

    // Poop: per-minute probability of pooping "spontaneously" (lower = less poop).
    static let poopChancePerMin = 0.03
    static let poopAfterEatMin  = 2.5     // poop ~2.5 min after eating (and not always)

    // Age / evolution (in simulated hours).
    static let hatchHours       = 0.05    // egg -> baby
    static let childHours       = 6.0     // baby -> child
    static let adultHours       = 24.0    // child -> adult

    // Offline decay cap (seconds). Prevents "vacations" from killing it instantly.
    static let offlineCapSeconds = 8.0 * 3600.0

    // Time multiplier. Set SLIMEPET_TIMESCALE=60 so that 1 real second ≈ 1 minute.
    static let timeScale: Double = {
        if let s = ProcessInfo.processInfo.environment["SLIMEPET_TIMESCALE"], let v = Double(s), v > 0 {
            return v
        }
        return 1.0
    }()

    // Thresholds
    static let lowThreshold     = 0.20    // "needs attention"
    static let careShow         = 0.32    // below this the care button/message appears
    static let sickHealth       = 0.22    // below this it can get sick (lower = sicker less often)
}

// MARK: - Foods

enum Food: String, CaseIterable, Codable {
    case apple, meat, candy

    var emoji: String { self == .apple ? "🍎" : self == .meat ? "🍖" : "🍬" }
    var name: String  { self == .apple ? "Manzana" : self == .meat ? "Carne" : "Dulce" }

    var hungerGain: Double { self == .apple ? 0.30 : self == .meat ? 0.55 : 0.15 }
    var happyGain:  Double { self == .apple ? 0.05 : self == .meat ? 0.10 : 0.30 }
    var healthDelta: Double { self == .apple ? 0.05 : self == .meat ? 0.00 : -0.12 }
}

// MARK: - Events produced by a tick (for animations / notifications)

enum PetEvent: Equatable {
    case pooped
    case gotSick
    case died
    case evolved(Int)   // new stage
    case hatched
}

// MARK: - Life stages

enum LifeStage: Int, Codable {
    case egg = 0, baby = 1, child = 2, adult = 3
}

// MARK: - Tamagotchi state

struct PetStats: Codable {
    var hunger = 1.0          // 0 hungry .. 1 full
    var happiness = 1.0
    var energy = 1.0
    var cleanliness = 1.0
    var health = 1.0
    var poops = 0
    var ageHours = 0.0
    var stage = LifeStage.egg
    var careScore = 0.0       // accumulated care quality
    var skinIndex = 0         // chosen color
    var isSick = false
    var isAsleep = false
    var isDead = false
    var lastUpdate = Date()
    var bornAt = Date()
    var name: String? = nil                       // name the owner gives it (optional)
    var displayName: String { (name?.isEmpty == false) ? name! : "Flubber" }

    // Internal clock to time pooping after eating.
    private var minutesSinceFed = 999.0
    private var pendingPoopAtFed = false

    // ------------------------------------------------------------------
    // Time advance. dt in real SECONDS. Returns the events that occurred.
    // ------------------------------------------------------------------
    mutating func tick(dt realDt: TimeInterval) -> [PetEvent] {
        guard !isDead else { lastUpdate = Date(); return [] }
        var events: [PetEvent] = []

        // simulated minutes elapsed
        let mins = (realDt * Tuning.timeScale) / 60.0
        guard mins > 0 else { return [] }

        let wasStage = stage

        // --- Age and evolution ---
        ageHours += mins / 60.0
        let newStage = stageFor(ageHours: ageHours)
        if newStage.rawValue > stage.rawValue {
            stage = newStage
            events.append(stage == .baby ? .hatched : .evolved(stage.rawValue))
        }

        // The egg has no needs yet.
        if stage == .egg { lastUpdate = Date(); return events }

        // --- Hunger ---
        hunger = clamp(hunger - Tuning.hungerDecay * mins)

        // --- Energy (depending on whether it sleeps) ---
        if isAsleep {
            energy = clamp(energy + Tuning.energyRegen * mins)
            if energy >= 1.0 { isAsleep = false }      // only wakes up once recharged
        } else {
            energy = clamp(energy - Tuning.energyDecay * mins)
            if energy <= 0.05 { isAsleep = true }       // faints from sleepiness
        }

        // --- Happiness (worse with hunger or dirtiness) ---
        var hap = Tuning.happyDecay
        if hunger <= 0.01 { hap *= 2 }
        if poops > 0 { hap *= 1.0 + Double(poops) * 0.4 }
        happiness = clamp(happiness - hap * mins)

        // --- Cleanliness ---
        if poops > 0 {
            cleanliness = clamp(cleanliness - Tuning.cleanDecayPerPoop * Double(poops) * mins)
        }

        // --- Poop ---
        minutesSinceFed += mins
        if pendingPoopAtFed && minutesSinceFed >= Tuning.poopAfterEatMin {
            pendingPoopAtFed = false
            poops += 1
            events.append(.pooped)
        }
        // spontaneous poop (probability accumulated over the interval)
        if Double.random(in: 0...1) < Tuning.poopChancePerMin * mins {
            poops += 1
            events.append(.pooped)
        }

        // --- Health ---
        let bad = hunger <= 0.01 || cleanliness <= 0.01 || isSick || poops >= 3
        if bad {
            health = clamp(health - Tuning.healthDecay * mins)
            careScore = max(0, careScore - 0.5 * mins)
        } else {
            health = clamp(health + Tuning.healthRegen * mins)
            if hunger > 0.5 && happiness > 0.5 && cleanliness > 0.5 {
                careScore += 0.5 * mins
            }
        }

        // --- Sickness ---
        if !isSick && (health < Tuning.sickHealth || poops >= 6) {
            if Double.random(in: 0...1) < 0.06 * mins {     // much less likely to get sick
                isSick = true
                events.append(.gotSick)
            }
        }

        // --- Death ---
        if health <= 0.0 {
            isDead = true
            isAsleep = false
            events.append(.died)
        }

        if stage != wasStage { /* already added above */ }
        lastUpdate = Date()
        return events
    }

    func stageFor(ageHours h: Double) -> LifeStage {
        if h < Tuning.hatchHours { return .egg }
        if h < Tuning.childHours { return .baby }
        if h < Tuning.adultHours { return .child }
        return .adult
    }

    // ------------------------------------------------------------------
    // Care actions
    // ------------------------------------------------------------------
    mutating func feed(_ food: Food) {
        guard !isDead, stage != .egg else { return }
        // overfeeding (already full) penalizes health
        if hunger > 0.95 { health = clamp(health - 0.05) }
        hunger = clamp(hunger + food.hungerGain)
        happiness = clamp(happiness + food.happyGain)
        health = clamp(health + food.healthDelta)
        minutesSinceFed = 0
        pendingPoopAtFed = Double.random(in: 0...1) < 0.5   // doesn't always poop after eating
    }

    mutating func play() {
        guard !isDead, stage != .egg, !isAsleep else { return }
        happiness = clamp(happiness + 0.25)
        energy = clamp(energy - 0.08)
    }

    mutating func clean() {
        guard !isDead else { return }
        poops = 0
        cleanliness = 1.0
    }

    mutating func medicine() {
        guard !isDead else { return }
        if isSick {
            isSick = false
            health = clamp(health + 0.35)
        }
    }

    mutating func toggleSleep() {
        guard !isDead, stage != .egg else { return }
        isAsleep.toggle()
    }

    mutating func restart() {
        let keepSkin = skinIndex
        self = PetStats()
        skinIndex = keepSkin
    }

    // ------------------------------------------------------------------
    // Derived values for the UI
    // ------------------------------------------------------------------
    var needsAttention: Bool {
        !isDead && stage != .egg &&
        (hunger < Tuning.careShow || energy < Tuning.careShow ||
         cleanliness < Tuning.careShow || isSick)
    }

    /// Visual scale of the body by stage (small baby .. large adult).
    var sizeScale: Double {
        switch stage {
        case .egg:   return 1.0
        case .baby:  return 0.6
        case .child: return 0.8
        case .adult: return 1.0
        }
    }

    /// Overall "mood" 0 (terrible) .. 1 (great), for picking an expression.
    var mood: Double {
        if isDead { return 0 }
        return (hunger + happiness + cleanliness + health) / 4.0
    }

    private func clamp(_ v: Double) -> Double { min(1.0, max(0.0, v)) }

    // ------------------------------------------------------------------
    // Persistence
    // ------------------------------------------------------------------
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlimePet", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }

    /// Loads the state and applies the decay for the time it was closed.
    /// The catch-up runs in sub-steps (~10 simulated min) so that the
    /// probabilistic events (poop, sickness, death) accumulate realistically
    /// instead of "one giant tick" that saturates the probabilities.
    static func load() -> PetStats {
        guard let data = try? Data(contentsOf: fileURL),
              var s = try? JSONDecoder().decode(PetStats.self, from: data) else {
            return PetStats()
        }
        var remaining = min(Date().timeIntervalSince(s.lastUpdate), Tuning.offlineCapSeconds)
        let chunk = max(1.0, 600.0 / Tuning.timeScale)      // ≈10 simulated min per step
        while remaining > 0, !s.isDead {
            let step = min(remaining, chunk)
            _ = s.tick(dt: step)
            remaining -= step
        }
        s.lastUpdate = Date()
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: PetStats.fileURL)
        }
    }
}
