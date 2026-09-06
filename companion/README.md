# Mate character companion

현재 Windows 데스크톱 펫은 [네이티브 호스트 안내](native/README.md)를 사용합니다.
슈발·라이스·에이신 프로필, 음성 입력 Thinker + 전용 Uma TTS, 작업 에이전트,
VRMA 동작과 데스크톱 이동은 [범용 엔진](engine/README.md)으로 연결됩니다.
창 경계 상호작용과 향후 소품 확장은 [Desktop world 계획](DESKTOP-WORLD.md)에 정리했습니다.
Windows에서는 [Launch-Mate.cmd](windows/Launch-Mate.cmd)로 실행합니다.
**행동** 탭에서 이름 있는 지점을 만들고 표식을 끌어 배치한 뒤 이동·살펴보기를
요청할 수 있습니다. 자율 대기에는 LLM 호출이 필요하지 않으며, 대화 중 받은
간헐적 행동 지시도 같은 제어기로 연결됩니다.

## 기존 브라우저 / Unity 어댑터

이하 실행 방법과 모델 설명은 기존 어댑터용입니다. 현재 네이티브 호스트의
음성 입력 모델은 Qwen2.5-Omni 3B Thinker이며 전용 Uma TTS를 사용합니다.

Mate Engine에 Cheval Grand의 대화, 음성 인식, 음성 합성, 표정·행동을 연결합니다. Unity 없이 실행할 수 있는 브라우저 화면도 같은 로컬 서버를 사용합니다.

```bash
# 이미 이 작업 공간에는 설치와 모델 다운로드가 완료되어 있습니다.
cd /home/hard2251/workspace/mate-engine/Mate-Engine
./companion/start.sh
```

http://localhost:8765 에 접속합니다. 포트 사용 중 메시지가 나오면 이미 실행 중인 화면을 열면 됩니다. 다른 컴퓨터에 새로 설치할 때는 `./companion/install.sh`를 먼저 실행하세요. Python 3.11은 uv로 설치하며, `uv`, Git, FFmpeg, Node.js/npm이 필요합니다. 모델·라이브러리 다운로드에는 수 GB가 필요합니다. `requirements-lock.txt`는 검증 환경의 전체 버전 기록입니다.

- 한국어/일본어 메시지 → **Qwen2.5-1.5B-Instruct Q4_K_M** → 일본어 대사 + 제한된 행동 JSON.
- 마이크 버튼 → 최대 30초 녹음 → **faster-whisper small**, CUDA float16 → 대화.
- 일본어 대사 → **UmaDiffusion GPT-SoVITS v2** + Cheval Grand 공식 샘플 → **LLM 생성 중 짧은 구절부터 TTS 추론 → 20ms PCM 스트리밍 재생** + 소리 크기에 맞춘 립싱크.
- Drive VRM → 마우스를 따라가는 눈, 숨쉬기·눈깜박임, `nod`, `shake_head`, `shy`, `wave`, `think`, `idle`, `bow`, `stretch`와 부드러운 표정 전환. 화면의 **움직임 보기**에서 직접 재생할 수 있습니다.
- 대화는 세션당 최근 6턴, 최대 32세션을 메모리에 보관합니다. 새 대화 버튼으로 초기화하며 재시작 시 사라집니다. 생성 WAV는 `output/`에 저장하고 24시간 지난 파일은 다음 합성 때 정리합니다.

기본 실행은 **LLM·TTS·STT 모두 RTX 4090 CUDA**입니다. 초기에는 GPU가 다른 작업으로 차 있어 CPU로 검증했고, 해당 작업이 종료된 뒤 GPU로 전환했습니다. 다른 작업을 강제로 종료하지 않았습니다. 시작 시 LLM·TTS와 기준 음성을 미리 워밍업합니다(`/health`의 `warmed`). 첫 음성 인식은 Whisper 로딩 때문에 더 느립니다. 실행 시 여유 VRAM 6 GiB 이상을 확인하며, GPU가 없을 때 CPU로 몰래 전환하지 않습니다. CPU 실행이 필요한 경우에만 `MATE_DEVICE=cpu ./companion/start.sh`를 사용하세요. 정확히 1.0B가 아닌 **1.54B의 1B급 모델**입니다. 작은 모델의 캐릭터 말투는 프롬프트/예시 기반이며 전용 파인튜닝은 아닙니다.

## 실시간 경로와 캐릭터 설정

`characters/cheval-grand.json`에 공식 정보 요약, 말투 지침, 직접 작성한 한국어 입력/일본어 응답 예시 16개를 넣었습니다. 모두 **SYSTEM 문맥**에 들어갑니다. 사용자는 인간 트레이너, 모델은 슈발 그랑이라는 역할을 명시하고 일본어 응답을 지시합니다. 별도 번역 모델 호출은 없습니다. `MATE_CHARACTER`로 다른 프로필을 선택할 수 있으나 음성 가중치·기준 음성·VRM도 별도로 교체해야 합니다.

`/chat/stream`은 NDJSON 이벤트(`text`, `phrase`, `action`, `audio`, `done`)를 보냅니다. 완성 중인 JSON에서 대사만 꺼내 쉼표·문장부호 또는 일본어 형태소 경계에서 TTS에 넘깁니다. LLM과 TTS가 서로 다른 작업 스레드에서 겹쳐 실행되고, 클라이언트는 다음 음성을 미리 큐에 넣습니다. 멈춤 버튼은 요청과 재생을 취소합니다. STT는 녹음 종료 후 처리하며, 아직 음소/발화 중간 STT 스트리밍은 아닙니다.

GPT-SoVITS v2는 **입력된 한 구절을 합성한 뒤** PCM을 반환합니다. 20ms는 전송 단위이며 음소별 모델 추론 단위가 아닙니다. LLM 토큰 하나가 나올 때마다 즉시 소리가 나는 수준은 달성하지 못했습니다. 대신 첫 구절을 빨리 시작하고, 다음 구절을 재생보다 빠르게 만드는 방식입니다.

TTS 최적화는 CUDA FP16, 기준 음성 캐시, 시작 워밍업, 단일 구절의 SDPA 추론 경로입니다. 배치 추론의 수동 attention도 `tts_optimization.py`에서 SDPA로 교체합니다. 원본 소스 해시를 확인하고 백업을 보관하며 `MATE_TTS_SDPA=0`으로 되돌릴 수 있습니다. 현재 스트리밍은 실측에서 더 빠른 `parallel_infer=False`를 씁니다. 즉, 배치 경로 패치만으로 모든 속도 향상이 생겼다고 주장하지 않습니다.

작은 모델의 한국어 이해와 캐릭터 일관성에는 아직 오류가 있습니다. 일본어 문자 범위 제약도 일본어 의미나 캐릭터성을 수학적으로 보장하지 않습니다. 측정 범위와 실패 예시는 `VALIDATION.md`에 남겼습니다.

## 음성을 직접 이해하는 모델 실험

Qwen2.5-Omni-3B의 **Thinker만 로드 → 일본어 대사 → 기존 슈발 GPT-SoVITS** 경로를 별도 환경에서 GPU 실행했습니다. 한국어 합성 입력 5개와 반복 1개가 음성 출력까지 연결됐습니다. 현재 UI의 기본 모델은 바꾸지 않았습니다. 실제 녹음 WAV로 실행하는 방법은 [실험 안내](experiments/omni/README.md), 측정과 한계는 [결과](experiments/omni/RESULTS.md)를 참고하세요.

## Mate Engine Unity 연결

프로젝트 버전은 **Unity 6000.2.6f2**입니다. 서버를 실행한 뒤 프로젝트의 기존 메인 씬을 Play하면 `StreamingAssets/cheval-companion.json`을 읽어 Companion을 생성합니다.

- 서버에서 Cheval VRM을 받아 Unity `persistentDataPath`에 저장하고 기존 `VRMLoader`로 로드합니다.
- `/chat/stream`을 증분 UTF-8 디코더로 읽고, 오디오 스레드가 PCM 링 버퍼를 재생합니다. 전체 WAV 다운로드를 기다리지 않습니다.
- 기존 ChatBot의 입력도 로컬 Companion에 연결합니다. F8 패널에서도 대화/마이크를 사용할 수 있습니다.
- `cheval-motions.json`의 공통 타임라인을 읽어 기존 Mate Engine Animator 기본 모션 위에 머리·가슴·팔 동작을 합성합니다. 브라우저는 VRM 좌표계에 맞춰 앞뒤 회전축을 변환합니다. 이전 프레임 오프셋은 다른 애니메이션 코드보다 먼저 해제합니다.
- `enabled: false`로 변경하면 기존 Mate Engine 대화/아바타 로딩 경로를 사용합니다.
- Linux에서는 Windows 전용 NAudio 오디오 장치 초기화를 건너뛰도록 수정했습니다.

**이 환경에는 Unity Editor가 없어 Unity 컴파일, Play, 네이티브 데스크톱 창 동작은 검증하지 못했습니다.** 브라우저 검증을 Unity 실행 검증으로 간주하지 않습니다. 현재 VRM은 VRM 0.x이며 Unity 립싱크는 해당 `VRMBlendShapeProxy`를 사용합니다.

## 실행 설정

| 변수 | 기본값 | 용도 |
|---|---|---|
| `MATE_PYTHON` | 작업 공간 `.venv/bin/python` | 다른 가상환경 사용 |
| `MATE_THREADS` | `8` | LLM/TTS CPU 스레드 수 |
| `MATE_GGUF` | `models/qwen2.5-1.5b-instruct-q4_k_m.gguf` | Qwen GGUF 파일 |
| `MATE_DEVICE` | `cuda` | 전체 스택 기본 장치, 명시적 `cpu` 선택 가능 |
| `MATE_GPU_LAYERS` | `-1` | LLM 전체 레이어 GPU, CPU 모드에서는 0 |
| `MATE_TTS_DEVICE` | `cuda` | TTS 실행 장치 |
| `MATE_STT_DEVICE` | `cuda` | STT 실행 장치 |
| `MATE_WARMUP` | `1` | 시작 시 LLM/TTS 미리 추론 |
| `MATE_TTS_SDPA` | `1` | v2 배치 attention 패치, 0으로 원복 |
| `MATE_CHARACTER` | `cheval-grand` | SYSTEM 캐릭터 프로필 |
| `MATE_STT_MODEL` | `small` | Whisper 모델 크기 |

`install.sh`는 Linux x86_64/WSL용 PyTorch 2.6.0 CUDA 12.6, llama-cpp-python 0.3.19 CUDA 12.4를 설치합니다. 4090에서 세 단계 모두 실행 검증했습니다. WSL GPU 정보는 `/usr/lib/wsl/lib/nvidia-smi`로 확인 가능합니다.

서버는 `127.0.0.1:8765`, TTS는 `127.0.0.1:9880`에만 바인딩합니다. `start.sh` 터미널에서 Ctrl-C를 누르면 둘 다 종료합니다. 이 작업 중 백그라운드로 띄운 인스턴스는 `.venv/bin/python Mate-Engine/companion/stop.py`로 종료할 수 있습니다. 로그는 `companion/logs/`에 있습니다.

## 검증

```bash
../.venv/bin/python -m pytest companion/test_app.py companion/test_stream.py -q
cd companion/web
node check-render.mjs
node check-pcm.mjs
node check-live.mjs
node check-cancel.mjs
node check-motions.mjs
node check-microphone.mjs
```

`check-microphone.mjs`는 실제 브라우저 마이크 처리 경로에 **미리 녹음한 WAV를 가상 장치로 입력**합니다. 사용자의 물리 마이크/스피커나 청취 환경은 자동 검증하지 않았습니다.

브라우저 검증 스크립트의 `CHROME_PATH`를 Chrome 실행 파일로 지정할 수 있습니다. WSL 테스트에서는 독립된 Chromium + SwiftShader를 사용해, 기존 브라우저 세션을 종료하지 않고 WebGL을 검증했습니다. WebGL 사용 불가 시에도 대화 UI는 작동합니다.

실제 측정 결과와 미검증 범위는 [VALIDATION.md](VALIDATION.md), 다운로드 출처와 자산 메타데이터는 [SOURCES.md](SOURCES.md)를 참조하세요. 모델·VRM·기준 음성·생성 음성은 Git에서 제외됩니다.
