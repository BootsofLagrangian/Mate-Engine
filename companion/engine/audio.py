"""WAV decoding for audio-input turns. The waveform is the model input; no ASR is involved."""
import base64
import binascii
import io

MAX_WAV_BYTES = 16 * 1024 * 1024
MAX_SECONDS = 30.0
TARGET_RATE = 16000


class AudioError(ValueError):
    pass


def decode_wav_base64(wav_b64):
    if not isinstance(wav_b64, str) or not wav_b64:
        raise AudioError('Missing wav payload')
    try:
        data = base64.b64decode(wav_b64, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise AudioError('wav is not valid base64') from exc
    if len(data) > MAX_WAV_BYTES:
        raise AudioError('Audio is limited to 16 MB')
    return decode_wav_bytes(data)


def decode_wav_bytes(data):
    """Return (float32 mono samples at 16 kHz, original duration seconds)."""
    import numpy as np
    import soundfile as sf
    try:
        audio, rate = sf.read(io.BytesIO(data), dtype='float32')
    except Exception as exc:  # soundfile raises RuntimeError/ValueError variants
        raise AudioError(f'Unreadable WAV: {exc}') from exc
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if len(audio) == 0:
        raise AudioError('Audio is empty')
    seconds = len(audio) / rate
    if seconds > MAX_SECONDS:
        raise AudioError('Recording is limited to 30 seconds')
    if not np.isfinite(audio).all():
        raise AudioError('Audio contains non-finite samples')
    if rate != TARGET_RATE:
        audio = resample(audio, rate, TARGET_RATE)
    return audio.astype('float32', copy=False), seconds


def resample(audio, rate, target):
    try:
        import librosa
        return librosa.resample(audio, orig_sr=rate, target_sr=target)
    except ImportError:
        # Linear fallback for environments without librosa (test venvs). Lower quality.
        import numpy as np
        length = int(round(len(audio) * target / rate))
        positions = np.linspace(0, len(audio) - 1, num=max(length, 1))
        return np.interp(positions, np.arange(len(audio)), audio).astype('float32')
