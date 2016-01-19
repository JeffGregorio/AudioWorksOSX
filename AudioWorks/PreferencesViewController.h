//
//  PreferencesViewController.h
//  AudioWorks
//
//  Created by Jeff Gregorio on 12/9/15.
//  Copyright © 2015 Jeff Gregorio. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#include "AudioController.hpp"

#define kDefaultAudioInputDeviceName @"Soundflower (16ch)"
#define kDefaultAudioInputNumChannels @"2"
#define kDefaultAudioOutputDeviceName @"Built-in Output"
#define kDefaultAudioOutputNumChannels @"2"

@interface PreferencesViewController : NSViewController {
    
    IBOutlet NSPopUpButton *audioInputDeviceSelector;
    NSMenuItem *previousAudioInputDevice;
    IBOutlet NSPopUpButton *audioInputNumChannelsSelector;
    IBOutlet NSPopUpButton *audioOutputDeviceSelector;
    NSMenuItem *previousAudioOutputDevice;
    IBOutlet NSPopUpButton *audioOutputNumChannelsSelector;
    IBOutlet NSPopUpButton *audioSampleRateSelector;
}

@property AudioController *audioController;

- (IBAction)audioInputDeviceSelected:(id)sender;
- (IBAction)audioOutputDeviceSelected:(id)sender;
- (IBAction)audioInputNumChannelsSelected:(id)sender;
- (IBAction)audioOutputNumChannelsSelected:(id)sender;
- (IBAction)audioSampleRateSelected:(id)sender;
- (IBAction)applyButtonPressed:(id)sender;


@end
