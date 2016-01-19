//
//  AppDelegate.m
//  AudioWorks
//
//  Created by Jeff Gregorio on 12/9/15.
//  Copyright © 2015 Jeff Gregorio. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

@synthesize audioController;
@synthesize preferencesWindow;
@synthesize preferencesViewController;
@synthesize scopeWindow;
@synthesize scopeViewController;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    audioController = new AudioController();
    
    /* Preferences window and ViewController setup */
    preferencesViewController = [[PreferencesViewController alloc]
                                 initWithNibName:@"PreferencesViewController"
                                 bundle:nil];
    [preferencesViewController setAudioController:audioController];
    preferencesWindow = [NSWindow windowWithContentViewController:preferencesViewController];
    [preferencesWindow setTitle:@"Preferences"];
    
    /* Scope window and ViewController setup */
    scopeViewController = [[ScopeViewController alloc]
                           initWithNibName:@"ScopeViewController"
                           bundle:nil];
    [scopeViewController setAudioController:audioController];
    scopeWindow = [NSWindow windowWithContentViewController:scopeViewController];
    [scopeWindow setTitle:@"Time Domain"];
    
//    NSLog(@"%s: %@", __PRETTY_FUNCTION__, [scopeWindow.contentView constraintsAffectingLayoutForOrientation:NSLayoutConstraintOrientationHorizontal]);
    
    [self openScopeWindow:self];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (IBAction)openPreferencesWindow:(id)sender {
    [preferencesWindow makeKeyAndOrderFront:preferencesWindow];
}

- (IBAction)openScopeWindow:(id)sender {
    [scopeWindow makeKeyAndOrderFront:scopeWindow];
}

@end


















