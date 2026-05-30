using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using SkiaSharp.Views.Desktop;
using Flubber.Core;
using Flubber.Core.AI;
using Flubber.Core.Agent;
using Flubber.Core.Util;
using Flubber.App.Interop;
using Flubber.App.Platform;
using Flubber.App.Rendering;
using Controls = System.Windows.Controls;
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

    // movimiento / física
    private double _targetX;
    private bool _walking;
    private double _walkSpeed = 5;
    private bool _rolling;
    private bool _falling;
    private bool _dragging;
    private double _vy;
    private int _wallSide;           // -1 izquierda, +1 derecha, 0 ninguno
    private int _nextWander = 240;
    private long _lastDownTick;      // para detectar doble clic de forma fiable

    // escucha de reunión
    private bool _listening;
    private DispatcherTimer? _meetingRollTimer;
    private int _meetingSummarizedLen;
    private readonly List<string> _meetingRollingSummaries = new();
    private DateTime _meetingStartedAt;
    private bool _meetingConvStarted;          // la conversación dedicada ya se creó esta sesión
    private const double MeetingThresholdSec = 60;   // ≥60s = reunión; si no, charla

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
        BuildHud();
        MouseEnter += (_, _) => { if (!_stats.IsDead && _stats.Stage != LifeStage.Egg) Hud.Visibility = Visibility.Visible; };
        MouseLeave += (_, _) => Hud.Visibility = Visibility.Collapsed;
        _timer.Start();
    }

    /// <summary>Botones de cuidado que aparecen al pasar el mouse (HUD).</summary>
    private void BuildHud()
    {
        Hud.Children.Clear();
        Hud.Children.Add(HudButton("🍖", () => { _stats.Feed(Food.Meat); SetTransient(SlimeState.Happy, 24); }));
        Hud.Children.Add(HudButton("🎮", DoPlay));
        Hud.Children.Add(HudButton("🛁", () => _stats.Clean()));
        Hud.Children.Add(HudButton("💊", () => _stats.Medicine()));
    }

    private Controls.Button HudButton(string emoji, Action onClick)
    {
        var b = new Controls.Button
        {
            Content = emoji, Width = 30, Height = 30, Margin = new Thickness(2, 0, 2, 0),
            FontSize = 14, Padding = new Thickness(0), Cursor = System.Windows.Input.Cursors.Hand,
        };
        b.Click += (_, _) => onClick();
        return b;
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

        UpdateMovement();
        UpdateView();
        Surface.InvalidateVisual();
    }

    /// <summary>Límites de roaming del MONITOR actual (área de trabajo), en DIP. Soporta multi-monitor y DPI mixto.</summary>
    private (double Left, double Right, double Ground) Bounds()
    {
        try
        {
            var src = PresentationSource.FromVisual(this);
            if (src?.CompositionTarget != null)
            {
                var wa = Forms.Screen.FromHandle(_hwnd).WorkingArea;   // px del monitor bajo la ventana
                var t = src.CompositionTarget.TransformFromDevice;     // device px -> DIP
                var tl = t.Transform(new System.Windows.Point(wa.Left, wa.Top));
                var br = t.Transform(new System.Windows.Point(wa.Right, wa.Bottom));
                var left = tl.X;
                var right = Math.Max(left, br.X - Width);
                return (left, right, br.Y - Height);
            }
        }
        catch { }
        var p = SystemParameters.WorkArea;   // respaldo: monitor primario
        return (p.Left, Math.Max(p.Left, p.Right - Width), p.Bottom - Height);
    }

    /// <summary>Mueve la ventana: pasear/rodar, caída con gravedad y escurrirse por la pared.</summary>
    private void UpdateMovement()
    {
        if (_dragging) return;

        var (leftBound, rightBound, ground) = Bounds();

        if (_stats.IsDead || _stats.Stage == LifeStage.Egg || _stats.IsAsleep)
        { _walking = _rolling = _falling = false; _wallSide = 0; return; }

        // 1) caída en el aire (tras soltar el arrastre)
        if (_falling)
        {
            _vy += 1.4; Top += _vy;
            if (Top >= ground) { Top = ground; _falling = false; _vy = 0; }
            return;
        }

        // 2) escurrirse por la pared hasta abajo
        if (_wallSide != 0)
        {
            if (Top < ground) Top = Math.Min(ground, Top + 3.0);
            else _wallSide = 0;
            return;
        }

        // 3) paseo / rodar
        if (_walking || _rolling)
        {
            var dir = Math.Sign(_targetX - Left);
            if (dir == 0) { _walking = _rolling = false; return; }
            Left += dir * (_rolling ? _walkSpeed * 1.8 : _walkSpeed);
            _facing = dir >= 0 ? 1 : -1;
            if (Math.Abs(_targetX - Left) <= _walkSpeed * 1.8) { Left = Math.Clamp(_targetX, leftBound, rightBound); _walking = _rolling = false; }
            return;
        }

        // 4) deambular cada cierto tiempo (solo en reposo; quieta si escucha)
        if (_transient == null && !_listening && _tick >= _nextWander && rightBound > leftBound)
        {
            _nextWander = _tick + _rng.Next(300, 700);
            _targetX = leftBound + _rng.NextDouble() * (rightBound - leftBound);
            _walking = true;
        }
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
            else if (_dragging) _view.State = SlimeState.Dragging;
            else if (_stats.IsAsleep) _view.State = SlimeState.Sleeping;
            else if (_falling) _view.State = SlimeState.Falling;
            else if (_wallSide != 0) _view.State = SlimeState.StuckWall;
            else if (_rolling) _view.State = SlimeState.Rolling;
            else if (_walking) _view.State = SlimeState.Walking;
            else _view.State = SlimeState.Idle;
        }

        if (_view.State == SlimeState.StuckWall) { _view.ScaleY = 1.30; _view.ScaleX = 0.85; }   // estirado contra la pared

        _view.Listening = _listening;
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
            // el facing solo lo controla el cursor cuando NO se está moviendo
            if (!_walking && !_rolling && !_falling && _wallSide == 0)
            {
                if (cxp < centerX - 20) _facing = -1; else if (cxp > centerX + 20) _facing = 1;
            }
        }
        catch { }
    }

    private void OnPaint(object? sender, SKPaintSurfaceEventArgs e) =>
        _renderer.Draw(e.Surface.Canvas, e.Info.Width, e.Info.Height, _view);

    // ---------------------------------------------------------------- input
    private void OnLeftDown(object sender, MouseButtonEventArgs e)
    {
        // doble clic por tiempo (ClickCount no es fiable porque DragMove abre un loop modal)
        var now = Environment.TickCount64;
        if (now - _lastDownTick < 300) { _lastDownTick = 0; DoPlay(); return; }
        _lastDownTick = now;

        _dragging = true;
        try { DragMove(); } catch { }
        _dragging = false;

        // al soltar: clamp dentro de la pantalla y decidir física
        var (leftBound, rightBound, ground) = Bounds();
        Left = Math.Clamp(Left, leftBound, rightBound);
        _walking = _rolling = false;
        if (Left <= leftBound + 2) _wallSide = -1;
        else if (Left >= rightBound - 2) _wallSide = +1;
        else if (Top < ground - 2) { _falling = true; _vy = 0; }
    }

    private void StartWalk(bool roll = false)
    {
        var (leftBound, rightBound, _) = Bounds();
        if (rightBound <= leftBound) return;
        _targetX = leftBound + _rng.NextDouble() * (rightBound - leftBound);
        _walking = !roll; _rolling = roll; _wallSide = 0; _falling = false;
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
        m.Items.Add(MeetingListener.Shared.IsListening
            ? Loc.T("Dejar de escuchar la reunión ⏹️", "Stop listening to meeting ⏹️")
            : Loc.T("Escuchar reunión 👂", "Listen to meeting 👂"), null, (_, _) => ToggleListen());
        m.Items.Add(Loc.T("Configurar IA… ⚙️", "AI settings… ⚙️"), null, (_, _) => OpenSettings());
        m.Items.Add(Loc.T("¡Pasea! 🚶", "Walk! 🚶"), null, (_, _) => StartWalk());
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
            _chat?.Close();   // el chat abierto tenía el backend viejo; al reabrir usa el nuevo
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
        try { MeetingListener.Shared.Stop(); } catch { }
        try { _stats.Save(); _tray.Visible = false; _tray.Dispose(); } catch { }
        System.Windows.Application.Current.Shutdown();
    }

    // ---------------------------------------------------------------- chat
    private ChatWindow? _chat;

    private void OpenChat()
    {
        if (!_cfg.IsConfigured)
        {
            Notify("Flubber", Loc.T("Primero configura la IA.", "Set up the AI first."));
            OpenSettings();
            return;
        }
        if (_chat == null)
        {
            _chat = new ChatWindow(_agent);
            _chat.Closed += (_, _) => _chat = null;
            _chat.Show();
        }
        _chat.Activate();
    }

    /// <summary>Abre el chat aunque no haya IA (para mostrar la transcripción de la reunión).</summary>
    private void EnsureChatOpen()
    {
        if (_chat == null)
        {
            _chat = new ChatWindow(_agent);
            _chat.Closed += (_, _) => _chat = null;
            _chat.Show();
        }
        _chat.Activate();
    }

    /// <summary>Crea (una sola vez por sesión) la conversación dedicada, con título según
    /// sea reunión (🎧) o charla (💬). Garantiza que cada escucha sea una conversación nueva.</summary>
    private void EnsureMeetingConversation(bool isMeeting)
    {
        if (_meetingConvStarted) return;
        EnsureChatOpen();
        var stamp = DateTime.Now.ToString("HH:mm");
        var title = isMeeting ? Loc.T($"🎧 Reunión {stamp}", $"🎧 Meeting {stamp}")
                              : Loc.T($"💬 Charla {stamp}", $"💬 Talk {stamp}");
        _chat?.StartConversation(title);
        _meetingConvStarted = true;
    }

    // ================================================================ escucha de reunión
    private void ToggleListen()
    {
        if (MeetingListener.Shared.IsListening) StopMeeting();
        else StartMeeting();
    }

    private void StartMeeting()
    {
        if (!MeetingListener.Shared.Start(out var err))
        {
            Notify("Flubber", err ?? Loc.T("No pude escuchar.", "Couldn't listen."));
            return;
        }
        _listening = true;
        _meetingSummarizedLen = 0;
        _meetingRollingSummaries.Clear();
        _meetingStartedAt = DateTime.UtcNow;
        _meetingConvStarted = false;            // cada escucha es una sesión NUEVA
        _meetingRollTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(240) };
        _meetingRollTimer.Tick += (_, _) => _ = RollMeetingSummaryAsync();
        _meetingRollTimer.Start();
        Notify("Flubber", Loc.T("Escuchando… 🎧", "Listening… 🎧"));
        _tray.ContextMenuStrip = BuildMenu();
    }

    private void StopMeeting()
    {
        MeetingListener.Shared.Stop();
        _listening = false;
        _meetingRollTimer?.Stop(); _meetingRollTimer = null;
        _tray.ContextMenuStrip = BuildMenu();
        Notify("Flubber", Loc.T("Listo, déjame resumir lo que escuché… 📝", "Done, let me summarize what I heard… 📝"));
        // espera a que el último segmento se vuelque y finaliza
        var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(700) };
        t.Tick += async (_, _) => { t.Stop(); await FinishMeetingAsync(); };
        t.Start();
    }

    /// <summary>Mini-resumen del trozo NUEVO de transcript (resumen rodante por lotes).</summary>
    private async Task RollMeetingSummaryAsync()
    {
        var full = MeetingListener.Shared.Transcript;
        var start = Math.Min(_meetingSummarizedLen, full.Length);
        var newText = full.Substring(start).Trim();
        if (newText.Length < 40 || !_cfg.IsConfigured) return;
        _meetingSummarizedLen = full.Length;
        var sys = Loc.T("Resume en 1-2 frases muy breves lo NUEVO de esta reunión. Solo el contenido esencial, sin preámbulos. Español.",
                        "Summarize in 1-2 very short sentences the NEW part of this meeting. Only essential content, no preamble. English.");
        var mini = (await _client.ChatAsync(sys, Array.Empty<(string, string)>(), newText, 220).ConfigureAwait(false) ?? "").Trim();
        if (mini.Length == 0) return;
        Log.Write("📝 resumen parcial: " + (mini.Length > 60 ? mini[..60] : mini));
        Dispatcher.Invoke(() =>
        {
            _meetingRollingSummaries.Add(mini);
            EnsureMeetingConversation(isMeeting: true);   // a estas alturas (>4min) ya es reunión
            _chat?.AppendAssistant("🎧 " + mini);
            Notify("Flubber", Loc.T("🎧 anoté algo de la reunión…", "🎧 jotted down something…"));
        });
    }

    /// <summary>Al parar: síntesis final en el chat (streaming) + link a la transcripción.
    /// Se invoca desde un DispatcherTimer → corre en el hilo UI.</summary>
    private async Task FinishMeetingAsync()
    {
        await RollMeetingSummaryAsync();   // cierra el último trozo pendiente

        var transcript = MeetingListener.Shared.FullText.Trim();
        var filePath = SaveTranscriptFile(transcript);
        var elapsed = (DateTime.UtcNow - _meetingStartedAt).TotalSeconds;
        var isMeeting = elapsed >= MeetingThresholdSec;     // ≥1 min = reunión; si no, charla
        Log.Write($"📝 finalize — {(int)elapsed}s, {(isMeeting ? "reunión" : "charla")}, transcript={transcript.Length} chars, partials={_meetingRollingSummaries.Count}");

        EnsureMeetingConversation(isMeeting);
        if (transcript.Length == 0)
        {
            _chat?.AppendAssistant(Loc.T("No escuché nada claro 👂", "Didn't catch anything clear 👂"));
            return;
        }
        // Sin IA: muestra la transcripción en crudo.
        if (!_cfg.IsConfigured)
        {
            _chat?.AppendAssistant(Loc.T("🎧 Esto fue lo que escuché (sin IA para resumir):\n\n",
                                         "🎧 Here's what I heard (no AI to summarize):\n\n") + transcript);
            if (filePath != null) _chat?.AppendFileLink(Loc.T("📄 Ver transcripción completa", "📄 View full transcript"), filePath);
            return;
        }

        var basis = _meetingRollingSummaries.Count > 0
            ? string.Join("\n", _meetingRollingSummaries.Select(s => "- " + s))
            : transcript;
        // Prompt distinto según fue reunión formal o solo una charla.
        var sys = isMeeting
            ? Loc.T(
                $"Eres {_stats.DisplayName}, una mascota que escuchó una reunión. Cuenta en PRIMERA PERSONA, tierno pero claro, lo que escuchaste. Estructura: 1) resumen breve, 2) puntos clave, 3) tareas/acuerdos si los hay. Solo español.",
                $"You are {_stats.DisplayName}, a pet that listened to a meeting. Tell in FIRST PERSON, cute but clear, what you heard. Structure: 1) short summary, 2) key points, 3) action items if any. English only.")
            : Loc.T(
                $"Eres {_stats.DisplayName}, una mascota que escuchó una breve conversación (NO una reunión formal). Cuenta en PRIMERA PERSONA, tierno y breve, de qué se habló. No uses secciones de tareas salvo que claramente las haya; solo un resumen natural. Solo español.",
                $"You are {_stats.DisplayName}, a pet that overheard a short conversation (NOT a formal meeting). Tell in FIRST PERSON, cute and brief, what was talked about. Don't use action-item sections unless clearly present; just a natural summary. English only.");
        var user = (isMeeting
                ? Loc.T("Esto es lo que escuché en la reunión (puede tener errores):\n\n",
                        "Here's what I heard in the meeting (may have errors):\n\n")
                : Loc.T("Esto es lo que escuché en la conversación (puede tener errores):\n\n",
                        "Here's what I heard in the conversation (may have errors):\n\n")) + basis;
        var msgs = new List<AIMessage> { new("system", sys), new("user", user) };

        var bubble = _chat?.BeginStreamingAssistant();
        var streamed = "";
        var result = await _client.CompleteStreamAsync(msgs, null, 1200, delta =>
        {
            streamed += delta;
            Dispatcher.Invoke(() => { if (bubble != null) _chat?.UpdateStreaming(bubble, streamed); });
        });

        var final = (result?.Content ?? streamed).Trim();
        if (final.Length == 0) final = Loc.T("No pude resumir lo que escuché 😅", "Couldn't summarize what I heard 😅");
        if (bubble != null) _chat?.CommitStreaming(bubble, final);
        else _chat?.AppendAssistant(final);
        if (filePath != null) _chat?.AppendFileLink(Loc.T("📄 Ver transcripción completa", "📄 View full transcript"), filePath);
    }

    private static string? SaveTranscriptFile(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        try
        {
            var dir = Flubber.Core.Platform.Paths.SubDir("transcripts");
            var path = System.IO.Path.Combine(dir, $"reunion-{DateTime.Now:yyyy-MM-dd_HH-mm}.txt");
            var header = Loc.T("Transcripción de reunión — ", "Meeting transcript — ") + DateTime.Now.ToString("g") + "\n\n";
            System.IO.File.WriteAllText(path, header + text);
            return path;
        }
        catch (Exception e) { Log.Write("📝 no pude guardar la transcripción: " + e.Message); return null; }
    }

    // ================================================================ IPlatformBridge
    public PetStats Stats => _stats;

    public Task<(string? Base64, string? Path)> CaptureScreenAsync(string? appHint)
        => Flubber.App.Platform.ScreenCapture.CaptureAsync(appHint);

    public void AttachShot(string path) => Dispatcher.Invoke(() => _chat?.AttachCapture(path));

    public string ControlSlime(string accion, string tema) => Dispatcher.Invoke(() =>
    {
        accion = (accion ?? "").ToLowerInvariant();
        tema = (tema ?? "").ToLowerInvariant();
        switch (accion)
        {
            case "bailar": SetTransient(SlimeState.Dancing, 120); return "¡A bailar! 💃";
            case "rodar": StartWalk(roll: true); return "¡Rodando! 🤸";
            case "pasear": StartWalk(); return "Me voy a pasear 🚶";
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
