//
//  AudioController.hpp
//  AudioWorks
//
//  Created by Jeff Gregorio on 12/4/15.
//  Copyright © 2015 Jeff Gregorio. All rights reserved.
//

#ifndef AudioController_hpp
#define AudioController_hpp

#include <stdio.h>
#include <pthread.h>
#include <portaudio.h>
//#include <common/pa_process.h>
#include <Accelerate/Accelerate.h>
#include <vector>
#include <string>
#include <map>

#define kDefaultAudioSampleType paFloat32
#define kDefaultAudioSampleRate (44100.0f)
#define kDefaultAudioBufferLength (512)
#define kMaxNumAudioChannels (8)
#define kRecordingBufferDuration (10.0f)

typedef float SAMPLE;

class AudioController {
    
    /* Port Audio i/o stream */
    PaStream *stream;
    PaStreamParameters inputStreamParams;
    PaStreamParameters outputStreamParams;
    int audioBufferLength;
    bool _streamIsOpen;
    float sampleRate;
    int numInputChannels;
    int numOutputChannels;
    
    SAMPLE outputGain;
    
    /* Devices */
    std::vector<const PaDeviceInfo *> devices;
    
    /* Array of recording buffers */
    int recordingBufferLength;
    int numRecordingBuffers;
    SAMPLE **recBuffers;
    pthread_mutex_t *recBufferMutex;
    
#pragma mark - Private Utility
    PaError paSetup();
    void allocateRecordingBuffers(bool reallocate);
    void appendToRecordingBuffer(SAMPLE *inBuffer, int channel, int length);
    bool validateDeviceIndex(PaDeviceIndex devIdx, std::string callingFunction);
    void printDeviceInfo(const PaDeviceInfo *device);
    void printStreamParameters(const PaStreamParameters _params, std::string title);
    
#pragma mark - Portaudio Callback
    /* Portaudio requires a static callback method, so the staticProcessingCallback() passes control to the instance-specified processingCallback() */
    int processingCallback(const void* input, void* output,
                           unsigned long frameCount,
                           const PaStreamCallbackTimeInfo* timeInfo,
                           PaStreamCallbackFlags statusFlags);
    static int staticProcessingCallback(const void* input, void* output,
                                        unsigned long frameCount,
                                        const PaStreamCallbackTimeInfo* timeInfo,
                                        PaStreamCallbackFlags statusFlags,
                                        void *userData) {
        return ((AudioController *)userData)
        ->processingCallback(input, output, frameCount, timeInfo, statusFlags);
    }

#pragma mark - Public Methods
public:
    
    /* Constructor/Destructor */
    AudioController();
    ~AudioController();
    
    /* Getters */
    std::map<PaDeviceIndex, std::string> getAvailableInputDeviceNames();
    std::map<PaDeviceIndex, std::string> getAvailableOutputDeviceNames();
    PaDeviceIndex getSelectedInputDeviceIdx() { return inputStreamParams.device; }
    PaDeviceIndex getSelectedOutputDeviceIdx() { return outputStreamParams.device; }
    int getMaxNumInputChannels(PaDeviceIndex deviceIndex);
    int getMaxNumOutputChannels(PaDeviceIndex deviceIndex);
    std::vector<float> getSupportedSampleRates(PaDeviceIndex inputDeviceIndex, PaDeviceIndex outputDeviceIndex);
    float getSampleRate() { return sampleRate; }
    int getNumInputChannels() { return numInputChannels; }
    int getNumOutputChannels() { return numOutputChannels; }
    int getAudioBufferLength() { return audioBufferLength; }
    int getRecordingBufferLength() { return recordingBufferLength; }
    float getAudioBufferDuration() { return (float)audioBufferLength / sampleRate; }
    float getRecordingBufferDuration() { return (float)recordingBufferLength / sampleRate; }
    void getRecordingBuffer(SAMPLE *outBuffer, int channel, int length);
    void getRecordingBuffer(SAMPLE *outBuffer, int channel, int startIdx, int endIdx);
    float getOutputGain() { return outputGain; }
    
    /* Setters */
    bool setInputDevice(PaDeviceIndex inputDeviceIdx);
    bool setOutputDevice(PaDeviceIndex outputDeviceIdx);
    bool setSampleRate(float fs);
    bool setNumInputChannels(int nChannels);
    bool setNumOutputChannels(int nChannels);
    void setOutputGain(float gain) { outputGain = gain; }
    
    /* Methods for opening/closing the audio stream */
    bool streamIsOpen() { return _streamIsOpen; }
    bool openStream();
    bool closeStream();
    
    /* Starting/stopping the stream */
    bool streamIsActive();
    bool startStream();
    bool stopStream();
    
    /* Public Utility */
    void printDeviceInfo();
    void printStreamParameters();
};

#endif /* AudioController_hpp */
