using System;
using System.Collections.Generic;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

/// <summary>NDJSON UTF-8 decoder; callbacks run on Unity's main thread.</summary>
public sealed class ChevalStream : DownloadHandlerScript
{
    readonly Decoder decoder = Encoding.UTF8.GetDecoder();
    readonly char[] chars = new char[Encoding.UTF8.GetMaxCharCount(16384)];
    readonly StringBuilder pending = new StringBuilder();
    readonly Action<string> receive;
    public string Failure { get; private set; }
    public ChevalStream(Action<string> receive) : base(new byte[16384]) { this.receive = receive; }
    protected override bool ReceiveData(byte[] data, int length)
    {
        try {
            int count = decoder.GetChars(data, 0, length, chars, 0, false);
            for (int i = 0; i < count; i++) {
                if (chars[i] == '\n') { if (pending.Length > 0) receive(pending.ToString()); pending.Clear(); }
                else pending.Append(chars[i]);
                if (pending.Length > 65536) throw new InvalidOperationException("Oversized stream event");
            }
            return true;
        } catch (Exception e) { Failure = e.Message; return false; }
    }
    protected override void CompleteContent()
    {
        try { if (pending.Length > 0) receive(pending.ToString()); pending.Clear(); }
        catch (Exception e) { Failure = e.Message; }
    }
}

/// <summary>Bounded mono PCM ring shared by the main and audio threads.</summary>
public sealed class ChevalPcm
{
    readonly object gate = new object();
    readonly float[] ring = new float[32000 * 60];
    int read, write, count;
    public int Count { get { lock (gate) return count; } }
    public void Enqueue(string encoded, int sampleRate)
    {
        if (sampleRate != 32000) throw new InvalidOperationException("Unexpected PCM sample rate");
        byte[] bytes = Convert.FromBase64String(encoded);
        if ((bytes.Length & 1) != 0) throw new InvalidOperationException("Invalid PCM length");
        lock (gate) {
            if (count + bytes.Length / 2 > ring.Length) throw new InvalidOperationException("PCM buffer full");
            for (int i = 0; i < bytes.Length; i += 2) {
                ring[write] = (short)(bytes[i] | bytes[i + 1] << 8) / 32768f;
                write = (write + 1) % ring.Length; count++;
            }
        }
    }
    public void Read(float[] output)
    {
        lock (gate) {
            for (int i = 0; i < output.Length; i++) {
                if (count == 0) output[i] = 0;
                else { output[i] = ring[read]; read = (read + 1) % ring.Length; count--; }
            }
        }
    }
}
