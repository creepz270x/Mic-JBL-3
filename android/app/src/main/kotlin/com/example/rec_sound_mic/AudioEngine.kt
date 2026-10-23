package com.example.rec_sound_mic

import android.content.Context
import android.media.*
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Process
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread
import kotlin.math.*

class BiquadFilter {
    private var b0 = 1.0
    private var b1 = 0.0
    private var b2 = 0.0
    private var a1 = 0.0
    private var a2 = 0.0
    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0

    fun configureLowPass(cutoffFreq: Double, sampleRate: Double, q: Double = 0.7071) {
        val w0 = 2.0 * Math.PI * cutoffFreq / sampleRate
        val alpha = sin(w0) / (2.0 * q)
        val cosW0 = cos(w0)

        val b0Raw = (1.0 - cosW0) / 2.0
        val b1Raw = 1.0 - cosW0
        val b2Raw = (1.0 - cosW0) / 2.0
        val a0Raw = 1.0 + alpha
        val a1Raw = -2.0 * cosW0
        val a2Raw = 1.0 - alpha

        b0 = b0Raw / a0Raw
        b1 = b1Raw / a0Raw
        b2 = b2Raw / a0Raw
        a1 = a1Raw / a0Raw
        a2 = a2Raw / a0Raw
        reset()
    }

    fun configureHighPass(cutoffFreq: Double, sampleRate: Double, q: Double = 0.7071) {
        val w0 = 2.0 * Math.PI * cutoffFreq / sampleRate
        val alpha = sin(w0) / (2.0 * q)
        val cosW0 = cos(w0)

        val b0Raw = (1.0 + cosW0) / 2.0
        val b1Raw = -(1.0 + cosW0)
        val b2Raw = (1.0 + cosW0) / 2.0
        val a0Raw = 1.0 + alpha
        val a1Raw = -2.0 * cosW0
        val a2Raw = 1.0 - alpha

        b0 = b0Raw / a0Raw
        b1 = b1Raw / a0Raw
        b2 = b2Raw / a0Raw
        a1 = a1Raw / a0Raw
        a2 = a2Raw / a0Raw
        reset()
    }

    fun process(sample: Double): Double {
        val y = b0 * sample + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = sample
        y2 = y1
        y1 = y
        return y
    }

    fun reset() {
        x1 = 0.0
        x2 = 0.0
        y1 = 0.0
        y2 = 0.0
    }
}

class NoiseGate(
    @Volatile var threshold: Float = 0.035f,
    private val attackCoeff: Float = 0.35f,  // fast open (~4ms)
    private val releaseCoeff: Float = 0.02f   // smooth close (~60ms)
) {
    @Volatile var isGateOpen: Boolean = false
        private set
    private var currentGainMultiplier: Float = 0.0f

    fun process(buffer: ShortArray, length: Int): Boolean {
        var maxVal = 0
        for (i in 0 until length) {
            val a = abs(buffer[i].toInt())
            if (a > maxVal) maxVal = a
        }
        val peak = maxVal / 32768.0f

        // Hysteresis: open at threshold, close slightly below to avoid stutter
        val openTarget = if (peak >= threshold) {
            1.0f
        } else if (peak < threshold * 0.7f) {
            0.0f
        } else {
            if (isGateOpen) 1.0f else 0.0f
        }

        isGateOpen = openTarget > 0.5f

        for (i in 0 until length) {
            // Smoothly interpolate multiplier
            if (openTarget > currentGainMultiplier) {
                currentGainMultiplier += attackCoeff * (openTarget - currentGainMultiplier)
            } else {
                currentGainMultiplier += releaseCoeff * (openTarget - currentGainMultiplier)
            }

            val sample = (buffer[i] * currentGainMultiplier).toInt()
            buffer[i] = sample.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        }
        return isGateOpen
    }

    fun reset() {
        currentGainMultiplier = 0.0f
        isGateOpen = false
    }
}

class AudioEngine(private val context: Context) {

    companion object {
        private const val TAG = "AudioEngine"
        private const val SAMPLE_RATE = 44100
        private const val CHANNEL_IN = AudioFormat.CHANNEL_IN_MONO
        private const val CHANNEL_OUT = AudioFormat.CHANNEL_OUT_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }

    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var echoCanceler: AcousticEchoCanceler? = null

    private var loopThread: Thread? = null
    @Volatile private var isRunning = false

    // Gain Control (1.0 = normal, 2.0 = 2x boost, etc.)
    @Volatile var gain: Float = 1.0f

    // Anti-Feedback and Noise Suppression toggles
    @Volatile var isNoiseSuppressionEnabled: Boolean = true
    @Volatile var isEchoCancellationEnabled: Boolean = true
    @Volatile var isBandpassEnabled: Boolean = true

    // Smart Noise Gate
    val noiseGate = NoiseGate(threshold = 0.035f)

    // Speech Bandpass Biquad Filters (130Hz Low-cut & 4200Hz High-cut)
    private val highPassFilter = BiquadFilter().apply {
        configureHighPass(130.0, SAMPLE_RATE.toDouble())
    }
    private val lowPassFilter = BiquadFilter().apply {
        configureLowPass(4200.0, SAMPLE_RATE.toDouble())
    }

    // Recording variables
    @Volatile private var isRecording = false
    private var recordingFile: File? = null
    private var recordingStream: FileOutputStream? = null
    private var totalPcmBytesRecorded: Long = 0

    // Native Media Player for playing back recorded audio
    private var mediaPlayer: MediaPlayer? = null
    var onPlaybackCompleted: (() -> Unit)? = null

    // Current normalized audio level (0.0 to 1.0) and gate status
    @Volatile var currentLevel: Float = 0.0f
        private set
    @Volatile var isGateOpen: Boolean = false
        private set

    var onAudioMetricsUpdated: ((Float, Boolean) -> Unit)? = null

    fun isLiveMicActive(): Boolean = isRunning
    fun isRecordingActive(): Boolean = isRecording

    @Synchronized
    fun startLiveMic(): Boolean {
        if (isRunning) return true

        try {
            val minInBufSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_IN, AUDIO_FORMAT)
            val minOutBufSize = AudioTrack.getMinBufferSize(SAMPLE_RATE, CHANNEL_OUT, AUDIO_FORMAT)

            if (minInBufSize <= 0 || minOutBufSize <= 0) {
                Log.e(TAG, "Invalid buffer sizes for audio hardware")
                return false
            }

            // CRITICAL FIX: Use VOICE_RECOGNITION for directional near-field mic on Galaxy S24
            // Avoids aggressive AGC boosting from VOICE_COMMUNICATION that amplifies room noise!
            var audioSource = MediaRecorder.AudioSource.VOICE_RECOGNITION

            audioRecord = AudioRecord(
                audioSource,
                SAMPLE_RATE,
                CHANNEL_IN,
                AUDIO_FORMAT,
                max(minInBufSize, 1024)
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                // Fallback to standard MIC if VOICE_RECOGNITION is unavailable
                audioRecord?.release()
                audioSource = MediaRecorder.AudioSource.MIC
                audioRecord = AudioRecord(
                    audioSource,
                    SAMPLE_RATE,
                    CHANNEL_IN,
                    AUDIO_FORMAT,
                    max(minInBufSize, 1024)
                )
            }

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord initialization failed")
                return false
            }

            val sessionId = audioRecord!!.audioSessionId

            // Attach Hardware Noise Suppressor
            if (NoiseSuppressor.isAvailable()) {
                try {
                    noiseSuppressor = NoiseSuppressor.create(sessionId)
                    noiseSuppressor?.enabled = isNoiseSuppressionEnabled
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to create NoiseSuppressor: ${e.message}")
                }
            }

            // Attach Hardware Acoustic Echo Canceler
            if (AcousticEchoCanceler.isAvailable()) {
                try {
                    echoCanceler = AcousticEchoCanceler.create(sessionId)
                    echoCanceler?.enabled = isEchoCancellationEnabled
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to create AcousticEchoCanceler: ${e.message}")
                }
            }

            // Setup Low Latency AudioTrack for output to JBL Go 3
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()

            val audioFormat = AudioFormat.Builder()
                .setSampleRate(SAMPLE_RATE)
                .setChannelMask(CHANNEL_OUT)
                .setEncoding(AUDIO_FORMAT)
                .build()

            audioTrack = AudioTrack.Builder()
                .setAudioAttributes(audioAttributes)
                .setAudioFormat(audioFormat)
                .setBufferSizeInBytes(max(minOutBufSize, 1024))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .build()

            if (audioTrack?.state != AudioTrack.STATE_INITIALIZED) {
                Log.e(TAG, "AudioTrack initialization failed")
                release()
                return false
            }

            highPassFilter.reset()
            lowPassFilter.reset()
            noiseGate.reset()

            audioRecord?.startRecording()
            audioTrack?.play()
            isRunning = true

            // High-priority real-time audio loop
            loopThread = thread(name = "LiveMicAudioLoop", priority = Thread.MAX_PRIORITY) {
                Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
                
                val chunkSize = 512
                val shortBuffer = ShortArray(chunkSize)
                val byteBuffer = ByteBuffer.allocate(chunkSize * 2).order(ByteOrder.LITTLE_ENDIAN)

                var reportCounter = 0

                while (isRunning) {
                    val readSamples = audioRecord?.read(shortBuffer, 0, chunkSize) ?: -1
                    if (readSamples > 0) {
                        var rawSumSquares = 0.0

                        for (i in 0 until readSamples) {
                            rawSumSquares += (shortBuffer[i] * shortBuffer[i])
                        }
                        val rawRms = sqrt(rawSumSquares / readSamples)
                        val normalizedPeak = (rawRms / 32768.0).coerceIn(0.0, 1.0).toFloat()
                        currentLevel = normalizedPeak

                        // 1. DSP Filter: Bandpass (130Hz - 4200Hz) to cut howling squeal & bass rumble
                        if (isBandpassEnabled) {
                            for (i in 0 until readSamples) {
                                var s = shortBuffer[i].toDouble()
                                s = highPassFilter.process(s)
                                s = lowPassFilter.process(s)
                                shortBuffer[i] = s.coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble()).toInt().toShort()
                            }
                        }

                        // 2. DSP Filter: Smart Noise Gate (cuts room noise & feedback loop when not speaking)
                        val gateOpen = noiseGate.process(shortBuffer, readSamples)
                        isGateOpen = gateOpen

                        // 3. DSP Filter: User Gain multiplier
                        for (i in 0 until readSamples) {
                            var s = (shortBuffer[i] * gain).toInt()
                            if (s > Short.MAX_VALUE) s = Short.MAX_VALUE.toInt()
                            else if (s < Short.MIN_VALUE) s = Short.MIN_VALUE.toInt()
                            shortBuffer[i] = s.toShort()
                        }

                        // 4. Send output to Bluetooth Speaker (JBL Go 3)
                        audioTrack?.write(shortBuffer, 0, readSamples)

                        // 5. If recording, stream PCM to file
                        if (isRecording && recordingStream != null) {
                            byteBuffer.clear()
                            for (i in 0 until readSamples) {
                                byteBuffer.putShort(shortBuffer[i])
                            }
                            val pcmBytes = byteBuffer.array()
                            val numBytes = readSamples * 2
                            try {
                                recordingStream?.write(pcmBytes, 0, numBytes)
                                totalPcmBytesRecorded += numBytes
                            } catch (e: Exception) {
                                Log.e(TAG, "Error writing recording stream: ${e.message}")
                            }
                        }

                        // 6. Report metrics to Flutter UI (~50ms)
                        reportCounter++
                        if (reportCounter >= 4) {
                            reportCounter = 0
                            onAudioMetricsUpdated?.invoke(normalizedPeak, gateOpen)
                        }
                    }
                }
            }

            Log.i(TAG, "Live Mic loop successfully started with anti-feedback DSP")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error starting live mic: ${e.message}", e)
            release()
            return false
        }
    }

    @Synchronized
    fun stopLiveMic(): Boolean {
        isRunning = false
        try {
            loopThread?.join(500)
        } catch (_: InterruptedException) {}
        loopThread = null

        release()
        currentLevel = 0.0f
        isGateOpen = false
        onAudioMetricsUpdated?.invoke(0.0f, false)
        Log.i(TAG, "Live Mic stopped")
        return true
    }

    fun setNoiseSuppression(enabled: Boolean) {
        isNoiseSuppressionEnabled = enabled
        try {
            noiseSuppressor?.enabled = enabled
        } catch (e: Exception) {
            Log.w(TAG, "Could not set noise suppressor enabled: ${e.message}")
        }
    }

    fun setEchoCancellation(enabled: Boolean) {
        isEchoCancellationEnabled = enabled
        try {
            echoCanceler?.enabled = enabled
        } catch (e: Exception) {
            Log.w(TAG, "Could not set echo canceler enabled: ${e.message}")
        }
    }

    fun setNoiseGateThreshold(threshold: Float) {
        noiseGate.threshold = threshold.coerceIn(0.005f, 0.25f)
    }

    @Synchronized
    fun startRecording(outputPath: String): Boolean {
        if (isRecording) return true
        try {
            val file = File(outputPath)
            file.parentFile?.mkdirs()
            if (file.exists()) file.delete()

            recordingFile = file
            recordingStream = FileOutputStream(file)
            totalPcmBytesRecorded = 0

            val placeholder = ByteArray(44)
            recordingStream?.write(placeholder)

            isRecording = true
            Log.i(TAG, "Recording started at: $outputPath")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start recording: ${e.message}", e)
            return false
        }
    }

    @Synchronized
    fun stopRecording(): String? {
        if (!isRecording) return null
        isRecording = false

        try {
            recordingStream?.flush()
            recordingStream?.close()
            recordingStream = null

            val file = recordingFile
            if (file != null && file.exists()) {
                val totalDataLen = totalPcmBytesRecorded + 36
                val byteRate = (SAMPLE_RATE * 1 * 16 / 8).toLong()

                val wavFile = RandomAccessFile(file, "rw")
                writeWavHeader(
                    wavFile,
                    totalPcmBytesRecorded,
                    totalDataLen,
                    SAMPLE_RATE.toLong(),
                    1,
                    byteRate
                )
                wavFile.close()
                Log.i(TAG, "Recording completed. File size: ${file.length()} bytes")
                return file.absolutePath
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error finalizing recording WAV header: ${e.message}", e)
        }
        return null
    }

    private fun writeWavHeader(
        out: RandomAccessFile,
        totalAudioLen: Long,
        totalDataLen: Long,
        sampleRate: Long,
        channels: Int,
        byteRate: Long
    ) {
        val header = ByteArray(44)
        header[0] = 'R'.code.toByte()
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()
        header[4] = (totalDataLen and 0xff).toByte()
        header[5] = ((totalDataLen shr 8) and 0xff).toByte()
        header[6] = ((totalDataLen shr 16) and 0xff).toByte()
        header[7] = ((totalDataLen shr 24) and 0xff).toByte()
        header[8] = 'W'.code.toByte()
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()
        header[12] = 'f'.code.toByte()
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()
        header[16] = 16
        header[17] = 0
        header[18] = 0
        header[19] = 0
        header[20] = 1
        header[21] = 0
        header[22] = channels.toByte()
        header[23] = 0
        header[24] = (sampleRate and 0xff).toByte()
        header[25] = ((sampleRate shr 8) and 0xff).toByte()
        header[26] = ((sampleRate shr 16) and 0xff).toByte()
        header[27] = ((sampleRate shr 24) and 0xff).toByte()
        header[28] = (byteRate and 0xff).toByte()
        header[29] = ((byteRate shr 8) and 0xff).toByte()
        header[30] = ((byteRate shr 16) and 0xff).toByte()
        header[31] = ((byteRate shr 24) and 0xff).toByte()
        header[32] = (channels * 2).toByte()
        header[33] = 0
        header[34] = 16
        header[35] = 0
        header[36] = 'd'.code.toByte()
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()
        header[40] = (totalAudioLen and 0xff).toByte()
        header[41] = ((totalAudioLen shr 8) and 0xff).toByte()
        header[42] = ((totalAudioLen shr 16) and 0xff).toByte()
        header[43] = ((totalAudioLen shr 24) and 0xff).toByte()

        out.seek(0)
        out.write(header, 0, 44)
    }

    fun playAudio(filePath: String): Boolean {
        stopAudio()
        return try {
            mediaPlayer = MediaPlayer().apply {
                setDataSource(filePath)
                prepare()
                start()
                setOnCompletionListener {
                    stopAudio()
                    onPlaybackCompleted?.invoke()
                }
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error playing audio file: ${e.message}")
            false
        }
    }

    fun pauseAudio() {
        try {
            if (mediaPlayer?.isPlaying == true) {
                mediaPlayer?.pause()
            }
        } catch (_: Exception) {}
    }

    fun resumeAudio() {
        try {
            mediaPlayer?.start()
        } catch (_: Exception) {}
    }

    fun stopAudio() {
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
        } catch (_: Exception) {}
        mediaPlayer = null
    }

    fun seekAudio(positionMs: Int) {
        try {
            mediaPlayer?.seekTo(positionMs)
        } catch (_: Exception) {}
    }

    fun getPlaybackStatus(): Map<String, Any> {
        val isPlaying = mediaPlayer?.isPlaying == true
        val pos = mediaPlayer?.currentPosition ?: 0
        val dur = mediaPlayer?.duration ?: 0
        return mapOf(
            "isPlaying" to isPlaying,
            "position" to pos,
            "duration" to dur
        )
    }

    fun getBluetoothStatus(): Map<String, Any> {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        var isConnected = false
        var deviceName = "Speaker HP / Kabel"
        var deviceType = "INTERNAL"

        if (audioManager != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                for (dev in devices) {
                    if (dev.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                        dev.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                        dev.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                        dev.type == AudioDeviceInfo.TYPE_BLE_SPEAKER) {
                        isConnected = true
                        val pName = dev.productName?.toString() ?: ""
                        deviceName = if (pName.isNotBlank()) pName else "Bluetooth Speaker (JBL Go 3)"
                        deviceType = "BLUETOOTH"
                        break
                    }
                }
            } else {
                @Suppress("DEPRECATION")
                if (audioManager.isBluetoothA2dpOn) {
                    isConnected = true
                    deviceName = "Bluetooth Speaker (JBL Go 3)"
                    deviceType = "BLUETOOTH"
                }
            }
        }

        return mapOf(
            "isConnected" to isConnected,
            "deviceName" to deviceName,
            "deviceType" to deviceType
        )
    }

    private fun release() {
        try {
            noiseSuppressor?.release()
            noiseSuppressor = null
        } catch (_: Exception) {}

        try {
            echoCanceler?.release()
            echoCanceler = null
        } catch (_: Exception) {}

        try {
            if (audioRecord?.state == AudioRecord.STATE_INITIALIZED) {
                audioRecord?.stop()
            }
            audioRecord?.release()
            audioRecord = null
        } catch (_: Exception) {}

        try {
            if (audioTrack?.state == AudioTrack.STATE_INITIALIZED) {
                audioTrack?.stop()
            }
            audioTrack?.release()
            audioTrack = null
        } catch (_: Exception) {}
    }
}
