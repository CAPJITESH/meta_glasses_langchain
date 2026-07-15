package com.example.flutter_meta_wearables_dat

import android.content.Context
import android.graphics.Bitmap
import com.meta.wearable.dat.camera.Stream
import com.meta.wearable.dat.camera.addStream
import com.meta.wearable.dat.camera.removeStream
import com.meta.wearable.dat.camera.types.PhotoData
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.VideoFrame
import com.meta.wearable.dat.camera.types.VideoQuality
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.AutoDeviceSelector
import com.meta.wearable.dat.core.session.DeviceSession
import com.meta.wearable.dat.core.session.DeviceSessionState
import android.util.Log
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

enum class CameraConnectionState { IDLE, CONNECTING, CONNECTED, STREAMING, ERROR }

/**
 * Wraps the real Meta DAT camera API (`Wearables` -> `DeviceSession` ->
 * `Stream`, verified against the v0.8 Android API reference) so the Flutter
 * plugin class only has to deal with a small connect/stream/capture surface.
 *
 * Device pairing itself happens out-of-band through the Meta AI companion
 * app + developer-mode toggle — this class only auto-selects among already
 * paired/connected devices via [AutoDeviceSelector].
 */
class GlassesCameraManager(private val context: Context) {
    companion object {
        private const val TAG = "GlassesCameraManager"
    }

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private var initialized = false
    private var session: DeviceSession? = null
    private var stream: Stream? = null
    private var sessionWatchJob: Job? = null
    private var streamWatchJob: Job? = null

    private val _connectionState = MutableStateFlow(CameraConnectionState.IDLE)
    val connectionState: StateFlow<CameraConnectionState> = _connectionState

    /** Invoked with each frame while a stream is active. */
    var onVideoFrame: ((VideoFrame) -> Unit)? = null

    fun connect(): Boolean {
        Log.d(TAG, "connect() called, initialized=$initialized")
        if (!initialized) {
            val initOk = Wearables.initialize(context).fold(
                onSuccess = {
                    Log.d(TAG, "Wearables.initialize() succeeded")
                    true
                },
                onFailure = { error, _ ->
                    Log.e(TAG, "Wearables.initialize() FAILED: $error")
                    false
                },
            )
            if (!initOk) {
                Log.e(TAG, "connect() aborting — SDK init failed")
                _connectionState.value = CameraConnectionState.ERROR
                return false
            }
            initialized = true
        }

        _connectionState.value = CameraConnectionState.CONNECTING
        Log.d(TAG, "Creating session with AutoDeviceSelector...")
        val newSession = Wearables.createSession(AutoDeviceSelector()).fold(
            onSuccess = {
                Log.d(TAG, "createSession() succeeded: $it")
                it
            },
            onFailure = { error, _ ->
                Log.e(TAG, "createSession() FAILED: $error")
                null
            },
        )
        if (newSession == null) {
            Log.e(TAG, "connect() aborting — no session (no paired device?)")
            _connectionState.value = CameraConnectionState.ERROR
            return false
        }
        session = newSession
        Log.d(TAG, "Starting session...")
        newSession.start()

        sessionWatchJob?.cancel()
        sessionWatchJob = newSession.state
            .onEach { sessionState ->
                Log.d(TAG, "Session state changed: $sessionState")
                _connectionState.value = when (sessionState) {
                    DeviceSessionState.STARTED ->
                        if (stream != null) CameraConnectionState.STREAMING else CameraConnectionState.CONNECTED
                    DeviceSessionState.STARTING -> CameraConnectionState.CONNECTING
                    else -> CameraConnectionState.IDLE
                }
            }
            .launchIn(scope)
        newSession.errors
            .onEach { error ->
                Log.e(TAG, "Session error: $error")
                _connectionState.value = CameraConnectionState.ERROR
            }
            .launchIn(scope)
        return true
    }

    fun disconnect() {
        streamWatchJob?.cancel()
        streamWatchJob = null
        stream?.close()
        stream = null
        sessionWatchJob?.cancel()
        sessionWatchJob = null
        // Only one stream may exist per session at a time — remove it at the
        // session level too, not just close()ing the local Stream handle, or
        // a later addStream() on a fresh session could see stale state.
        session?.removeStream()
        session?.stop()
        session = null
        _connectionState.value = CameraConnectionState.IDLE
    }

    /** [videoQuality] is the wire-format name of [VideoQuality] (e.g. "MEDIUM"). */
    fun startStream(videoQuality: String, frameRate: Int, compressVideo: Boolean): Boolean {
        val activeSession = session ?: return false
        val quality = try {
            VideoQuality.valueOf(videoQuality)
        } catch (_: IllegalArgumentException) {
            VideoQuality.MEDIUM
        }
        val config = StreamConfiguration(
            videoQuality = quality,
            frameRate = frameRate,
            compressVideo = compressVideo,
        )
        val newStream = activeSession.addStream(config).fold(
            onSuccess = { it },
            onFailure = { _, _ -> null },
        )
        if (newStream == null) {
            _connectionState.value = CameraConnectionState.ERROR
            return false
        }
        stream = newStream

        streamWatchJob?.cancel()
        streamWatchJob = newStream.videoStream
            .onEach { frame -> onVideoFrame?.invoke(frame) }
            .launchIn(scope)
        newStream.errorStream
            .onEach { _connectionState.value = CameraConnectionState.ERROR }
            .launchIn(scope)

        val started = newStream.start().fold(
            onSuccess = { true },
            onFailure = { _, _ -> false },
        )
        if (!started) {
            _connectionState.value = CameraConnectionState.ERROR
            return false
        }
        _connectionState.value = CameraConnectionState.STREAMING
        return true
    }

    fun stopStream() {
        streamWatchJob?.cancel()
        streamWatchJob = null
        stream?.stop()
        stream?.close()
        stream = null
        session?.removeStream()
        if (_connectionState.value == CameraConnectionState.STREAMING) {
            _connectionState.value = CameraConnectionState.CONNECTED
        }
    }

    /** Returns (bytes, isHeic), or null if there's no active stream or capture failed. */
    suspend fun capturePhoto(): Pair<ByteArray, Boolean>? {
        val activeStream = stream ?: return null
        val photo = activeStream.capturePhoto().fold(
            onSuccess = { it },
            onFailure = { _, _ -> null },
        ) ?: return null

        return when (photo) {
            is PhotoData.HEIC -> {
                val bytes = ByteArray(photo.data.remaining())
                photo.data.get(bytes)
                bytes to true
            }
            is PhotoData.Bitmap -> {
                val output = ByteArrayOutputStream()
                photo.bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                output.toByteArray() to false
            }
            else -> null
        }
    }

    fun release() {
        disconnect()
        scope.cancel()
    }
}
