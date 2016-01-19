//
//  AudioController.cpp
//  AudioWorks
//
//  Created by Jeff Gregorio on 12/4/15.
//  Copyright © 2015 Jeff Gregorio. All rights reserved.
//

#include "AudioController.hpp"

AudioController::AudioController() : audioBufferLength(kDefaultAudioBufferLength), _streamIsOpen(false), numInputChannels(0), numOutputChannels(0), sampleRate(kDefaultAudioSampleRate), recordingBufferLength(kRecordingBufferDuration * kDefaultAudioSampleRate), numRecordingBuffers(0), outputGain(1.0) {
    
    recBufferMutex = new pthread_mutex_t;
    
    /* Initialize portaudio, get available devices, and initialize input stream info */
    paSetup();
    allocateRecordingBuffers(false);
}

AudioController::~AudioController() {
    
    PaError error = paNoError;
    
    if (_streamIsOpen)
        Pa_AbortStream(stream);
    
    error = Pa_Terminate();
    if (error != paNoError)
        printf("%s: PaError = %s\n", __PRETTY_FUNCTION__, Pa_GetErrorText(error));
}

#pragma mark - Private Methods
PaError AudioController::paSetup() {
    
    PaError error = paNoError;
    
    /* --------------------------- */
    /* === Initialze portaudio === */
    /* --------------------------- */
    error = Pa_Initialize();
    if (error != paNoError) {
        printf("%s: PaError = %s\n", __PRETTY_FUNCTION__, Pa_GetErrorText(error));
        return error;
    }
    
    /* ----------------------------------------- */
    /* === Initialze Input Stream Parameters === */
    /* ----------------------------------------- */
    inputStreamParams.channelCount = 0;
    inputStreamParams.device = paNoDevice;
    inputStreamParams.hostApiSpecificStreamInfo = NULL;
    inputStreamParams.sampleFormat = kDefaultAudioSampleType;
    inputStreamParams.suggestedLatency = NULL;
    
    /* ------------------------------------------ */
    /* === Initialze Output Stream Parameters === */
    /* ------------------------------------------ */
    outputStreamParams.channelCount = 0;
    outputStreamParams.device = paNoDevice;
    outputStreamParams.hostApiSpecificStreamInfo = NULL;
    outputStreamParams.sampleFormat = kDefaultAudioSampleType;
    outputStreamParams.suggestedLatency = NULL;
    
    /* --------------------------------------- */
    /* === Get available audio i/o devices === */
    /* --------------------------------------- */
    int numDevs = Pa_GetDeviceCount();
    if (numDevs == 0)
        return paNoDevice;
    
    for (int i = 0; i < numDevs; i++)
        devices.push_back(Pa_GetDeviceInfo(i));
    
    return error;
}

void AudioController::allocateRecordingBuffers(bool reallocate) {
   
    recordingBufferLength = (int)kRecordingBufferDuration * sampleRate;
    
    /* Delete old buffers if we're reallocating. */
    if (reallocate) {
        for (int i = 0; i < numRecordingBuffers; i++)
            delete [] recBuffers[i];    // Delete each row (channel)
        delete [] recBuffers;           // Delete row pointer array
    }
    
    printf("nInputChannels = %d, numRecordingBuffers = %d\n", numInputChannels, numRecordingBuffers);
    /* If we're allocating new channels, create a mutex for each new channel. */
    if (numRecordingBuffers < numInputChannels) {
        for (int i = numRecordingBuffers; i < numInputChannels; i++) {
            pthread_mutex_init(&recBufferMutex[i], NULL);
            printf("%s: new mutex for channel %d\n", __PRETTY_FUNCTION__, i);
        }
    }
    
    /* Allocate a recording buffer for each input channel */
    recBuffers = new SAMPLE *[numInputChannels];
    for (int i = 0; i < numInputChannels; i++) {
        recBuffers[i] = new SAMPLE[recordingBufferLength];
    }
    
    numRecordingBuffers = numInputChannels;
}

void AudioController::appendToRecordingBuffer(SAMPLE *inBuffer, int channel, int length) {
    
    if (channel >= numInputChannels) {
        printf("%s: Invalid input channel index %d. %d input channels open.\n", __PRETTY_FUNCTION__, channel, numInputChannels);
        return;
    }
    if (length >= recordingBufferLength) {
        printf("%s: Invalid requested buffer length %d. Recording buffer length = %d\n", __PRETTY_FUNCTION__, length, recordingBufferLength);
        return;
    }
    
    pthread_mutex_lock(&recBufferMutex[channel]);
    for (int i = 0; i < recordingBufferLength - length; i++)
        recBuffers[channel][i] = recBuffers[channel][i+length];             // Shift old values back
    for (int i = 0; i < length; i++)
        recBuffers[channel][recordingBufferLength - (length-i)] = inBuffer[i];    // Append new values to the front
    pthread_mutex_unlock(&recBufferMutex[channel]);
}

void AudioController::getRecordingBuffer(SAMPLE *outBuffer, int channel, int length) {
    
    if (channel >= numInputChannels) {
        printf("%s: Invalid input channel index %d. %d input channels open.\n", __PRETTY_FUNCTION__, channel, numInputChannels);
        return;
    }
    if (length > recordingBufferLength) {
        printf("%s: Invalid requested buffer length %d. Recording buffer length = %d\n", __PRETTY_FUNCTION__, length, recordingBufferLength);
        return;
    }
    
    pthread_mutex_lock(&recBufferMutex[channel]);
    for (int i = 0; i < length; i++)
        outBuffer[i] = recBuffers[channel][recordingBufferLength - (length-i)];
    pthread_mutex_unlock(&recBufferMutex[channel]);
}

void AudioController::getRecordingBuffer(SAMPLE *outBuffer, int channel, int startIdx, int endIdx) {
    
    if (channel >= numInputChannels) {
        printf("%s: Invalid input channel index %d. %d input channels open.\n", __PRETTY_FUNCTION__, channel, numInputChannels);
        return;
    }
    if (startIdx < 0 || (endIdx > recordingBufferLength)) {
        printf("%s: Invalid requested buffer indices [%d, %d]. Recording buffer length = %d\n", __PRETTY_FUNCTION__, startIdx, endIdx, recordingBufferLength);
        return;
    }
    
    int length = endIdx - startIdx;
    
    pthread_mutex_lock(&recBufferMutex[channel]);
    for (int i = 0, j = startIdx; i < length; i++, j++)
        outBuffer[i] = recBuffers[channel][j];
    pthread_mutex_unlock(&recBufferMutex[channel]);
}



#pragma mark - Portaudio Callback
int AudioController::processingCallback(const void* input, void* output,
                                        unsigned long bufferLength,
                                        const PaStreamCallbackTimeInfo* timeInfo,
                                        PaStreamCallbackFlags statusFlags) {

    const SAMPLE *in = (const SAMPLE *)input;
    SAMPLE *out = (SAMPLE *)output;

    /* Deinterleave samples into buffer matrix with a row for each channel */
    SAMPLE inBuffers[numInputChannels][bufferLength];
    for (int i = 0; i < bufferLength; i++) {
        for (int j = 0; j < numInputChannels; j++) {
            inBuffers[j][i] = *in++;
        }
    }
    
    /* Copy each channel's samples into recording buffers */
    for (int j = 0; j < numInputChannels; j++) {
        SAMPLE proc[bufferLength];
        for (int i = 0; i < bufferLength; i++) {
            proc[i] = inBuffers[j][i];
        }
        appendToRecordingBuffer(proc, j, (int)bufferLength);
    }

    /* Copy input samples into output, interleaved */
    for (int i = 0; i < bufferLength; i++) {
        for (int j = 0; j < numOutputChannels; j++) {
            *out++ = inBuffers[j][i] * outputGain;
        }
    }
    
    return 0;
}

#pragma mark - Interface Methods
/* Return a map/dictionary of device indices to names for devices supporting input */
std::map<PaDeviceIndex, std::string> AudioController::getAvailableInputDeviceNames() {
    
    std::map<PaDeviceIndex, std::string> devs;
    for (int i = 0; i < devices.size(); i++) {
        if (devices[i]->maxInputChannels > 0)
            devs[i] = devices[i]->name;
    }
    return devs;
}

/* Return a map/dictionary of device indices to names for devices supporting output */
std::map<PaDeviceIndex, std::string> AudioController::getAvailableOutputDeviceNames() {
    
    std::map<PaDeviceIndex, std::string> devs;
    for (int i = 0; i < devices.size(); i++) {
        if (devices[i]->maxOutputChannels > 0)
            devs[i] = devices[i]->name;
    }
    return devs;
}

int AudioController::getMaxNumInputChannels(PaDeviceIndex deviceIndex) {
    
    int num;
    if(validateDeviceIndex(deviceIndex, __PRETTY_FUNCTION__))
        num = devices[deviceIndex]->maxInputChannels;
    return num;
}

int AudioController::getMaxNumOutputChannels(PaDeviceIndex deviceIndex) {
    
    int num;
    if(validateDeviceIndex(deviceIndex, __PRETTY_FUNCTION__))
        num = devices[deviceIndex]->maxOutputChannels;
    return num;
}

std::vector<float> AudioController::getSupportedSampleRates(PaDeviceIndex inputDeviceIndex, PaDeviceIndex outputDeviceIndex) {
    
    std::vector<float> rates;
    
    if(!validateDeviceIndex(inputDeviceIndex, __PRETTY_FUNCTION__))
        return rates;
    if(!validateDeviceIndex(outputDeviceIndex, __PRETTY_FUNCTION__))
        return rates;
    
    /* Standard sample rates to test */
    static double testRates[] = {8000.0, 9600.0, 11025.0, 12000.0, 16000.0, 22050.0, 24000.0, 32000.0, 44100.0, 48000.0, 88200.0, 96000.0, 192000.0, -1.0};      // Negative-terminated array
    
    /* Test input stream parameters */
    PaStreamParameters inputParams;
    inputParams.device = inputDeviceIndex;
    inputParams.channelCount = devices[inputParams.device]->maxInputChannels;
    inputParams.sampleFormat = paFloat32;
    inputParams.suggestedLatency = 0;    // Ignored by Pa_IsFormatSupported
    inputParams.hostApiSpecificStreamInfo = NULL;
    
    /* Test output stream parameters */
    PaStreamParameters outputParams;
    outputParams.device = outputDeviceIndex;
    outputParams.channelCount = devices[outputParams.device]->maxOutputChannels;
    outputParams.sampleFormat = paFloat32;
    outputParams.suggestedLatency = 0;    // Ignored by Pa_IsFormatSupported
    outputParams.hostApiSpecificStreamInfo = NULL;
    
    /* Add the test rate to the input vector if supported */
    for (int i = 0; testRates[i] > 0; i++) {
        if (Pa_IsFormatSupported(&inputParams, &outputParams, testRates[i]) == paFormatIsSupported)
            rates.push_back(testRates[i]);
    }
    
    return rates;
}

/* Set a device to use for input. Return true on success, false otherwise */
bool AudioController::setInputDevice(PaDeviceIndex deviceIndex) {
    
    /* Make sure the device index is valid */
    if(!validateDeviceIndex(deviceIndex, __PRETTY_FUNCTION__))
        return false;
    
    /* Make sure the chosen device supports input */
    if (devices[deviceIndex]->maxInputChannels <= 0) {
        printf("%s: Device #%d (%s) doesn't support input\n", __PRETTY_FUNCTION__, deviceIndex, devices[deviceIndex]->name);
        return false;
    }
    
    /* The index of the device in the input devices list may not be the same as the index in the devices list, so set the device using its actual PaDeviceIndex (second in std::pair<const PaDeviceInfo*, PaDeviceIndex>) */
    inputStreamParams.device = deviceIndex;
    inputStreamParams.suggestedLatency = devices[inputStreamParams.device]->defaultLowInputLatency;
    printf("%s: Using input device %s\n", __PRETTY_FUNCTION__, devices[inputStreamParams.device]->name);
    
    return true;
}

/* Set a device to use for input. Return true on success, false otherwise */
bool AudioController::setOutputDevice(PaDeviceIndex deviceIndex) {
    
    /* Make sure the device index is valid */
    if(!validateDeviceIndex(deviceIndex, __PRETTY_FUNCTION__))
        return false;
    
    /* Make sure the chosen device supports input */
    if (devices[deviceIndex]->maxOutputChannels <= 0) {
        printf("%s: Device #%d (%s) doesn't support output\n", __PRETTY_FUNCTION__, deviceIndex, devices[deviceIndex]->name);
        return false;
    }
    
    /* The index of the device in the input devices list may not be the same as the index in the devices list, so set the device using its actual PaDeviceIndex (second in std::pair<const PaDeviceInfo*, PaDeviceIndex>) */
    outputStreamParams.device = deviceIndex;
    outputStreamParams.suggestedLatency = devices[outputStreamParams.device]->defaultLowOutputLatency;
    printf("%s: Using output device %s\n", __PRETTY_FUNCTION__, devices[outputStreamParams.device]->name);
    
    return true;
}

bool AudioController::setSampleRate(float fs) {
    
    /* Make sure we've already specified an input device to use */
    if (inputStreamParams.device == paNoDevice) {
        printf("%s: Set an input device before specifying input sample rate\n", __PRETTY_FUNCTION__);
        return false;
    }
    
    /* Test input stream parameters */
    PaStreamParameters inputParams;
    inputParams.device = inputStreamParams.device;
    inputParams.channelCount = devices[inputStreamParams.device]->maxInputChannels;
    inputParams.sampleFormat = paFloat32;
    inputParams.suggestedLatency = 0;    // Ignored by Pa_IsFormatSupported
    inputParams.hostApiSpecificStreamInfo = NULL;
    
    if (Pa_IsFormatSupported(&inputParams, NULL, fs) != paFormatIsSupported) {
        printf("%s: Input device %s does not support sample rate %.0f\n", __PRETTY_FUNCTION__, devices[inputStreamParams.device]->name, fs);
        return false;
    }
    
    /* Test output stream parameters */
    PaStreamParameters outputParams;
    outputParams.device = outputStreamParams.device;
    outputParams.channelCount = devices[outputStreamParams.device]->maxOutputChannels;
    outputParams.sampleFormat = paFloat32;
    outputParams.suggestedLatency = 0;    // Ignored by Pa_IsFormatSupported
    outputParams.hostApiSpecificStreamInfo = NULL;
    
    if (Pa_IsFormatSupported(NULL, &outputParams, fs) != paFormatIsSupported) {
        printf("%s: Output device %s does not support sample rate %.0f\n", __PRETTY_FUNCTION__, devices[outputStreamParams.device]->name, fs);
        return false;
    }
    
    sampleRate = fs;
    allocateRecordingBuffers(true);     // Reallocate recording buffers
    
    return true;
}

bool AudioController::setNumInputChannels(int nChannels) {
    
    /* Make sure we've already specified an input device to use */
    if (inputStreamParams.device == paNoDevice) {
        printf("%s: No input device specified\n", __PRETTY_FUNCTION__);
        return false;
    }
    
    numInputChannels = nChannels;
    inputStreamParams.channelCount = numInputChannels;
    
    allocateRecordingBuffers(true);     // Reallocate recording buffers
    
    return true;
}

bool AudioController::setNumOutputChannels(int nChannels) {
    
    /* Make sure we've already specified an input device to use */
    if (outputStreamParams.device == paNoDevice) {
        printf("%s: No output device specified\n", __PRETTY_FUNCTION__);
        return false;
    }
    
    numOutputChannels = nChannels;
    outputStreamParams.channelCount = numOutputChannels;
    
    return true;
}

bool AudioController::openStream() {
    
    /* Make sure we've already specified an input device to use */
    if (inputStreamParams.device == paNoDevice) {
        printf("%s: No input device specified\n", __PRETTY_FUNCTION__);
        return false;
    }
    
    /* Make sure we have input channels allocated */
    if (inputStreamParams.channelCount <= 0) {
        printf("%s: No input channels specified\n", __PRETTY_FUNCTION__);
        return false;
    }
    
    /* Make sure we've already specified an input device to use */
    if (outputStreamParams.device == paNoDevice) {
        printf("%s: No output device specified\n", __PRETTY_FUNCTION__);
        return false;
    }
    
    /* Make sure we have input channels allocated */
    if (outputStreamParams.channelCount <= 0) {
        printf("%s: No output channels specified\n", __PRETTY_FUNCTION__);
        return false;
    }
    
    printStreamParameters(inputStreamParams, "\n== Opening stream with input parameters:");
    printStreamParameters(outputStreamParams, "\n== Output parameters:");
    
    /* Open the stream, passing the static render callback method and input stream parameters */
    PaError error = Pa_OpenStream(&stream,
                                  &inputStreamParams,
                                  &outputStreamParams,
                                  (double)sampleRate,
                                  audioBufferLength,
                                  paNoFlag,
                                  AudioController::staticProcessingCallback,
                                  this);
    if (error != paNoError) {
        printf("%s: PaError = %s\n", __PRETTY_FUNCTION__, Pa_GetErrorText(error));
        return false;
    }
    
//    PaUtil_InitializeBufferProcessor(bufferProcessor,
//                                     numInputChannels,
//                                     inputStreamParams.sampleFormat,
//                                     inputStreamParams.sampleFormat,
//                                     numOutputChannels,
//                                     outputStreamParams.sampleFormat,
//                                     outputStreamParams.sampleFormat,
//                                     (double)sampleRate,
//                                     paNoFlag,
//                                     audioBufferLength,
//                                     audioBufferLength,
//                                     paUtilFixedHostBufferSize,
//                                     AudioController::staticProcessingCallback,
//                                     this);
    
    _streamIsOpen = true;
    
    return true;
}

bool AudioController::closeStream() {
    
    if (!_streamIsOpen) {
        printf("%s: Portaudio stream is not open\n", __PRETTY_FUNCTION__);
        return false;
    }
    
    PaError error = Pa_CloseStream(stream);
    if (error != paNoError) {
        printf("%s: PaError = %s\n", __PRETTY_FUNCTION__, Pa_GetErrorText(error));
        return false;
    }
    
    _streamIsOpen = false;
    
    return true;
}

bool AudioController::streamIsActive() {
    
    if (!stream)
        return false;
    
    return Pa_IsStreamActive(&stream);
}

bool AudioController::startStream() {
    
    if (!_streamIsOpen) {
        printf("%s: Portaudio stream is not open. Use AudioController::openStream() first\n", __PRETTY_FUNCTION__);
        return false;
    }
    
    PaError error = Pa_StartStream(stream);
    if (error != paNoError) {
        printf("%s: PaError = %s\n", __PRETTY_FUNCTION__, Pa_GetErrorText(error));
        return false;
    }
    
    return true;
}

bool AudioController::stopStream() {
    
    if (!Pa_IsStreamActive(stream)) {
        printf("%s: Portaudio stream is not active\n", __PRETTY_FUNCTION__);
        return false;
    }
    
    PaError error = Pa_StopStream(stream);
    if (error != paNoError) {
        printf("%s: PaError = %s\n", __PRETTY_FUNCTION__, Pa_GetErrorText(error));
        return false;
    }
    
    return true;
}

#pragma mark - Utility
bool AudioController::validateDeviceIndex(PaDeviceIndex devIdx, std::string callingFunction) {
    
    bool success = false;
    
    if (devIdx < 0 || devIdx >= devices.size()) {
        printf("%s: Invalid device index %d. %lu available devices\n",
               callingFunction.c_str(), devIdx, devices.size());
        printDeviceInfo();
    }
    else success = true;
    
    return success;
}

void AudioController::printDeviceInfo() {
    for (int i = 0; i < devices.size(); i++) {
        printf("=== Device %d: ================================\n", i);
        printDeviceInfo(devices[i]);
    }
}

void AudioController::printDeviceInfo(const PaDeviceInfo *device) {
    
    printf( "Name                        = %s\n",       device->name);
    printf( "Host API                    = %s\n",       Pa_GetHostApiInfo(device->hostApi)->name);
    printf( "Max inputs = %d\n",                        device->maxInputChannels);
    printf( "Max outputs = %d\n",                       device->maxOutputChannels);
    printf( "Default low input latency   = %8.4f\n",    device->defaultLowInputLatency);
    printf( "Default low output latency  = %8.4f\n",    device->defaultLowOutputLatency);
    printf( "Default high input latency  = %8.4f\n",    device->defaultHighInputLatency);
    printf( "Default high output latency = %8.4f\n",    device->defaultHighOutputLatency);
}

void AudioController::printStreamParameters() {
    printStreamParameters(inputStreamParams, "Input Stream");
    printStreamParameters(outputStreamParams, "Output Stream");
}

void AudioController::printStreamParameters(const PaStreamParameters _params, std::string title) {
    
    printf("%s\n", title.c_str());
    for (int i = 0; i < title.size(); i++)
        printf("-");
    printf("\n");
    printf("device            = %s\n", devices[_params.device]->name);
    printf("channelCount      = %d\n", _params.channelCount);
    printf("sampleFormat      = ");
    
    bool flagTrue = false;
    bool lastTrue = false;
    flagTrue = _params.sampleFormat & paFloat32;
    printf("%s", flagTrue ? "paFloat32" : "\b\b\b ");
    lastTrue = flagTrue;
    flagTrue = _params.sampleFormat & paInt32;
    printf("%s%s", lastTrue ? " | " : "", flagTrue ? "paInt32" : "");
    lastTrue = flagTrue;
    flagTrue = _params.sampleFormat & paInt24;
    printf("%s%s", lastTrue ? " | " : "", flagTrue ? "paInt24" : "");
    lastTrue = flagTrue;
    flagTrue = _params.sampleFormat & paInt16;
    printf("%s%s", lastTrue ? " | " : "", flagTrue ? "paInt16" : "");
    lastTrue = flagTrue;
    flagTrue = _params.sampleFormat & paInt8;
    printf("%s%s", lastTrue ? " | " : "", flagTrue ? "paInt8" : "");
    lastTrue = flagTrue;
    flagTrue = _params.sampleFormat & paCustomFormat;
    printf("%s%s", lastTrue ? " | " : "", flagTrue ? "paCustomFormat" : "");
    lastTrue = flagTrue;
    flagTrue = _params.sampleFormat & paNonInterleaved;
    printf("%s%s", lastTrue ? " | " : "", flagTrue ? "paNonInterleaved" : "");
    printf("\n");
    
    printf("suggestedLatency  = %f\n", _params.suggestedLatency);
    printf("bufferLength      = %d\n", audioBufferLength);
    for (int i = 0; i < title.size(); i++)
        printf("-");
    printf("\n");
}