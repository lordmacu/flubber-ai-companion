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

- [x] Portable core: model, AI providers (MiniMax/Claude/ChatGPT/DeepSeek) with real SSE streaming, agent loop, web tools.
- [ ] WPF app: transparent click-through pet window + pixel-art render (SkiaSharp).
- [ ] System tray + menu, animation loop, chat panel, HUD.
- [ ] Windows-native tools: screen capture (Windows.Graphics.Capture), capture-stealth
      (`SetWindowDisplayAffinity` / `WDA_EXCLUDEFROMCAPTURE`), browser control (Chrome DevTools Protocol),
      open/run, toast notifications.

The platform-specific tools are abstracted behind `Agent/IPlatformBridge.cs`, implemented by the WPF app.

## Build

```bash
dotnet build Flubber.Core/Flubber.Core.csproj -c Release   # portable core (any OS)
```

CI builds the core on every push that touches `windows/` (see `.github/workflows/windows-build.yml`).
