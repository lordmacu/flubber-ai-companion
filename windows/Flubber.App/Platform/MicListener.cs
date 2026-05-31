using System.Speech.AudioFormat;
using System.Speech.Recognition;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using Flubber.Core.Util;

namespace Flubber.App.Platform;

/// <summary>
/// Escucha el MICRÓFONO (tu voz) con NAudio (WasapiCapture del dispositivo de entrada
/// por defecto) y lo transcribe ON-DEVICE con System.Speech. Mismo stack que
/// <see cref="MeetingListener"/> (audio del sistema), pero la fuente es el micrófono.
/// Es una fuente INDEPENDIENTE: su propio icono 🎤, separado del 👂 del sistema.
/// </summary>
public sealed class MicListener
{
    public static readonly MicListener Shared = new();

    public bool IsListening { get; private set; }

    private readonly object _lock = new();
    private string _transcript = "";
    private string _partial = "";

    public string Transcript { get { lock (_lock) return _transcript; } }
    public string FullText { get { lock (_lock) return (_transcript + " " + _partial).Trim(); } }

    private WasapiCapture? _capture;
    private BufferedWaveProvider? _buffered;
    private MediaFoundationResampler? _resampler;
    private SpeechStreamer? _speechStream;
    private SpeechRecognitionEngine? _engine;
    private Thread? _pump;
    private volatile bool _running;

    public bool Start(out string? error)
    {
        error = null;
        if (IsListening) return true;
        try
        {
            Log.Write("🎤 mic.start — abriendo WasapiCapture (micrófono)…");
            _capture = new WasapiCapture();   // dispositivo de entrada por defecto (mic)
            _buffered = new BufferedWaveProvider(_capture.WaveFormat)
            {
                ReadFully = false,
                BufferDuration = TimeSpan.FromSeconds(20),
                DiscardOnBufferOverflow = true,
            };
            _capture.DataAvailable += OnAudio;

            NAudio.MediaFoundation.MediaFoundationApi.Startup();
            var target = new WaveFormat(16000, 16, 1);
            _resampler = new MediaFoundationResampler(_buffered, target) { ResamplerQuality = 60 };
            _speechStream = new SpeechStreamer(1 << 20);

            _engine = new SpeechRecognitionEngine();
            _engine.LoadGrammar(new DictationGrammar());
            _engine.SetInputToAudioStream(_speechStream,
                new SpeechAudioFormatInfo(16000, AudioBitsPerSample.Sixteen, AudioChannel.Mono));
            _engine.SpeechRecognized += OnRecognized;
            _engine.SpeechHypothesized += OnHypothesized;

            lock (_lock) { _transcript = ""; _partial = ""; }
            _running = true;
            _capture.StartRecording();
            _pump = new Thread(PumpLoop) { IsBackground = true, Name = "FlubberMicPump" };
            _pump.Start();
            _engine.RecognizeAsync(RecognizeMode.Multiple);
            IsListening = true;
            Log.Write($"🎤 mic capturando ✅ origen={_capture.WaveFormat}");
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            Log.Write("🎤 ERROR start: " + ex.Message);
            Stop();
            return false;
        }
    }

    private void OnAudio(object? sender, WaveInEventArgs e) => _buffered?.AddSamples(e.Buffer, 0, e.BytesRecorded);

    private void PumpLoop()
    {
        var buf = new byte[3200];
        while (_running)
        {
            int n = 0;
            try { n = _resampler!.Read(buf, 0, buf.Length); } catch { n = 0; }
            if (n > 0) { try { _speechStream!.Write(buf, 0, n); } catch { } }
            else Thread.Sleep(15);
        }
    }

    private void OnHypothesized(object? sender, SpeechHypothesizedEventArgs e) { lock (_lock) _partial = e.Result.Text; }

    private void OnRecognized(object? sender, SpeechRecognizedEventArgs e)
    {
        var txt = (e.Result?.Text ?? "").Trim();
        if (txt.Length == 0) return;
        lock (_lock) { _transcript += (_transcript.Length > 0 ? " " : "") + txt; _partial = ""; }
        Log.Write("🎤 segmento: " + (txt.Length > 60 ? txt[..60] : txt));
    }

    public void Stop()
    {
        if (!_running && _engine == null && _capture == null) { IsListening = false; return; }
        Log.Write($"🎤 mic.stop — transcript={FullText.Length} chars");
        IsListening = false;
        _running = false;
        try { _engine?.RecognizeAsyncCancel(); } catch { }
        try { if (_capture != null) _capture.DataAvailable -= OnAudio; } catch { }
        try { _capture?.StopRecording(); } catch { }
        try { _pump?.Join(400); } catch { }
        try { _speechStream?.Close(); } catch { }
        try { _engine?.Dispose(); } catch { }
        try { _resampler?.Dispose(); } catch { }
        try { _capture?.Dispose(); } catch { }
        _engine = null; _resampler = null; _capture = null; _buffered = null; _speechStream = null; _pump = null;
    }
}
