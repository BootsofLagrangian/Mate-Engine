# Started navigation completion budget — independent root review

APPROVED after source/test inspection. Implementer: autonomy agent; reviewer: root.

The packaged Windows authored-idle run at `logs/windows-intent-authored/report.json`
received a valid Japanese reply and left-target intent, began actual walking, then
expired 24 pixels before arrival. First PCM was 3756 ms in this restarted-model run;
the dialogue hold, settle, turn and travel together outlived the original 30-second
command freshness. The failed 10/12 run is retained, not relabeled a success.

The director now keeps the original expiry for queued commands and starts a fixed
45-second completion deadline only when a fresh move is accepted by navigation.
This covers the native 6-second heading watchdog and 35-second travel watchdog
with a small margin. Repeated start acknowledgments cannot extend it, and started
moves cannot be requeued to reset their clock. Character changes, target expiry,
user cancellation and priority preemption retain authority.

The dedicated suite passes 9719 checks, including 11 new late-dispatch, bounded
completion, duplicate-start, target-expiry and stale-command cases. Root inspected
the expiry/resolve ordering, synchronous host dispatch and native interest
consumption: the host target observation is consumed immediately, while the
live director target remains subject to its own refreshed lifetime. No unrelated
conversation hold or movement speed was changed. Final Windows rerun remains
separate evidence.
