# Default scene exploration review

REVISE pending two lifecycle corrections. Independent read-only source review covers SceneInterests, generic SceneNavigationHost completion/ground latching, Living dispatch and the Director alternate-target selection.

1. Living's explicit non-scene move path calls `release_to_contact()` while a generic scene route can still own a completion callback. That method cancels navigation and clears holding but leaves the callback. Subsequent `cancel()` returns early because holding is false. A later furniture route can therefore inherit and notify the stale generic callback instead of notifying ObjectsHost at arrival. Explicit departure must resolve and clear old ownership exactly once before releasing the ground latch.
2. Projection availability and surface mode are checked only in the inactive-navigation branch. Active mode changes can reach a null canonical camera or keep moving until a later interest refresh. Mandatory release guards must apply before the active/idle split.

The six stable targets and geometry/view cache do not invoke an LM. Per-frame committed placement retains workarea validation; candidate admission alone is not relied upon for final safety. Director's alternate floor/surface selection retains the existing quiet schedule and cooldown. Ordinary voice interruption preserving the current canonical ground point is coherent, provided explicit departure and mode shutdown clear ownership correctly. Existing local counts and the planned Windows idle run remain separate evidence.

## Corrected lifecycle follow-up

APPROVED for the bounded source scope. `release_to_contact` now clears the pending generic owner before callback invocation and resolves it even if an earlier caller already released the foot. Explicit non-scene departure uses the superseded outcome. Internal cancellation suppresses duplicate notification and then delivers the terminal event once. Direct release also stops the owned scene walk loop before handing control back, so a rejected replacement cannot leave it walking in place.

Mandatory drag, projection availability, autonomy-enabled and surface-mode checks now run before the active/idle branch. Ordinary foreground interruption retains the canonical idle ground point while resolving the old request; explicit mode/character/disable departure releases it. The implementation owner's 268-check real-rig lifecycle log reports zero failures, including active generic→rejected legacy→furniture ownership, cleared walk playback and active mode-exit cases. This review verifies the source corrections; actual Windows idle frequency, visuals and sustained natural movement remain separate acceptance work.
