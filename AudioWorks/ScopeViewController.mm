//
//  ScopeViewController.m
//  AudioWorks
//
//  Created by Jeff Gregorio on 12/15/15.
//  Copyright © 2015 Jeff Gregorio. All rights reserved.
//

#import "ScopeViewController.h"

@interface ScopeViewController ()

@end

@implementation ScopeViewController

@synthesize audioController;
@synthesize scopeView;

- (void)viewDidLoad {
    
    [super viewDidLoad];
    
    /* Time domain scope setup */
    [scopeView setYLabelPosition:kMETScopeYLabelPositionOutsideLeft];
    
    [scopeView setSamplingRate:audioController->getSampleRate()];
    [scopeView setUpFFTWithSize:2048];
    
    [scopeView setHardXLim:-0.001 max:audioController->getRecordingBufferDuration()];
    [scopeView setVisibleXLim:-0.001 max:audioController->getAudioBufferDuration()];
    [scopeView performAutoScale];
    
    numPlots = 0;
    [self reallocatePlots];
    
    [self muteButtonPressed:self];
}

- (void)viewDidAppear {
    [self setScopeClockRate:kScopeUpdateRate];
}

- (void)reallocatePlots {
    
    int nChannels = audioController->getNumInputChannels();
    float hues[nChannels];
    [self linspace:0.0 max:0.75 numElements:nChannels array:hues];
    
    [scopeView removeAllPlots];
    for (int i = 0; i < nChannels; i++)
        [scopeView addPlotWithColor:[NSColor colorWithHue:hues[i]
                                                 saturation:1.0
                                                 brightness:1.0
                                                      alpha:1.0]
                            lineWidth:2.0];
    numPlots = nChannels;
}

#pragma mark - Plot Updates
- (void)setScopeClockRate:(float)rate {
    
    if ([scopeClock isValid])
        [scopeClock invalidate];
    
    if ([scopeView displayMode] == kMETScopeDisplayModeTimeDomain)
        scopeClock = [NSTimer scheduledTimerWithTimeInterval:rate
                                                        target:self
                                                      selector:@selector(updateTDScope)
                                                      userInfo:nil
                                                       repeats:YES];
    else
        scopeClock = [NSTimer scheduledTimerWithTimeInterval:rate
                                                      target:self
                                                    selector:@selector(updateFDScope)
                                                    userInfo:nil
                                                     repeats:YES];
    
}

- (void)updateTDScope {
    
    if ([scopeView currentPan] || [scopeView currentMagnify])
        return;
    
    if (numPlots != audioController->getNumInputChannels())
        [self reallocatePlots];
    
    int startIdx = fmax(scopeView.visiblePlotMin.x * audioController->getSampleRate(), 0.0f);
    int endIdx = fmin(scopeView.visiblePlotMax.x * audioController->getSampleRate(),
                      audioController->getRecordingBufferLength());
    int visibleBufferLength = endIdx - startIdx;

    /* Get buffer of times for each sample */
    plotTimes = (float *)malloc(visibleBufferLength * sizeof(float));
    [self linspace:fmax(scopeView.visiblePlotMin.x, 0.0f)
               max:scopeView.visiblePlotMax.x
       numElements:visibleBufferLength
             array:plotTimes];
    
    /* Allocate wet/dry signal buffers */
    float *ybuffer = (float *)malloc(visibleBufferLength * sizeof(float));
    
    for (int channel = 0; channel < audioController->getNumInputChannels(); channel++) {
        
        audioController->getRecordingBuffer((SAMPLE *)ybuffer, channel, visibleBufferLength);
        [scopeView setPlotDataAtIndex:channel
                             withLength:visibleBufferLength
                                  xData:plotTimes
                                  yData:ybuffer];
    }
    
    free(plotTimes);
    free(ybuffer);
}

- (void)updateFDScope {
    
    if ([scopeView currentPan] || [scopeView currentMagnify])
        return;
    
    if (numPlots != audioController->getNumInputChannels())
        [self reallocatePlots];
    
    int nChannels = audioController->getNumInputChannels();
    int bufferLength = audioController->getAudioBufferLength();
    float sampleRate = audioController->getSampleRate();
    
    /* Get buffer of times for each sample */
    plotTimes = (float *)malloc(bufferLength * sizeof(float));
    [self linspace:0.0 max:(bufferLength * sampleRate) numElements:bufferLength array:plotTimes];
    
    /* Allocate wet/dry signal buffers */
    float *ybuffer = (float *)malloc(bufferLength * sizeof(float));
    
    for (int channel = 0; channel < nChannels; channel++) {
    
        /* Get current visible samples from the audio controller */
        audioController->getRecordingBuffer((SAMPLE *)ybuffer, channel, bufferLength);
        
        [scopeView setPlotDataAtIndex:channel
                             withLength:bufferLength
                                  xData:plotTimes
                                  yData:ybuffer];
    }
    
    free(plotTimes);
    free(ybuffer);
}



- (IBAction)domainChanged:(NSSegmentedControl *)sender {
    
    switch ([sender selectedSegment]) {
            
        case 0:
            [scopeView setDisplayMode:kMETScopeDisplayModeTimeDomain];
            break;
        case 1:
            [scopeView setDisplayMode:kMETScopeDisplayModeFrequencyDomain];
            break;
        default:
            return;
    }
    
    [self setScopeClockRate:kScopeUpdateRate];
}

- (IBAction)muteButtonPressed:(id)sender {
    
    if (audioController->getOutputGain() == 1.0)
        audioController->setOutputGain(0.0);
    else
        audioController->setOutputGain(1.0);
}


#pragma mark - METScopeViewDelegate Methods
- (void)magnifyBegan:(METScopeView*)sender {
    [self setScopeClockRate:kScopeUpdateRate/2.0];
}
- (void)magnifyUpdate:(METScopeView*)sender {
    
}
- (void)magnifyEnded:(METScopeView*)sender {
    [self setScopeClockRate:kScopeUpdateRate];
}
- (void)panBegan:(METScopeView*)sender {
    [self setScopeClockRate:kScopeUpdateRate/2.0];
}
- (void)panUpdate:(METScopeView*)sender {
    
}
- (void)panEnded:(METScopeView*)sender {
    [self setScopeClockRate:kScopeUpdateRate];
}


#pragma mark - Utility
/* Generate a linearly-spaced set of indices for sampling an incoming waveform */
- (void)linspace:(float)minVal max:(float)maxVal numElements:(int)size array:(float *)array {
    
    float step = (maxVal - minVal) / (size-1);
    array[0] = minVal;
    for (int i = 1; i < size-1 ;i++) {
        array[i] = array[i-1] + step;
    }
    array[size-1] = maxVal;
}

- (void)logspace:(float)minVal max:(float)maxVal numElements:(int)size array:(float *)array {
    
    float min = log10f(minVal);
    float max = log10f(maxVal);
    [self linspace:min max:max numElements:size array:array];
    for (int i = 0;i<size;i++) {
        array[i] = powf(10, array[i]);
    }
}


@end
