# Independent automatic cape review

**APPROVED: retain the diagnostic evidence and keep the existing imported settings. Candidate 1.2 is REJECTED for production adoption.** This corrected automatic-scheduling run supersedes the historical manual run for the temporal comparison. No runtime spring parameters were edited.

I reviewed the driver before launch and independently recomputed the callback/mesh results afterward. Source events run at priority -20, the real automatic MotionPlayer at -10, and diagnostic host placement at -5. Passive modifier observers receive engine-supplied delta; post-draw only records the paired viewport output. Both worlds receive the same scripted actions, transforms, clips and seed. Source and addon hashes match between run start and finish.

There are exactly 1,320 modifier callbacks per avatar, one per engine frame, and 660 synchronous sparse mesh comparisons. Of those passes, 1,319 receive engine delta 1/60; model replacement at source frame 720 receives one zero-delta pass. There is no extra steady integration. The addon still substitutes node delta at the replacement refresh, so this is a measured installed-addon reload behavior rather than proof that its zero-time semantics are correct. Source humanoid and world-transform discrepancies are exactly zero. Heading ranges from zero to 1.9198 radians during actual travel.

Independent parameter checks pass **384/384**: selected effective stiffness/gravity arrays match the documented source-relative mapping, their scales are one, imported drag/radii/collider identities are preserved, every nonselected chain is unchanged, and endpoint configuration survives reload and seated exit. See `independent-validation.json`, which includes exact raw/source hashes.

| Phase | Existing maximum tip step | Candidate maximum tip step |
| --- | ---: | ---: |
| Initial settling | 20.19 mm | 36.04 mm |
| Replacement settling | 17.45 mm | 33.26 mm |
| Seated entry | 34.71 mm | 47.74 mm |
| Seated exit | 26.09 mm | 71.19 mm |

The candidate exit maximum is at source frame 1147 on `Sp_Sh_Mantle0_L_04`, inside the authored rise rather than a boundary. The baseline maximum is at frame 1143 on `Sp_Sh_Mantle0_L_00`; maxima are across each condition's cape joints, not a claim that the same joint/frame has both values. I inspected paired capture indices 0570, 0573, 0574 and 0577, including the samples immediately around source 1147. They show differing cape configurations as the torso rises; the full-rate tail trace establishes the larger candidate jump.

During exit the sparse candidate-versus-baseline edge difference reaches 58.99%, its within-sample p95 reaches 34.83%, and minimum area ratio is 0.3558. No sampled normals oppose their baseline counterparts. These are cross-condition shape differences, not rest-mesh strain or proof of tearing/inversion. Bone segment error stays below 0.284 micrometres, which does not establish garment quality. The sample contains only 114 vertices / 38 Mantle-selected triangles, and this probe contains no chair, backrest or full Windows host. No body/furniture collision or full cloth acceptance follows.

The corrected run supports withholding the candidate despite some closer-hanging poses. It does not certify the existing cape as fully natural. Further tuning should address generic garment constraints and real interaction geometry rather than conceal missing constraints with stronger gravity. The historical two-pass result remains separately retained with its scheduling limitation; its larger 83.1 mm figure must not replace the corrected 71.2 mm result.
