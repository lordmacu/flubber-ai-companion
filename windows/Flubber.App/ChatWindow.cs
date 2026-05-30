using System.Windows;
using Flubber.Core;
using Flubber.Core.Agent;
using Controls = System.Windows.Controls;
using Media = System.Windows.Media;
using WpfAlign = System.Windows.HorizontalAlignment;

namespace Flubber.App;

/// <summary>Ventana de chat con streaming token a token + persistencia de la conversación.</summary>
public sealed class ChatWindow : Window
{
    private readonly Agent _agent;
    private readonly ConversationStore _store;
    private Conversation _conv;

    private readonly Controls.StackPanel _messages = new() { Margin = new Thickness(10) };
    private readonly Controls.ScrollViewer _scroll;
    private readonly Controls.TextBox _input;
    private readonly Controls.Button _send;
    private readonly Controls.TextBlock _status = new() { Margin = new Thickness(12, 0, 12, 4), Foreground = Media.Brushes.Gray, FontSize = 11 };
    private bool _busy;

    public ChatWindow(Agent agent)
    {
        _agent = agent;
        _store = ConversationStore.Load();
        _conv = _store.Conversations.Count > 0 ? _store.Conversations[^1] : Conversation.New();
        if (_store.Conversations.Count == 0) _store.Conversations.Add(_conv);

        Title = "Flubber 💬";
        Width = 420; Height = 560;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = new Media.SolidColorBrush(Media.Color.FromRgb(0xF7, 0xF7, 0xF8));

        _scroll = new Controls.ScrollViewer
        {
            VerticalScrollBarVisibility = Controls.ScrollBarVisibility.Auto,
            Content = _messages,
        };

        _input = new Controls.TextBox
        {
            Margin = new Thickness(10, 4, 6, 10), MinHeight = 30, MaxHeight = 90,
            TextWrapping = TextWrapping.Wrap, AcceptsReturn = false, VerticalContentAlignment = VerticalAlignment.Center,
        };
        _input.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) { e.Handled = true; _ = SendAsync(); } };

        _send = new Controls.Button { Content = "➤", Width = 44, Margin = new Thickness(0, 4, 10, 10) };
        _send.Click += (_, _) => _ = SendAsync();

        var inputRow = new Controls.DockPanel();
        Controls.DockPanel.SetDock(_send, Controls.Dock.Right);
        inputRow.Children.Add(_send);
        inputRow.Children.Add(_input);

        var bottom = new Controls.StackPanel();
        bottom.Children.Add(_status);
        bottom.Children.Add(inputRow);

        var topBar = new Controls.DockPanel { Margin = new Thickness(8, 6, 8, 0) };
        var newBtn = new Controls.Button { Content = Loc.T("＋ Nueva", "＋ New"), Padding = new Thickness(8, 2, 8, 2) };
        newBtn.Click += (_, _) => NewConversation();
        Controls.DockPanel.SetDock(newBtn, Controls.Dock.Left);
        topBar.Children.Add(newBtn);

        var root = new Controls.DockPanel();
        Controls.DockPanel.SetDock(bottom, Controls.Dock.Bottom);
        Controls.DockPanel.SetDock(topBar, Controls.Dock.Top);
        root.Children.Add(bottom);
        root.Children.Add(topBar);
        root.Children.Add(_scroll);
        Content = root;

        foreach (var m in _conv.Messages)
        {
            AddBubble(m.Role, m.Content);
            if (!string.IsNullOrEmpty(m.ImagePath)) AddImage(m.ImagePath!);
        }
        _agent.SeedHistory(_conv.Messages.Select(m => (m.Role, m.Content)));   // memoria del LLM
        Loaded += (_, _) => _input.Focus();
    }

    /// <summary>Adjunta una captura (la dibuja y la persiste en el último mensaje de usuario).</summary>
    public void AttachCapture(string path)
    {
        AddImage(path);
        var lastUser = _conv.Messages.LastOrDefault(m => m.Role == "user");
        if (lastUser != null) { lastUser.ImagePath = path; _store.Save(); }
    }

    /// <summary>Dibuja el thumbnail de una captura (sin persistir).</summary>
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
        _input.Focus();
    }

    private Controls.TextBlock AddBubble(string role, string text)
    {
        var isUser = role == "user";
        var tb = new Controls.TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = isUser ? Media.Brushes.White : Media.Brushes.Black };
        var border = new Controls.Border
        {
            Background = isUser ? new Media.SolidColorBrush(Media.Color.FromRgb(0x2E, 0x7D, 0xF6)) : new Media.SolidColorBrush(Media.Color.FromRgb(0xEA, 0xEA, 0xEC)),
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(10, 7, 10, 7),
            Margin = new Thickness(0, 4, 0, 4),
            MaxWidth = 320,
            HorizontalAlignment = isUser ? WpfAlign.Right : WpfAlign.Left,
            Child = tb,
        };
        _messages.Children.Add(border);
        _scroll.ScrollToEnd();
        return tb;
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
            assistant.Text = reply;                       // texto final ya limpio
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
