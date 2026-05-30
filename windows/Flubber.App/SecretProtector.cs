using System.Security.Cryptography;
using System.Text;

namespace Flubber.App;

/// <summary>
/// Cifra las claves API con DPAPI (ámbito usuario actual): solo este usuario de Windows
/// puede descifrarlas. Reemplaza al Keychain de macOS. Las claves en config.json quedan
/// como "dpapi:&lt;base64&gt;". Migración: una clave en texto plano se devuelve tal cual.
/// </summary>
public static class SecretProtector
{
    private const string Prefix = "dpapi:";

    public static string Protect(string plain)
    {
        try
        {
            var enc = ProtectedData.Protect(Encoding.UTF8.GetBytes(plain), null, DataProtectionScope.CurrentUser);
            return Prefix + Convert.ToBase64String(enc);
        }
        catch { return plain; }   // si DPAPI falla, no rompemos el guardado
    }

    public static string Unprotect(string stored)
    {
        if (!stored.StartsWith(Prefix)) return stored;   // texto plano (versión anterior)
        try
        {
            var dec = ProtectedData.Unprotect(Convert.FromBase64String(stored[Prefix.Length..]), null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(dec);
        }
        catch { return ""; }   // irrecuperable (p.ej. otro usuario): forzar reconfigurar, no corromper
    }
}
