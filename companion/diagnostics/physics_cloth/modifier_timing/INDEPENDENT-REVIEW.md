# Modifier time ownership: independent audit

**APPROVED as a diagnostic finding; a general production double-tick claim is withdrawn. No runtime change is proposed from this bounded test.** Godot 4.5.2 headless, fixed 60 Hz, one actual Cheval VRM and the installed addon were used. Passive SkeletonModifier3D observers immediately before and after the imported VRM modifier record the engine-supplied delta and actual Verlet-tail change without writing bones.

| Scheduling path | Steady animated frames | Actual modifier passes | Engine delta per frame |
| --- | ---: | ---: | --- |
| Automatic production MotionPlayer `_process` | 55 | 55 | 1/60 once |
| Coroutine writes avatar pose before awaiting `process_frame` | 55 | 110 | zero, then 1/60 |
| Held pose, either test | 25 | 25 | 1/60 once |

The explicit steady windows are loop steps 5–59 and 65–89; startup and the disable boundary are excluded. The automatic trial uses authored Cheval idle and normal MotionPlayer process priority, with gaze disabled. This is not a Windows full-host or every-action timing test. The coroutine trial's zero-time pass changes tails by up to 11.169 mm inside the steady window. This establishes actual integration during a pose refresh, not just duplicate notification counting.

Godot's pose setters mark modifier work dirty; internal process separately accumulates elapsed time. Deferred skeleton updates pass the accumulated delta to modifiers and then clear it. Depending on scheduling, a dirty-pose update can therefore receive zero before the timed pass. SkeletonModifier3D forwards that delta to its virtual method before emitting the parameterless completion signal. The relevant primary sources are [Skeleton3D 4.5.2](https://github.com/godotengine/godot/blob/4.5.2-stable/scene/3d/skeleton_3d.cpp) and [SkeletonModifier3D 4.5.2](https://github.com/godotengine/godot/blob/4.5.2-stable/scene/3d/skeleton_modifier_3d.cpp).

The installed addon connects that parameterless signal to `vrm_secondary.gd::_on_secondary_process_modification_processed`, substitutes the node's 1/60 delta, and runs the spring integrator for both passes. No explicit runtime skeleton `advance`/force-update call was found to explain the pair. The scheduling distinction is experimentally demonstrated by switching only the source-pose writer arrangement; it must not be generalized to the normal automatic MotionPlayer path, which has one steady pass here.

A future engine-delta-aware bridge should use `_process_modification_with_delta`. Zero-time refresh must reapply the current secondary pose without advancing Verlet history, drag, forces or collision dynamics. Merely forwarding zero to `do_process` is insufficient: the existing integrator includes a velocity/drag term independent of delta. Merely skipping all pose work can also lose the secondary pose after the engine restores source bones. This is an implementation boundary, not a reviewed patch. Do not compensate for this scheduling issue by retuning gravity.

The historical continuous cape candidate probe manually advances MotionPlayer from a coroutine and records two addon integrations per source frame. Its measured geometry remains real diagnostic evidence, but its timing and numeric jumps do not establish the automatic production path's behavior. A subsequent [automatic 22-second comparison](../cape_continuous_automatic/INDEPENDENT-REVIEW.md) confirms one pass per frame across authored idle, walk, turning and seated transitions; the sole zero-delta pass is model replacement at source frame 720. Candidate settings remain unapproved after the corrected comparison.

Exact executed probes, raw traces, logs, derived counts and dependency hashes are adjacent. The probes retain their executed `/tmp` paths: to reproduce, copy the three `.gd` files to `/tmp` and run each `review_modifier_delta_{trace,auto}.gd` using `./tools/Godot_v4.5.2-stable_linux.x86_64 --headless --fixed-fps 60 --path native --script /tmp/<filename>` from companion. Reports overwrite the matching `/tmp` JSON. Observer source is identical across trials.
