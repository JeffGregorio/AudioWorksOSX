//
//  PreferencesViewController.m
//  AudioWorks
//
//  Created by Jeff Gregorio on 12/9/15.
//  Copyright © 2015 Jeff Gregorio. All rights reserved.
//

#import "PreferencesViewController.h"

@interface PreferencesViewController ()

@end

@implementation PreferencesViewController
@synthesize audioController;

- (void)viewDidLoad {
    
    [super viewDidLoad];
    [self audioSetup];
}

- (void)viewDidAppear {
    [super viewDidAppear];
}

- (void)viewDidDisappear {
    [super viewDidDisappear];
}

- (void)audioSetup {
    
    /* Generate list of input/output devices; select the defaults */
    [self populateAudioInputDeviceSelector];
    [audioInputDeviceSelector selectItemWithTitle:kDefaultAudioInputDeviceName];
    previousAudioInputDevice = [audioInputDeviceSelector selectedItem];
    [self populateAudioOutputDeviceSelector];
    [audioOutputDeviceSelector selectItemWithTitle:kDefaultAudioOutputDeviceName];
    previousAudioOutputDevice = [audioOutputDeviceSelector selectedItem];
    
    /* Generate list for number of i/o channels and supported sample rates */
    [self populateAudioInputNumChannelsSelector:false];
    [audioInputNumChannelsSelector selectItemWithTitle:kDefaultAudioInputNumChannels];
    [self populateAudioOutputNumChannelsSelector:false];
    [audioOutputNumChannelsSelector selectItemWithTitle:kDefaultAudioOutputNumChannels];
    [self populateAudioSampleRateSelector:false];
    [audioSampleRateSelector selectItemWithTitle:[NSString stringWithFormat:@"%.f", kDefaultAudioSampleRate]];
    
    /* Set devices/channels/sample rate and enable audio */
    [self applyButtonPressed:self];
    audioController->openStream();
    audioController->startStream();
}

- (void)populateAudioInputDeviceSelector {
    
    /* Query input devices */
    std::map<PaDeviceIndex, std::string> devNames = audioController->getAvailableInputDeviceNames();
    
    /* Clear the input device list */
    [audioInputDeviceSelector removeAllItems];
    
    /* Add an item with the name of the device, tagged with the device's index */
    for (auto it = devNames.begin(); it != devNames.end(); ++it) {
        [audioInputDeviceSelector addItemWithTitle:[NSString stringWithFormat:@"%s", it->second.c_str()]];
        [[audioInputDeviceSelector lastItem] setTag:it->first];
    }
}

- (void)populateAudioOutputDeviceSelector {
    
    /* Query output devices */
    std::map<PaDeviceIndex, std::string> devNames = audioController->getAvailableOutputDeviceNames();
    
    /* Clear the input device list */
    [audioOutputDeviceSelector removeAllItems];
    
    /* Add an item with the name of the device, tagged with the device's index */
    for (auto it = devNames.begin(); it != devNames.end(); ++it) {
        [audioOutputDeviceSelector addItemWithTitle:[NSString stringWithFormat:@"%s", it->second.c_str()]];
        [[audioOutputDeviceSelector lastItem] setTag:it->first];
    }
}

- (void)populateAudioInputNumChannelsSelector:(bool)retainCurrent {
    
    /* Get the currently selected item if we're retaining */
    NSString *title;
    if (retainCurrent) {
        title = [audioInputNumChannelsSelector titleOfSelectedItem];
    }
    
    /* Remove all items from the number of ouptut channels list */
    [audioInputNumChannelsSelector removeAllItems];
    
    /* Get maximum number of input channels for current device and populate the list to the max */
    int chMax = audioController->getMaxNumInputChannels((PaDeviceIndex)[audioInputDeviceSelector selectedTag]);
    
    /* Populate the number of input channels list */
    for (int i = 1; i <= chMax; i++)
        [audioInputNumChannelsSelector addItemWithTitle:[NSString stringWithFormat:@"%d", i]];
    
    /* Select previously selected item if present, last item otherwise */
    if (retainCurrent) {
        if ([audioInputNumChannelsSelector itemWithTitle:title])
            [audioInputNumChannelsSelector selectItemWithTitle:title];
        else
            [audioInputNumChannelsSelector selectItem:[audioInputNumChannelsSelector lastItem]];
    }
}

- (void)populateAudioOutputNumChannelsSelector:(bool)retainCurrent {
    
    /* Get the currently selected item if we're retaining */
    NSString *title;
    if (retainCurrent)
        title = [audioOutputNumChannelsSelector titleOfSelectedItem];
    
    /* Remove all items from the number of ouptut channels list */
    [audioOutputNumChannelsSelector removeAllItems];
    
    /* Get maximum number of input channels for current device and populate the list to the max */
    int chMax = audioController->getMaxNumOutputChannels((PaDeviceIndex)[audioOutputDeviceSelector selectedTag]);
    
    /* Populate the number of input channels list */
    for (int i = 1; i <= chMax; i++)
        [audioOutputNumChannelsSelector addItemWithTitle:[NSString stringWithFormat:@"%d", i]];
    
    /* Select previously selected item if present, last item otherwise. */
    if (retainCurrent) {
        if ([audioOutputNumChannelsSelector itemWithTitle:title])
            [audioOutputNumChannelsSelector selectItemWithTitle:title];
        else
            [audioOutputNumChannelsSelector selectItem:[audioOutputNumChannelsSelector lastItem]];
    }
}

- (void)populateAudioSampleRateSelector:(bool)retainCurrent {
    
    /* Get the currently selected item if we're retaining */
    NSString *title;
    if (retainCurrent)
        title = [audioSampleRateSelector titleOfSelectedItem];
    
    [audioSampleRateSelector removeAllItems];
    
    /* Only add a sample rate to the list if it is supported by both current input and output devices */
    PaDeviceIndex inputDeviceIdx = (PaDeviceIndex)[audioInputDeviceSelector selectedTag];
    PaDeviceIndex outputDeviceIdx = (PaDeviceIndex)[audioOutputDeviceSelector selectedTag];
    std::vector<float> sampleRates = audioController->getSupportedSampleRates(inputDeviceIdx, outputDeviceIdx);
    
    for (int i = 0; i < sampleRates.size(); i++) {
        [audioSampleRateSelector addItemWithTitle:[NSString stringWithFormat:@"%.f", sampleRates[i]]];
    }
    
    /* Select previously selected item if present, last item otherwise. */
    if (retainCurrent) {
        if ([audioSampleRateSelector itemWithTitle:title])
            [audioSampleRateSelector selectItemWithTitle:title];
        else
            [audioSampleRateSelector selectItem:[audioSampleRateSelector lastItem]];
    }
}

/* Select the input device with specified default name */
- (void)selectDefaultAudioInputDevice {
    
    NSString *devName;
    for (int i = 0; i < [audioInputDeviceSelector numberOfItems]; i++) {
        devName = [[audioInputDeviceSelector itemAtIndex:i] title];;
        if ([devName isEqualToString:kDefaultAudioInputDeviceName])
            [audioInputDeviceSelector selectItemAtIndex:i];
    }
}

#pragma mark - IBActions
- (IBAction)audioInputDeviceSelected:(id)sender {
    
    /* Querying supported sample rates using a device that's currently open causes an error, so don't bother repopulating num channels and sample rate menus if we haven't selected a new device */
    if ([audioInputDeviceSelector selectedItem] == previousAudioInputDevice)
        return;
    
    [self populateAudioInputNumChannelsSelector:true];
    [self populateAudioSampleRateSelector:true];
    previousAudioInputDevice = [audioInputDeviceSelector selectedItem];
}

- (IBAction)audioOutputDeviceSelected:(id)sender {
    
    /* Querying supported sample rates using a device that's currently open causes an error, so don't bother repopulating num channels and sample rate menus if we haven't selected a new device */
    if ([audioOutputDeviceSelector selectedItem] == previousAudioOutputDevice)
        return;
    
    [self populateAudioOutputNumChannelsSelector:true];
    [self populateAudioSampleRateSelector:true];
    previousAudioOutputDevice = [audioOutputDeviceSelector selectedItem];
}

- (IBAction)audioInputNumChannelsSelected:(id)sender {}
- (IBAction)audioOutputNumChannelsSelected:(id)sender {}
- (IBAction)audioSampleRateSelected:(id)sender {}

- (IBAction)applyButtonPressed:(id)sender {
    
    bool streamWasActive = audioController->streamIsActive();
    bool streamWasOpen = audioController->streamIsOpen();
    if (streamWasActive) audioController->stopStream();
    if (streamWasOpen)  audioController->closeStream();
    
    PaDeviceIndex idx;
    int num;
    float fs;
    
    /* Audio input device */
    idx = (PaDeviceIndex)[audioInputDeviceSelector selectedTag];
    audioController->setInputDevice(idx);
    
    num = [[audioInputNumChannelsSelector titleOfSelectedItem] intValue];
    audioController->setNumInputChannels(num);
    
    /* Audio output device */
    idx = (PaDeviceIndex)[audioOutputDeviceSelector selectedTag];
    audioController->setOutputDevice(idx);
    
    num = [[audioOutputNumChannelsSelector titleOfSelectedItem] intValue];
    audioController->setNumOutputChannels(num);
    
    /* Sample rate */
    fs = [[audioSampleRateSelector titleOfSelectedItem] floatValue];
    audioController->setSampleRate(fs);
    
    if (streamWasOpen) audioController->openStream();
    if (streamWasActive) audioController->startStream();
}

@end





















