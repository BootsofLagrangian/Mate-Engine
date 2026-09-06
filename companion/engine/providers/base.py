"""Provider interface consumed by stream_pipeline.conversation_stream.

conversation_stream calls `brain.stream_turn(req, cancelled)` and expects the
generator protocol used by the original companion:
    ('token', None)  first token observed
    ('text', str)    monotonically growing spoken text
    ('result', dict) final {'text','emotion','gesture', optional intensity/speed/repeat}
The request carries the modality (text or 16 kHz audio) plus the voice reference.
"""
import threading


class TurnRequest:
    """Duck-types the attributes conversation_stream reads (text, session, voice, reference)."""

    def __init__(self, *, turn_id, character, profile, session, voice=True, text='', audio=None,
                 audio_seconds=0.0, ref_audio_path=None, reference_text=None, save_audio=False):
        self.turn_id = turn_id
        self.character = character
        self.profile = profile
        self.session = session
        self.voice = voice
        self.text = text or ''
        self.audio = audio
        self.audio_seconds = audio_seconds
        self.ref_audio_path = ref_audio_path
        self.reference_text = reference_text
        self.save_audio = save_audio
        self.gestures = None
        self.motion_descriptions = {}
        self.pending_history = None
        self.defer_history = False
        self.world_interests = ()
        self.furniture_types = ()
        self.furniture_catalog = ()
        self.locomotion_catalog = ()
        self.appearance_variants = ()
        self.active_variant_id = "default"
        self.execution_feedback = ()
        self.world_context_valid = lambda: False

    @property
    def modality(self):
        return 'audio' if self.audio is not None else 'text'


class Provider:
    name = 'base'

    def __init__(self, history):
        self.history = history
        self.lock = threading.Lock()  # one generation at a time; models are not reentrant
        self.loaded = False

    def load(self):
        self.loaded = True

    def status(self):
        return {'provider': self.name, 'loaded': self.loaded}

    def stream_turn(self, req, cancelled):
        raise NotImplementedError

    def remember(self, req, result):
        user = {'kind': req.modality, 'text': req.text if req.modality == 'text' else None,
                'audio': req.audio if req.modality == 'audio' else None}
        if req.defer_history:
            req.pending_history = (self.history, user, result)
        else:
            self.history.append(req.session, req.character, user, result)


class ScriptedProvider(Provider):
    """Speaks a fixed line (job acknowledgements). Never touches model history."""
    name = 'scripted'

    def __init__(self, text, emotion='neutral', gesture='nod'):
        super().__init__(history=None)
        self.text = text
        self.emotion = emotion
        self.gesture = gesture

    def stream_turn(self, req, cancelled):
        if cancelled.is_set():
            return
        yield 'token', None
        yield 'text', self.text
        yield 'result', {'text': self.text, 'emotion': self.emotion, 'gesture': self.gesture}
