using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;
using VRM;

/// <summary>Local Qwen/STT/SoVITS bridge; F8 toggles the panel. Audio capture is explicit.</summary>
[DefaultExecutionOrder(30000)]
public class ChevalCompanion : MonoBehaviour
{
    [Serializable] public class Settings { public bool enabled = true; public string server = "http://127.0.0.1:8765"; }
    [Serializable] class Request { public string text; public string session; public bool voice = true; }
    [Serializable] class Reply { public string text; public string emotion; public string gesture; public string audio_url; public string voice_error; }
    [Serializable] class StreamEvent { public string type, text, emotion, gesture, pcm, message, voice_error; public int sample_rate; }
    [Serializable] class Transcript { public string text; }
    [Serializable] class MotionLibrary { public Motion[] motions; }
    [Serializable] class Motion { public string name; public float duration; public Track[] tracks; }
    [Serializable] class Track { public string bone; public Key[] keys; }
    [Serializable] class Key { public float time, x, y, z; public Vector3 Rotation => new Vector3(x, y, z); }
    readonly Dictionary<string, Motion> motions = new Dictionary<string, Motion>();
    readonly Dictionary<string, HumanBodyBones> bones = new Dictionary<string, HumanBodyBones> {
        {"head",HumanBodyBones.Head},{"neck",HumanBodyBones.Neck},{"spine",HumanBodyBones.Spine},{"chest",HumanBodyBones.Chest},
        {"leftUpperArm",HumanBodyBones.LeftUpperArm},{"rightUpperArm",HumanBodyBones.RightUpperArm},
        {"leftLowerArm",HumanBodyBones.LeftLowerArm},{"rightLowerArm",HumanBodyBones.RightLowerArm}
    };
    public static ChevalCompanion Instance { get; private set; }
    public bool IsBusy => busy || recording;
    Settings settings;
    readonly string session = Guid.NewGuid().ToString("N");
    string input = "", transcript = "", status = "Companion ready · F8", gesture = "idle", emotion = "neutral";
    bool busy, visible = true, recording;
    float actionStart, recordingStart;
    AudioSource voice;
    UnityWebRequest activeChat;
    ChevalPcm pcm;
    bool streamComplete;
    float drainedAt = -1;
    AudioClip microphoneClip;
    string microphoneDevice;
    VRMLoader loader;
    GameObject avatar;
    Animator animator;
    VRMBlendShapeProxy expressions;
    readonly Dictionary<Transform, Quaternion> applied = new Dictionary<Transform, Quaternion>();
    readonly float[] samples = new float[256];
    Vector2 scroll;

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void Bootstrap()
    {
        if (Instance != null) return;
        string path = Path.Combine(Application.streamingAssetsPath, "cheval-companion.json");
        if (!File.Exists(path)) return;
        try {
            var config = JsonUtility.FromJson<Settings>(File.ReadAllText(path));
            if (config == null || !config.enabled) return;
            var go = new GameObject("Cheval Companion");
            var bridge = go.AddComponent<ChevalCompanion>();
            bridge.settings = config;
            DontDestroyOnLoad(go);
        } catch (Exception e) { Debug.LogError("[Companion] " + e.Message); }
    }

    void Awake() { Instance = this; gameObject.AddComponent<ChevalPoseReset>(); voice = gameObject.AddComponent<AudioSource>(); voice.spatialBlend = 0; }
    IEnumerator Start()
    {
        string motionPath = Path.Combine(Application.streamingAssetsPath, "cheval-motions.json");
        try {
            var library = JsonUtility.FromJson<MotionLibrary>(File.ReadAllText(motionPath));
            foreach (var motion in library.motions) motions[motion.name] = motion;
        } catch (Exception e) { Debug.LogError("[Companion motions] " + e.Message); }
        yield return null;
        loader = FindFirstObjectByType<VRMLoader>();
        if (loader == null) { status = "VRMLoader missing in this scene"; yield break; }
        using (var req = UnityWebRequest.Get(settings.server.TrimEnd('/') + "/avatar")) {
            req.timeout = 60;
            yield return req.SendWebRequest();
            if (req.result != UnityWebRequest.Result.Success) { status = "Start companion/run.py first: " + req.error; yield break; }
            var data = req.downloadHandler.data;
            if (data.Length < 20 || Encoding.ASCII.GetString(data, 0, 4) != "glTF") { status = "Invalid VRM response"; yield break; }
            string path = Path.Combine(Application.persistentDataPath, "cheval-grand.vrm");
            try { File.WriteAllBytes(path, data); loader.LoadVRM(path); }
            catch (Exception e) { status = e.Message; }
        }
    }

    public void Send(string message, Action<string> completed = null)
    {
        if (busy || recording || string.IsNullOrWhiteSpace(message)) return;
        StartCoroutine(Chat(message, completed));
    }
    IEnumerator Chat(string message, Action<string> completed)
    {
        busy = true; voice.Stop(); streamComplete = false; drainedAt = -1;
        if (voice.clip != null) Destroy(voice.clip);
        pcm = new ChevalPcm(); var turnPcm = pcm;
        status = "Thinking…"; transcript += "\nYou: " + message;
        string prefix = transcript + "\nCheval: "; string answer = "";
        bool done = false; string failure = null;
        var handler = new ChevalStream(line => {
            var ev = JsonUtility.FromJson<StreamEvent>(line);
            if (ev.type == "text") { answer = ev.text; transcript = prefix + answer; scroll.y = float.MaxValue; }
            else if (ev.type == "action") PlayMotion(ev.gesture, ev.emotion);
            else if (ev.type == "audio") {
                turnPcm.Enqueue(ev.pcm, ev.sample_rate);
                if (voice.clip == null && turnPcm.Count >= 1920) {
                    voice.clip = AudioClip.Create("Cheval stream", 32000, 1, 32000, true, turnPcm.Read);
                    voice.loop = true; voice.Play(); status = "Speaking…";
                }
            }
            else if (ev.type == "error" || ev.type == "voice_error") failure = ev.message;
            else if (ev.type == "done") { done = true; answer = ev.text ?? answer; if (!string.IsNullOrEmpty(ev.voice_error)) failure = ev.voice_error; }
        });
        using (var req = JsonPost("/chat/stream", JsonUtility.ToJson(new Request { text = message, session = session }))) {
            req.downloadHandler.Dispose(); req.downloadHandler = handler; activeChat = req;
            yield return req.SendWebRequest(); activeChat = null;
            if (req.result != UnityWebRequest.Result.Success) failure = handler.Failure ?? req.error;
            else if (!done) failure = "Response stream ended early";
        }
        streamComplete = true;
        if (failure != null) { voice.Stop(); status = failure; }
        else {
            // Very short utterances may end before reaching the normal prebuffer.
            if (voice.clip == null && turnPcm.Count > 0) {
                voice.clip = AudioClip.Create("Cheval stream", 32000, 1, 32000, true, turnPcm.Read);
                voice.loop = true; voice.Play();
            }
            status = "Ready";
        }
        if (transcript.Length > 16000) transcript = transcript.Substring(transcript.Length - 16000);
        busy = false; completed?.Invoke(failure ?? answer);
    }
    void StopSpeech()
    {
        activeChat?.Abort(); voice.Stop(); streamComplete = true;
    }
    UnityWebRequest JsonPost(string endpoint, string json)
    {
        var req = new UnityWebRequest(settings.server.TrimEnd('/') + endpoint, "POST");
        req.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(json)); req.downloadHandler = new DownloadHandlerBuffer();
        req.SetRequestHeader("Content-Type", "application/json"); req.timeout = 300; return req;
    }
    public void RestorePose()
    {
        foreach (var pair in applied) if (pair.Key != null) pair.Key.localRotation *= Quaternion.Inverse(pair.Value);
        applied.Clear();
    }
    void OnDisable() { RestorePose(); }
    void Update()
    {
        if (streamComplete && voice.isPlaying && pcm != null && pcm.Count == 0) {
            if (drainedAt < 0) drainedAt = Time.unscaledTime;
            // Let Unity's already-read DSP buffer drain before stopping the source.
            AudioSettings.GetDSPBufferSize(out int bufferLength, out int buffers);
            if (Time.unscaledTime - drainedAt > (float)(bufferLength * buffers) / AudioSettings.outputSampleRate + .1f) voice.Stop();
        } else drainedAt = -1;
        if (Input.GetKeyDown(KeyCode.F8)) visible = !visible;
        if (recording && Time.realtimeSinceStartup - recordingStart >= 29f) StopMicrophone();
        if (loader == null) loader = FindFirstObjectByType<VRMLoader>();
        var current = loader != null ? loader.GetCurrentModel() : null;
        if (current != avatar) {
            avatar = current; animator = avatar != null ? avatar.GetComponent<Animator>() : null;
            expressions = avatar != null ? avatar.GetComponent<VRMBlendShapeProxy>() : null;
        }
    }
    void Offset(HumanBodyBones bone, Vector3 degrees)
    {
        if (animator == null || !animator.isHuman) return;
        var t = animator.GetBoneTransform(bone); if (t == null) return;
        var q = Quaternion.Euler(degrees); t.localRotation *= q; applied[t] = q;
    }
    void LateUpdate()
    {
        float age = Time.time - actionStart;
        motions.TryGetValue(gesture ?? "idle", out Motion motion);
        float duration = motion != null ? motion.duration : 4f;
        float envelope = Mathf.Clamp01(age / .35f) * Mathf.Clamp01((duration - age) / .6f);
        if (motion != null && age >= 0 && age < duration) {
            foreach (var track in motion.tracks) {
                if (bones.TryGetValue(track.bone, out HumanBodyBones bone)) Offset(bone, Sample(track, age));
            }
        }
        if (expressions != null) {
            float rms = 0;
            if (voice.isPlaying) { voice.GetOutputData(samples, 0); foreach (float s in samples) rms += s * s; rms = Mathf.Sqrt(rms / samples.Length); }
            expressions.ImmediatelySetValue(BlendShapeKey.CreateFromPreset(BlendShapePreset.A), Mathf.Clamp01(rms * 5));
            expressions.ImmediatelySetValue(BlendShapeKey.CreateFromPreset(BlendShapePreset.Joy), emotion == "happy" ? .45f * envelope : 0);
            expressions.ImmediatelySetValue(BlendShapeKey.CreateFromPreset(BlendShapePreset.Sorrow), emotion == "sad" ? .35f * envelope : 0);
            expressions.ImmediatelySetValue(BlendShapeKey.CreateFromPreset(BlendShapePreset.Fun), emotion == "relaxed" ? .35f * envelope : 0);
        }
    }
    public void PlayMotion(string name, string expression = "relaxed")
    {
        gesture = motions.ContainsKey(name ?? "idle") ? name : "idle";
        emotion = expression; actionStart = Time.time;
    }
    static Vector3 Sample(Track track, float time)
    {
        var keys = track.keys;
        if (keys == null || keys.Length == 0) return Vector3.zero;
        if (time <= keys[0].time) return keys[0].Rotation;
        for (int i = 1; i < keys.Length; i++) {
            if (time <= keys[i].time) {
                float u = Mathf.InverseLerp(keys[i - 1].time, keys[i].time, time);
                u = u * u * (3f - 2f * u);
                return Vector3.LerpUnclamped(keys[i - 1].Rotation, keys[i].Rotation, u);
            }
        }
        return keys[keys.Length - 1].Rotation;
    }
    void StartMicrophone()
    {
        if (Microphone.devices.Length == 0) { status = "No microphone found"; return; }
        voice.Stop(); microphoneDevice = Microphone.devices[0];
        microphoneClip = Microphone.Start(microphoneDevice, false, 30, 16000);
        if (microphoneClip == null) { status = "Microphone permission/device unavailable"; return; }
        recordingStart = Time.realtimeSinceStartup; recording = true; status = "Listening…";
    }
    void StopMicrophone()
    {
        if (!recording) return;
        int frames = Microphone.GetPosition(microphoneDevice); Microphone.End(microphoneDevice); recording = false;
        if (frames <= 0) { if (microphoneClip != null) Destroy(microphoneClip); microphoneClip = null; status = "No audio captured"; return; }
        float[] data = new float[frames * microphoneClip.channels]; microphoneClip.GetData(data, 0);
        int channels = microphoneClip.channels, rate = microphoneClip.frequency;
        Destroy(microphoneClip); microphoneClip = null;
        StartCoroutine(Transcribe(Wav(data, channels, rate)));
    }
    IEnumerator Transcribe(byte[] wav)
    {
        busy = true; status = "Transcribing…";
        var form = new WWWForm(); form.AddBinaryData("audio", wav, "recording.wav", "audio/wav");
        string text = null;
        using (var req = UnityWebRequest.Post(settings.server.TrimEnd('/') + "/stt", form)) {
            req.timeout = 180; yield return req.SendWebRequest();
            if (req.result == UnityWebRequest.Result.Success) {
                try { text = JsonUtility.FromJson<Transcript>(req.downloadHandler.text).text; }
                catch (Exception e) { status = e.Message; }
            } else status = req.error;
        }
        busy = false;
        if (!string.IsNullOrWhiteSpace(text)) Send(text);
    }
    static byte[] Wav(float[] samples, int channels, int rate)
    {
        using (var stream = new MemoryStream()) using (var w = new BinaryWriter(stream)) {
            w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + samples.Length * 2); w.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
            w.Write(16); w.Write((short)1); w.Write((short)channels); w.Write(rate); w.Write(rate * channels * 2); w.Write((short)(channels * 2)); w.Write((short)16);
            w.Write(Encoding.ASCII.GetBytes("data")); w.Write(samples.Length * 2);
            foreach (float sample in samples) w.Write((short)(Mathf.Clamp(sample, -1, 1) * 32767));
            return stream.ToArray();
        }
    }
    void OnGUI()
    {
        if (!visible) return;
        GUILayout.BeginArea(new Rect(20, 50, Mathf.Min(440, Screen.width - 40), Mathf.Min(500, Screen.height - 70)), GUI.skin.box);
        GUILayout.Label("Cheval Grand · Local companion (F8)");
        scroll = GUILayout.BeginScrollView(scroll, GUILayout.Height(250)); GUILayout.Label(transcript); GUILayout.EndScrollView();
        GUILayout.Label(status); GUI.enabled = !busy && !recording; input = GUILayout.TextField(input, 2000);
        if (GUILayout.Button("Send")) { Send(input); input = ""; }
        GUI.enabled = !busy;
        if (GUILayout.Button(recording ? "Stop recording" : "Microphone")) { if (recording) StopMicrophone(); else StartMicrophone(); }
        GUI.enabled = true;
        if (GUILayout.Button("Stop speech")) StopSpeech();
        GUILayout.BeginHorizontal();
        foreach (string name in new[] { "nod", "shy", "wave", "bow", "stretch" })
            if (GUILayout.Button(name)) PlayMotion(name);
        GUILayout.EndHorizontal();
        GUILayout.EndArea();
    }
    void OnDestroy()
    {
        activeChat?.Abort();
        if (recording) Microphone.End(microphoneDevice);
        if (microphoneClip != null) Destroy(microphoneClip);
        if (voice != null && voice.clip != null) Destroy(voice.clip);
        if (Instance == this) Instance = null;
    }
}
