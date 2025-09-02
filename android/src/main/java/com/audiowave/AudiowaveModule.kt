package com.audiowave

import android.media.MediaPlayer
import android.media.MediaMetadataRetriever
import android.media.MediaExtractor
import android.media.MediaCodec
import android.media.MediaFormat
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.Arguments
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.*
import android.media.AudioAttributes
import android.media.AudioManager
import android.content.Context
import android.content.res.AssetFileDescriptor
import android.os.Build
import java.io.FileDescriptor
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

@ReactModule(name = AudiowaveModule.NAME)
class AudiowaveModule(reactContext: ReactApplicationContext) :
  NativeAudiowaveSpec(reactContext) {

  companion object {
    const val NAME = "Audiowave"
  }

  private var mediaPlayer: MediaPlayer? = null
  private var currentAudioUri: String? = null
  private var isPaused: Boolean = false

  override fun getName(): String = NAME

  // Test Methods for Integration Verification
  override fun testing(promise: Promise) {
    try {
      promise.resolve("NativeAudioModule native integration successful! 🎵")
    } catch (e: Exception) {
      promise.reject("TEST_ERROR", e.message, e)
    }
  }

  override fun testSync(): String {
    return "NativeAudioModule sync connection working! ⚡"
  }

  // Audio Playback Methods
  override fun playAudio(uri: String, promise: Promise) {
    try {
      val audioManager = reactApplicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
      audioManager.requestAudioFocus(
        null,
        AudioManager.STREAM_MUSIC,
        AudioManager.AUDIOFOCUS_GAIN
      )

      // If we have an existing paused player with the same URI, just resume it
      if (mediaPlayer != null && isPaused && currentAudioUri == uri) {
        mediaPlayer?.start()
        isPaused = false
        promise.resolve(true)
        return
      }

      // Only create new player if we don't have one or URI changed
      if (mediaPlayer == null || currentAudioUri != uri) {
        mediaPlayer?.release()

        mediaPlayer = MediaPlayer().apply {
          setDataSource(resolveAudioUri(uri))
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            setAudioAttributes(
              AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            )
          } else {
            setAudioStreamType(AudioManager.STREAM_MUSIC)
          }
          prepareAsync()
          setOnPreparedListener {
            start()
            isPaused = false
            currentAudioUri = uri
            promise.resolve(true)
          }
          setOnErrorListener { _, what, extra ->
            promise.reject("AUDIO_ERROR", "MediaPlayer error: $what, $extra")
            true
          }
        }
      } else {
        // Same URI, just start playing
        mediaPlayer?.start()
        isPaused = false
        promise.resolve(true)
      }
    } catch (e: Exception) {
      promise.reject("AUDIO_ERROR", e.message, e)
    }
  }

  override fun pauseAudio(promise: Promise) {
    try {
      val player = mediaPlayer
      if (player != null && player.isPlaying) {
        player.pause()
        isPaused = true
        promise.resolve(true)
      } else {
        promise.resolve(false)
      }
    } catch (e: Exception) {
      promise.reject("AUDIO_ERROR", e.message, e)
    }
  }

  override fun stopAudio(promise: Promise) {
    try {
      mediaPlayer?.let { player ->
        player.stop()
        player.prepareAsync() // Reset for next play
        isPaused = false
        promise.resolve(true)
      } ?: promise.resolve(false)
    } catch (e: Exception) {
      promise.reject("AUDIO_ERROR", e.message, e)
    }
  }

  override fun seekToPosition(position: Double, promise: Promise) {
    try {
      mediaPlayer?.let { player ->
        player.seekTo((position * 1000).toInt()) // Convert to milliseconds
        promise.resolve(true)
      } ?: promise.resolve(false)
    } catch (e: Exception) {
      promise.reject("AUDIO_ERROR", e.message, e)
    }
  }

  // Audio Info Methods
  override fun getAudioDuration(uri: String, promise: Promise) {
    try {
      val retriever = MediaMetadataRetriever()
      val resolvedUri = resolveAudioUri(uri)
      retriever.setDataSource(resolvedUri)
      val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
      retriever.release()

      durationStr?.let {
        val durationMs = it.toLong()
        val durationSeconds = durationMs / 1000.0
        promise.resolve(durationSeconds)
      } ?: promise.reject("DURATION_ERROR", "Could not extract duration")
    } catch (e: Exception) {
      promise.reject("DURATION_ERROR", e.message, e)
    }
  }

  override fun getCurrentPosition(promise: Promise) {
    try {
      mediaPlayer?.let { player ->
        val positionSeconds = player.currentPosition / 1000.0
        promise.resolve(positionSeconds)
      } ?: promise.resolve(0.0)
    } catch (e: Exception) {
      promise.reject("POSITION_ERROR", e.message, e)
    }
  }

  // Synchronous Methods
  override fun getCurrentPositionSync(): Double {
    return try {
      mediaPlayer?.currentPosition?.div(1000.0) ?: 0.0
    } catch (e: Exception) {
      0.0
    }
  }

  override fun isPlaying(): Boolean {
    return mediaPlayer?.isPlaying ?: false
  }

  // URI Resolution Helper
  private fun resolveAudioUri(uri: Any): String {
    return when (uri) {
      is String -> {
        when {
          uri.startsWith("http://") || uri.startsWith("https://") -> uri
          uri.startsWith("file://") -> uri
          uri.startsWith("asset://") -> {
            val assetPath = uri.removePrefix("asset://")
            "file:///android_asset/$assetPath"
          }
          uri.startsWith("content://") -> uri
          uri.startsWith("/") -> "file://$uri"
          else -> {
            try {
              val afd: AssetFileDescriptor = reactApplicationContext.assets.openFd(uri)
              afd.close()
              "file:///android_asset/$uri"
            } catch (e: Exception) {
              uri // Let MediaPlayer try
            }
          }
        }
      }
      is Int -> {
        // Handle require('./file.mp3') case
        val resId = uri
        val resName = reactApplicationContext.resources.getResourceEntryName(resId)
        "file:///android_res/raw/$resName"
      }
      else -> uri.toString()
    }
  }


  // Waveform Generation
  override fun generateWaveform(uri: String, samples: Double, promise: Promise) {
    Thread {
      try {
        val waveformData = processAudioForWaveform(resolveAudioUri(uri), samples.toInt())

        // Convert double array to WritableArray for React Native
        val result = Arguments.createArray()
        waveformData.forEach { value ->
          result.pushDouble(value)
        }

        promise.resolve(result)
      } catch (e: Exception) {
        promise.reject("WAVEFORM_ERROR", e.message, e)
      }
    }.start()
  }

  /**
   * Process audio file to generate waveform data
   */
  private fun processAudioForWaveform(uri: String, samples: Int): DoubleArray {
    val extractor = MediaExtractor()
    var codec: MediaCodec? = null

    try {
      extractor.setDataSource(uri)

      // Select first audio track
      var audioTrackIndex = -1
      var format: MediaFormat? = null
      for (i in 0 until extractor.trackCount) {
        val f = extractor.getTrackFormat(i)
        val mime = f.getString(MediaFormat.KEY_MIME)
        if (mime != null && mime.startsWith("audio/")) {
          audioTrackIndex = i
          format = f
          break
        }
      }
      if (audioTrackIndex == -1 || format == null) {
        throw Exception("No audio track found")
      }
      extractor.selectTrack(audioTrackIndex)

      val mime = format.getString(MediaFormat.KEY_MIME)!!
      codec = MediaCodec.createDecoderByType(mime)
      codec.configure(format, null, null, 0)
      codec.start()

      val durationUs = format.getLong(MediaFormat.KEY_DURATION)
      val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
      val totalSamples = (durationUs * sampleRate) / 1_000_000L
      val samplesPerPoint = maxOf(1L, totalSamples / samples)

      val waveformData = DoubleArray(samples)
      var waveformIndex = 0
      var currentSample = 0L
      var sumSquares = 0.0
      var samplesInPoint = 0
      var maxAmplitude = 0.0

      val bufferInfo = MediaCodec.BufferInfo()
      var endOfStream = false

      while (!endOfStream && waveformIndex < samples) {
        // Feed extractor data into codec
        val inIndex = codec.dequeueInputBuffer(10_000)
        if (inIndex >= 0) {
          val inputBuffer = codec.getInputBuffer(inIndex)!!
          val sampleSize = extractor.readSampleData(inputBuffer, 0)
          if (sampleSize < 0) {
            codec.queueInputBuffer(
              inIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM
            )
            endOfStream = true
          } else {
            val presentationTimeUs = extractor.sampleTime
            codec.queueInputBuffer(
              inIndex, 0, sampleSize, presentationTimeUs, 0
            )
            extractor.advance()
          }
        }

        // Drain decoded PCM
        var outIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
        while (outIndex >= 0) {
          val outputBuffer = codec.getOutputBuffer(outIndex)!!
          outputBuffer.order(ByteOrder.LITTLE_ENDIAN)

          // Process PCM samples (assume 16-bit)
          while (outputBuffer.remaining() >= 2 && waveformIndex < samples) {
            val sample = outputBuffer.short.toInt()
            val normalized = abs(sample) / 32768.0

            sumSquares += normalized * normalized
            samplesInPoint++
            currentSample++

            if (currentSample >= (waveformIndex + 1) * samplesPerPoint) {
              val rms = sqrt(sumSquares / samplesInPoint)
              waveformData[waveformIndex] = min(1.0, rms * 2.0)
              maxAmplitude = max(maxAmplitude, waveformData[waveformIndex])
              sumSquares = 0.0
              samplesInPoint = 0
              waveformIndex++
            }
          }

          outputBuffer.clear()
          codec.releaseOutputBuffer(outIndex, false)
          outIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
        }
      }

      // Handle any leftover samples
      if (waveformIndex < samples && samplesInPoint > 0) {
        val rms = sqrt(sumSquares / samplesInPoint)
        waveformData[waveformIndex] = min(1.0, rms * 2.0)
        maxAmplitude = max(maxAmplitude, waveformData[waveformIndex])
        waveformIndex++
      }

      // Pad with zeros
      while (waveformIndex < samples) {
        waveformData[waveformIndex++] = 0.0
      }

      // Normalize
      if (maxAmplitude > 0) {
        for (i in waveformData.indices) {
          waveformData[i] /= maxAmplitude
        }
      }

      return waveformData
    } finally {
      codec?.stop()
      codec?.release()
      extractor.release()
    }
  }


  override fun onCatalystInstanceDestroy() {
    super.onCatalystInstanceDestroy()
    mediaPlayer?.release()
    mediaPlayer = null
    currentAudioUri = null
    isPaused = false
  }
}
