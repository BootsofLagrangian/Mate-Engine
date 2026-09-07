using UnityEngine;
// Restore last frame's companion offsets before sway/animation writers run.
[DefaultExecutionOrder(-30000)]
public class ChevalPoseReset : MonoBehaviour
{
    void Update() { if (ChevalCompanion.Instance != null) ChevalCompanion.Instance.RestorePose(); }
}
