# Independent mini-character mouth review

Reviewer: `astra_prop_design`, 2026-09-06. Verdict: **REVISE** for the reviewed geometry-crossfade candidate; replacement single-mouth-surface candidate is pending review.

Inspected `extract_mini.py` mouth atlas preparation, persistent skin cover and neutral/vowel mesh construction. Visually inspected front and 45-degree closeups for both Mambo and Hachimi in `/tmp/meme-mouth-final-front` and `/tmp/meme-mouth-final-45`: neutral and aa at 0.3/0.6/1.0 (front Mambo 0.6 and Hachimi 0.3 were not inspected in this first pass). These directory names predate the next candidate and do not imply final approval.

The opaque skin cover fixes the visible dark mouth cavity in these samples, including the 45-degree view. Neutral mouths look coherent. However, aa at 0.6 shows two curved mouth contours with skin-colored fill, while 0.3 and 1.0 show a pink mouth interior. Thus increasing the expression weight produces a visible regression at an ordinary intermediate speech weight. This blocks acceptance of the current partial-vowel rendering even though the hole is covered.

The converter simultaneously shrinks the textured neutral mouth and expands a separate textured vowel surface. Their overlapping visible artwork is consistent with the observed double contours. The implementer independently identified the same defect and is replacing this construction with one visible mouth surface and shape targets; that replacement has not yet been reviewed here.

This review covers the supplied Linux rendered static face samples and source construction only. It does not establish real-time speech continuity, Windows renderer parity, full head-angle coverage, body motion quality or redistribution rights. These are user-local game mini assets, not newly authored or independently licensed character models.

## Replacement candidate review

Final follow-up verdict: **APPROVED for the supplied static mouth samples**, superseding the geometry-crossfade rejection above. Read the new single-mouth-surface construction and inspected 24 closeups under `/tmp/meme-mouth-final2-front` and `/tmp/meme-mouth-final2-45`. Front coverage: Mambo neutral, aa 0.3/0.6/1, ih 1, ou 1, ee 0.6, oh 0.6; Hachimi neutral, aa 0.6, ih 0.6, ou 1, ee 1, oh 0.6. At 45 degrees: Mambo neutral, aa 0.3/0.6/1, ih 0.6, ee 1; Hachimi neutral, aa 0.6, ou 0.6, oh 1.

The dark void and double contour are absent in these samples. Pink fill remains visible across aa 0.3→0.6→1, with a single outline and increasing aperture. Neutral is now a nearly straight closed line rather than the earlier curved smile; this is a visible expression change, not an exact recreation of all original atlas expressions. The five vowel morphs deform one aa-artwork surface over a permanent skin cover. The quadratic fitted surface with 2mm outward clearance provides a source-level reason the partial morphs no longer intersect the cover in the reviewed views. No new blocker in this bounded mouth review. Blink modification was not reviewed here.

Reviewed current file SHA-256:

- Mambo VRM: `42f3fba3b12d22a4019661206f6c04f3b8b51206b6637fa46d6bb5951fb5cae7`
- Hachimi VRM: `521f8f33c9b8e17f473dbe56982b9537d261686cbf5ed055e9f6c90027604d1d`
- Converter: `cf0e5582f7ee6ceb6ae0b3bcead5f1922604b19cfb7b6dc97c079720ab851c28`

Windows captures, continuous speech transitions and other angles remain outside this follow-up's inspected evidence. Earlier failure evidence above is retained.

## Dry texture follow-up

2026-09-07: **APPROVED bounded dry appearance/mouth presentation** after inspecting eight aa=0.6 closeups: both characters, front and 45°, in `/tmp/meme-dry-front`, `/tmp/meme-dry-45`, `logs/meme-dry-windows-front`, and `logs/meme-dry-windows-45`. Hair/body droplets are absent, the clean source palette is readable, and each sampled mouth retains one outline with uninterrupted pink fill. The supplied Windows and Linux views show comparable appearance. This does not extend the review to uninspected vowels, blink continuity, spring dynamics or a whole speech sequence.

The asset owner reports subsequent spring-metadata changes after these dry captures; current on-disk VRM hashes consequently differ from the earlier reviewed wet candidate. This appendix approves the listed images and does not claim those captures prove byte identity with a later metadata revision. Previous hash records and failed geometry-crossfade evidence above are retained.
