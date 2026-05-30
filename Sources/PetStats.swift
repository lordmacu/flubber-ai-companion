import Foundation

// ============================================================================
// PetStats — el "alma" Tamagotchi del slime.
// Modelo puro (sin UI): necesidades que decaen en tiempo real, acciones de
// cuidado, salud/enfermedad, edad/evolución, muerte y persistencia en disco.
// ============================================================================

// MARK: - Ajustes (todo tunable desde aquí)

enum Tuning {
    // Tasas de decaimiento POR MINUTO (de un rango 0..1). Más bajo = más lento.
    static let hungerDecay      = 0.0035
    static let happyDecay       = 0.0025
    static let energyDecay      = 0.0025  // despierto
    static let energyRegen      = 0.020   // dormido
    static let cleanDecayPerPoop = 0.0015 // por cada popó presente, por minuto
    static let healthDecay      = 0.005   // cuando algo va mal
    static let healthRegen      = 0.004   // cuando todo va bien

    // Popó: probabilidad por minuto de hacer popó "espontánea" (más baja = menos popó).
    static let poopChancePerMin = 0.03
    static let poopAfterEatMin  = 2.5     // popó ~2.5 min tras comer (y no siempre)

    // Edad / evolución (en horas simuladas).
    static let hatchHours       = 0.05    // huevo -> bebé
    static let childHours       = 6.0     // bebé -> niño
    static let adultHours       = 24.0    // niño -> adulto

    // Tope de decaimiento offline (segundos). Evita que "vacaciones" lo maten al instante.
    static let offlineCapSeconds = 8.0 * 3600.0

    // Multiplicador de tiempo. Pon SLIMEPET_TIMESCALE=60 para que 1s real ≈ 1min.
    static let timeScale: Double = {
        if let s = ProcessInfo.processInfo.environment["SLIMEPET_TIMESCALE"], let v = Double(s), v > 0 {
            return v
        }
        return 1.0
    }()

    // Umbrales
    static let lowThreshold     = 0.20    // "necesita atención"
    static let careShow         = 0.32    // bajo esto aparece el botón/mensaje de cuidado
    static let sickHealth       = 0.22    // bajo esto puede enfermar (más bajo = enferma menos)
}

// MARK: - Comidas

enum Food: String, CaseIterable, Codable {
    case apple, meat, candy

    var emoji: String { self == .apple ? "🍎" : self == .meat ? "🍖" : "🍬" }
    var name: String  { self == .apple ? "Manzana" : self == .meat ? "Carne" : "Dulce" }

    var hungerGain: Double { self == .apple ? 0.30 : self == .meat ? 0.55 : 0.15 }
    var happyGain:  Double { self == .apple ? 0.05 : self == .meat ? 0.10 : 0.30 }
    var healthDelta: Double { self == .apple ? 0.05 : self == .meat ? 0.00 : -0.12 }
}

// MARK: - Eventos que produce un tick (para animaciones / notificaciones)

enum PetEvent: Equatable {
    case pooped
    case gotSick
    case died
    case evolved(Int)   // nueva etapa
    case hatched
}

// MARK: - Etapas de vida

enum LifeStage: Int, Codable {
    case egg = 0, baby = 1, child = 2, adult = 3
}

// MARK: - Estado del Tamagotchi

struct PetStats: Codable {
    var hunger = 1.0          // 0 hambriento .. 1 lleno
    var happiness = 1.0
    var energy = 1.0
    var cleanliness = 1.0
    var health = 1.0
    var poops = 0
    var ageHours = 0.0
    var stage = LifeStage.egg
    var careScore = 0.0       // calidad de cuidado acumulada
    var skinIndex = 0         // color elegido
    var isSick = false
    var isAsleep = false
    var isDead = false
    var lastUpdate = Date()
    var bornAt = Date()
    var name: String? = nil                       // nombre que le pone el dueño (opcional)
    var displayName: String { (name?.isEmpty == false) ? name! : "Flubber" }

    // Reloj interno para temporizar la popó tras comer.
    private var minutesSinceFed = 999.0
    private var pendingPoopAtFed = false

    // ------------------------------------------------------------------
    // Avance del tiempo. dt en SEGUNDOS reales. Devuelve eventos ocurridos.
    // ------------------------------------------------------------------
    mutating func tick(dt realDt: TimeInterval) -> [PetEvent] {
        guard !isDead else { lastUpdate = Date(); return [] }
        var events: [PetEvent] = []

        // minutos simulados transcurridos
        let mins = (realDt * Tuning.timeScale) / 60.0
        guard mins > 0 else { return [] }

        let wasStage = stage

        // --- Edad y evolución ---
        ageHours += mins / 60.0
        let newStage = stageFor(ageHours: ageHours)
        if newStage.rawValue > stage.rawValue {
            stage = newStage
            events.append(stage == .baby ? .hatched : .evolved(stage.rawValue))
        }

        // El huevo no tiene necesidades todavía.
        if stage == .egg { lastUpdate = Date(); return events }

        // --- Hambre ---
        hunger = clamp(hunger - Tuning.hungerDecay * mins)

        // --- Energía (según duerma o no) ---
        if isAsleep {
            energy = clamp(energy + Tuning.energyRegen * mins)
            if energy >= 1.0 { isAsleep = false }      // despierta solo al recargar
        } else {
            energy = clamp(energy - Tuning.energyDecay * mins)
            if energy <= 0.05 { isAsleep = true }       // se desmaya de sueño
        }

        // --- Felicidad (peor con hambre o suciedad) ---
        var hap = Tuning.happyDecay
        if hunger <= 0.01 { hap *= 2 }
        if poops > 0 { hap *= 1.0 + Double(poops) * 0.4 }
        happiness = clamp(happiness - hap * mins)

        // --- Limpieza ---
        if poops > 0 {
            cleanliness = clamp(cleanliness - Tuning.cleanDecayPerPoop * Double(poops) * mins)
        }

        // --- Popó ---
        minutesSinceFed += mins
        if pendingPoopAtFed && minutesSinceFed >= Tuning.poopAfterEatMin {
            pendingPoopAtFed = false
            poops += 1
            events.append(.pooped)
        }
        // popó espontánea (probabilidad acumulada en el intervalo)
        if Double.random(in: 0...1) < Tuning.poopChancePerMin * mins {
            poops += 1
            events.append(.pooped)
        }

        // --- Salud ---
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

        // --- Enfermedad ---
        if !isSick && (health < Tuning.sickHealth || poops >= 6) {
            if Double.random(in: 0...1) < 0.06 * mins {     // mucho menos probable enfermar
                isSick = true
                events.append(.gotSick)
            }
        }

        // --- Muerte ---
        if health <= 0.0 {
            isDead = true
            isAsleep = false
            events.append(.died)
        }

        if stage != wasStage { /* ya añadido arriba */ }
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
    // Acciones de cuidado
    // ------------------------------------------------------------------
    mutating func feed(_ food: Food) {
        guard !isDead, stage != .egg else { return }
        // sobrealimentar (ya lleno) penaliza salud
        if hunger > 0.95 { health = clamp(health - 0.05) }
        hunger = clamp(hunger + food.hungerGain)
        happiness = clamp(happiness + food.happyGain)
        health = clamp(health + food.healthDelta)
        minutesSinceFed = 0
        pendingPoopAtFed = Double.random(in: 0...1) < 0.5   // no siempre hace popó tras comer
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
    // Derivados para la UI
    // ------------------------------------------------------------------
    var needsAttention: Bool {
        !isDead && stage != .egg &&
        (hunger < Tuning.careShow || energy < Tuning.careShow ||
         cleanliness < Tuning.careShow || isSick)
    }

    /// Escala visual del cuerpo según la etapa (bebé pequeño .. adulto grande).
    var sizeScale: Double {
        switch stage {
        case .egg:   return 1.0
        case .baby:  return 0.6
        case .child: return 0.8
        case .adult: return 1.0
        }
    }

    /// "Humor" general 0 (fatal) .. 1 (genial), para elegir expresión.
    var mood: Double {
        if isDead { return 0 }
        return (hunger + happiness + cleanliness + health) / 4.0
    }

    private func clamp(_ v: Double) -> Double { min(1.0, max(0.0, v)) }

    // ------------------------------------------------------------------
    // Persistencia
    // ------------------------------------------------------------------
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlimePet", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }

    /// Carga el estado y aplica el decaimiento del tiempo que estuvo cerrado.
    /// El catch-up se hace en sub-pasos (~10 min simulados) para que los eventos
    /// probabilísticos (popó, enfermedad, muerte) se acumulen de forma realista
    /// en vez de "un solo tick gigante" que satura las probabilidades.
    static func load() -> PetStats {
        guard let data = try? Data(contentsOf: fileURL),
              var s = try? JSONDecoder().decode(PetStats.self, from: data) else {
            return PetStats()
        }
        var remaining = min(Date().timeIntervalSince(s.lastUpdate), Tuning.offlineCapSeconds)
        let chunk = max(1.0, 600.0 / Tuning.timeScale)      // ≈10 min simulados por paso
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
