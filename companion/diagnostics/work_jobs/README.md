# Actual native work-job probe

`native/tools/probe_windows_job.gd` is an external Windows script extending the
sibling `probe_windows_space_skills.gd`. Run it with the packaged executable's
`--script` option and arguments after `--`:

```text
--output <new Windows output directory> --character cheval-grand --workspace <Windows-readable path to the backend's companion/user-data/workspace>
```

The root operator must map `--workspace` to the advertised backend directory
(e.g. the corresponding WSL UNC path). The probe checks advertised jobs,
workspace-write sandbox and the `user-data/workspace` suffix before submission.
It uses the real native `_start_job` path, not ordinary chat or an injected tool
intent. Its only job asks Codex to exclusively create `mate-native-job-smoke.txt`
with `MATE_NATIVE_JOB_OK` plus newline and read it back. If already present, a
fresh timestamped name is selected; the prompt also refuses overwrite races.
The probe independently reads the resulting bytes through the supplied mapping.
It retains the fixture and never deletes or edits other workspace files.

The report records native job ID, tool progress, terminal status, ack/result PCM
byte counts and actual playback start/drain signals. Ack PCM must precede the
job-start event, and playback must begin before first tool progress. Whether
playback begins before job start is separately measured: the server gates on
first PCM generation, not on an acoustic or native-playback acknowledgement.
A completed process alone cannot pass missing speech or file verification.

No microphone audio is captured. Original settings are restored on normal or
watchdog cleanup; outstanding owned jobs are cancelled on teardown. The complete
probe has a 240-second watchdog and a 170-second job/result wait after readiness.
Raw PCM payloads are omitted from retained events. This fixture does not measure
acoustic onset, general agent reliability or autonomous chat-to-job routing.
Root owns actual Windows launches; source review/check-only is not that evidence.

## Actual Windows result

`windows-native-completed.json` retains one 18-check, zero-failure execution.
Relative to submission, acknowledgment playback started at 534 ms, the native
job-start event arrived at 538 ms, first tool progress at 11,683 ms, completion at
15,566 ms, and result playback at 15,933 ms. Exclusive file creation and exact
byte readback passed, as did persisted-settings restoration. The launch record
identifies the executable and both external scripts. These are native playback
signals, not microphone-measured sound or a general reliability benchmark.
