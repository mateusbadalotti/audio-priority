#import "ApplicationVolumeEngine.h"

#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>

#include <algorithm>
#include <atomic>
#include <cstring>

namespace {

constexpr AudioObjectPropertyAddress PropertyAddress(
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal,
    AudioObjectPropertyElement element = kAudioObjectPropertyElementMain
) noexcept {
    return {selector, scope, element};
}

OSStatus VolumeIOProc(
    AudioObjectID,
    const AudioTimeStamp *,
    const AudioBufferList *inputData,
    const AudioTimeStamp *,
    AudioBufferList *outputData,
    const AudioTimeStamp *,
    void *clientData
) noexcept;

NSString *StringForProperty(AudioObjectID objectID, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = PropertyAddress(selector);
    CFStringRef value = nullptr;
    UInt32 size = sizeof(value);
    OSStatus status = AudioObjectGetPropertyData(objectID, &address, 0, nullptr, &size, &value);
    if (status != noErr || value == nullptr) {
        return nil;
    }

    return CFBridgingRelease(value);
}

} // namespace

@interface ApplicationVolumeEngine () {
    AudioObjectID _outputDeviceID;
    AudioObjectID _processObjectID;
    AudioObjectID _tapID;
    AudioObjectID _aggregateDeviceID;
    AudioDeviceIOProcID _ioProcID;
    std::atomic<float> _gain;
    BOOL _isRunning;
}
@end

@implementation ApplicationVolumeEngine

- (instancetype)initWithOutputDeviceID:(AudioObjectID)outputDeviceID
                       processObjectID:(AudioObjectID)processObjectID {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _outputDeviceID = outputDeviceID;
    _processObjectID = processObjectID;
    _tapID = kAudioObjectUnknown;
    _aggregateDeviceID = kAudioObjectUnknown;
    _ioProcID = nullptr;
    _gain.store(1, std::memory_order_relaxed);
    _isRunning = NO;
    return self;
}

- (float)volume {
    return _gain.load(std::memory_order_relaxed);
}

- (void)setVolume:(float)volume {
    _gain.store(std::clamp(volume, 0.0f, 1.0f), std::memory_order_relaxed);
}

- (OSStatus)start {
    if (_isRunning) {
        return noErr;
    }

    NSString *outputDeviceUID = StringForProperty(_outputDeviceID, kAudioDevicePropertyDeviceUID);
    if (outputDeviceUID == nil) {
        return kAudioHardwareBadDeviceError;
    }

    CATapDescription *tapDescription = [[CATapDescription alloc]
        initWithProcesses:@[@(_processObjectID)]
        andDeviceUID:outputDeviceUID
        withStream:0];
    tapDescription.name = @"AudioPriority Volume Mixer";
    tapDescription.privateTap = YES;
    tapDescription.muteBehavior = CATapMutedWhenTapped;

    OSStatus status = AudioHardwareCreateProcessTap(tapDescription, &_tapID);
    if (status != noErr) {
        [self stop];
        return status;
    }

    NSString *tapUID = StringForProperty(_tapID, kAudioTapPropertyUID);
    if (tapUID == nil) {
        [self stop];
        return kAudioHardwareUnspecifiedError;
    }

    NSString *aggregateUID = [NSString stringWithFormat:@"app.audiopriority.volume.%@",
                                                        NSUUID.UUID.UUIDString];
    NSDictionary *description = @{
        @kAudioAggregateDeviceNameKey: @"AudioPriority Volume",
        @kAudioAggregateDeviceUIDKey: aggregateUID,
        @kAudioAggregateDeviceSubDeviceListKey: @[
            @{
                @kAudioSubDeviceUIDKey: outputDeviceUID
            }
        ],
        @kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
        @kAudioAggregateDeviceTapListKey: @[
            @{
                @kAudioSubTapUIDKey: tapUID
            }
        ],
        @kAudioAggregateDeviceIsPrivateKey: @YES,
        @kAudioAggregateDeviceIsStackedKey: @NO
    };

    status = AudioHardwareCreateAggregateDevice(
        (__bridge CFDictionaryRef)description,
        &_aggregateDeviceID
    );
    if (status != noErr) {
        [self stop];
        return status;
    }

    status = AudioDeviceCreateIOProcID(
        _aggregateDeviceID,
        VolumeIOProc,
        (__bridge void *)self,
        &_ioProcID
    );
    if (status != noErr) {
        [self stop];
        return status;
    }

    status = AudioDeviceStart(_aggregateDeviceID, _ioProcID);
    if (status != noErr) {
        [self stop];
        return status;
    }

    _isRunning = YES;
    return noErr;
}

- (void)stop {
    if (_aggregateDeviceID != kAudioObjectUnknown && _ioProcID != nullptr) {
        AudioDeviceStop(_aggregateDeviceID, _ioProcID);
        AudioDeviceDestroyIOProcID(_aggregateDeviceID, _ioProcID);
        _ioProcID = nullptr;
    }

    if (_aggregateDeviceID != kAudioObjectUnknown) {
        AudioHardwareDestroyAggregateDevice(_aggregateDeviceID);
        _aggregateDeviceID = kAudioObjectUnknown;
    }

    if (_tapID != kAudioObjectUnknown) {
        AudioHardwareDestroyProcessTap(_tapID);
        _tapID = kAudioObjectUnknown;
    }

    _isRunning = NO;
}

- (void)dealloc {
    [self stop];
}

@end

namespace {

OSStatus VolumeIOProc(
    AudioObjectID,
    const AudioTimeStamp *,
    const AudioBufferList *inputData,
    const AudioTimeStamp *,
    AudioBufferList *outputData,
    const AudioTimeStamp *,
    void *clientData
) noexcept {
    if (outputData == nullptr) {
        return noErr;
    }

    for (UInt32 index = 0; index < outputData->mNumberBuffers; ++index) {
        AudioBuffer &outputBuffer = outputData->mBuffers[index];
        if (outputBuffer.mData != nullptr) {
            std::memset(outputBuffer.mData, 0, outputBuffer.mDataByteSize);
        }
    }

    if (inputData == nullptr || clientData == nullptr) {
        return noErr;
    }

    ApplicationVolumeEngine *engine = (__bridge ApplicationVolumeEngine *)clientData;
    const float gain = engine.volume;
    const UInt32 bufferCount = std::min(inputData->mNumberBuffers, outputData->mNumberBuffers);

    for (UInt32 bufferIndex = 0; bufferIndex < bufferCount; ++bufferIndex) {
        const AudioBuffer &inputBuffer = inputData->mBuffers[bufferIndex];
        AudioBuffer &outputBuffer = outputData->mBuffers[bufferIndex];
        if (inputBuffer.mData == nullptr || outputBuffer.mData == nullptr) {
            continue;
        }

        const UInt32 byteCount = std::min(inputBuffer.mDataByteSize, outputBuffer.mDataByteSize);
        const UInt32 sampleCount = byteCount / sizeof(Float32);
        const Float32 *inputSamples = static_cast<const Float32 *>(inputBuffer.mData);
        Float32 *outputSamples = static_cast<Float32 *>(outputBuffer.mData);

        for (UInt32 sampleIndex = 0; sampleIndex < sampleCount; ++sampleIndex) {
            outputSamples[sampleIndex] = inputSamples[sampleIndex] * gain;
        }
    }

    return noErr;
}

} // namespace
