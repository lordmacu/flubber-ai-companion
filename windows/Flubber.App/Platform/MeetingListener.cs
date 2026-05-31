using System.Speech.AudioFormat;
using System.Speech.Recognition;
using NAudio.Wave;
using Flubber.Core;
using Flubber.Core.Util;

namespace Flubber.App.Platform;

/// <summary>
/// Listens to the SYSTEM AUDIO (what plays in a Meet/Teams/Zoom meeting)
/// with WASAPI loopback (NAudio) and transcribes it ON-DEVICE with System.Speech.
/// Accumulates a transcript that the agent can summarize. Equivalent to MeetingListener.swift.
///
/// Note: as on macOS, it picks up what comes out of the speakers (the others), NOT your
/// microphone. System.Speech transcription is free but of medium quality.
/// </summary>
public sealed class MeetingListener
{
    public static readonly MeetingListener Shared = new();

    public bool IsListening { get; private set; }

    private readonly object _lock = new();
    private string _transcript = "";
    private string _partial = "";

    /// <summary>Only the final segments (stable text).</summary>
    public string Transcript { get { lock (_lock) return _transcript; } }
    /// <summary>Final + whatever is being recognized right now.</summary>
    public string FullText { get { lock (_lock) return (_transcript + " " + _partial).Trim(); } }

    /// <summary>Fires on each new final segment (text).</summary>
    public event Action<string>? SegmentRecognized;

    private WasapiLoopbackCapture? _capture;
    private BufferedWaveProvider? _buffered;
    private MediaFoundationResampler? _resampler;
    private SpeechStreamer? _speechStream;
    private SpeechRecognitionEngine? _engine;
    private Thread? _pump;
    private volatile bool _running;
    private int _audioBuffers;

    public bool Start(out string? error)
    {
        error = null;
        if (IsListening) return true;
        try
        {
            Log.Write("🎧 listen.start — opening WASAPI loopback…");
            _capture = new WasapiLoopbackCapture();   // default output device
            _buffered = new BufferedWaveProvider(_capture.WaveFormat)
            {
                ReadFully = false,
                BufferDuration = TimeSpan.FromSeconds(20),
                DiscardOnBufferOverflow = true,
            };
            _capture.DataAvailable += OnAudio;

            NAudio.MediaFoundation.MediaFoundationApi.Startup();
            var target = new WaveFormat(16000, 16, 1);                 // System.Speech: 16kHz/16-bit/mono
            _resampler = new MediaFoundationResampler(_buffered, target) { ResamplerQuality = 60 };

            _speechStream = new SpeechStreamer(1 << 20);               // 1 MB buffer

            _engine = new SpeechRecognitionEngine();
            _engine.LoadGrammar(new DictationGrammar());              // free dictation
            _engine.SetInputToAudioStream(_speechStream,
                new SpeechAudioFormatInfo(16000, AudioBitsPerSample.Sixteen, AudioChannel.Mono));
            _engine.SpeechRecognized += OnRecognized;
            _engine.SpeechHypothesized += OnHypothesized;

            lock (_lock) { _transcript = ""; _partial = ""; }
            _audioBuffers = 0;
            _running = true;
            _capture.StartRecording();
            _pump = new Thread(PumpLoop) { IsBackground = true, Name = "FlubberAudioPump" };
            _pump.Start();
            _engine.RecognizeAsync(RecognizeMode.Multiple);
            IsListening = true;
            Log.Write($"🎧 capturing audio ✅ source={_capture.WaveFormat}");
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            Log.Write("🎧 ERROR start: " + ex.Message);
            Stop();
            return false;
        }
    }

    private void OnAudio(object? sender, WaveInEventArgs e)
    {
        _buffered?.AddSamples(e.Buffer, 0, e.BytesRecorded);
        if (++_audioBuffers == 1) Log.Write("🎧 first audio buffer received ✅");
    }

    // Pumps resampled audio (16kHz mono) into the recognizer.
    private void PumpLoop()
    {
        var buf = new byte[3200];   // ~100 ms at 16kHz/16-bit/mono
        while (_running)
        {
            int n = 0;
            try { n = _resampler!.Read(buf, 0, buf.Length); } catch { n = 0; }
            if (n > 0) { try { _speechStream!.Write(buf, 0, n); } catch { } }
            else Thread.Sleep(15);
        }
    }

    private void OnHypothesized(object? sender, SpeechHypothesizedEventArgs e)
    {
        lock (_lock) _partial = e.Result.Text;
    }

    private void OnRecognized(object? sender, SpeechRecognizedEventArgs e)
    {
        var txt = (e.Result?.Text ?? "").Trim();
        if (txt.Length == 0) return;
        lock (_lock) { _transcript += (_transcript.Length > 0 ? " " : "") + txt; _partial = ""; }
        Log.Write("🎧 segment: " + (txt.Length > 60 ? txt[..60] : txt));
        SegmentRecognized?.Invoke(txt);
    }

    public void Stop()
    {
        if (!_running && _engine == null && _capture == null) { IsListening = false; return; }
        Log.Write($"🎧 listen.stop — buffers={_audioBuffers}, transcript={FullText.Length} chars");
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
