import { TurboModuleRegistry, type TurboModule } from 'react-native';

export interface Spec extends TurboModule {
  testing(): Promise<string>;
  testSync(): string;
  // Audio playback methods
  playAudio(uri: string): Promise<boolean>;
  pauseAudio(): Promise<boolean>;
  stopAudio(): Promise<boolean>;
  seekToPosition(position: number): Promise<boolean>;

  // Audio info methods
  getAudioDuration(uri: string): Promise<number>;
  getCurrentPosition(): Promise<number>;

  // Waveform generation
  generateWaveform(uri: string, samples: number): Promise<number[]>;

  // Synchronous methods (JSI benefits)
  isPlaying(): boolean;
  getCurrentPositionSync(): number;
}

export default TurboModuleRegistry.getEnforcing<Spec>('Audiowave');
