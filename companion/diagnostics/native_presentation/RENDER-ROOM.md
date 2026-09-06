# Native render room

The native transparent canvas is 1920×1760. The original 680×760 camera reference,
character pixel scale and MToon outline widths are kept separately. The character
has equal horizontal animation room; subtitles follow the rendered character.
Mouse passthrough still follows visible character/UI bounds, not the whole canvas.

Window persistence now records the character's global foot position. Keeping an
old window origin while adding render padding moved the character farther from
the perspective camera axis, creating both a position regression and additional
projective distortion. Legacy 680×760 saved positions are migrated through that
reference frame. New saved anchors on removed monitors fall back to a usable screen.

Actual exported Windows test `logs/windows-render-room-anchor-maxscale` passed
13 checks, with 96 viewport samples across authored wave, overhead stretch and
stretch in orthographic front and perspective yaw45/pitch30 views. Cheval at the
maximum selectable pet scale 1.25 retained at least 113px transparent margin.
These are owned native viewport readbacks, not screenshots of other applications.
PNG frames and exact executable/probe hashes are retained with each run.

[All six attempts](render-room-attempts.json) include the earlier failed crops;
increasing padding alone was not treated as sufficient evidence. Source projection
checks preserve the original pixels/metre for three rigs, including camera crops
and negative monitor coordinates. Independent outline and persistence reviews live
under `diagnostics/desktop_view/independent-spatial-review`.

Coverage is finite: these results do not establish every rig, animation, camera
zoom or desktop position. They also do not establish OS compositor alpha, mesh
collision avoidance, cloth quality or subjective motion naturalness. The larger
render target costs more GPU memory/fill than the original; no final desktop GPU
performance benchmark is claimed here.
