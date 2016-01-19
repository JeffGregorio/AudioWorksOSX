//
//  ScopeViewController.h
//  AudioWorks
//
//  Created by Jeff Gregorio on 12/15/15.
//  Copyright © 2015 Jeff Gregorio. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "AudioController.hpp"
#import "METScopeView.h"

#define kScopeUpdateRate (0.05)

@interface ScopeViewController : NSViewController <METScopeViewDelegate> {

    IBOutlet METScopeView *scopeView;
    NSTimer *scopeClock;
    int numPlots;
    
    float *plotTimes;
}

@property AudioController *audioController;
@property (readonly) METScopeView *scopeView;

- (IBAction)domainChanged:(NSSegmentedControl *)sender;
- (IBAction)muteButtonPressed:(id)sender;
- (void)magnifyBegan:(METScopeView*)sender;
- (void)magnifyUpdate:(METScopeView*)sender;
- (void)magnifyEnded:(METScopeView*)sender;
- (void)panBegan:(METScopeView*)sender;
- (void)panUpdate:(METScopeView*)sender;
- (void)panEnded:(METScopeView*)sender;

@end
