using System.IO;

namespace Flubber.App.Platform;

/// <summary>
/// Stream circular bloqueante: el hilo de audio ESCRIBE PCM (16kHz/16-bit/mono) y
/// el motor de System.Speech LEE de aquí. Read() se bloquea hasta que hay datos;
/// al cerrar, Read devuelve 0 (fin de stream) para que el reconocedor termine.
/// </summary>
public sealed class SpeechStreamer : Stream
{
    private readonly byte[] _buf;
    private int _head, _tail, _count;
    private readonly object _l = new();
    private bool _closed;

    public SpeechStreamer(int capacity) { _buf = new byte[capacity]; }

    public override bool CanRead => true;
    public override bool CanWrite => true;
    public override bool CanSeek => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();

    public override int Read(byte[] buffer, int offset, int count)
    {
        lock (_l)
        {
            while (_count == 0 && !_closed) System.Threading.Monitor.Wait(_l);
            if (_count == 0 && _closed) return 0;
            int n = Math.Min(count, _count);
            for (int i = 0; i < n; i++) { buffer[offset + i] = _buf[_head]; _head = (_head + 1) % _buf.Length; }
            _count -= n;
            System.Threading.Monitor.PulseAll(_l);
            return n;
        }
    }

    public override void Write(byte[] buffer, int offset, int count)
    {
        lock (_l)
        {
            for (int i = 0; i < count; i++)
            {
                while (_count == _buf.Length && !_closed) System.Threading.Monitor.Wait(_l);
                if (_closed) return;
                _buf[_tail] = buffer[offset + i]; _tail = (_tail + 1) % _buf.Length; _count++;
            }
            System.Threading.Monitor.PulseAll(_l);
        }
    }

    public override void Close()
    {
        lock (_l) { _closed = true; System.Threading.Monitor.PulseAll(_l); }
        base.Close();
    }
}
