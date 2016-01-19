//
//  METScopeView.h
//  AudioWorks
//
//  Created by Jeff Gregorio on 12/9/15.
//  Copyright © 2015 Jeff Gregorio. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import <Accelerate/Accelerate.h>
#import <pthread.h>

/* ---------------------------- */
/* === Forward declarations === */
/* ---------------------------- */
@protocol METScopeViewDelegate;
@class METScopeAxisView;
@class METScopeGridView;
@class METScopeLabelView;
@class METScopePlotDataView;

/* -------------------- */
/* === Enumerations === */
/* -------------------- */
typedef enum METScopeDisplayMode {
    kMETScopeDisplayModeTimeDomain,
    kMETScopeDisplayModeFrequencyDomain
} METScopeDisplayMode;

typedef enum METScopeAxisScale {
    kMETScopeAxisScaleLinear,
    kMETScopeAxisScaleSemilogY
} METScopeAxisScale;

typedef enum METScopePinchZoomMode {
    kMETScopePinchZoomHoldCenter,
    kMETScopePinchZoomHoldMin,
    kMETScopePinchZoomHoldMax
} METScopePinchZoomMode;

typedef enum METScopeXLabelPosition {
    kMETScopeXLabelPositionBelowAxis,
    kMETScopeXLabelPositionAboveAxis,
    kMETScopeXLabelPositionOutsideBelow,
    kMETScopeXLabelPositionOutsideAbove
} METScopeXLabelPosition;

typedef enum METScopeYLabelPosition {
    kMETScopeYLabelPositionRightOfAxis,
    kMETScopeYLabelPositionLeftOfAxis,
    kMETScopeYLabelPositionOutsideLeft,
    kMETScopeYLabelPositionOutsideRight
} METScopeYLabelPosition;

#pragma mark - METScopeView
@interface METScopeView : NSView {
    
    NSMutableArray *plotDataSubviews;   // Subview array of plot waveforms
    
    METScopeAxisScale axisScale;
    
    int plotResolution;                 // Default plot resolution for added plot data subviews
    
    CGPoint minPlotMin;                 // Hard limits on bounds and range
    CGPoint maxPlotMax;
    CGPoint minPlotRange;
    CGPoint maxPlotRange;
}

@property id <METScopeViewDelegate> delegate;
@property METScopePinchZoomMode pinchZoomMode;
@property (readonly) METScopeDisplayMode displayMode;

@property (readonly) METScopeAxisView *axes;        // Subview that draws axes
@property (readonly) METScopeGridView *grid;        // Subveiw that draws grid
@property (readonly) METScopeLabelView *labels;     // Subview that draws labels

@property (readonly) METScopeXLabelPosition xLabelPosition;
@property (readonly) METScopeYLabelPosition yLabelPosition;
@property NSString *xLabelFormatString;
@property NSString *yLabelFormatString;

@property (readonly) bool axesOn;
@property (readonly) bool gridOn;
@property (readonly) bool xLabelsOn;
@property (readonly) bool yLabelsOn;

@property (readonly) CGPoint visiblePlotMin;
@property (readonly) CGPoint visiblePlotMax;
@property (readonly) CGPoint unitsPerPixel;        // Plot unit <-> pixel conversion factor

@property bool autoScaleXTick;
@property bool autoScaleYTick;
@property (readonly) CGPoint tickSpacing;          // Tick mark/grid line spacing
@property (readonly) CGPoint maxNumTicks;
@property (readonly) CGPoint minNumTicks;

@property NSColor *backgroundColor;

@property int samplingRate;                     /* Set for proper x-axis scaling in
                                                 frequency domain mode (default 44.1kHz) */

@property (readonly) bool currentPan;
@property (readonly) bool currentMagnify;

#pragma mark Public Interface Methods
/* Display parameters */
- (void)setPlotResolution:(int)res;
- (void)setUpFFTWithSize:(int)size;
- (void)setDisplayMode:(METScopeDisplayMode)mode;
- (void)setAxisScale:(METScopeAxisScale)pAxisScale;
- (void)setAxesOn:(bool)pAxesOn;
- (void)setGridOn:(bool)pGridOn;
- (void)setXLabelsOn:(bool)pXLabelsOn;
- (void)setYLabelsOn:(bool)pYLabelsOn;
- (void)setXLabelPosition:(METScopeXLabelPosition)pXLabelPosition;
- (void)setYLabelPosition:(METScopeYLabelPosition)pYLabelPosition;

/* Axis limits and basic grid spacing */
- (void)setHardXLim:(CGFloat)xMin max:(CGFloat)xMax;
- (void)setHardYLim:(CGFloat)yMin max:(CGFloat)yMax;
- (void)setVisibleXLim:(CGFloat)xMin max:(CGFloat)xMax;
- (void)setVisibleYLim:(CGFloat)yMin max:(CGFloat)yMax;
- (void)setPlotUnitsPerXTick:(CGFloat)xTick;
- (void)setPlotUnitsPerYTick:(CGFloat)yTick;

/* Tick/grid auto-scaling */
- (void)setAutoScaleHorizontalTickMin:(int)minNumTicks max:(int)maxNumTicks;
- (void)setAutoScaleVerticalTickMin:(int)minNumTicks max:(int)maxNumTicks;
- (void)performAutoScale;

/* Adding plots, setting/getting plot data */
- (int)addPlotWithColor:(NSColor *)color lineWidth:(float)width;
- (int)addPlotWithResolution:(int)res color:(NSColor *)color lineWidth:(float)width;
- (void)setPlotDataAtIndex:(int)idx withLength:(int)len xData:(float *)xx yData:(float *)yy;
- (void)getPlotDataAtIndex:(int)idx withLength:(int)len xData:(float *)xx yData:(float *)yy;
- (void)setCoordinatesInFDModeAtIndex:(int)idx withLength:(int)len xData:(float *)xx yData:(float *)yy;
- (void)removeAllPlots;


#pragma mark Public Uitility
/* Plot scale units to pixel conversion */
- (CGPoint)plotScaleToPixel:(CGPoint)plotScale;
- (CGFloat)plotScaleToPixelHorizontal:(CGFloat)x;
- (CGFloat)plotScaleToPixelVertical:(CGFloat)y;

/* Pixel to plot scale units conversion */
- (CGPoint)pixelToPlotScale:(CGPoint)pixel;
- (CGFloat)pixelToPlotScaleHorizontal:(CGFloat)x;
- (CGFloat)pixelToPlotScaleVertical:(CGFloat)y;

@end

#pragma mark - METScopeViewDelegate
@protocol METScopeViewDelegate <NSObject>
@optional
- (void)magnifyBegan:(METScopeView*)sender;
- (void)magnifyUpdate:(METScopeView*)sender;
- (void)magnifyEnded:(METScopeView*)sender;
- (void)panBegan:(METScopeView*)sender;
- (void)panUpdate:(METScopeView*)sender;
- (void)panEnded:(METScopeView*)sender;
@end


#pragma mark - METScopeAxisView
@interface METScopeAxisView : NSView {}
@property METScopeView *parent;
@property CGFloat lineWidth;
@property CGFloat lineAlpha;
@property NSColor *lineColor;
@end

#pragma mark - METScopeGridView
@interface METScopeGridView : NSView {}
@property METScopeView *parent;
@property CGFloat lineWidth;
@property CGFloat lineAlpha;
@property CGFloat dashLength;
@property NSColor *lineColor;
@end

#pragma mark - METScopeLabelView
@interface METScopeLabelView : NSView {}
@property METScopeView *parent;
@property NSFont *labelFont;
@property NSColor *labelColor;
@end

#pragma mark - METScopePlotDataView
typedef enum METScopePlotMode {
    kMETScopePlotModeLine,
    kMETScopePlotModeFillSymmetrical,
    kMETScopePlotModeFillBelow              // TO DO
} METScopePlotMode;

@interface METScopePlotDataView : NSView {}
@property METScopeView *parent;
@property (readonly) bool visible;
@property (readonly) int resolution;
@property METScopePlotMode plotMode;
@property CGFloat lineWidth;
@property NSColor *lineColor;
@end






