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
- [x] Real screen capture (GDI BitBlt — full screen or a specific app/window) feeding the AI vision tool.
- [x] Browser control via **Chrome DevTools Protocol** (`navegador_url` / `navegador_js`) — needs the browser started with `--remote-debugging-port=9222`.
- [x] AI-settings window (provider / key / model / test connection) + streaming chat window with persistence.
- [x] Package the `.exe` (win-x64, self-contained) + **Inno Setup installer** (install/repair/uninstall, shortcuts, optional autostart) — both built in CI.
- [x] Slime icon embedded in the `.exe`, installer and system tray.
- [x] Polish: hover HUD of care buttons + walk/wander, roll, fall and wall-slide physics (multi-monitor aware).
- [x] **API keys encrypted at rest with DPAPI** (`CurrentUser` scope) — replaces macOS Keychain; plaintext configs auto-migrate.
- [x] Streaming chat: persisted conversations, **LLM memory restored across restarts**, capture thumbnails, "＋ New conversation".

**Functional parity with macOS reached.** The platform-specific tools are abstracted behind
`Agent/IPlatformBridge.cs`, implemented by the WPF app (`PetWindow.xaml.cs`). Both projects compile in
`.github/workflows/windows-build.yml`, which also publishes the Windows `.exe`.

## Download (Windows)

The Windows build is produced on every push that touches `windows/`. Grab `Flubber-windows` (a zip with the
self-contained `Flubber.exe`) from the latest run's **Artifacts**:
<https://github.com/lordmacu/flubber-ai-companion/actions/workflows/windows-build.yml>

Requires Windows 10 (2004+) / 11. First run: Windows SmartScreen may warn (unsigned) — "More info" → "Run anyway".

## Build

```bash
dotnet build Flubber.Core/Flubber.Core.csproj -c Release   # portable core (any OS)
```

CI builds the core on every push that touches `windows/` (see `.github/workflows/windows-build.yml`).
