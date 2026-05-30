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

        // Idioma guardado (config) antes de construir la UI.
        var cfg = AIConfig.Load();
        Loc.Override = cfg.Lang;

        _pet = new PetWindow();
        _pet.Show();
    }
}
