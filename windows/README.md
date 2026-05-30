# Flubber for Windows (C# / .NET 8 port)

Work-in-progress port of Flubber from Swift/AppKit (macOS) to **C# / .NET 8** for Windows.

## Layout

```
windows/
  Flubber.Core/        # portable core (no UI): Tamagotchi, AI backends, agent, tools
    Tamagotchi.cs      # PetStats model (real-time needs, life cycle, persistence)
    Localization.cs    # ES/EN
    Personality.cs     # prompts + canned phrases (bilingual)
    Conversations.cs   # conversation store
    AI/                # AIConfig, types, Anthropic + OpenAI backends (SSE streaming)
    Agent/             # function-calling loop + tool catalog + IPlatformBridge
    Tools/             # WebTools (DuckDuckGo / fetch / weather)
    Platform/Paths.cs  # %APPDATA%\SlimePet
  Flubber.App/         # (coming) WPF app: transparent window, Skia render, tray, capture
```

## Status

- [x] Portable core: model, AI providers (MiniMax/Claude/ChatGPT/DeepSeek) with real SSE streaming, agent loop, web tools. **Builds in CI (ubuntu).**
- [x] WPF app: transparent topmost pet window + pixel-art render (SkiaSharp), system tray + care menu, animation loop, look-at-cursor, drag-to-move, minimal chat. **Builds in CI (windows).**
- [x] Capture-stealth: `SetWindowDisplayAffinity` / `WDA_EXCLUDEFROMCAPTURE` (on by default, toggle in tray).
- [x] Platform tools wired via `Agent/IPlatformBridge.cs`: open, run command, reminders, confirmations, control-slime, AI skin.
- [ ] Real screen capture (`Windows.Graphics.Capture`) — currently stubbed.
- [ ] Browser control (Chrome DevTools Protocol) — currently stubbed.
- [ ] Full pixel chat panel + HUD + AI-settings window (parity with macOS).
- [ ] Extra animations (walk across screen, roll, wall-slide) and toast polish.
- [ ] Package the `.exe` as a CI artifact / release.

The platform-specific tools are abstracted behind `Agent/IPlatformBridge.cs`, implemented by the WPF app
(`PetWindow.xaml.cs`). Both projects compile in `.github/workflows/windows-build.yml`.

## Build

```bash
dotnet build Flubber.Core/Flubber.Core.csproj -c Release   # portable core (any OS)
```

CI builds the core on every push that touches `windows/` (see `.github/workflows/windows-build.yml`).
