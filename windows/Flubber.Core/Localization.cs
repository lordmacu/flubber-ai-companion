using System.Globalization;

namespace Flubber.Core;

public enum Lang { Es, En }

/// <summary>
/// App language (interface + prompts + responses). By default it follows the system;
/// it can be forced to "es" or "en" and changes on the fly. Equivalent to Loc.swift.
/// </summary>
public static class Loc
{
    /// <summary>null = follow the system; "es"/"en" = forced by the user.</summary>
    public static string? Override { get; set; }

    public static Lang Lang
    {
        get
        {
            if (Override is { } o) return o == "en" ? Lang.En : Lang.Es;
            var sys = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.ToLowerInvariant();
            return sys.StartsWith("es") ? Lang.Es : Lang.En;
        }
    }

    /// <summary>Returns the string in the current language.</summary>
    public static string T(string es, string en) => Lang == Lang.Es ? es : en;

    public static bool IsES => Lang == Lang.Es;
    public static string Name => Lang == Lang.Es ? "Español" : "English";
}
