# Windows 실행

화면은 Godot 네이티브 실행 파일, GPU 음성·대화 서버는 WSL에서 실행됩니다.
브라우저를 열 필요는 없습니다. 현재 구성은 완전한 Windows 단독 ML 설치가 아닙니다.

이 작업 공간의 환경·캐릭터 자산이 설치된 상태에서 WSL로 빌드합니다.

```bash
cd /home/hard2251/workspace/mate-engine/Mate-Engine
python3 companion/setup_native.py --build
```

Windows 탐색기에서 `companion/native/build/Launch-Mate.cmd`를 실행합니다.
런처는 전용 GPU 서버를 시작하고 준비를 기다린 뒤 `MateCompanion.exe`를 띄웁니다.
빌드할 때 현재 WSL 배포판과 백엔드 위치를 `runtime-location.json`에 기록합니다.
다른 위치로 옮겼다면 이 파일을 고치거나 PowerShell 인자를 사용합니다.

```powershell
.\Launch-Mate.ps1 -Distro Ubuntu-24.04 -BackendRoot /path/to/Mate-Engine/companion
```

펫이나 패널에 포커스가 있을 때 F8로 패널을 열고 닫고, F9를 누르는 동안 마이크를 녹음합니다. Escape는 진행 중인
대화와 재생을 중단합니다. 캐릭터, 음량, 마이크, 이동과 크기는 패널에서 설정합니다.
작업 탭의 Codex는 `companion/user-data/workspace`에서 작업합니다.
음성 응답은 작업 시작 안내와 짧은 결과이고, 자세한 진행은 패널에서 확인합니다.

펫을 종료해도 GPU 서버는 유지됩니다. 서버까지 끄려면 다음을 실행합니다.

```powershell
.\Launch-Mate.ps1 -StopBackend
```

또는 WSL에서 `python3 companion/desktop.py stop`을 사용합니다. 이 감독 프로세스가
시작한 서버만 종료합니다. 상태는 `python3 companion/desktop.py status`로 봅니다.
문제가 있으면 `companion/logs/desktop-runtime.log`, `desktop-engine.log`,
`desktop-tts.log`를 확인합니다.

새 설치에는 기존 `install.sh`, `experiments/omni/setup.sh`, `setup_characters.py`로
대화·음성 환경과 자산을 준비하고, `setup_native.py`로 Godot 도구와 고정 버전 플러그인을
설치해야 합니다. `setup_motions.py --ual-zip <무료 Standard ZIP>`은 CC0 모션을 변환합니다.
원본 VRM과 음성 모델은 실행 파일에 포함하지 않습니다. 빌드의 `licenses/`는 함께
보관하세요. 소스와 적용한 플러그인 패치는 이 저장소에 있습니다.

작은 음성 입력 모델은 모호한 과거 대화 회상에서 틀리거나 사용자 정보를 지어낼 수
있습니다. 현재는 신뢰할 수 있는 장기 기억 시스템이 아닙니다. 마이크 입력은 발화가
끝난 뒤 모델에 전달하며, 응답 텍스트와 전용 TTS의 PCM은 생성 도중 스트리밍합니다.
