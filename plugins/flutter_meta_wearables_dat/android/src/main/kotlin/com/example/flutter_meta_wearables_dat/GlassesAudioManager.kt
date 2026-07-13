package com.example.flutter_meta_wearables_dat

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Build
import androidx.core.app.ActivityCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext

enum class AudioMode { IDLE, LISTENING, SPEAKING }

enum class AudioRoute { NONE, A2DP_SPEAKER, HFP_MIC_SPEAKER }

data class AudioSessionState(
    val mode: AudioMode,
    val route: AudioRoute,
    val isRouteSettled: Boolean,
)

/**
 * Owns the AudioManager/AudioRecord/AudioTrack lifecycle for talking to the
 * glasses' microphone and speaker over standard Bluetooth profiles.
 *
 * There is no DAT API for this: mic capture goes over HFP/SCO (8kHz mono,
 * bidirectional) and speaker playback over A2DP (44.1/48kHz stereo, output
 * only). The two profiles are mutually exclusive on the underlying
 * Bluetooth Classic link, so [startListening] and [speak] switch modes
 * rather than running concurrently.
 */
class GlassesAudioManager(private val context: Context) {
    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var captureJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val _state = MutableStateFlow(AudioSessionState(AudioMode.IDLE, AudioRoute.NONE, false))
    val state: StateFlow<AudioSessionState> = _state

    /** Invoked with raw PCM16 mono chunks while listening. */
    var onAudioChunk: ((ByteArray, Int, Long) -> Unit)? = null

    companion object {
        const val HFP_SAMPLE_RATE = 8000 // fixed by the Bluetooth HFP/SCO profile
        private const val CHUNK_MS = 40 // ~emit interval; tune for your STT pipeline
        private const val ROUTE_SETTLE_DELAY_MS = 1500L
    }

    fun hasAudioPermissions(): Boolean {
        val record = ActivityCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        val bt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        return record && bt
    }

    // ---------- LISTENING (HFP mic capture) ----------

    /**
     * Routes audio to the glasses' Bluetooth SCO (HFP) device and starts
     * streaming raw PCM16 mono @ 8kHz from a VOICE_COMMUNICATION source.
     *
     * IMPORTANT ORDERING: callers combining this with a DAT camera stream
     * must wait for [state].isRouteSettled == true BEFORE starting/resuming
     * that stream, or the audio route can fail silently.
     */
    @Suppress("MissingPermission")
    fun startListening(): Boolean {
        if (!hasAudioPermissions()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false // setCommunicationDevice needs API 31+

        val scoDevice = audioManager.availableCommunicationDevices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        } ?: return false

        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        val routed = audioManager.setCommunicationDevice(scoDevice)
        if (!routed) return false

        _state.value = AudioSessionState(AudioMode.LISTENING, AudioRoute.HFP_MIC_SPEAKER, false)

        val minBuf = AudioRecord.getMinBufferSize(
            HFP_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufSize = maxOf(minBuf, HFP_SAMPLE_RATE * 2 * CHUNK_MS / 1000)
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            HFP_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufSize,
        )
        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            stopListening()
            return false
        }
        audioRecord?.startRecording()

        // Give the BT SCO route ~1.5-2s to settle before trusting it.
        captureJob = scope.launch {
            delay(ROUTE_SETTLE_DELAY_MS)
            val settled = audioManager.communicationDevice?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            _state.value = AudioSessionState(AudioMode.LISTENING, AudioRoute.HFP_MIC_SPEAKER, settled)
            if (!settled) {
                stopListening()
                return@launch
            }
            val buffer = ByteArray(bufSize)
            while (isActive) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                if (read > 0) {
                    onAudioChunk?.invoke(buffer.copyOf(read), HFP_SAMPLE_RATE, System.currentTimeMillis())
                }
            }
        }
        return true
    }

    fun stopListening() {
        captureJob?.cancel()
        captureJob = null
        audioRecord?.let {
            try {
                it.stop()
            } catch (_: Exception) {
                // Already stopped/released — nothing to clean up.
            }
            it.release()
        }
        audioRecord = null
        clearCommunicationDevice()
        _state.value = AudioSessionState(AudioMode.IDLE, AudioRoute.NONE, false)
    }

    // ---------- SPEAKING (A2DP playback) ----------

    /**
     * Plays PCM16 audio through the glasses speaker via the high-quality A2DP
     * route. Automatically tears down any active HFP session first, since
     * they're mutually exclusive.
     */
    suspend fun speak(pcm: ByteArray, sampleRateHz: Int) = withContext(Dispatchers.IO) {
        if (_state.value.mode == AudioMode.LISTENING) {
            stopListening()
        }
        audioManager.mode = AudioManager.MODE_NORMAL
        _state.value = AudioSessionState(AudioMode.SPEAKING, AudioRoute.A2DP_SPEAKER, false)

        val minBuf = AudioTrack.getMinBufferSize(
            sampleRateHz,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA) // media usage -> eligible for A2DP routing
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val format = AudioFormat.Builder()
            .setSampleRate(sampleRateHz)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .build()
        audioTrack = AudioTrack(
            attributes,
            format,
            maxOf(minBuf, pcm.size),
            AudioTrack.MODE_STATIC,
            AudioManager.AUDIO_SESSION_ID_GENERATE,
        )
        audioTrack?.write(pcm, 0, pcm.size)

        // Confirm A2DP is actually the active output before/while playing.
        val hasA2dp = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
        }
        _state.value = AudioSessionState(AudioMode.SPEAKING, AudioRoute.A2DP_SPEAKER, hasA2dp)
        audioTrack?.play()

        val durationMs = (pcm.size / 2.0 / sampleRateHz * 1000).toLong() // 16-bit mono
        delay(durationMs + 150)

        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
        _state.value = AudioSessionState(AudioMode.IDLE, AudioRoute.NONE, false)
    }

    fun stopSpeaking() {
        audioTrack?.let {
            try {
                it.pause()
                it.flush()
                it.stop()
            } catch (_: Exception) {
                // Already stopped/released — nothing to clean up.
            }
            it.release()
        }
        audioTrack = null
        _state.value = AudioSessionState(AudioMode.IDLE, AudioRoute.NONE, false)
    }

    fun release() {
        stopListening()
        stopSpeaking()
        clearCommunicationDevice()
        scope.cancel()
    }

    /** Strips a 44-byte RIFF/WAVE header, detected via the `RIFF`/`WAVE` magic bytes. */
    fun stripWavHeaderIfPresent(bytes: ByteArray): ByteArray {
        val isWav = bytes.size > 44 &&
            bytes[0] == 'R'.code.toByte() && bytes[1] == 'I'.code.toByte() &&
            bytes[2] == 'F'.code.toByte() && bytes[3] == 'F'.code.toByte() &&
            bytes[8] == 'W'.code.toByte() && bytes[9] == 'A'.code.toByte() &&
            bytes[10] == 'V'.code.toByte() && bytes[11] == 'E'.code.toByte()
        return if (isWav) bytes.copyOfRange(44, bytes.size) else bytes
    }

    private fun clearCommunicationDevice() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        }
        audioManager.mode = AudioManager.MODE_NORMAL
    }
}
