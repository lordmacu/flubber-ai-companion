using System.Windows;
using System.Windows.Input;
using Input = System.Windows.Input;
using Flubber.Core;
using Flubber.Core.Agent;
using Controls = System.Windows.Controls;
using Media = System.Windows.Media;
using Effects = System.Windows.Media.Effects;
using WpfAlign = System.Windows.HorizontalAlignment;

namespace Flubber.App;

/// <summary>
/// Chat window with token-by-token streaming + conversation persistence.
/// Borderless + transparent + custom-painted to match the macOS chat overlay
/// (drawChat in main.swift): dark rounded panel, green border, monospaced bubbles.
/// </summary>
public sealed class ChatWindow : Window
{
    // Colors copied 1:1 from the macOS drawChat() so both platforms look identical.
    private static readonly Media.Color PanelBg     = Media.Color.FromRgb(0x29, 0x29, 0x29);   // white 0.16
    private static readonly Media.Color PanelBorder = Media.Color.FromRgb(0x5C, 0xD9, 0x8C);   // green accent
    private static readonly Media.Color HeaderName  = Media.Color.FromRgb(0x9E, 0xF5, 0xB8);   // bright green
    private static readonly Media.Color UserBubble  = Media.Color.FromRgb(0x33, 0x6B, 0xC7);   // blue 0.20,0.42,0.78
    private static readonly Media.Color BotBubble   = Media.Color.FromRgb(0x33, 0x8C, 0x61);   // green 0.20,0.55,0.38
    private static readonly Media.Color InputBg     = Media.Color.FromRgb(0xF2, 0xF2, 0xF2);   // white 0.95
    private static readonly Media.Color SendBlue    = Media.Color.FromRgb(0x4C, 0xA8, 0xFA);   // 0.30,0.66,0.98
    private static readonly Media.Brush BtnBg       = new Media.SolidColorBrush(Media.Color.FromArgb(0x1F, 0xFF, 0xFF, 0xFF)); // white 12%
    private static readonly Media.FontFamily Mono   = new("Consolas, Cascadia Mono, Courier New");

    private readonly Agent _agent;
    private readonly ConversationStore _store;
    private Conversation _conv;

    private readonly Controls.StackPanel _messages = new() { Margin = new Thickness(8, 6, 8, 6) };
    private readonly Controls.ScrollViewer _scroll;
    private readonly Controls.TextBox _input;
    private readonly Controls.Button _send;
    private readonly Controls.TextBlock _status = new() { Margin = new Thickness(10, 0, 10, 2), Foreground = new Media.SolidColorBrush(Media.Color.FromRgb(0xAA, 0xAA, 0xAA)), FontSize = 11 };
    private bool _busy;

    public ChatWindow(Agent agent)
    {
        _agent = agent;
        _store = ConversationStore.Load();
        _conv = _store.Conversations.Count > 0 ? _store.Conversations[^1] : Conversation.New();
        if (_store.Conversations.Count == 0) _store.Conversations.Add(_conv);

        // Borderless, transparent shell — no native chrome.
        Title = "Flubber";
        Width = 372; Height = 500;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Media.Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        // --- header: name + buttons (draggable) ---
        var name = new Controls.TextBlock
        {
            Text = $"{(string.IsNullOrEmpty(_conv.Title) ? "Flubber" : _conv.Title)} 💬",
            Foreground = new Media.SolidColorBrush(HeaderName),
            FontWeight = FontWeights.SemiBold, FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 0, 0),
        };
        var newBtn = HeaderButton("＋", () => NewConversation());
        var closeBtn = HeaderButton("✕", Close);
        var btnRow = new Controls.StackPanel { Orientation = Controls.Orientation.Horizontal, HorizontalAlignment = WpfAlign.Right };
        btnRow.Children.Add(newBtn);
        btnRow.Children.Add(closeBtn);

        var header = new Controls.DockPanel { Height = 28, Margin = new Thickness(2, 2, 2, 2), Background = Media.Brushes.Transparent };
        Controls.DockPanel.SetDock(btnRow, Controls.Dock.Right);
        header.Children.Add(btnRow);
        header.Children.Add(name);
        header.MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };
        _headerName = name;

        // separator under header
        var sep = new Controls.Border { Height = 1, Background = BtnBg, Margin = new Thickness(2, 0, 2, 0) };

        // --- messages ---
        _scroll = new Controls.ScrollViewer
        {
            VerticalScrollBarVisibility = Controls.ScrollBarVisibility.Auto,
            Content = _messages,
            Margin = new Thickness(0, 2, 0, 2),
        };

        // --- input + send ---
        _input = new Controls.TextBox
        {
            Margin = new Thickness(4, 4, 4, 4), MinHeight = 28, MaxHeight = 110,
            TextWrapping = TextWrapping.Wrap, AcceptsReturn = false,
            VerticalContentAlignment = VerticalAlignment.Center,
            Background = new Media.SolidColorBrush(InputBg),
            Foreground = Media.Brushes.Black, BorderThickness = new Thickness(0),
            Padding = new Thickness(7, 4, 7, 4), FontSize = 12,
        };
        _input.KeyDown += (_, e) => { if (e.Key == Key.Enter) { e.Handled = true; _ = SendAsync(); } };
        var inputBorder = new Controls.Border
        {
            CornerRadius = new CornerRadius(5), Background = new Media.SolidColorBrush(InputBg),
            Child = _input,
        };

        _send = new Controls.Button { Content = "➤", Width = 34, Foreground = Media.Brushes.White, Cursor = Input.Cursors.Hand };
        StyleSendButton(_send);
        _send.Click += (_, _) => _ = SendAsync();

        var inputRow = new Controls.DockPanel { Margin = new Thickness(6, 2, 6, 6) };
        Controls.DockPanel.SetDock(_send, Controls.Dock.Right);
        _send.Margin = new Thickness(4, 0, 0, 0);
        inputRow.Children.Add(_send);
        inputRow.Children.Add(inputBorder);

        var bottom = new Controls.StackPanel();
        bottom.Children.Add(_status);
        bottom.Children.Add(inputRow);

        // --- assemble panel ---
        var root = new Controls.DockPanel { Margin = new Thickness(6, 4, 6, 6) };
        Controls.DockPanel.SetDock(header, Controls.Dock.Top);
        Controls.DockPanel.SetDock(sep, Controls.Dock.Top);
        Controls.DockPanel.SetDock(bottom, Controls.Dock.Bottom);
        root.Children.Add(header);
        root.Children.Add(sep);
        root.Children.Add(bottom);
        root.Children.Add(_scroll);

        var panel = new Controls.Border
        {
            CornerRadius = new CornerRadius(8),
            Background = new Media.SolidColorBrush(PanelBg),
            BorderBrush = new Media.SolidColorBrush(PanelBorder),
            BorderThickness = new Thickness(2),
            Margin = new Thickness(10),   // room for the drop shadow
            Effect = new Effects.DropShadowEffect { BlurRadius = 16, ShadowDepth = 0, Opacity = 0.5, Color = Media.Colors.Black },
            Child = root,
        };
        Content = panel;

        foreach (var m in _conv.Messages)
        {
            AddBubble(m.Role, m.Content);
            if (!string.IsNullOrEmpty(m.ImagePath)) AddImage(m.ImagePath!);
        }
        _agent.SeedHistory(_conv.Messages.Select(m => (m.Role, m.Content)));   // LLM memory
        Loaded += (_, _) => _input.Focus();
    }

    private readonly Controls.TextBlock _headerName;

    /// <summary>Small translucent rounded header button (close / new), matching the macOS HUD buttons.</summary>
    private Controls.Button HeaderButton(string glyph, Action onClick)
    {
        var b = new Controls.Button
        {
            Content = glyph, Width = 22, Height = 22, Margin = new Thickness(4, 0, 0, 0),
            Foreground = Media.Brushes.White, FontSize = 12, Cursor = Input.Cursors.Hand,
            BorderThickness = new Thickness(0), Background = BtnBg,
        };
        // Strip the default WPF chrome and give it rounded corners.
        b.Template = RoundButtonTemplate(4);
        b.Click += (_, _) => onClick();
        return b;
    }

    private void StyleSendButton(Controls.Button b)
    {
        b.Background = new Media.SolidColorBrush(SendBlue);
        b.BorderThickness = new Thickness(0);
        b.FontSize = 13;
        b.Template = RoundButtonTemplate(6);
    }

    /// <summary>A minimal button template: a rounded Border that shows the content, no native chrome.</summary>
    private static System.Windows.Controls.ControlTemplate RoundButtonTemplate(double radius)
    {
        var t = new Controls.ControlTemplate(typeof(Controls.Button));
        var border = new FrameworkElementFactory(typeof(Controls.Border));
        border.SetValue(Controls.Border.CornerRadiusProperty, new CornerRadius(radius));
        border.SetBinding(Controls.Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var content = new FrameworkElementFactory(typeof(Controls.ContentPresenter));
        content.SetValue(Controls.ContentPresenter.HorizontalAlignmentProperty, WpfAlign.Center);
        content.SetValue(Controls.ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(content);
        t.VisualTree = border;
        return t;
    }

    /// <summary>Attaches a capture (draws it and persists it on the last user message).</summary>
    public void AttachCapture(string path)
    {
        AddImage(path);
        var lastUser = _conv.Messages.LastOrDefault(m => m.Role == "user");
        if (lastUser != null) { lastUser.ImagePath = path; _store.Save(); }
    }

    /// <summary>Draws the thumbnail of a capture (without persisting).</summary>
    private void AddImage(string path)
    {
        try
        {
            var bmp = new Media.Imaging.BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = Media.Imaging.BitmapCacheOption.OnLoad;
            bmp.UriSource = new Uri(path);
            bmp.EndInit();
            var img = new Controls.Image
            {
                Source = bmp, MaxWidth = 240, Margin = new Thickness(0, 4, 0, 4),
                HorizontalAlignment = WpfAlign.Left, Stretch = Media.Stretch.Uniform,
            };
            _messages.Children.Add(img);
            _scroll.ScrollToEnd();
        }
        catch { /* ignore */ }
    }

    private void NewConversation()
    {
        _conv = Conversation.New();
        _store.Conversations.Add(_conv);
        _store.Save();
        _messages.Children.Clear();
        _agent.Reset();
        _status.Text = "";
        _headerName.Text = $"{(string.IsNullOrEmpty(_conv.Title) ? "Flubber" : _conv.Title)} 💬";
        _input.Focus();
    }

    private Controls.TextBlock AddBubble(string role, string text)
    {
        var isUser = role == "user";
        var tb = new Controls.TextBlock
        {
            Text = text, TextWrapping = TextWrapping.Wrap,
            Foreground = Media.Brushes.White, FontFamily = Mono, FontSize = 12,
        };
        var border = new Controls.Border
        {
            Background = new Media.SolidColorBrush(isUser ? UserBubble : BotBubble),
            CornerRadius = new CornerRadius(5),
            Padding = new Thickness(8, 6, 8, 6),
            Margin = new Thickness(0, 3, 0, 3),
            MaxWidth = 280,
            HorizontalAlignment = isUser ? WpfAlign.Right : WpfAlign.Left,
            Child = tb,
        };
        _messages.Children.Add(border);
        _scroll.ScrollToEnd();
        return tb;
    }

    // ---- API for meeting listening (called from PetWindow, on the UI thread) ----

    /// <summary>Starts a NEW conversation with a given title (for each meeting/chat).</summary>
    public void StartConversation(string title)
    {
        _conv = Conversation.New();
        _conv.Title = title;
        _store.Conversations.Add(_conv);
        _store.Save();
        _messages.Children.Clear();
        _agent.Reset();
        _status.Text = "";
        _headerName.Text = $"{title} 💬";
    }

    /// <summary>Adds a message from the slime and persists it.</summary>
    public void AppendAssistant(string text)
    {
        AddBubble("assistant", text);
        _conv.Messages.Add(new Msg { Role = "assistant", Content = text });
        _store.Save();
    }

    /// <summary>Adds a clickable bubble that opens a file (the transcript) and persists it.</summary>
    public void AppendFileLink(string label, string filePath)
    {
        var tb = new Controls.TextBlock { Text = label, TextWrapping = TextWrapping.Wrap, Foreground = Media.Brushes.White, FontFamily = Mono, FontSize = 12, FontWeight = FontWeights.SemiBold };
        var border = new Controls.Border
        {
            Background = new Media.SolidColorBrush(BotBubble),
            BorderBrush = new Media.SolidColorBrush(PanelBorder),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(5),
            Padding = new Thickness(8, 6, 8, 6),
            Margin = new Thickness(0, 3, 0, 3),
            MaxWidth = 280,
            HorizontalAlignment = WpfAlign.Left,
            Cursor = Input.Cursors.Hand,
            Child = tb,
        };
        border.MouseLeftButtonUp += (_, _) =>
        {
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo { FileName = filePath, UseShellExecute = true }); }
            catch { }
        };
        _messages.Children.Add(border);
        _scroll.ScrollToEnd();
        _conv.Messages.Add(new Msg { Role = "assistant", Content = label, FilePath = filePath });
        _store.Save();
    }

    /// <summary>Creates an empty slime bubble to fill in via streaming.</summary>
    public Controls.TextBlock BeginStreamingAssistant() => AddBubble("assistant", "");

    /// <summary>Updates the text of the streaming bubble (without persisting yet).</summary>
    public void UpdateStreaming(Controls.TextBlock tb, string text) { tb.Text = text; _scroll.ScrollToEnd(); }

    /// <summary>Sets the final text of the streaming bubble and persists it.</summary>
    public void CommitStreaming(Controls.TextBlock tb, string finalText)
    {
        tb.Text = finalText;
        _conv.Messages.Add(new Msg { Role = "assistant", Content = finalText });
        _store.Save();
        _scroll.ScrollToEnd();
    }

    private async Task SendAsync()
    {
        if (_busy) return;
        var text = _input.Text.Trim();
        if (text.Length == 0) return;
        _busy = true; _send.IsEnabled = false;
        _input.Clear();

        AddBubble("user", text);
        _conv.Messages.Add(new Msg { Role = "user", Content = text });
        var assistant = AddBubble("assistant", "");
        var streamed = "";

        try
        {
            var reply = await _agent.RunAsync(text, null,
                onStep: s => Dispatcher.Invoke(() => _status.Text = s),
                onToken: t => Dispatcher.Invoke(() =>
                {
                    streamed += t;
                    assistant.Text = streamed;
                    _scroll.ScrollToEnd();
                }));
            assistant.Text = reply;                       // final text, already cleaned up
            _conv.Messages.Add(new Msg { Role = "assistant", Content = reply });
            _store.Save();
        }
        catch (Exception ex) { assistant.Text = "Error: " + ex.Message; }
        finally
        {
            _status.Text = "";
            _busy = false; _send.IsEnabled = true;
            _input.Focus();
        }
    }
}
