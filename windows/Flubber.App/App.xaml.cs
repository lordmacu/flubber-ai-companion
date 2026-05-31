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

        // Key encryption with DPAPI (must be ready BEFORE the first Load).
        AIConfig.ProtectFn = SecretProtector.Protect;
        AIConfig.UnprotectFn = SecretProtector.Unprotect;

        // Saved language (config) before building the UI.
        var cfg = AIConfig.Load();
        Loc.Override = cfg.Lang;

        _pet = new PetWindow();
        _pet.Show();
    }
}
