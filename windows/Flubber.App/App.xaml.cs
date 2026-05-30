using System.Windows;
using Flubber.Core;
using Flubber.Core.AI;

namespace Flubber.App;

public partial class App : System.Windows.Application
{
    private PetWindow? _pet;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Cifrado de claves con DPAPI (debe quedar listo ANTES del primer Load).
        AIConfig.ProtectFn = SecretProtector.Protect;
        AIConfig.UnprotectFn = SecretProtector.Unprotect;

        // Idioma guardado (config) antes de construir la UI.
        var cfg = AIConfig.Load();
        Loc.Override = cfg.Lang;

        _pet = new PetWindow();
        _pet.Show();
    }
}
