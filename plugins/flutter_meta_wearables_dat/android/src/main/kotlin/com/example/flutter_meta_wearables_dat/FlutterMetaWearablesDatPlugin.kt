package com.example.flutter_meta_wearables_dat

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Registers the camera (DAT) and audio (standard Bluetooth profiles)
 * channels described in the plugin README, and enforces the one ordering
 * constraint between them: a camera stream must not start while HFP mic
 * capture is still settling, or the audio route can fail silently.
 */
class FlutterMetaWearablesDatPlugin : FlutterPlugin {
    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private lateinit var audioManager: GlassesAudioManager
    private lateinit var cameraManager: GlassesCameraManager

    private var micAudioSink: EventChannel.EventSink? = null
    private var audioStateSink: EventChannel.EventSink? = null
    private var cameraFramesSink: EventChannel.EventSink? = null
    private var cameraStateSink: EventChannel.EventSink? = null

    private var audioStateWatchJob: Job? = null
    private var cameraStateWatchJob: Job? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        audioManager = GlassesAudioManager(context)
        cameraManager = GlassesCameraManager(context)

        setUpAudioChannels(binding)
        setUpCameraChannels(binding)
    }

    private fun setUpAudioChannels(binding: FlutterPlugin.FlutterPluginBinding) {
        MethodChannel(binding.binaryMessenger, "flutter_meta_wearables_dat/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestAudioPermissions" -> result.success(audioManager.hasAudioPermissions())
                    "startListening" -> {
                        audioManager.onAudioChunk = { bytes, sampleRate, timestampMs ->
                            postToMain {
                                micAudioSink?.success(
                                    mapOf(
                                        "pcm" to bytes,
                                        "sampleRateHz" to sampleRate,
                                        "timestampMs" to timestampMs,
                                    ),
                                )
                            }
                        }
                        result.success(audioManager.startListening())
                    }
                    "stopListening" -> {
                        audioManager.stopListening()
                        result.success(null)
                    }
                    "speak" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val sampleRate = call.argument<Int>("sampleRateHz") ?: 22050
                        val isWav = call.argument<Boolean>("isWav") ?: true
                        if (bytes == null) {
                            result.error("invalid_argument", "speak() requires bytes", null)
                        } else {
                            val pcm = if (isWav) audioManager.stripWavHeaderIfPresent(bytes) else bytes
                            mainScope.launch {
                                audioManager.speak(pcm, sampleRate)
                                result.success(null)
                            }
                        }
                    }
                    "stopSpeaking" -> {
                        audioManager.stopSpeaking()
                        result.success(null)
                    }
                    "releaseAudioSession" -> {
                        audioManager.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(binding.binaryMessenger, "flutter_meta_wearables_dat/mic_audio")
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, events: EventChannel.EventSink) {
                        micAudioSink = events
                    }

                    override fun onCancel(args: Any?) {
                        micAudioSink = null
                    }
                },
            )

        EventChannel(binding.binaryMessenger, "flutter_meta_wearables_dat/audio_state")
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, events: EventChannel.EventSink) {
                        audioStateSink = events
                        audioStateWatchJob?.cancel()
                        audioStateWatchJob = mainScope.launch {
                            audioManager.state.collect { s ->
                                audioStateSink?.success(
                                    mapOf(
                                        "mode" to s.mode.name,
                                        "route" to s.route.name,
                                        "settled" to s.isRouteSettled,
                                    ),
                                )
                            }
                        }
                    }

                    override fun onCancel(args: Any?) {
                        audioStateSink = null
                        audioStateWatchJob?.cancel()
                        audioStateWatchJob = null
                    }
                },
            )
    }

    private fun setUpCameraChannels(binding: FlutterPlugin.FlutterPluginBinding) {
        MethodChannel(binding.binaryMessenger, "flutter_meta_wearables_dat/camera")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> result.success(cameraManager.connect())
                    "disconnect" -> {
                        cameraManager.disconnect()
                        result.success(null)
                    }
                    "startStream" -> {
                        val quality = call.argument<String>("videoQuality") ?: "MEDIUM"
                        val frameRate = call.argument<Int>("frameRate") ?: 24
                        val compress = call.argument<Boolean>("compressVideo") ?: false
                        mainScope.launch {
                            // Ordering constraint: if HFP listening is in flight, wait for the
                            // Bluetooth route to settle before starting the DAT camera stream,
                            // or the audio route can fail silently.
                            if (audioManager.state.value.mode == AudioMode.LISTENING) {
                                withTimeoutOrNull(3000) {
                                    audioManager.state.first {
                                        it.isRouteSettled || it.mode != AudioMode.LISTENING
                                    }
                                }
                            }
                            cameraManager.onVideoFrame = { frame ->
                                postToMain {
                                    val bytes = ByteArray(frame.buffer.remaining())
                                    frame.buffer.get(bytes)
                                    cameraFramesSink?.success(
                                        mapOf(
                                            "bytes" to bytes,
                                            "width" to frame.width,
                                            "height" to frame.height,
                                            "timestampUs" to frame.presentationTimeUs,
                                            "isCompressed" to frame.isCompressed,
                                        ),
                                    )
                                }
                            }
                            result.success(cameraManager.startStream(quality, frameRate, compress))
                        }
                    }
                    "stopStream" -> {
                        cameraManager.stopStream()
                        result.success(null)
                    }
                    "capturePhoto" -> {
                        mainScope.launch {
                            val photo = cameraManager.capturePhoto()
                            if (photo == null) {
                                result.error("capture_failed", "No active stream or capture failed", null)
                            } else {
                                val (bytes, isHeic) = photo
                                result.success(mapOf("bytes" to bytes, "isHeic" to isHeic))
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(binding.binaryMessenger, "flutter_meta_wearables_dat/camera_frames")
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, events: EventChannel.EventSink) {
                        cameraFramesSink = events
                    }

                    override fun onCancel(args: Any?) {
                        cameraFramesSink = null
                    }
                },
            )

        EventChannel(binding.binaryMessenger, "flutter_meta_wearables_dat/camera_state")
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, events: EventChannel.EventSink) {
                        cameraStateSink = events
                        cameraStateWatchJob?.cancel()
                        cameraStateWatchJob = mainScope.launch {
                            cameraManager.connectionState.collect { s ->
                                cameraStateSink?.success(s.name)
                            }
                        }
                    }

                    override fun onCancel(args: Any?) {
                        cameraStateSink = null
                        cameraStateWatchJob?.cancel()
                        cameraStateWatchJob = null
                    }
                },
            )
    }

    private fun postToMain(action: () -> Unit) {
        Handler(Looper.getMainLooper()).post(action)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        audioManager.release()
        cameraManager.release()
        mainScope.cancel()
    }
}
