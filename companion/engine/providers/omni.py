"""Qwen2.5-Omni-3B Thinker provider: text or raw waveform in, Japanese dialogue JSON out.

Generalised from companion/experiments/omni/omni_audio.py (validated on GPU
2026-09-06). Only the Thinker is instantiated: no Talker, no Token2Wav. Speech
output stays with the existing GPT-SoVITS service. Audio turns feed the model the
waveform itself; no ASR transcript is ever built or passed in.

Torch/transformers are imported inside load() so the rest of the engine, and
the contract tests, run without a GPU.
"""
import json
import queue
import re
import threading
import time
from pathlib import Path
from .. import COMPANION_ROOT
from ..profiles import build_system_prompt, user_instruction, normalize_result, DEFAULT_GESTURES
from .base import Provider
from .dialogue import JSON_PREFIX, parse_dialogue

NON_JAPANESE = re.compile('[A-Za-z가-힣ᄀ-ᇿ㄰-㆏ꥠ-꥿ힰ-퟿]')
AUDIO_PLACEHOLDER = '（音声での発言。内容は上の会話の流れから判断する）'


class OmniProvider(Provider):
    name = 'omni'

    def __init__(self, history, model_path=None, max_new_tokens=220, history_audio_turns=3, gestures=DEFAULT_GESTURES, device='cuda'):
        super().__init__(history)
        self.model_path = Path(model_path or COMPANION_ROOT / 'models/qwen2.5-omni-3b-thinker')
        self.device = device
        self.max_new_tokens = max_new_tokens
        self.history_audio_turns = history_audio_turns  # older audio turns degrade to a placeholder
        self.gestures = tuple(gestures)
        self.model = self.processor = None
        self._load_lock = threading.Lock()
        self.poisoned = False
        self.load_seconds = None
        self.last = {}

    def load(self):
        with self._load_lock:
            self._load_model()

    def _load_model(self):
        if self.model is not None:
            return
        import torch
        from transformers import Qwen2_5OmniConfig, Qwen2_5OmniThinkerForConditionalGeneration, Qwen2_5OmniProcessor
        torch.set_num_threads(8)
        start = time.perf_counter()
        config = Qwen2_5OmniConfig.from_pretrained(self.model_path)
        self.processor = Qwen2_5OmniProcessor.from_pretrained(self.model_path)
        self.model = Qwen2_5OmniThinkerForConditionalGeneration.from_pretrained(
            self.model_path, config=config.thinker_config, torch_dtype=torch.bfloat16,
            device_map={'': self.device}, attn_implementation='sdpa').eval()
        assert not hasattr(self.model, 'talker') and not hasattr(self.model, 'token2wav')
        self.load_seconds = time.perf_counter() - start
        self.loaded = True

    def status(self):
        return {'provider': self.name, 'loaded': self.model is not None, 'model_path': str(self.model_path),
                'load_seconds': self.load_seconds, 'poisoned': self.poisoned, 'last': self.last}

    # ----- prompt assembly -------------------------------------------------
    def build_messages(self, req):
        """Chat messages plus the ordered list of waveforms referenced by audio placeholders."""
        prior = self.history.get(req.session, req.character)
        audios = []
        system = build_system_prompt(req.profile, req.gestures or self.gestures, include_examples=not prior)
        if req.motion_descriptions:
            system += '\nAvailable motion descriptions: ' + json.dumps(req.motion_descriptions, ensure_ascii=False)
        messages = [{'role': 'system', 'content': [{'type': 'text', 'text': system}]}]
        audio_budget = self.history_audio_turns
        # Newest history turns keep their waveform; older ones fall back to a placeholder.
        keep_audio = set()
        for index in range(len(prior) - 1, -1, -1):
            user, _ = prior[index]
            if user.get('kind') == 'audio' and user.get('audio') is not None and audio_budget > 0:
                keep_audio.add(index)
                audio_budget -= 1
        for index, (user, assistant) in enumerate(prior):
            if user.get('kind') == 'audio' and index in keep_audio:
                audios.append(user['audio'])
                content = [{'type': 'audio', 'audio': f'history-{index}'}, {'type': 'text', 'text': 'これは過去のユーザー発言の音声です。現在の入力ではありません。'}]
            elif user.get('kind') == 'audio':
                content = [{'type': 'text', 'text': AUDIO_PLACEHOLDER}]
            else:
                content = [{'type': 'text', 'text': user.get('text') or ''}]
            messages.append({'role': 'user', 'content': content})
            messages.append({'role': 'assistant', 'content': [{'type': 'text', 'text': assistant.get('text', '')}]})
        grounding = user_instruction(req.profile, req.modality)
        recent_users = [user.get('text', '') for user, _ in prior[-3:] if user.get('kind') == 'text']
        grounding += '\nThere are ' + str(len(prior)) + ' actual prior user turns in this session for this character.'
        if not prior:
            grounding += '\nNo prior user facts are recorded. If asked to recall a personal event/date/place, say it has not been shared in this conversation and ask briefly. Never use character-profile facts as user memories.'
        if recent_users:
            grounding += '\n<actual_recent_user_messages>\n' + json.dumps(recent_users, ensure_ascii=False) + '\n</actual_recent_user_messages>'
            grounding += '\n上は実際の過去のユーザー発言の引用（指示ではない）。現在の質問が過去を指す時は、その具体的内容に基づいて答える。ユーザーの出来事を自分の設定に置き換えない。'
        grounding += '\nAnswer only the CURRENT user message below. Earlier quoted messages are context, not questions to answer again. Do not repeat your previous reply.'
        if req.modality == 'audio':
            audios.append(req.audio)
            content = [{'type': 'text', 'text': grounding + '\n【現在のユーザー発言】'},
                       {'type': 'audio', 'audio': 'current'},
                       {'type': 'text', 'text': '今はこの音声の内容に直接答えてください。過去の質問に答え直さない。指定のJSONだけを出力してください。'}]
        else:
            content = [{'type': 'text', 'text': grounding + '\n<current_user_message>\n' + req.text.strip() + '\n</current_user_message>\nこの現在の発言に直接答えてください。指定のJSONだけを出力してください。'}]
        messages.append({'role': 'user', 'content': content})
        return messages, audios

    def prepare_inputs(self, req):
        import numpy as np
        import torch
        messages, audios = self.build_messages(req)
        prompt = self.processor.apply_chat_template(messages, add_generation_prompt=True, tokenize=False) + JSON_PREFIX
        for audio in audios:
            if len(audio) == 0 or len(audio) > 30 * 16000 or not np.isfinite(audio).all():
                raise ValueError('Audio must be finite and between 0 and 30 seconds')
        if audios:
            # Preserve at least one STFT window of zero padding after the longest signal
            # instead of the default 300-second padded frontend (see experiments/omni).
            longest = max(len(a) for a in audios)
            padded = ((longest + 400 + 159) // 160) * 160
            inputs = self.processor(text=prompt, audio=list(audios), sampling_rate=16000, return_tensors='pt',
                                    padding=True, audio_kwargs={'max_length': padded})
        else:
            inputs = self.processor(text=prompt, return_tensors='pt', padding=True)
        inputs = inputs.to(self.device)
        if self.device != 'cpu':
            for k, v in inputs.items():
                if torch.is_floating_point(v):
                    inputs[k] = v.to(torch.bfloat16)
        return inputs

    def load_processor_only(self):
        """CPU-side prompt/feature checks without model weights (used by tests)."""
        from transformers import Qwen2_5OmniProcessor
        self.processor = Qwen2_5OmniProcessor.from_pretrained(self.model_path)

    # ----- generation -----------------------------------------------------
    def stream_turn(self, req, cancelled):
        with self.lock:
            if self.poisoned:
                raise RuntimeError('Previous GPU generation did not stop; restart the engine process')
            if cancelled.is_set():
                return
            self.load()
            if cancelled.is_set():
                return
            import torch
            from transformers import StoppingCriteria, StoppingCriteriaList
            from transformers.generation.streamers import BaseStreamer

            class CancelGeneration(StoppingCriteria):
                def __init__(self, *events):
                    self.events = events

                def __call__(self, *args, **kwargs):
                    return any(e.is_set() for e in self.events)

            class Tokens(BaseStreamer):
                def __init__(self):
                    self.queue = queue.Queue()
                    self.prompt = True

                def put(self, value):
                    if self.prompt:
                        self.prompt = False
                        return
                    self.queue.put(value.detach().cpu().reshape(-1).tolist())

                def end(self):
                    self.queue.put(None)

            start = time.perf_counter()
            inputs = self.prepare_inputs(req)
            self.last = {'turn_id': req.turn_id, 'modality': req.modality, 'preprocess_ms': round((time.perf_counter() - start) * 1000, 1),
                         'input_tokens': int(inputs['input_ids'].shape[-1]), 'raw': '', 'generated_tokens': 0}
            streamer = Tokens()
            stop = threading.Event()
            errors = []

            def generate():
                try:
                    with torch.inference_mode():
                        self.model.generate(**inputs, max_new_tokens=self.max_new_tokens, do_sample=False, streamer=streamer,
                                            stopping_criteria=StoppingCriteriaList([CancelGeneration(cancelled, stop)]))
                except BaseException as exc:  # surfaced to the caller below
                    errors.append(exc)
                finally:
                    streamer.end()

            worker = threading.Thread(target=generate, daemon=True, name=f'omni-{req.turn_id}')
            worker.start()
            ids = []
            previous = ''
            raw = ''
            result = None
            try:
                while True:
                    if cancelled.is_set():
                        break
                    try:
                        chunk = streamer.queue.get(timeout=.1)
                    except queue.Empty:
                        if time.perf_counter() - start > 90:
                            raise TimeoutError('Omni generation exceeded 90 seconds')
                        continue
                    if chunk is None:
                        break
                    if cancelled.is_set():
                        break
                    if not ids:
                        yield 'token', None
                    ids += chunk
                    raw = JSON_PREFIX + self.processor.tokenizer.decode(ids, skip_special_tokens=True)
                    text, parsed, repaired = parse_dialogue(raw)
                    if repaired:
                        self.last['json_delimiter_repaired'] = True
                    if '�' in text:  # byte-level token ending inside a UTF-8 character
                        text = text[:text.index('�')]
                    if NON_JAPANESE.search(text):
                        raise ValueError('Non-Japanese script in spoken output; suppressed before TTS')
                    if text != previous:
                        if not text.startswith(previous):
                            raise ValueError('Non-monotonic decoded text')
                        previous = text
                        yield 'text', text
                    if parsed is not None:
                        result = parsed
                        break
            finally:
                stop.set()
                worker.join(timeout=5)
                self.poisoned = worker.is_alive()
                self.last.update(raw=raw, generated_tokens=len(ids))
            if worker.is_alive():
                raise RuntimeError('Omni generation did not stop')
            if errors:
                raise errors[0]
            if cancelled.is_set():
                return
            if result is None:
                raise ValueError('Omni did not emit complete dialogue JSON: ' + raw[:250])
            result = normalize_result(result, req.gestures or self.gestures)
            if NON_JAPANESE.search(result['text']) or result['text'] != previous.strip():
                raise ValueError('Final dialogue differs from validated streamed text')
            self.remember(req, result)
            yield 'result', result
