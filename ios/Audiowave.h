#import <AudiowaveSpec/AudiowaveSpec.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface Audiowave : NSObject <NativeAudiowaveSpec>

@property (nonatomic, strong) AVAudioPlayer *audioPlayer;     // Local playback
@property (nonatomic, strong) AVAudioSession *audioSession;
@property (nonatomic, strong) NSString *currentAudioURI;
@property (nonatomic, strong) AVPlayer *avPlayer;             // Remote playback
@property (nonatomic, strong) AVAsset *currentAsset;  

@end
