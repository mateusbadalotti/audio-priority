#ifndef ApplicationVolumeEngine_h
#define ApplicationVolumeEngine_h

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

@interface ApplicationVolumeEngine : NSObject

- (instancetype)initWithOutputDeviceID:(AudioObjectID)outputDeviceID
                       processObjectID:(AudioObjectID)processObjectID NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (atomic) float volume;

- (OSStatus)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END

#endif
