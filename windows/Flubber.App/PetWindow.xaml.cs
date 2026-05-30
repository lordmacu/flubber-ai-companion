using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using SkiaSharp.Views.Desktop;
using Flubber.Core;
using Flubber.Core.AI;
using Flubber.Core.Agent;
using Flubber.App.Interop;
using Flubber.App.Rendering;
using Forms = System.Windows.Forms;

namespace Flubber.App;

/// <summary>
/// Ventana de la mascota: transparente, topmost, fuera del Alt-Tab y excluible de
/// capturas. Hospeda el render Skia + el loop de animación e implementa el puente
/// de plataforma (IPlatformBridge) que usa el Agent.
/// </summary>
public partial class PetWindow : Window, IPlatformBridge
{
    private readonly PetStats _stats;
    private readonly AIConfig _cfg;
    private IAIBackend _client;
    private Agent _agent;

    private readonly SlimeRenderer _renderer = new();
    private readonly SlimeView _view = new();
    private readonly DispatcherTimer _timer = new();
    private readonly Random _rng = new();

    private Forms.NotifyIcon _tray = null!;
    private IntPtr _hwnd;
    private int _tick;
    private DateTime _lastTick = DateTime.UtcNow;
    private int _saveCounter;
    private int _blinkUntil;
    private int _nextBlink = 60;
    private int _facing = 1;
    private SlimeState? _transient;
    private int _transientUntil;

    public PetWindow()
    {
        InitializeComponent();

        _stats = PetStats.Load();
        _cfg = AIConfig.Load();
        Loc.Override = _cfg.Lang;
        _client = BackendFactory.Make(_cfg);
        _agent = new Agent(_client, this);

        Palette.Index = Math.Clamp(_stats.SkinIndex, 0, Palette.Skins.Length - 1);
        if (_cfg.CustomSkin is { } spec && Palette.FromSpec(spec) is { } sk) Palette.SetAiSkin(sk);
        _view.Skin = Palette.Current;

        Loaded += OnLoaded;
        SourceInitialized += OnSourceInitialized;
        Closed += (_, _) => { try { _tray.Visible = false; _tray.Dispose(); } catch { } };
        MouseLeftButtonDown += OnLeftDown;
        MouseRightButtonUp += OnRightUp;

        _timer.Interval = TimeSpan.FromMilliseconds(33);
        _timer.Tick += OnFrame;
    }

    // ---------------------------------------------------------------- ciclo de vida
    private void OnLoaded(object? sender, RoutedEventArgs e)
    {
        var wa = SystemParameters.WorkArea;
        Left = wa.Left + (wa.Width - Width) / 2;
        Top = wa.Bottom - Height;
        SetupTray();
        _timer.Start();
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;
        try
        {
            var ex = Native.GetWindowLong(_hwnd, Native.GWL_EXSTYLE);
            Native.SetWindowLong(_hwnd, Native.GWL_EXSTYLE, ex | Native.WS_EX_TOOLWINDOW);
        }
        catch { }
        ApplyStealth(_cfg.HideFromCaptureValue);
    }

    private void ApplyStealth(bool hide)
    {
        try { Native.SetWindowDisplayAffinity(_hwnd, hide ? Native.WDA_EXCLUDEFROMCAPTURE : Native.WDA_NONE); }
        catch { }
    }

    // ---------------------------------------------------------------- loop de animación
    private void OnFrame(object? sender, EventArgs e)
    {
        _tick++;
        var now = DateTime.UtcNow;
        var dt = (now - _lastTick).TotalSeconds;
        _lastTick = now;

        foreach (var ev in _stats.Tick(dt)) HandleEvent(ev);
        if (++_saveCounter >= 300) { _saveCounter = 0; _stats.Save(); }

        if (_tick >= _nextBlink) { _blinkUntil = _tick + 4; _nextBlink = _tick + _rng.Next(60, 200); }

        UpdateView();
        Surface.InvalidateVisual();
    }

    private void UpdateView()
    {
        _view.Skin = Palette.Current;
        _view.Tick = _tick;
        _view.SizeScale = _stats.SizeScale;
        _view.Blink = _tick < _blinkUntil;

        var sy = 1 - Math.Sin(_tick * 0.08) * 0.04;       // respiración
        _view.ScaleY = sy;
        _view.ScaleX = 1 / Math.Sqrt(sy);
        _view.Expr = _stats.IsSick ? Expr.Sick
            : (_stats.Hunger < 0.25 || _stats.Mood < 0.4 ? Expr.Sad : Expr.Normal);

        if (_transient is { } ts && _tick < _transientUntil) _view.State = ts;
        else
        {
            _transient = null;
            if (_stats.IsDead) _view.State = SlimeState.Dead;
            else if (_stats.Stage == LifeStage.Egg) _view.State = SlimeState.Egg;
            else if (_stats.IsAsleep) _view.State = SlimeState.Sleeping;
            else _view.State = SlimeState.Idle;
        }

        ComputeLook();
        _view.Facing = _facing;
    }

    private void ComputeLook()
    {
        try
        {
            Native.GetWindowRect(_hwnd, out var r);
            var (cxp, cyp) = Native.CursorPos();
            double centerX = (r.Left + r.Right) / 2.0;
            double centerY = (r.Top + r.Bottom) / 2.0;
            _view.LookX = Math.Sign(cxp - centerX);
            _view.LookY = Math.Sign(cyp - centerY);
            if (cxp < centerX - 20) _facing = -1; else if (cxp > centerX + 20) _facing = 1;
        }
        catch { }
    }

    private void OnPaint(object? sender, SKPaintSurfaceEventArgs e) =>
        _renderer.Draw(e.Surface.Canvas, e.Info.Width, e.Info.Height, _view);

    // ---------------------------------------------------------------- input
    private void OnLeftDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2) { DoPlay(); return; }
        try { DragMove(); } catch { }
    }

    private void OnRightUp(object sender, MouseButtonEventArgs e)
    {
        var (x, y) = Native.CursorPos();
        _tray.ContextMenuStrip?.Show(x, y);
    }

    private void DoPlay()
    {
        _stats.Play();
        SetTransient(SlimeState.Happy, 30);
    }

    private void SetTransient(SlimeState s, int frames) { _transient = s; _transientUntil = _tick + frames; }

    private void HandleEvent(PetEvent ev)
    {
        switch (ev.Kind)
        {
            case PetEventKind.Hatched: Notify("🐣 Flubber", Loc.T("¡Nació!", "Born!")); SetTransient(SlimeState.Happy, 40); break;
            case PetEventKind.Evolved: Notify("✨ Flubber", Loc.T("¡Creció!", "Grew up!")); SetTransient(SlimeState.Happy, 40); break;
            case PetEventKind.GotSick: Notify("🤒 Flubber", Loc.T("Me siento mal…", "I feel sick…")); break;
            case PetEventKind.Died: Notify("💀 Flubber", Loc.T("Me descuidaste demasiado…", "Too neglected…")); break;
        }
    }

    private void Notify(string title, string body)
    {
        try { _tray.ShowBalloonTip(4000, title, body, Forms.ToolTipIcon.None); } catch { }
    }

    // ---------------------------------------------------------------- bandeja + menú
    private void SetupTray()
    {
        _tray = new Forms.NotifyIcon
        {
            Icon = IconFactory.SlimeTrayIcon(),
            Visible = true,
            Text = "Flubber",
            ContextMenuStrip = BuildMenu(),
        };
        _tray.DoubleClick += (_, _) => OpenChat();
    }

    private Forms.ContextMenuStrip BuildMenu()
    {
        var m = new Forms.ContextMenuStrip();
        m.Items.Add(Loc.T("Alimentar 🍖", "Feed 🍖"), null, (_, _) => { _stats.Feed(Food.Meat); SetTransient(SlimeState.Happy, 24); });
        m.Items.Add(Loc.T("Jugar 🎮", "Play 🎮"), null, (_, _) => DoPlay());
        m.Items.Add(Loc.T("Limpiar 🛁", "Clean 🛁"), null, (_, _) => _stats.Clean());
        m.Items.Add(Loc.T("Medicina 💊", "Medicine 💊"), null, (_, _) => _stats.Medicine());
        m.Items.Add(Loc.T("Dormir / Despertar 💤", "Sleep / Wake 💤"), null, (_, _) => _stats.ToggleSleep());
        m.Items.Add(new Forms.ToolStripSeparator());
        m.Items.Add(Loc.T("Hablar con Flubber… 💬", "Chat with Flubber… 💬"), null, (_, _) => OpenChat());
        m.Items.Add(Loc.T("Configurar IA… ⚙️", "AI settings… ⚙️"), null, (_, _) => OpenSettings());
        m.Items.Add(Loc.T("Cambiar color 🎨", "Change color 🎨"), null, (_, _) => CycleColor());

        var hide = new Forms.ToolStripMenuItem(Loc.T("Ocultar en capturas/grabaciones 🕵️", "Hide from captures/recordings 🕵️"))
        { Checked = _cfg.HideFromCaptureValue, CheckOnClick = false };
        hide.Click += (_, _) =>
        {
            _cfg.HideFromCapture = !_cfg.HideFromCaptureValue;
            _cfg.Save();
            ApplyStealth(_cfg.HideFromCaptureValue);
            hide.Checked = _cfg.HideFromCaptureValue;
        };
        m.Items.Add(hide);

        m.Items.Add(Loc.T("Idioma: English 🌐", "Language: Español 🌐"), null, (_, _) => ToggleLang());
        m.Items.Add(new Forms.ToolStripSeparator());
        m.Items.Add(Loc.T("Nuevo huevo 🥚", "New egg 🥚"), null, (_, _) => _stats.Restart());
        m.Items.Add(Loc.T("Salir de Flubber", "Quit Flubber"), null, (_, _) => Quit());
        return m;
    }

    private void CycleColor()
    {
        Palette.Index = (Palette.Index + 1) % Palette.Skins.Length;
        Palette.ClearAiSkin();
        _stats.SkinIndex = Palette.Index;
    }

    private void OpenSettings()
    {
        var w = new SettingsWindow(_cfg);
        w.ShowDialog();
        if (w.Saved)
        {
            _client = BackendFactory.Make(_cfg);
            _agent = new Agent(_client, this);
        }
    }

    private void ToggleLang()
    {
        var next = Loc.Lang == Lang.Es ? "en" : "es";
        Loc.Override = next;
        _cfg.Lang = next;
        _cfg.Save();
        _tray.ContextMenuStrip = BuildMenu();
    }

    private void Quit()
    {
        try { _stats.Save(); _tray.Visible = false; _tray.Dispose(); } catch { }
        System.Windows.Application.Current.Shutdown();
    }

    // ---------------------------------------------------------------- chat mínimo
    private async void OpenChat()
    {
        if (!_cfg.IsConfigured)
        {
            Notify("Flubber", Loc.T("Configura la IA en config.json (%APPDATA%\\SlimePet).",
                                    "Set up AI in config.json (%APPDATA%\\SlimePet)."));
            return;
        }
        var text = ShowPrompt("Flubber", Loc.T("¿Qué quieres decirle a Flubber?", "What do you want to tell Flubber?"));
        if (text == null) return;
        SetTransient(SlimeState.Happy, 100000);
        try
        {
            var reply = await _agent.RunAsync(text, null, _ => { });
            Notify("Flubber 💬", reply);
        }
        catch (Exception ex) { Notify("Flubber", "Error: " + ex.Message); }
        finally { _transient = null; }
    }

    private static string? ShowPrompt(string title, string message)
    {
        var dlg = new Window
        {
            Title = title, Width = 400, Height = 160, ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.CenterScreen, Topmost = true,
        };
        var panel = new System.Windows.Controls.StackPanel { Margin = new Thickness(12) };
        panel.Children.Add(new System.Windows.Controls.TextBlock { Text = message, Margin = new Thickness(0, 0, 0, 8) });
        var tb = new System.Windows.Controls.TextBox();
        panel.Children.Add(tb);
        var ok = new System.Windows.Controls.Button
        {
            Content = "OK", Width = 90, Margin = new Thickness(0, 10, 0, 0),
            HorizontalAlignment = System.Windows.HorizontalAlignment.Right, IsDefault = true,
        };
        string? result = null;
        ok.Click += (_, _) => { result = tb.Text; dlg.DialogResult = true; };
        panel.Children.Add(ok);
        dlg.Content = panel;
        tb.Loaded += (_, _) => tb.Focus();
        dlg.ShowDialog();
        return string.IsNullOrWhiteSpace(result) ? null : result;
    }

    // ================================================================ IPlatformBridge
    public PetStats Stats => _stats;

    public Task<(string? Base64, string? Path)> CaptureScreenAsync(string? appHint)
        => Flubber.App.Platform.ScreenCapture.CaptureAsync(appHint);

    public void AttachShot(string path) { /* Fase 8: thumbnail en el chat */ }

    public string ControlSlime(string accion, string tema) => Dispatcher.Invoke(() =>
    {
        accion = (accion ?? "").ToLowerInvariant();
        tema = (tema ?? "").ToLowerInvariant();
        switch (accion)
        {
            case "bailar": SetTransient(SlimeState.Dancing, 120); return "¡A bailar! 💃";
            case "rodar": SetTransient(SlimeState.Dancing, 90); return "¡Rodando! 🤸";
            case "pasear": return "Me voy a pasear 🚶";
            case "feliz": SetTransient(SlimeState.Happy, 60); return "¡Yupi! 😄";
            case "dormir": _stats.IsAsleep = true; return "Zzz 😴";
            case "color":
                var names = new[] { "verde", "azul", "morado", "rosa" };
                var i = Array.FindIndex(names, n => tema.Contains(n));
                if (i >= 0) { Palette.Index = i; Palette.ClearAiSkin(); _stats.SkinIndex = i; } else CycleColor();
                return "Nuevo color 🎨";
            case "skin":
                if (string.IsNullOrEmpty(tema)) return "¿De qué tema quieres el skin?";
                _ = GenerateAiSkinAsync(tema);
                return $"Generando un skin de {tema}… ✨";
            default: return "No conozco esa acción.";
        }
    });

    private async Task GenerateAiSkinAsync(string theme)
    {
        var reply = await _client.ChatAsync(
            Loc.T("Eres un diseñador de paletas. Responde SOLO con JSON.", "You are a palette designer. Reply ONLY with JSON."),
            Array.Empty<(string, string)>(), Personality.SkinPrompt(theme), 800).ConfigureAwait(false);
        if (reply != null && Personality.ParseSkin(reply) is { } spec)
        {
            Dispatcher.Invoke(() =>
            {
                if (Palette.FromSpec(spec) is { } sk) { Palette.SetAiSkin(sk); _cfg.CustomSkin = spec; _cfg.Save(); }
            });
        }
    }

    public Task<string> BrowserGetUrlAsync() => Flubber.App.Platform.BrowserCdp.GetUrlAsync();

    public Task<string> BrowserRunJsAsync(string js) => Flubber.App.Platform.BrowserCdp.RunJsAsync(js);

    public Task<string> OpenTargetAsync(string target)
    {
        try
        {
            var t = target.Contains("://") ? target : (target.Contains('.') ? "https://" + target : target);
            Process.Start(new ProcessStartInfo { FileName = t, UseShellExecute = true });
            return Task.FromResult($"Abierto: {target}");
        }
        catch (Exception e) { return Task.FromResult("No pude abrir: " + e.Message); }
    }

    public Task<string> RunCommandAsync(string cmd) => Task.Run(() =>
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -Command \"" + cmd.Replace("\"", "\\\"") + "\"",
                RedirectStandardOutput = true, RedirectStandardError = true,
                UseShellExecute = false, CreateNoWindow = true,
            };
            using var p = Process.Start(psi)!;
            var outp = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
            p.WaitForExit();
            if (outp.Length > 2000) outp = outp[..2000] + "…";
            return "Salida:\n" + (string.IsNullOrWhiteSpace(outp) ? "(sin salida)" : outp);
        }
        catch (Exception e) { return "Error: " + e.Message; }
    });

    public void ScheduleReminder(string text, double seconds) => Dispatcher.Invoke(() =>
    {
        var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(Math.Max(1, seconds)) };
        t.Tick += (_, _) => { t.Stop(); Notify("⏰ Flubber", text); };
        t.Start();
    });

    public Task<(bool Ok, bool Always)> ConfirmAsync(string title, string detail) => Dispatcher.Invoke(() =>
    {
        var r = System.Windows.MessageBox.Show(detail, title, MessageBoxButton.YesNo, MessageBoxImage.Question);
        return Task.FromResult((r == MessageBoxResult.Yes, false));
    });
}
