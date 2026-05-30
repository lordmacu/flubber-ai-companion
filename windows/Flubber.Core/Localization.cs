using System.Globalization;

namespace Flubber.Core;

public enum Lang { Es, En }

/// <summary>
/// Idioma de la app (interfaz + prompts + respuestas). Por defecto sigue al sistema;
/// se puede forzar a "es" o "en" y cambia al vuelo. Equivalente a Loc.swift.
/// </summary>
public static class Loc
{
    /// <summary>null = seguir al sistema; "es"/"en" = forzado por el usuario.</summary>
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

    /// <summary>Devuelve la cadena en el idioma actual.</summary>
    public static string T(string es, string en) => Lang == Lang.Es ? es : en;

    public static bool IsES => Lang == Lang.Es;
    public static string Name => Lang == Lang.Es ? "Español" : "English";
}
