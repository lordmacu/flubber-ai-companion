using System.Text.Json;
using System.Text.Json.Serialization;
using Flubber.Core.Platform;

namespace Flubber.Core;

// ============================================================================
// The Tamagotchi "soul" of the slime. Faithful port of PetStats.swift.
// Pure model (no UI): needs that decay in real time, care actions,
// health/sickness, age/evolution, death and on-disk persistence.
// ============================================================================

/// <summary>Tuning (everything tunable from here).</summary>
public static class Tuning
{
    // Decay rates PER MINUTE (of a 0..1 range). Lower = slower.
    public const double HungerDecay = 0.0035;
    public const double HappyDecay = 0.0025;
    public const double EnergyDecay = 0.0025;   // awake
    public const double EnergyRegen = 0.020;    // asleep
    public const double CleanDecayPerPoop = 0.0015; // per poop present, per minute
    public const double HealthDecay = 0.005;    // when something is wrong
    public const double HealthRegen = 0.004;    // when everything is fine

    public const double PoopChancePerMin = 0.03;
    public const double PoopAfterEatMin = 2.5;  // poop ~2.5 min after eating (and not always)

    // Age / evolution (in simulated hours).
    public const double HatchHours = 0.0014;   // egg -> baby (~5 s reales con timeScale=1)
    public const double ChildHours = 6.0;
    public const double AdultHours = 24.0;

    // Cap on offline decay (seconds).
    public const double OfflineCapSeconds = 8.0 * 3600.0;

    // Time multiplier. SLIMEPET_TIMESCALE=60 => 1s real ≈ 1min.
    public static readonly double TimeScale = ReadTimeScale();
    private static double ReadTimeScale()
    {
        var s = Environment.GetEnvironmentVariable("SLIMEPET_TIMESCALE");
        if (s != null && double.TryParse(s, System.Globalization.CultureInfo.InvariantCulture, out var v) && v > 0)
            return v;
        return 1.0;
    }

    public const double LowThreshold = 0.20;
    public const double CareShow = 0.32;
    public const double SickHealth = 0.22;
}

public enum Food { Apple, Meat, Candy }

public static class FoodExtensions
{
    public static string Emoji(this Food f) => f switch { Food.Apple => "🍎", Food.Meat => "🍖", _ => "🍬" };
    public static string Name(this Food f) => f switch { Food.Apple => "Manzana", Food.Meat => "Carne", _ => "Dulce" };
    public static double HungerGain(this Food f) => f switch { Food.Apple => 0.30, Food.Meat => 0.55, _ => 0.15 };
    public static double HappyGain(this Food f) => f switch { Food.Apple => 0.05, Food.Meat => 0.10, _ => 0.30 };
    public static double HealthDelta(this Food f) => f switch { Food.Apple => 0.05, Food.Meat => 0.00, _ => -0.12 };
}

public enum LifeStage { Egg = 0, Baby = 1, Child = 2, Adult = 3 }

public enum PetEventKind { Pooped, GotSick, Died, Evolved, Hatched }

public readonly record struct PetEvent(PetEventKind Kind, int Stage = 0)
{
    public static PetEvent Pooped => new(PetEventKind.Pooped);
    public static PetEvent GotSick => new(PetEventKind.GotSick);
    public static PetEvent Died => new(PetEventKind.Died);
    public static PetEvent Hatched => new(PetEventKind.Hatched);
    public static PetEvent Evolved(int stage) => new(PetEventKind.Evolved, stage);
}

/// <summary>Tamagotchi state (mutable; persisted in state.json).</summary>
public sealed class PetStats
{
    public double Hunger { get; set; } = 1.0;       // 0 hungry .. 1 full
    public double Happiness { get; set; } = 1.0;
    public double Energy { get; set; } = 1.0;
    public double Cleanliness { get; set; } = 1.0;
    public double Health { get; set; } = 1.0;
    public int Poops { get; set; }
    public double AgeHours { get; set; }
    public LifeStage Stage { get; set; } = LifeStage.Egg;
    public double CareScore { get; set; }
    public int SkinIndex { get; set; }
    public bool IsSick { get; set; }
    public bool IsAsleep { get; set; }
    public bool IsDead { get; set; }
    public DateTime LastUpdate { get; set; } = DateTime.UtcNow;
    public DateTime BornAt { get; set; } = DateTime.UtcNow;
    public string? Name { get; set; }

    [JsonIgnore] public string DisplayName => !string.IsNullOrEmpty(Name) ? Name! : "Flubber";

    // Internal clock to time the poop after eating.
    public double MinutesSinceFed { get; set; } = 999.0;
    public bool PendingPoopAtFed { get; set; }

    // ------------------------------------------------------------------
    // Time advance. dt in real SECONDS. Returns the events that occurred.
    // ------------------------------------------------------------------
    public List<PetEvent> Tick(double realDtSeconds)
    {
        var events = new List<PetEvent>();
        if (IsDead) { LastUpdate = DateTime.UtcNow; return events; }

        var mins = (realDtSeconds * Tuning.TimeScale) / 60.0;
        if (mins <= 0) return events;

        // --- Age and evolution ---
        AgeHours += mins / 60.0;
        var newStage = StageFor(AgeHours);
        if ((int)newStage > (int)Stage)
        {
            Stage = newStage;
            events.Add(Stage == LifeStage.Baby ? PetEvent.Hatched : PetEvent.Evolved((int)Stage));
        }

        if (Stage == LifeStage.Egg) { LastUpdate = DateTime.UtcNow; return events; }

        // --- Hunger ---
        Hunger = Clamp(Hunger - Tuning.HungerDecay * mins);

        // --- Energy ---
        if (IsAsleep)
        {
            Energy = Clamp(Energy + Tuning.EnergyRegen * mins);
            if (Energy >= 1.0) IsAsleep = false;
        }
        else
        {
            Energy = Clamp(Energy - Tuning.EnergyDecay * mins);
            if (Energy <= 0.05) IsAsleep = true;
        }

        // --- Happiness ---
        var hap = Tuning.HappyDecay;
        if (Hunger <= 0.01) hap *= 2;
        if (Poops > 0) hap *= 1.0 + Poops * 0.4;
        Happiness = Clamp(Happiness - hap * mins);

        // --- Cleanliness ---
        if (Poops > 0)
            Cleanliness = Clamp(Cleanliness - Tuning.CleanDecayPerPoop * Poops * mins);

        // --- Poop ---
        MinutesSinceFed += mins;
        if (PendingPoopAtFed && MinutesSinceFed >= Tuning.PoopAfterEatMin)
        {
            PendingPoopAtFed = false;
            Poops += 1;
            events.Add(PetEvent.Pooped);
        }
        if (Random.Shared.NextDouble() < Tuning.PoopChancePerMin * mins)
        {
            Poops += 1;
            events.Add(PetEvent.Pooped);
        }

        // --- Health ---
        var bad = Hunger <= 0.01 || Cleanliness <= 0.01 || IsSick || Poops >= 3;
        if (bad)
        {
            Health = Clamp(Health - Tuning.HealthDecay * mins);
            CareScore = Math.Max(0, CareScore - 0.5 * mins);
        }
        else
        {
            Health = Clamp(Health + Tuning.HealthRegen * mins);
            if (Hunger > 0.5 && Happiness > 0.5 && Cleanliness > 0.5)
                CareScore += 0.5 * mins;
        }

        // --- Sickness ---
        if (!IsSick && (Health < Tuning.SickHealth || Poops >= 6))
        {
            if (Random.Shared.NextDouble() < 0.06 * mins)
            {
                IsSick = true;
                events.Add(PetEvent.GotSick);
            }
        }

        // --- Death ---
        if (Health <= 0.0)
        {
            IsDead = true;
            IsAsleep = false;
            events.Add(PetEvent.Died);
        }

        LastUpdate = DateTime.UtcNow;
        return events;
    }

    public LifeStage StageFor(double h)
    {
        if (h < Tuning.HatchHours) return LifeStage.Egg;
        if (h < Tuning.ChildHours) return LifeStage.Baby;
        if (h < Tuning.AdultHours) return LifeStage.Child;
        return LifeStage.Adult;
    }

    // ------------------------------------------------------------------
    // Care actions
    // ------------------------------------------------------------------
    public void Feed(Food food)
    {
        if (IsDead || Stage == LifeStage.Egg) return;
        if (Hunger > 0.95) Health = Clamp(Health - 0.05);
        Hunger = Clamp(Hunger + food.HungerGain());
        Happiness = Clamp(Happiness + food.HappyGain());
        Health = Clamp(Health + food.HealthDelta());
        MinutesSinceFed = 0;
        PendingPoopAtFed = Random.Shared.NextDouble() < 0.5;
    }

    public void Play()
    {
        if (IsDead || Stage == LifeStage.Egg || IsAsleep) return;
        Happiness = Clamp(Happiness + 0.25);
        Energy = Clamp(Energy - 0.08);
    }

    public void Clean()
    {
        if (IsDead) return;
        Poops = 0;
        Cleanliness = 1.0;
    }

    public void Medicine()
    {
        if (IsDead) return;
        if (IsSick)
        {
            IsSick = false;
            Health = Clamp(Health + 0.35);
        }
    }

    public void ToggleSleep()
    {
        if (IsDead || Stage == LifeStage.Egg) return;
        IsAsleep = !IsAsleep;
    }

    public void Restart()
    {
        var keepSkin = SkinIndex;
        Hunger = Happiness = Energy = Cleanliness = Health = 1.0;
        Poops = 0; AgeHours = 0; Stage = LifeStage.Egg; CareScore = 0;
        IsSick = IsAsleep = IsDead = false;
        LastUpdate = BornAt = DateTime.UtcNow;
        Name = null; MinutesSinceFed = 999.0; PendingPoopAtFed = false;
        SkinIndex = keepSkin;
    }

    // ------------------------------------------------------------------
    // Derived values for the UI
    // ------------------------------------------------------------------
    [JsonIgnore]
    public bool NeedsAttention =>
        !IsDead && Stage != LifeStage.Egg &&
        (Hunger < Tuning.CareShow || Energy < Tuning.CareShow ||
         Cleanliness < Tuning.CareShow || IsSick);

    [JsonIgnore]
    public double SizeScale => Stage switch
    {
        LifeStage.Egg => 1.0,
        LifeStage.Baby => 0.6,
        LifeStage.Child => 0.8,
        _ => 1.0,
    };

    [JsonIgnore]
    public double Mood => IsDead ? 0 : (Hunger + Happiness + Cleanliness + Health) / 4.0;

    private static double Clamp(double v) => Math.Min(1.0, Math.Max(0.0, v));

    // ------------------------------------------------------------------
    // Persistence
    // ------------------------------------------------------------------
    public static PetStats Load()
    {
        try
        {
            if (System.IO.File.Exists(Paths.StateJson))
            {
                var json = System.IO.File.ReadAllText(Paths.StateJson);
                var s = JsonSerializer.Deserialize<PetStats>(json);
                if (s != null)
                {
                    var elapsed = Math.Min((DateTime.UtcNow - s.LastUpdate).TotalSeconds, Tuning.OfflineCapSeconds);
                    if (elapsed > 0) s.Tick(elapsed);
                    return s;
                }
            }
        }
        catch { /* ignore */ }
        return new PetStats();
    }

    public void Save()
    {
        try { System.IO.File.WriteAllText(Paths.StateJson, JsonSerializer.Serialize(this)); }
        catch { /* ignore */ }
    }
}
