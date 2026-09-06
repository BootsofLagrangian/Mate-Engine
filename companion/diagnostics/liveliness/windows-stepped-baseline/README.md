# Windows stepped-motion milestone

Actual exported `MateCompanion.exe`, Windows 11, Vulkan Forward+ on RTX 4090.
This milestone precedes the later request to integrate additional authored and
locally extracted Uma motions; it must not be relabeled as validating those assets.
`summary.json` identifies the executable and separate integration checks.

- Continuous liveliness: **40 checks, zero failures**, 5,692 measured frames,
  actual owned OS-window movement, no pointer interference. Frame intervals were
  33.326 ms median and 42.068 ms p95, including optional capture cost and the
  production idle FPS policy. This probe manually invokes the normal motion/main/
  autonomy ordering; it is not a normal-process spring-physics benchmark.
- Gait: maximum projected planted-ankle drift 0.06386 px, p95 0.01624 px over 32
  contact epochs. No-displacement gait phase drift was zero.
- Turning: 31 fully weighted support epochs, maximum projected ankle drift
  0.000252 px; initial blends exclude 1.095 s of support claims. Measured heading
  speed was 70.001 degrees/s or less, acceleration 124.73 degrees/s² or less, and
  departure heading error below 0.002 degrees. These are geometric engineering
  measurements, not a biological or perceptual naturalness score.
- Normal production processing, live GPU voice and Korean movement request:
  **12 checks, zero failures**. Dedicated voice PCM arrived at 968 ms in this one
  captured run. Spoken acknowledgment produced zero window drift; the requested
  left target produced one arrival, moving x=890 to x=-354 at constant y=672.
  This separate probe retains normal scene processing, including spring updates.
- Actual owned window-top/floor regression: **17 checks, zero failures**, including
  scale, panel pause, seated speech, closed-support release and helper cleanup.

The coordinator inspected rendered turn/walk frames. The revised sequence shows
alternating lifted-foot repositioning and then walking; the earlier comparison
shows a rigid standing swivel. This supports the intended visible mechanism.
It does not establish full-body dynamics or eliminate every awkward interruption:
the six-cell simulation still records elevated authored-walk interruption angular
acceleration. Raw derivative peaks and contact exclusions remain in the reports.

Own-viewport captures, normal-processing voice events, and full logs remain local:
`logs/windows-liveliness-final/`, `logs/windows-native-intent-stepped/`,
`logs/windows-world-stepped/`. No unrelated desktop pixels or microphone input
were recorded by these probes. Reported latency includes capture overhead and is
a single observation, not a controlled performance comparison.
