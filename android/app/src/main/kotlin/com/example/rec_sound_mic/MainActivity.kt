package com.example.rec_sound_mic

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.rec_sound_mic/audio"
    private val EVENT_CHANNEL = "com.example.rec_sound_mic/audio_level"
    private val PERMISSION_REQUEST_CODE = 301

    private lateinit var audioEngine: AudioEngine
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioEngine = AudioEngine(applicationContext)

        audioEngine.onAudioMetricsUpdated = { level, isGateOpen ->
            mainHandler.post {
                eventSink?.success(mapOf(
                    "level" to level.toDouble(),
                    "isGateOpen" to isGateOpen
                ))
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    val permissionsNeeded = mutableListOf<String>()
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        permissionsNeeded.add(Manifest.permission.RECORD_AUDIO)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                            permissionsNeeded.add(Manifest.permission.BLUETOOTH_CONNECT)
                        }
                    }

                    if (permissionsNeeded.isEmpty()) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(this, permissionsNeeded.toTypedArray(), PERMISSION_REQUEST_CODE)
                    }
                }
                "startLiveMic" -> {
                    val success = audioEngine.startLiveMic()
                    result.success(success)
                }
                "stopLiveMic" -> {
                    val success = audioEngine.stopLiveMic()
                    result.success(success)
                }
                "isLiveMicActive" -> {
                    result.success(audioEngine.isLiveMicActive())
                }
                "setGain" -> {
                    val gainVal = call.argument<Double>("gain") ?: 1.0
                    audioEngine.gain = gainVal.toFloat()
                    result.success(true)
                }
                "setNoiseSuppression" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    audioEngine.setNoiseSuppression(enabled)
                    result.success(true)
                }
                "setEchoCancellation" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    audioEngine.setEchoCancellation(enabled)
                    result.success(true)
                }
                "setNoiseGateThreshold" -> {
                    val threshold = call.argument<Double>("threshold") ?: 0.035
                    audioEngine.setNoiseGateThreshold(threshold.toFloat())
                    result.success(true)
                }
                "setBandpassEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    audioEngine.isBandpassEnabled = enabled
                    result.success(true)
                }
                "startRecording" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val success = audioEngine.startRecording(path)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGS", "Path cannot be null", null)
                    }
                }
                "stopRecording" -> {
                    val savedPath = audioEngine.stopRecording()
                    result.success(savedPath)
                }
                "isRecording" -> {
                    result.success(audioEngine.isRecordingActive())
                }
                "getBluetoothStatus" -> {
                    val status = audioEngine.getBluetoothStatus()
                    result.success(status)
                }
                "getAudioLevel" -> {
                    result.success(audioEngine.currentLevel.toDouble())
                }
                "playAudio" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val ok = audioEngine.playAudio(path)
                        result.success(ok)
                    } else {
                        result.error("INVALID_ARGS", "Path cannot be null", null)
                    }
                }
                "pauseAudio" -> {
                    audioEngine.pauseAudio()
                    result.success(true)
                }
                "resumeAudio" -> {
                    audioEngine.resumeAudio()
                    result.success(true)
                }
                "stopAudio" -> {
                    audioEngine.stopAudio()
                    result.success(true)
                }
                "seekAudio" -> {
                    val pos = call.argument<Int>("position") ?: 0
                    audioEngine.seekAudio(pos)
                    result.success(true)
                }
                "getPlaybackStatus" -> {
                    result.success(audioEngine.getPlaybackStatus())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val micIndex = permissions.indexOf(Manifest.permission.RECORD_AUDIO)
            val isMicGranted = micIndex != -1 && grantResults.getOrNull(micIndex) == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(isMicGranted)
            pendingPermissionResult = null
        }
    }

    override fun onDestroy() {
        if (::audioEngine.isInitialized) {
            audioEngine.stopLiveMic()
            audioEngine.stopRecording()
            audioEngine.stopAudio()
        }
        super.onDestroy()
    }
}
