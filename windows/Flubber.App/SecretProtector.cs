using System.Security.Cryptography;
using System.Text;

namespace Flubber.App;

/// <summary>
/// Encrypts API keys with DPAPI (current-user scope): only this Windows user can
/// decrypt them. Replaces the macOS Keychain. Keys in config.json are stored
/// as "dpapi:&lt;base64&gt;". Migration: a plaintext key is returned as-is.
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
        catch { return plain; }   // if DPAPI fails, don't break saving
    }

    public static string Unprotect(string stored)
    {
        if (!stored.StartsWith(Prefix)) return stored;   // plaintext (older version)
        try
        {
            var dec = ProtectedData.Unprotect(Convert.FromBase64String(stored[Prefix.Length..]), null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(dec);
        }
        catch { return ""; }   // unrecoverable (e.g. another user): force reconfigure, don't corrupt
    }
}
