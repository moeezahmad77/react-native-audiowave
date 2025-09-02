#import "Audiowave.h"
#import <React/RCTLog.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#import <React/RCTConvert.h>
#import <React/RCTUtils.h>

@implementation Audiowave
RCT_EXPORT_MODULE()

- (id)init {
  if (self = [super init]) {
    _audioSession = [AVAudioSession sharedInstance];
    NSError *sessionError = nil;
    [_audioSession setCategory:AVAudioSessionCategoryPlayback error:&sessionError];
    if (sessionError) {
      RCTLogError(@"Audio session setup error: %@", sessionError.localizedDescription);
    }
  }
  return self;
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeAudiowaveSpecJSI>(params);
}


#pragma mark - Helpers

// - (NSURL * _Nullable)parseAudioURI:(NSString *)uri {
//   if ([uri hasPrefix:@"http://"] || [uri hasPrefix:@"https://"]) {
//     return [NSURL URLWithString:uri];
//   } else if ([uri hasPrefix:@"file://"] || [uri hasPrefix:@"/"]) {
//     return [NSURL fileURLWithPath:uri];
//   } else {
//     return nil;
//   }
// }

- (NSURL * _Nullable)parseAudioURI:(id)uri {
  if ([uri isKindOfClass:[NSNumber class]]) {
    // Handle require('./file.mp3')
    return [RCTConvert NSURL:uri];
  }
  
  if ([uri isKindOfClass:[NSString class]]) {
    NSString *uriStr = (NSString *)uri;

    if ([uriStr hasPrefix:@"http://"] || [uriStr hasPrefix:@"https://"]) {
      return [NSURL URLWithString:uriStr];
    } else if ([uriStr hasPrefix:@"file://"]) {
      return [NSURL fileURLWithPath:[uriStr stringByReplacingOccurrencesOfString:@"file://" withString:@""]];
    } else if ([uriStr hasPrefix:@"/"]) {
      return [NSURL fileURLWithPath:uriStr];
    }
  }
  
  return nil;
}

#pragma mark - Test

- (void)testing:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject {
  @try {
    resolve(@"AudioModule native integration successful! 🎵");
  } @catch (NSException *exception) {
    reject(@"TEST_ERROR", exception.reason, nil);
  }
}

- (NSString *)testSync {
  return @"AudioModule sync connection working! ⚡";
}

#pragma mark - Playback

- (void)playAudio:(NSString *)uri
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject {
  @try {
    NSError *sessionError = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&sessionError];
    if (sessionError) {
      reject(@"AUDIO_SESSION_ERROR", sessionError.localizedDescription, sessionError);
      return;
    }

    NSURL *url = [self parseAudioURI:uri];
    if (!url) {
      reject(@"INVALID_URI", @"Could not parse audio URI", nil);
      return;
    }

    if ([uri hasPrefix:@"http://"] || [uri hasPrefix:@"https://"]) {
      // remote → AVPlayer
      if (!self.avPlayer || ![self.currentAudioURI isEqualToString:uri]) {
        self.avPlayer = [AVPlayer playerWithURL:url];
        self.currentAsset = [AVAsset assetWithURL:url];
        self.currentAudioURI = uri;
      }
      [self.avPlayer play];
      resolve(@YES);
    } else {
      // local → AVAudioPlayer
      if (self.audioPlayer) { [self.audioPlayer stop]; }
      NSError *playerError = nil;
      self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&playerError];
      if (playerError || !self.audioPlayer) {
        reject(@"AUDIO_ERROR", playerError.localizedDescription ?: @"AVAudioPlayer init failed", playerError);
        return;
      }
      self.currentAudioURI = uri;
      [self.audioPlayer prepareToPlay];
      BOOL ok = [self.audioPlayer play];
      resolve(@(ok));
    }
  } @catch (NSException *exception) {
    reject(@"AUDIO_ERROR", exception.reason, nil);
  }
}

- (void)pauseAudio:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject {
  @try {
    if (self.audioPlayer && self.audioPlayer.isPlaying) {
      [self.audioPlayer pause];
      resolve(@YES);
      return;
    }
    if (self.avPlayer && self.avPlayer.rate > 0.0) {
      [self.avPlayer pause];
      resolve(@YES);
      return;
    }
    resolve(@NO);
  } @catch (NSException *exception) {
    reject(@"AUDIO_ERROR", exception.reason, nil);
  }
}

- (void)stopAudio:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject {
  @try {
    if (self.audioPlayer) {
      [self.audioPlayer stop];
      self.audioPlayer.currentTime = 0;
      resolve(@YES);
      return;
    }
    if (self.avPlayer) {
      [self.avPlayer pause];
      [self.avPlayer seekToTime:kCMTimeZero];
      resolve(@YES);
      return;
    }
    resolve(@NO);
  } @catch (NSException *exception) {
    reject(@"AUDIO_ERROR", exception.reason, nil);
  }
}

- (void)seekToPosition:(double)position
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  @try {
    if (self.audioPlayer) {
      self.audioPlayer.currentTime = position;
      resolve(@YES);
      return;
    }
    if (self.avPlayer) {
      CMTime t = CMTimeMakeWithSeconds(position, NSEC_PER_SEC);
      [self.avPlayer seekToTime:t completionHandler:^(BOOL finished) {
        resolve(@(finished));
      }];
      return;
    }
    resolve(@NO);
  } @catch (NSException *exception) {
    reject(@"AUDIO_ERROR", exception.reason, nil);
  }
}

#pragma mark - Info

- (void)getAudioDuration:(NSString *)uri
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  @try {
    NSURL *url = [self parseAudioURI:uri];
    if (!url) {
      reject(@"INVALID_URI", @"Could not parse audio URI", nil);
      return;
    }

    if ([uri hasPrefix:@"http://"] || [uri hasPrefix:@"https://"]) {
      AVAsset *asset = [AVAsset assetWithURL:url];
      CMTime d = asset.duration;
      if (CMTIME_IS_INVALID(d) || d.timescale == 0) {
        reject(@"DURATION_ERROR", @"Unable to determine duration of remote file", nil);
        return;
      }
      resolve(@(CMTimeGetSeconds(d)));
    } else {
      NSError *err = nil;
      AVAudioPlayer *p = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&err];
      if (err || !p) {
        reject(@"DURATION_ERROR", err.localizedDescription ?: @"AVAudioPlayer init failed", err);
        return;
      }
      resolve(@(p.duration));
    }
  } @catch (NSException *exception) {
    reject(@"DURATION_ERROR", exception.reason, nil);
  }
}

- (void)getCurrentPosition:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject {
  @try {
    if (self.audioPlayer) {
      resolve(@(self.audioPlayer.currentTime));
      return;
    }
    if (self.avPlayer) {
      CMTime t = self.avPlayer.currentTime;
      if (CMTIME_IS_INVALID(t) || t.timescale == 0) {
        resolve(@(0.0));
        return;
      }
      resolve(@(CMTimeGetSeconds(t)));
      return;
    }
    resolve(@(0.0));
  } @catch (NSException *exception) {
    reject(@"POSITION_ERROR", exception.reason, nil);
  }
}

#pragma mark - Waveform (public)

- (void)generateWaveform:(NSString *)uri
                 samples:(double)samples
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @try {
      NSArray<NSNumber *> *data = [self processAudioForWaveform:uri samples:(int)samples];
      dispatch_async(dispatch_get_main_queue(), ^{ resolve(data); });
    } @catch (NSException *exception) {
      dispatch_async(dispatch_get_main_queue(), ^{ reject(@"WAVEFORM_ERROR", exception.reason, nil); });
    }
  });
}

#pragma mark - Waveform (internal)

- (NSArray<NSNumber *> *)processAudioForWaveform:(NSString *)uri samples:(int)samples {
  NSURL *url = [self parseAudioURI:uri];
  if (!url) return [self generateFallbackWaveform:samples];
  if ([uri hasPrefix:@"http://"] || [uri hasPrefix:@"https://"]) {
    return [self processRemoteAudioForWaveform:url samples:samples];
  } else {
    return [self processLocalAudioForWaveform:url samples:samples];
  }
}

// Local file waveform using AudioFile APIs (reads chunks, computes average amplitude)
- (NSArray<NSNumber *> *)processLocalAudioForWaveform:(NSURL *)url samples:(int)samples {
  @try {
    AudioFileID audioFile = NULL;
    OSStatus st = AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &audioFile);
    if (st != noErr || !audioFile) return [self generateFallbackWaveform:samples];

    AudioStreamBasicDescription fmt = {0};
    UInt32 sz = sizeof(fmt);
    st = AudioFileGetProperty(audioFile, kAudioFilePropertyDataFormat, &sz, &fmt);
    if (st != noErr) { AudioFileClose(audioFile); return [self generateFallbackWaveform:samples]; }

    UInt64 dataBytes = 0;
    sz = sizeof(dataBytes);
    st = AudioFileGetProperty(audioFile, kAudioFilePropertyAudioDataByteCount, &sz, &dataBytes);
    if (st != noErr || dataBytes == 0) { AudioFileClose(audioFile); return [self generateFallbackWaveform:samples]; }

    UInt32 bytesPerSample = MAX(1, fmt.mBitsPerChannel / 8);
    UInt32 channels = MAX(1, fmt.mChannelsPerFrame);
    UInt64 totalSamples = dataBytes / (bytesPerSample * channels);
    UInt64 step = MAX((UInt64)1, totalSamples / MAX(1, (UInt64)samples));

    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:samples];
    const UInt32 bufSize = 4096;
    void *buffer = malloc(bufSize);

    UInt64 cur = 0;
    int outIdx = 0;
    double maxAmp = 0.0;

    while (outIdx < samples) {
      UInt32 toRead = bufSize;
      UInt64 start = (cur * bytesPerSample * channels);
      if (start >= dataBytes) break;

      st = AudioFileReadBytes(audioFile, false, start, &toRead, buffer);
      if (st != noErr || toRead == 0) break;

      double amp = 0.0;
      int frames = (int)(toRead / (bytesPerSample * channels));

      if (fmt.mBitsPerChannel == 16) {
        int16_t *s16 = (int16_t *)buffer;
        double sum = 0.0;
        for (int i = 0; i < frames; i++) {
          double sample = 0.0;
          for (int ch = 0; ch < channels; ch++) {
            sample += fabs((double)s16[i * channels + ch]);
          }
          sum += (sample / channels);
        }
        if (frames > 0) amp = (sum / frames) / 32768.0;
      } else if (fmt.mBitsPerChannel == 32) {
        int32_t *s32 = (int32_t *)buffer;
        double sum = 0.0;
        for (int i = 0; i < frames; i++) {
          double sample = 0.0;
          for (int ch = 0; ch < channels; ch++) {
            sample += fabs((double)s32[i * channels + ch]);
          }
          sum += (sample / channels);
        }
        if (frames > 0) amp = (sum / frames) / 2147483648.0;
      } else {
        // unsupported bit depth → fallback to zero for this chunk
        amp = 0.0;
      }

      amp = MIN(1.0, MAX(0.0, amp));
      maxAmp = MAX(maxAmp, amp);
      [out addObject:@(amp)];

      outIdx++;
      cur += step;
    }

    free(buffer);
    AudioFileClose(audioFile);

    while (out.count < (NSUInteger)samples) { [out addObject:@(0.0)]; }

    if (maxAmp > 0) {
      for (NSUInteger i = 0; i < out.count; i++) {
        out[i] = @([out[i] doubleValue] / maxAmp);
      }
    }
    return out;
  } @catch (__unused NSException *e) {
    return [self generateFallbackWaveform:samples];
  }
}

// Remote waveform using AVAssetReader → 16-bit PCM average amplitude
- (NSArray<NSNumber *> *)processRemoteAudioForWaveform:(NSURL *)url samples:(int)samples {
  @try {
    AVAsset *asset = [AVAsset assetWithURL:url];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    if (!track) return [self generateFallbackWaveform:samples];

    NSError *err = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&err];
    if (err || !reader) return [self generateFallbackWaveform:samples];

    NSDictionary *settings = @{
      AVFormatIDKey: @(kAudioFormatLinearPCM),
      AVLinearPCMBitDepthKey: @16,
      AVLinearPCMIsBigEndianKey: @NO,
      AVLinearPCMIsFloatKey: @NO,
      AVLinearPCMIsNonInterleaved: @NO
    };
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:settings];
    [reader addOutput:output];
    [reader startReading];

    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:samples];
    double maxAmp = 0.0;
    int chunks = 0;

    while (reader.status == AVAssetReaderStatusReading) {
      CMSampleBufferRef sbuf = [output copyNextSampleBuffer];
      if (!sbuf) break;

      CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sbuf);
      size_t length = CMBlockBufferGetDataLength(block);
      if (length == 0) { CFRelease(sbuf); continue; }

      SInt16 *data = (SInt16 *)malloc(length); // cast for .mm strictness
      if (!data) { CFRelease(sbuf); break; }
      CMBlockBufferCopyDataBytes(block, 0, length, data);

      size_t count = length / sizeof(SInt16);
      double sum = 0.0;
      for (size_t i = 0; i < count; i++) {
        sum += fabs((double)data[i] / (double)INT16_MAX);
      }
      double avg = (count > 0) ? (sum / (double)count) : 0.0;
      avg = MIN(1.0, MAX(0.0, avg));
      maxAmp = MAX(maxAmp, avg);
      [out addObject:@(avg)];
      chunks++;

      free(data);
      CFRelease(sbuf);

      if (chunks >= samples) break;
    }

    while (out.count < (NSUInteger)samples) { [out addObject:@(0.0)]; }

    if (maxAmp > 0) {
      for (NSUInteger i = 0; i < out.count; i++) {
        out[i] = @([out[i] doubleValue] / maxAmp);
      }
    }
    return out;
  } @catch (__unused NSException *e) {
    return [self generateFallbackWaveform:samples];
  }
}

#pragma mark - Fallback waveform

- (NSArray<NSNumber *> *)generateFallbackWaveform:(int)samples {
  NSMutableArray<NSNumber *> *arr = [NSMutableArray arrayWithCapacity:samples];
  srand((unsigned int)samples);
  for (int i = 0; i < samples; i++) {
    double base = 0.2 + (double)rand() / RAND_MAX * 0.6;
    double var  = sin((double)i / samples * M_PI * 3) * 0.2;
    double amp  = MAX(0.0, MIN(1.0, base + var));
    [arr addObject:@(amp)];
  }
  return arr;
}

#pragma mark - Sync (JSI) methods

// - (BOOL)isPlaying {
//   @try {
//     if (self.audioPlayer) { return self.audioPlayer.isPlaying; }
//     if (self.avPlayer)    { return (self.avPlayer.error == nil) && (self.avPlayer.rate > 0.0); }
//     return NO;
//   } @catch (__unused NSException *e) {
//     return NO;
//   }
// }

// - (double)getCurrentPositionSync {
//   @try {
//     if (self.audioPlayer) { return self.audioPlayer.currentTime; }
//     if (self.avPlayer) {
//       CMTime t = self.avPlayer.currentTime;
//       if (CMTIME_IS_INVALID(t) || t.timescale == 0) return 0.0;
//       return CMTimeGetSeconds(t);
//     }
//     return 0.0;
//   } @catch (__unused NSException *e) {
//     return 0.0;
//   }
// }

- (NSNumber *)isPlaying {
  @try {
    __block BOOL playing = NO;
    if ([NSThread isMainThread]) {
      playing = (self.audioPlayer && self.audioPlayer.isPlaying)
             || (self.avPlayer && self.avPlayer.error == nil && self.avPlayer.rate > 0.0);
    } else {
      dispatch_sync(dispatch_get_main_queue(), ^{
        playing = (self.audioPlayer && self.audioPlayer.isPlaying)
               || (self.avPlayer && self.avPlayer.error == nil && self.avPlayer.rate > 0.0);
      });
    }
    return @(playing); // Boxed
  } @catch (__unused NSException *e) {
    return @(NO);
  }
}

- (NSNumber *)getCurrentPositionSync {
  @try {
    __block double pos = 0.0;
    if ([NSThread isMainThread]) {
      if (self.audioPlayer) {
        pos = self.audioPlayer.currentTime;
      } else if (self.avPlayer) {
        CMTime t = self.avPlayer.currentTime;
        if (!CMTIME_IS_INVALID(t) && t.timescale != 0) {
          pos = CMTimeGetSeconds(t);
          if (!isfinite(pos)) pos = 0.0;
        }
      }
    } else {
      dispatch_sync(dispatch_get_main_queue(), ^{
        if (self.audioPlayer) {
          pos = self.audioPlayer.currentTime;
        } else if (self.avPlayer) {
          CMTime t = self.avPlayer.currentTime;
          if (!CMTIME_IS_INVALID(t) && t.timescale != 0) {
            pos = CMTimeGetSeconds(t);
            if (!isfinite(pos)) pos = 0.0;
          }
        }
      });
    }
    return @(pos); // Boxed
  } @catch (__unused NSException *e) {
    return @(0.0);
  }
}

#pragma mark - Cleanup

- (void)dealloc {
  if (self.audioPlayer) { [self.audioPlayer stop]; self.audioPlayer = nil; }
  if (self.avPlayer)    { [self.avPlayer pause];   self.avPlayer    = nil; }
  self.currentAsset = nil;
}


@end
