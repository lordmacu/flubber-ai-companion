using System.Diagnostics;
using System.Windows;
using Flubber.Core;
using Flubber.Core.AI;
using Controls = System.Windows.Controls;

namespace Flubber.App;

/// <summary>AI settings window (provider, key, model). Parity with the macOS "AI settings" window.</summary>
public sealed class SettingsWindow : Window
{
    private readonly AIConfig _cfg;
    private readonly Controls.ComboBox _provider = new() { Margin = new Thickness(0, 2, 0, 10) };
    private readonly Controls.TextBox _key = new() { Margin = new Thickness(0, 2, 0, 10) };
    private readonly Controls.TextBox _model = new() { Margin = new Thickness(0, 2, 0, 10) };
    private readonly Controls.TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) };

    private static readonly (string Id, string Label)[] Providers =
    {
        ("minimax", "MiniMax (recomendado)"), ("claude", "Claude (Anthropic)"),
        ("openai", "ChatGPT (OpenAI)"), ("deepseek", "DeepSeek"),
    };

    public bool Saved { get; private set; }

    public SettingsWindow(AIConfig cfg)
    {
        _cfg = cfg;
        Title = Loc.T("Configurar IA", "AI settings");
        Width = 440; Height = 360; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen; Topmost = true;

        var panel = new Controls.StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(Label(Loc.T("Proveedor", "Provider")));
        foreach (var p in Providers) _provider.Items.Add(p.Label);
        _provider.SelectionChanged += (_, _) => LoadProvider(Providers[_provider.SelectedIndex].Id, fromConfig: false);
        panel.Children.Add(_provider);

        panel.Children.Add(Label(Loc.T("Clave API", "API key")));
        panel.Children.Add(_key);
        panel.Children.Add(Label(Loc.T("Modelo", "Model")));
        panel.Children.Add(_model);

        var row = new Controls.StackPanel { Orientation = Controls.Orientation.Horizontal };
        row.Children.Add(Button(Loc.T("Abrir consola", "Open console"), OpenConsole));
        row.Children.Add(Button(Loc.T("Probar conexión", "Test connection"), async () => await TestAsync()));
        row.Children.Add(Button(Loc.T("Guardar", "Save"), Save, isDefault: true));
        panel.Children.Add(row);
        panel.Children.Add(_status);

        Content = panel;

        var idx = Array.FindIndex(Providers, p => p.Id == cfg.Provider);
        _provider.SelectedIndex = idx < 0 ? 0 : idx;
        LoadProvider(cfg.Provider, fromConfig: true);
    }

    private static Controls.TextBlock Label(string t) => new() { Text = t, FontWeight = FontWeights.SemiBold };

    private Controls.Button Button(string text, Action onClick, bool isDefault = false)
    {
        var b = new Controls.Button { Content = text, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(10, 4, 10, 4), IsDefault = isDefault };
        b.Click += (_, _) => onClick();
        return b;
    }

    private void LoadProvider(string id, bool fromConfig)
    {
        (string key, string model) = id switch
        {
            "claude" => (_cfg.ClaudeKey ?? "", _cfg.ClaudeModel ?? "claude-haiku-4-5-20251001"),
            "openai" => (_cfg.OpenaiKey ?? "", _cfg.OpenaiModel ?? "gpt-4o"),
            "deepseek" => (_cfg.DeepseekKey ?? "", _cfg.DeepseekModel ?? "deepseek-chat"),
            _ => (_cfg.ApiKey, string.IsNullOrEmpty(_cfg.Model) ? "MiniMax-M2.5" : _cfg.Model),
        };
        _key.Text = key;
        _model.Text = model;
    }

    private string CurrentProviderId => Providers[Math.Max(0, _provider.SelectedIndex)].Id;

    private AIConfig WorkingCopy()
    {
        var c = new AIConfig { Provider = CurrentProviderId };
        switch (c.Provider)
        {
            case "claude": c.ClaudeKey = _key.Text.Trim(); c.ClaudeModel = _model.Text.Trim(); break;
            case "openai": c.OpenaiKey = _key.Text.Trim(); c.OpenaiModel = _model.Text.Trim(); break;
            case "deepseek": c.DeepseekKey = _key.Text.Trim(); c.DeepseekModel = _model.Text.Trim(); break;
            default: c.ApiKey = _key.Text.Trim(); c.Model = _model.Text.Trim(); break;
        }
        return c;
    }

    private void OpenConsole()
    {
        var url = CurrentProviderId switch
        {
            "claude" => "https://console.anthropic.com/settings/keys",
            "openai" => "https://platform.openai.com/api-keys",
            "deepseek" => "https://platform.deepseek.com/api_keys",
            _ => "https://platform.minimax.io",
        };
        try { Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true }); } catch { }
    }

    private async Task TestAsync()
    {
        _status.Text = Loc.T("Probando…", "Testing…");
        var backend = BackendFactory.Make(WorkingCopy());
        try
        {
            var (ok, msg) = await backend.TestAsync();
            _status.Text = (ok ? "✅ " : "❌ ") + msg;
        }
        catch (Exception e) { _status.Text = "❌ " + e.Message; }
    }

    private void Save()
    {
        var id = CurrentProviderId;
        _cfg.Provider = id;
        switch (id)
        {
            case "claude": _cfg.ClaudeKey = _key.Text.Trim(); _cfg.ClaudeModel = _model.Text.Trim(); break;
            case "openai": _cfg.OpenaiKey = _key.Text.Trim(); _cfg.OpenaiModel = _model.Text.Trim(); break;
            case "deepseek": _cfg.DeepseekKey = _key.Text.Trim(); _cfg.DeepseekModel = _model.Text.Trim(); break;
            default: _cfg.ApiKey = _key.Text.Trim(); _cfg.Model = _model.Text.Trim(); break;
        }
        _cfg.Save();
        Saved = true;
        Close();
    }
}
