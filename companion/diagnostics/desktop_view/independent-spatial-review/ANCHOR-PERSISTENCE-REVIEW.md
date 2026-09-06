# Independent render-anchor persistence review

Verdict: **APPROVED for the bounded anchor save/restore and legacy migration change**, after the explicit-anchor visibility correction. Canvas containment, locomotion, seated choreography and concurrent main changes remain outside scope.

`_save_window_position` retains the native origin for compatibility and records the character's actual projected stable foot in global desktop pixels when loaded (default local foot otherwise). `_restore_window_position` delegates to a pure helper that interprets old origin-only records in the 680×760 reference canvas, reconstructs the global foot and subtracts the current render-canvas foot. Newly saved explicit anchors therefore do not move merely because render padding changes. The current view still owns actual avatar reprojection.

Review found that validating an explicit anchor through legacy rectangle intersection alone could retain a foot on a removed adjacent monitor: the fictitious 680×760 rectangle might overlap a current monitor even while the entire character was outside it. The owner corrected this before the independent regression executed. Explicit anchors must now be finite and lie in a current workarea (one-pixel allowance for exact floor/right boundaries), otherwise they use the normal fallback. Origin-only legacy records retain their prior rectangle-intersection behavior.

The reviewer-authored `test_render_anchor.gd` passed **24 checks** across 1160×1120, 1600×1440 and 1920×1760 render sizes. Cases cover stable positive/negative/fractional anchors, negative legacy origins, removed adjacent monitor fallback, exact bottom workarea edge, an unsaved flag overriding stale coordinates and non-finite explicit coordinates. Fractional positions permit the unavoidable integer native-origin rounding (<0.71 px).

`render-anchor-initial-test.log` is retained for transparency: it ran after the owner's visibility fix had already landed and failed only because its initial non-finite-anchor expectation still required legacy fallback. The corrected safety expectation uses the default location. It is not a before-fix reproduction of the removed-monitor defect.

Main save/restore methods were inspected, while the new automated test directly exercises the pure helper without changing user settings or creating a window. Actual Windows persistence, multi-monitor movement and rendered motion containment still require the parent's native checkpoint. Exact source/test hashes and the final result log are adjacent to this review.
