import React, { useEffect, useRef, useState } from 'react';
import {
  View,
  TouchableOpacity,
  Dimensions,
  Alert,
  Text,
  ActivityIndicator,
  StyleSheet,
  type GestureResponderEvent,
} from 'react-native';
import Svg, { Path, Rect } from 'react-native-svg';
import NativeAudio from './NativeAudiowave';
import { AudioAssetResolver } from './AudioAssetResolver';

const { width: screenWidth } = Dimensions.get('window');

interface AudioWaveformProps {
  audioUri: string;
  height?: number;
  samples?: number;
  backgroundColor?: string;
  waveformColor?: string;
  progressColor?: string;
  style?: any;
  onPlayStateChange?: (isPlaying: boolean) => void;
  onPositionChange?: (position: number, duration: number) => void;
  onLoadComplete?: (duration: number) => void;
  onError?: (error: string) => void;
}

const PlayIcon: React.FC<{ size?: number; color?: string }> = ({
  size = 18,
  color = '#0b61ff',
}) => (
  <Svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    accessibilityRole="image"
  >
    <Path d="M5 3v18l15-9L5 3z" fill={color} />
  </Svg>
);

const PauseIcon: React.FC<{ size?: number; color?: string }> = ({
  size = 18,
  color = '#0b61ff',
}) => (
  <Svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    accessibilityRole="image"
  >
    <Rect x="5" y="4" width="4" height="16" rx="1" fill={color} />
    <Rect x="15" y="4" width="4" height="16" rx="1" fill={color} />
  </Svg>
);

const AudioWaveform: React.FC<AudioWaveformProps> = ({
  audioUri,
  height = 48,
  samples = 60,
  backgroundColor = '#0b61ff',
  waveformColor = 'rgba(255,255,255,0.55)',
  progressColor = 'rgba(255,255,255,0.95)',
  style,
  onPlayStateChange,
  onPositionChange,
  onLoadComplete,
  onError,
}) => {
  const [waveformData, setWaveformData] = useState<number[]>([]);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentPosition, setCurrentPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isLoading, setIsLoading] = useState(false);
  const [resolvedUri, setResolvedUri] = useState<string>('');

  const positionInterval = useRef<ReturnType<typeof setInterval> | null>(null);
  const leftRightReserved = 42 + 12 + 70; // play button + padding + time width
  const waveformWidth = Math.max(120, screenWidth - leftRightReserved - 48);
  const barWidth = waveformWidth / samples - 2;
  const effectiveBarWidth = Math.max(2, barWidth);

  useEffect(() => {
    const uri = AudioAssetResolver.resolve(audioUri);
    setResolvedUri(uri);
    void loadAudio(uri);
    return cleanup;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [audioUri]);

  useEffect(() => {
    if (isPlaying) {
      positionInterval.current = setInterval(() => {
        void updatePosition();
      }, 200);
    } else {
      if (positionInterval.current) {
        clearInterval(positionInterval.current);
        positionInterval.current = null;
      }
    }

    return () => {
      if (positionInterval.current) {
        clearInterval(positionInterval.current);
      }
    };
  }, [isPlaying]);

  useEffect(() => {
    onPlayStateChange?.(isPlaying);
  }, [isPlaying, onPlayStateChange]);

  useEffect(() => {
    onPositionChange?.(currentPosition, duration);
  }, [currentPosition, duration, onPositionChange]);

  const loadAudio = async (uri: string) => {
    try {
      setIsLoading(true);
      setCurrentPosition(0);
      setWaveformData([]);

      const [durationResult, waveformResult] = await Promise.allSettled([
        NativeAudio.getAudioDuration(uri),
        NativeAudio.generateWaveform(uri, samples),
      ]);

      // Handle duration
      if (durationResult.status === 'fulfilled') {
        const dur =
          typeof durationResult.value === 'number'
            ? durationResult.value
            : Number(durationResult.value) || 0;
        setDuration(dur);
        onLoadComplete?.(dur);
      } else {
        console.warn('Failed to get audio duration:', durationResult.reason);
        onError?.(`Failed to load audio duration: ${durationResult.reason}`);
      }

      // Handle waveform
      if (
        waveformResult.status === 'fulfilled' &&
        Array.isArray(waveformResult.value) &&
        waveformResult.value.length > 0
      ) {
        setWaveformData(waveformResult.value);
      } else {
        console.warn('Failed to generate waveform, using fallback');
        setWaveformData(generateFallbackWaveform());
      }
    } catch (error) {
      console.error('Failed to load audio:', error);
      const errorMessage = `Failed to load audio: ${error}`;
      onError?.(errorMessage);
      Alert.alert('Error', errorMessage);
      setWaveformData(generateFallbackWaveform());
    } finally {
      setIsLoading(false);
    }
  };

  const generateFallbackWaveform = (): number[] =>
    Array.from(
      { length: samples },
      (_, i) =>
        0.25 +
        Math.abs(Math.sin((i / samples) * Math.PI * 2)) * 0.6 * Math.random()
    );

  const updatePosition = async () => {
    try {
      const position = await NativeAudio.getCurrentPosition();
      const pos =
        typeof position === 'number' ? position : Number(position) || 0;
      setCurrentPosition(pos);

      // Check if playback finished
      const playing = NativeAudio.isPlaying ? NativeAudio.isPlaying() : false;
      if (isPlaying && !playing && pos >= duration - 0.1) {
        setIsPlaying(false);
        setCurrentPosition(0);
        // Reset to beginning for next play
        try {
          await NativeAudio.seekToPosition(0);
        } catch (seekError) {
          console.warn('Failed to reset position:', seekError);
        }
      }
    } catch (error) {
      console.error('Position update error:', error);
    }
  };

  const handlePlayPause = async () => {
    try {
      if (isPlaying) {
        const success = await NativeAudio.pauseAudio();
        if (success) {
          setIsPlaying(false);
        }
      } else {
        const success = await NativeAudio.playAudio(resolvedUri);
        if (success) {
          setIsPlaying(true);
        } else {
          // Still set to true as some implementations return false even on success
          setIsPlaying(true);
        }
      }
    } catch (error) {
      console.error('Play/Pause error:', error);
      const errorMessage = `Failed to ${isPlaying ? 'pause' : 'play'} audio`;
      onError?.(errorMessage);
      Alert.alert('Error', errorMessage);
    }
  };

  const handleWaveformPress = async (event: GestureResponderEvent) => {
    if (!duration || duration <= 0) return;

    try {
      const native = event.nativeEvent as any;
      const locationX = native.locationX;
      const touchX = Math.max(0, Math.min(waveformWidth, locationX));
      const progress = waveformWidth > 0 ? touchX / waveformWidth : 0;
      const seekPosition = Math.max(0, Math.min(duration, progress * duration));

      await NativeAudio.seekToPosition(seekPosition);
      setCurrentPosition(seekPosition);
    } catch (error) {
      console.error('Seek error:', error);
      onError?.('Failed to seek audio');
    }
  };

  const cleanup = () => {
    try {
      if (positionInterval.current) {
        clearInterval(positionInterval.current);
        positionInterval.current = null;
      }
      if (isPlaying) {
        void NativeAudio.stopAudio();
      }
    } catch (error) {
      console.error('Cleanup error:', error);
    }
  };

  const formatTime = (seconds: number) => {
    if (!seconds || Number.isNaN(seconds)) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${String(secs).padStart(2, '0')}`;
  };

  const progressRatio =
    duration > 0 ? Math.min(1, currentPosition / duration) : 0;
  const barsToFill = Math.round(progressRatio * samples);

  return (
    <View style={[styles.wrapper, style]}>
      <View style={[styles.container, { backgroundColor }]}>
        <TouchableOpacity
          style={styles.playButton}
          onPress={handlePlayPause}
          disabled={isLoading}
          accessibilityRole="button"
          accessibilityLabel={isPlaying ? 'Pause audio' : 'Play audio'}
        >
          {isLoading ? (
            <ActivityIndicator size="small" color={backgroundColor} />
          ) : isPlaying ? (
            <PauseIcon size={20} color={backgroundColor} />
          ) : (
            <PlayIcon size={20} color={backgroundColor} />
          )}
        </TouchableOpacity>

        <TouchableOpacity
          onPress={handleWaveformPress}
          activeOpacity={0.9}
          style={[styles.waveformRow, { height }]}
          disabled={isLoading || !duration}
        >
          {waveformData.length === 0
            ? Array.from({ length: samples }).map((_, i) => {
                const barH = Math.max(4, (height - 12) * 0.4);
                return (
                  <View
                    key={`ph-${i}`}
                    style={[
                      styles.bar,
                      {
                        width: effectiveBarWidth,
                        height: barH,
                        backgroundColor: waveformColor,
                        opacity: 0.7,
                        marginHorizontal: 1,
                      },
                    ]}
                  />
                );
              })
            : waveformData.map((amp, i) => {
                const barHeight = Math.max(4, amp * (height - 12));
                const isInProgress = i < barsToFill;
                return (
                  <View
                    key={`bar-${i}`}
                    style={[
                      styles.bar,
                      {
                        width: effectiveBarWidth,
                        height: barHeight,
                        marginHorizontal: 1,
                        backgroundColor: isInProgress
                          ? progressColor
                          : waveformColor,
                        opacity: isInProgress ? 1 : 0.9,
                        borderRadius: 2,
                        alignSelf: 'flex-end',
                      },
                    ]}
                  />
                );
              })}
        </TouchableOpacity>

        <View style={styles.timeBox}>
          <Text style={styles.timeText}>{formatTime(currentPosition)}</Text>
          <Text style={[styles.timeText, { opacity: 0.8 }]}> / </Text>
          <Text style={styles.timeText}>{formatTime(duration)}</Text>
        </View>
      </View>
    </View>
  );
};

export default AudioWaveform;

const styles = StyleSheet.create({
  wrapper: {
    padding: 12,
  },
  container: {
    borderRadius: 18,
    paddingVertical: 10,
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.12,
    shadowRadius: 10,
  },
  playButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: '#ffffff',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  waveformRow: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 6,
    overflow: 'hidden',
  },
  bar: {},
  timeBox: {
    width: 70,
    marginLeft: 10,
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
  },
  timeText: {
    color: '#fff',
    fontSize: 12,
    fontVariant: ['tabular-nums'],
  },
});
