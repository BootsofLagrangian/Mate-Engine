# Outcome callback reentrancy

The actual Windows `logs/text-scenario-computer-bilingual-ko-01` run contains duplicate Director expiry terminals for `object-use:obj_2:19564` and an empty-array `remove_at(0)` error. The Director emitted the queued outcome before removing its item. ObjectsHost cancellation synchronously reentered Director cancellation, removed the same item, and caused the outer code to remove it again.

The fix detaches queued and active ownership before notifying listeners. Snapshot iteration tolerates listeners removing other queued entries. Bulk cancellation reserves retiring IDs before callbacks, while preserving distinct work created by callbacks. Supersession rechecks the incoming ID after callbacks to prevent duplicate submission of that ID.

`test_outcome_reentrancy.gd` first reproduced eight failures across fourteen checks, including the observed empty-array error. Two additional tests reproduced retiring-ID reuse and duplicate incoming IDs before their follow-up guards. A final character-transition guard rejects reentrant submissions until the switch completes, preventing old-character work from surviving the cancellation callback. Final result: **18 checks, zero failures**. The existing Director suite reports **9,746 checks, zero failures**, with unchanged deterministic 16-minute idle distribution. Logs are retained here. The initial failing fixture had callback reference cycles; the final fixture disconnects its listeners and exits without those cleanup warnings.

This fixes duplicate terminal delivery and queue mutation errors. It does not establish why the original computer approach remained queued until expiry, nor claim successful computer use or new Windows acceptance.

Independent review: Astra Autonomy approved the final Director change, reran the focused 18 checks successfully, and verified the character admission guard resets after the switch. Exact source/test hashes are recorded in `source-hashes.json`.
