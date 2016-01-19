//
//  AppDelegate.h
//  AudioWorks
//
//  Created by Jeff Gregorio on 12/9/15.
//  Copyright © 2015 Jeff Gregorio. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#include "AudioController.hpp"
#import "PreferencesViewController.h"
#import "ScopeViewController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

/* Back end */
@property AudioController *audioController;

/* Windows and ViewControllers */
@property NSWindow *preferencesWindow;
@property PreferencesViewController *preferencesViewController;
@property NSWindow *scopeWindow;
@property ScopeViewController *scopeViewController;

- (IBAction)openPreferencesWindow:(id)sender;
- (IBAction)openScopeWindow:(id)sender;

@end

