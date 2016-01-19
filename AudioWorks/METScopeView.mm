//
//  METScopeView.m
//  AudioWorks
//
//  Created by Jeff Gregorio on 12/9/15.
//  Copyright © 2015 Jeff Gregorio. All rights reserved.
//

#import "METScopeView.h"

static NSColor *const kDefaultBackgroundColor = [NSColor blackColor];
static NSColor *const kDefaultGridColor = [NSColor whiteColor];

#define METScopeView_XLabel_Outside_Extension 15
#define METScopeview_YLabel_Outside_Extension 28

#pragma mark Private Interfaces
@interface METScopeView () {
    
    /* Gesture recognizers */
    NSPanGestureRecognizer *panGestureRecognizer;
    CGPoint previousPanLoc;
    
    NSMagnificationGestureRecognizer *magnificationGestureRecognizer;
    CGFloat previousMagnificationScale;
    
    /* Spectrum mode FFT parameters */
    int fftSize;                // Length of FFT, 2*nBins
    int windowSize;             // Length of Hann window
    float *freqs;               // Frequency bin centers
    float *inRealBuffer;        // Input buffer
    float *outRealBuffer;       // Output buffer
    float *window;              // Hann window
    CGFloat scale;              // Normalization constant
    FFTSetup fftSetup;          // vDSP FFT struct
    COMPLEX_SPLIT splitBuffer;  // Buffer holding real and complex parts
}

/* Private uitility methods */
- (CGPoint)tickSpacingInPixels;     /* Get current tick spacing converted to pixels */
- (void)linspace:(float)minVal max:(float)maxVal numElements:(int)size array:(float *)array;
- (void)logspace:(float)minVal max:(float)maxVal numElements:(int)size array:(float *)array;

/* Gesture handling */
- (void)handlePan:(NSPanGestureRecognizer *)sender;
- (void)handleMagnify:(NSMagnificationGestureRecognizer *)sender;
@end

@interface METScopeAxisView () {}
- (id)initWithParentView:(METScopeView *)parent;
@end

@interface METScopeGridView () {}
- (id)initWithParentView:(METScopeView *)parent;
@end

@interface METScopeLabelView () {
    NSDictionary *labelAttributes;
    CGPoint pixelOffset;
}
- (id)initWithParentView:(METScopeView *)parent;
@end

@interface METScopePlotDataView () {
    float *inputXBuffer;
    float *inputYBuffer;
    float *resamplingIndices;
    CGPoint *plotPixels;
    pthread_mutex_t dataMutex;
}
@property (readonly) CGPoint *plotUnits;
- (id)initWithParentView:(METScopeView *)pParent resolution:(int)pRes plotColor:(NSColor *)pColor lineWidth:(CGFloat)pWidth;
- (void)setResolution:(int)pRes;
- (void)setDataWithLength:(int)length xData:(float *)xx yData:(float *)yy;
- (void)rescalePlotData;
@end

#pragma mark - METScopeView
@implementation METScopeView

@synthesize delegate;
@synthesize pinchZoomMode;
@synthesize displayMode;

@synthesize axes;
@synthesize grid;
@synthesize labels;

@synthesize xLabelPosition;
@synthesize yLabelPosition;
@synthesize xLabelFormatString;
@synthesize yLabelFormatString;

@synthesize axesOn;
@synthesize gridOn;
@synthesize xLabelsOn;
@synthesize yLabelsOn;

@synthesize visiblePlotMin;
@synthesize visiblePlotMax;
@synthesize unitsPerPixel;

@synthesize autoScaleXTick;
@synthesize autoScaleYTick;
@synthesize tickSpacing;
@synthesize maxNumTicks;
@synthesize minNumTicks;

@synthesize backgroundColor;

@synthesize samplingRate;

@synthesize currentPan;
@synthesize currentMagnify;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)dealloc {
    
}

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    
    [super setNeedsDisplay:needsDisplay];
    
    /* Propagate update to all subviews */
    [axes setNeedsDisplay:needsDisplay];
    [grid setNeedsDisplay:needsDisplay];
    [labels setNeedsDisplay:needsDisplay];
    for (int i = 0; i < plotDataSubviews.count; i++) {
        [((METScopePlotDataView *)plotDataSubviews[i]) setNeedsDisplay:needsDisplay];
    }
}

- (void)viewWillStartLiveResize {
    
}

- (void)viewDidEndLiveResize {
    NSLog(@"x = [%f, %f]", visiblePlotMin.x, visiblePlotMax.x);
    NSLog(@"y = [%f, %f]", visiblePlotMin.y, visiblePlotMax.y);
    [self performAutoScale];
}

- (void)setup {
    
    /* Appearance */
    backgroundColor = kDefaultBackgroundColor;
    plotResolution = self.frame.size.width;
    
    [self setWantsLayer:YES];
    [self.layer setBackgroundColor:backgroundColor.CGColor];
    [self.layer setBorderWidth:1.0];
    [self.layer setBorderColor:[NSColor blackColor].CGColor];
    
    [self setUpSubviews];
//    [self setUpSubviewConstraints];
    [self setUpGestureRecognizers];
    
    axisScale = kMETScopeAxisScaleLinear;
    pinchZoomMode = kMETScopePinchZoomHoldMin;
    
    maxPlotRange.x = INFINITY;
    maxPlotRange.y = INFINITY;
    minPlotRange.x = 0.000001;
    minPlotRange.y = 0.000001;
    
    /* setDisplayMode: sets default hard and visible plot limits */
    [self setDisplayMode:kMETScopeDisplayModeTimeDomain];
    
    maxNumTicks.x = 8;
    maxNumTicks.y = 6;
    minNumTicks.x = 6;
    minNumTicks.y = 4;
    autoScaleXTick = true;
    autoScaleYTick = true;
    [self performAutoScale];
}

- (void)setUpSubviews {
    
    /* Axes */
    axesOn = true;
    axes = [[METScopeAxisView alloc] initWithParentView:self];
    [self addSubview:axes];
    
    /* Grid */
    gridOn = true;
    grid = [[METScopeGridView alloc] initWithParentView:self];
    [self addSubview:grid];
    
    /* Labels */
    xLabelsOn = true;
    yLabelsOn = true;
    xLabelPosition = kMETScopeXLabelPositionBelowAxis;
    yLabelPosition = kMETScopeYLabelPositionLeftOfAxis;
    labels = [[METScopeLabelView alloc] initWithParentView:self];
    [self addSubview:labels];
    
    /* Plot Data */
    plotDataSubviews = [[NSMutableArray alloc] init];
}

/* Set the subviews (axes, grid, labels, plot data) to resize with METScopeView */
- (void)setUpSubviewConstraints {
    
    [axes setTranslatesAutoresizingMaskIntoConstraints:NO];
    [grid setTranslatesAutoresizingMaskIntoConstraints:NO];
    [labels setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    NSDictionary *subviews = NSDictionaryOfVariableBindings(axes, grid, labels);
    
    [self addConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[axes]|"
                                             options:0
                                             metrics:nil
                                               views:subviews]];
    [self addConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[axes]|"
                                             options:0
                                             metrics:nil
                                               views:subviews]];
    
    [self addConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[grid]|"
                                             options:0
                                             metrics:nil
                                               views:subviews]];
    [self addConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[grid]|"
                                             options:0
                                             metrics:nil
                                               views:subviews]];
    
    [self addConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[labels]|"
                                             options:0
                                             metrics:nil
                                               views:subviews]];
    [self addConstraints:
     [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[labels]|"
                                             options:0
                                             metrics:nil
                                               views:subviews]];
}

- (void)setUpGestureRecognizers {
    
    panGestureRecognizer = [[NSPanGestureRecognizer alloc]
                            initWithTarget:self
                            action:@selector(handlePan:)];
    [self addGestureRecognizer:panGestureRecognizer];
    
    magnificationGestureRecognizer = [[NSMagnificationGestureRecognizer alloc]
                                      initWithTarget:self
                                      action:@selector(handleMagnify:)];
    [self addGestureRecognizer:magnificationGestureRecognizer];
}

#pragma mark Interface Methods
/* Set number of points sampled from incoming waveforms */
- (void)setPlotResolution:(int)res {
    
    plotResolution = res;   // Default plot resolution for new plot data subviews
    
    /* Update resoution for any existing subviews */
    for (int i = 0; i < plotDataSubviews.count; i++) {
        [((METScopePlotDataView *)plotDataSubviews[i]) setResolution:plotResolution];
    }
}

/* Initialize a vDSP fft struct, buffers, windows, etc. */
- (void)setUpFFTWithSize:(int)size {
    
    fftSize = size;
    
    scale = 2.0f / (float)(fftSize);     // Normalization constant
    
    /* Buffers */
    freqs = (float *)malloc(fftSize/2 * sizeof(float));
    [self linspace:0.0 max:samplingRate/2 numElements:fftSize/2 array:freqs];
    
    inRealBuffer = (float *)malloc(fftSize * sizeof(float));
    outRealBuffer = (float *)malloc(fftSize * sizeof(float));
    splitBuffer.realp = (float *)malloc(fftSize/2 * sizeof(float));
    splitBuffer.imagp = (float *)malloc(fftSize/2 * sizeof(float));
    
    /* Hann Window */
    windowSize = size;
    window = (float *)calloc(windowSize, sizeof(float));
    vDSP_hann_window(window, windowSize, vDSP_HANN_NORM);
    
    /* Allocate the FFT struct */
    fftSetup = vDSP_create_fftsetup(log2f(fftSize), FFT_RADIX2);
}

/* Set the display mode to time/frequency domain and automatically rescale to default limits */
- (void)setDisplayMode:(METScopeDisplayMode)mode {
    
    if (mode == kMETScopeDisplayModeTimeDomain) {
        
        axisScale = kMETScopeAxisScaleLinear;
    
        /* Hard limits */
        [self setHardXLim:-0.001 max:10.0];
        [self setHardYLim:-2.0 max:2.0];
        
        /* Tick/grid/labels */
        [self setPlotUnitsPerXTick:1.0];
        [self setPlotUnitsPerYTick:0.25];
        xLabelFormatString = @"%5.3f";
        yLabelFormatString = @"%3.2f";
        
        /* Visible limits */
        [self setVisibleXLim:-0.001 max:5.0];
        [self setVisibleYLim:-1.0 max:1.0];
        
        displayMode = mode;
    }
    
    else if (mode == kMETScopeDisplayModeFrequencyDomain) {
        
        axisScale = kMETScopeAxisScaleSemilogY;
        
        /* Hard limits */
        [self setHardXLim:0.0 max:12000.0];
        [self setHardYLim:-80.0 max:0.0];
        
        /* Tick/grid/labels*/
        [self setPlotUnitsPerXTick:4000.0];
        [self setPlotUnitsPerYTick:20.0];
        xLabelFormatString = @"%5.0f";
        yLabelFormatString = @"%3.2f";
        
        /* Visible limits */
        [self setVisibleXLim:minPlotMin.x max:maxPlotMax.x];
        [self setVisibleYLim:minPlotMin.y max:maxPlotMax.y];
        
        displayMode = mode;
    }
    
    /* Update the subviews */
    [self setNeedsDisplay:true];
}

/* Set the scaling linear/semilogx/semilogy/loglog of the axes */
- (void)setAxisScale:(METScopeAxisScale)pAxisScale {
    
    axisScale = pAxisScale;
    
    if (axisScale != kMETScopeAxisScaleLinear) {
        [self setAxesOn:false];
    }
    
    else {
        [self setAxesOn:true];
    }
}

- (void)setAxesOn:(bool)pAxesOn {
    
    if (axesOn == pAxesOn)
        return;
    
    axesOn = pAxesOn;
    
    if (!axesOn) {
        [axes removeFromSuperview];
    }
    else {
        [self addSubview:axes];
    }
}
- (void)setGridOn:(bool)pGridOn {
    
    if (gridOn == pGridOn)
        return;
    
    gridOn = pGridOn;
    
    if (!gridOn) {
        [grid removeFromSuperview];
    }
    else {
        [self addSubview:grid];
    }
}
- (void)setXLabelsOn:(bool)pXLabelsOn {
    
    if (xLabelsOn == pXLabelsOn)
        return;
    
    xLabelsOn = pXLabelsOn;
    
    if (!xLabelsOn && !yLabelsOn) {
        [labels removeFromSuperview];
    }
    else {
        [self addSubview:labels];
    }
}
- (void)setYLabelsOn:(bool)pYLabelsOn {
    
    if (yLabelsOn == pYLabelsOn)
        return;
    
    yLabelsOn = pYLabelsOn;
    
    if (!yLabelsOn && !xLabelsOn) {
        [labels removeFromSuperview];
    }
    else {
        [self addSubview:labels];
    }
}

/* Set the positions of the labels relative to the axis or plot bounds */
- (void)setXLabelPosition:(METScopeXLabelPosition)pXLabelPosition {
    
    xLabelPosition = pXLabelPosition;
    CGRect labelFrame = labels.frame;
    
    /* If the labels are at one of the outside positions, extend the frame */
    if (xLabelPosition == kMETScopeXLabelPositionOutsideBelow) {
        labelFrame.size.height += METScopeView_XLabel_Outside_Extension;
        labelFrame.origin.y += METScopeView_XLabel_Outside_Extension;
    }
    else if (xLabelPosition == kMETScopeXLabelPositionOutsideAbove)
        labelFrame.size.height += METScopeView_XLabel_Outside_Extension;
    
    [labels setFrame:labelFrame];
    [labels setNeedsDisplay:true];    // Update
}

- (void)setYLabelPosition:(METScopeYLabelPosition)pYLabelPosition {
    
    yLabelPosition = pYLabelPosition;
    CGRect labelFrame = labels.frame;
    
    /* If the labels are at one of the outside positions, extend the frame */
    if (yLabelPosition == kMETScopeYLabelPositionOutsideLeft) {
        labelFrame.size.width += METScopeview_YLabel_Outside_Extension;
        labelFrame.origin.x -= METScopeview_YLabel_Outside_Extension;
    }
    else if (yLabelPosition == kMETScopeYLabelPositionOutsideRight)
        labelFrame.size.width += METScopeview_YLabel_Outside_Extension;
    
    [labels setFrame:labelFrame];
    [labels setNeedsDisplay:true];    // Update
}

/* Set x-axis hard limit constraining pinch zoom */
- (void)setHardXLim:(CGFloat)xMin max:(CGFloat)xMax {
    
    if (xMin >= xMax) {
        NSLog(@"%s: Invalid x-axis limits (min = %f, max = %f)", __PRETTY_FUNCTION__, xMin, xMax);
        return;
    }
    
    minPlotMin.x = xMin;
    maxPlotMax.x = xMax;
    
    /* Reset the visible limits to their current values to apply new constraints */
    [self setVisibleXLim:visiblePlotMin.x max:visiblePlotMax.x];
}

/* Set y-axis hard limit constraining pinch zoom */
- (void)setHardYLim:(CGFloat)yMin max:(CGFloat)yMax {
    
    if (yMin >= yMax) {
        NSLog(@"%s: Invalid y-axis limits (min = %f, max = %f)", __PRETTY_FUNCTION__, yMin, yMax);
        return;
    }
    
    minPlotMin.y = yMin;
    maxPlotMax.y = yMax;
    
    /* Reset the visible limits to their current values to apply new constraints */
    [self setVisibleYLim:visiblePlotMin.y max:visiblePlotMax.y];
}

/* Set the range of the x-axis */
- (void)setVisibleXLim:(CGFloat)xMin max:(CGFloat)xMax {
    
    if (xMin >= xMax) {
        NSLog(@"%s: Invalid x-axis limits (min = %f, max = %f)", __PRETTY_FUNCTION__, xMin, xMax);
        return;
    }
    
    /* Cap visible limits at specified hard limits */
    xMin = xMin >= minPlotMin.x ? xMin : minPlotMin.x;
    xMax = xMax <= maxPlotMax.x ? xMax : maxPlotMax.x;
    
    /* Cap xMax if specified range exceeds hard range limit */
    xMax = (xMax-xMin) < maxPlotRange.x ? xMax : (xMin + maxPlotRange.x);
    xMax = (xMax-xMin) > minPlotRange.x ? xMax : (xMin + minPlotRange.x);
    
    /* Update limits and unit-pixel conversion factor */
    visiblePlotMin.x = xMin;
    visiblePlotMax.x = xMax;
    unitsPerPixel.x = (visiblePlotMax.x - visiblePlotMin.x) / self.frame.size.width;
    
    for (int i = 0; i < plotDataSubviews.count; i++) {
        [((METScopePlotDataView *)plotDataSubviews[i]) rescalePlotData];
    }
    
    [self setNeedsDisplay:true];
}

/* Set the range of the y-axis */
- (void)setVisibleYLim:(CGFloat)yMin max:(CGFloat)yMax {
    
    if (yMin >= yMax) {
        NSLog(@"%s: Invalid y-axis limits (min = %f, max = %f)", __PRETTY_FUNCTION__, yMin, yMax);
        return;
    }
    
    /* Cap visible limits at specified hard limits */
    yMin = yMin >= minPlotMin.y ? yMin : minPlotMin.y;
    yMax = yMax <= maxPlotMax.y ? yMax : maxPlotMax.y;
    
    /* Cap xMax if specified range exceeds hard range limit */
    yMax = (yMax-yMin) < maxPlotRange.y ? yMax : (yMin + maxPlotRange.y);
    yMax = (yMax-yMin) > minPlotRange.y ? yMax : (yMin + minPlotRange.y);
    
    /* Update limits and unit-pixel conversion factor */
    visiblePlotMin.y = yMin;
    visiblePlotMax.y = yMax;
    unitsPerPixel.y = (visiblePlotMax.y - visiblePlotMin.y) / self.frame.size.height;
    
    for (int i = 0; i < plotDataSubviews.count; i++) {
        [((METScopePlotDataView *)plotDataSubviews[i]) rescalePlotData];
    }
    
    [self setNeedsDisplay:true];
}

/* Set ticks and grid scale by specifying the input magnitude per tick/grid block */
- (void)setPlotUnitsPerXTick:(CGFloat)xTick {
    
    if (xTick <= 0.0) {
        NSLog(@"%s: Invalid x-tick spacing (%f)", __PRETTY_FUNCTION__, xTick);
        return;
    }
    
    tickSpacing.x = xTick;
    [self setNeedsDisplay:true];
}

- (void)setPlotUnitsPerYTick:(CGFloat)yTick {
    
    if (yTick <= 0.0) {
        NSLog(@"%s: Invalid y-tick spacing (%f)", __PRETTY_FUNCTION__, yTick);
        return;
    }
    
    tickSpacing.y = yTick;
    [self setNeedsDisplay:true];
}

- (void)setAutoScaleHorizontalTickMin:(int)pMinNumTicks max:(int)pMaxNumTicks {
    
    if (pMinNumTicks <= 0.0) {
        NSLog(@"%s: Invalid minimum number of ticks (%d)", __PRETTY_FUNCTION__, pMinNumTicks);
        return;
    }
    
    if (pMaxNumTicks <= 0.0) {
        NSLog(@"%s: Invalid minimum number of ticks (%d)", __PRETTY_FUNCTION__, pMaxNumTicks);
        return;
    }
    
    minNumTicks.x = pMinNumTicks;
    maxNumTicks.x = pMaxNumTicks;
    
    [self performAutoScale];
}

- (void)setAutoScaleVerticalTickMin:(int)pMinNumTicks max:(int)pMaxNumTicks {
    
    if (pMinNumTicks <= 0.0) {
        NSLog(@"%s: Invalid minimum number of ticks (%d)", __PRETTY_FUNCTION__, pMinNumTicks);
        return;
    }
    
    if (pMaxNumTicks <= 0.0) {
        NSLog(@"%s: Invalid minimum number of ticks (%d)", __PRETTY_FUNCTION__, pMaxNumTicks);
        return;
    }
    
    minNumTicks.y = pMinNumTicks;
    maxNumTicks.y = pMaxNumTicks;
    
    [self performAutoScale];
}

- (void)performAutoScale {
    
    if (!autoScaleXTick && !autoScaleYTick) {
        NSLog(@"%s: AutoScale disabled", __PRETTY_FUNCTION__);
        return;
    }
    
    CGPoint visibleRange;
    visibleRange.x = visiblePlotMax.x - visiblePlotMin.x;
    visibleRange.y = visiblePlotMax.y - visiblePlotMin.y;
    
    CGPoint ticksInFrame;
    ticksInFrame.x = visibleRange.x / tickSpacing.x;
    ticksInFrame.y = visibleRange.y / tickSpacing.y;
    
    CGPoint orderOfMag;
    orderOfMag.x = floorf(log10f(visibleRange.x)) - 1;
    orderOfMag.y = floorf(log10f(visibleRange.y)) - 1;
    
    if (autoScaleXTick) {
        
        /* Double or halve the tick units if we've got too few or too many within visible bounds */
        while (ticksInFrame.x > maxNumTicks.x) {
            tickSpacing.x *= 2.0;
            ticksInFrame.x = visibleRange.x / tickSpacing.x;
        }
        
        while (ticksInFrame.x < minNumTicks.x) {
            tickSpacing.x /= 2.0;
            ticksInFrame.x = visibleRange.x / tickSpacing.x;
        }
        
        /* Round tick units to a reasonable number based on the order of magnitude */
        tickSpacing.x = floorf(tickSpacing.x / powf(10, orderOfMag.x) + 0.5f) * powf(10, orderOfMag.x);
        
        xLabelFormatString = [NSString stringWithFormat:@"%%%d.%df", (int)fabs(orderOfMag.x) + 1,
                              orderOfMag.x < 0 ? (int)fabs(orderOfMag.x) : 0];
    }
    
    if (autoScaleYTick) {
        
        /* Double or halve the tick units if we've got too few or too many within visible bounds */
        while (ticksInFrame.y > maxNumTicks.y) {
            tickSpacing.y *= 2.0;
            ticksInFrame.y = visibleRange.y / tickSpacing.y;
        }
        
        while (ticksInFrame.y < minNumTicks.y) {
            tickSpacing.y /= 2.0;
            ticksInFrame.y = visibleRange.y / tickSpacing.y;
        }
        
        /* Round tick units to a reasonable number based on the order of magnitude */
        tickSpacing.y = floorf(tickSpacing.y / powf(10, orderOfMag.y) + 0.5) * powf(10, orderOfMag.y);
        yLabelFormatString = [NSString stringWithFormat:@"%%%d.%df", (int)fabs(orderOfMag.y) + 1,
                              orderOfMag.y < 0 ? (int)fabs(orderOfMag.y) : 0];
    }
}

/* Allocate a subview for new plot data with specified color/linewidth, return the index */
- (int)addPlotWithColor:(NSColor *)color lineWidth:(float)width {
    return [self addPlotWithResolution:plotResolution color:color lineWidth:width];
}

/* Allocate a subview with a specified resolution */
- (int)addPlotWithResolution:(int)res color:(NSColor *)color lineWidth:(float)width {
    
    METScopePlotDataView *newSub;
    newSub = [[METScopePlotDataView alloc] initWithParentView:self
                                                   resolution:res
                                                    plotColor:color
                                                    lineWidth:width];
    [plotDataSubviews addObject:newSub];
    [self addSubview:newSub];
    return ((int)plotDataSubviews.count - 1);
}

/* Set the plot data for a subview at a specified index */
- (void)setPlotDataAtIndex:(int)idx withLength:(int)len xData:(float *)xx yData:(float *)yy {
    
    /* Sanity check */
    if (idx < 0 || idx >= plotDataSubviews.count) {
        NSLog(@"Invalid plot data index %d\nplotDataSubviews.count = %lu", idx, (unsigned long)plotDataSubviews.count);
        return;
    }
    
    /* Get the subview */
    METScopePlotDataView *subView = plotDataSubviews[idx];
    
    /* Time-domain mode: just pass the waveform */
    if (displayMode == kMETScopeDisplayModeTimeDomain)
        [subView setDataWithLength:len xData:xx yData:yy];
    
    /* Frequency-domain mode: perform FFT, pass magnitude */
    else if (displayMode == kMETScopeDisplayModeFrequencyDomain) {
        
        Float32 *yBuffer = (Float32 *)calloc(fftSize/2, sizeof(Float32));
        [self computeMagnitudeFFT:yy inBufferLength:len outMagnitude:yBuffer seWindow:true];
        [subView setDataWithLength:fftSize/2 xData:freqs yData:yBuffer];
        free(yBuffer);
    }
}

- (void)getPlotDataAtIndex:(int)idx withLength:(int)len xData:(float *)xx yData:(float *)yy {
    
    if (idx >= 0 && idx < plotDataSubviews.count) {
        
        METScopePlotDataView *dataView = ((METScopePlotDataView *)plotDataSubviews[idx]);
        for (int i = 0; i < len; i++) {
            xx[i] = dataView.plotUnits[i].x;
            yy[i] = dataView.plotUnits[i].y;
        }
    }
    else
        NSLog(@"Invalid plot data index %d\nplotDataSubviews.count = %lu", idx, (unsigned long)plotDataSubviews.count);
}

/* Set raw coordinates (plot units) while in frequency domain mode without taking the FFT */
- (void)setCoordinatesInFDModeAtIndex:(int)idx withLength:(int)len xData:(float *)xx yData:(float *)yy {
    
    /* Get the subview and set its data */
    METScopePlotDataView *subView = plotDataSubviews[idx];
    [subView setDataWithLength:len xData:xx yData:yy];
}

- (void)removeAllPlots {
    
    for (int i = 0; i < [plotDataSubviews count]; i++)
         [plotDataSubviews[i] removeFromSuperview];
    [plotDataSubviews removeAllObjects];
}

#pragma mark Public Utility
/* Return a pixel location in the view for a given plot-scale value */
- (CGPoint)plotScaleToPixel:(CGPoint)plotScale {
    return CGPointMake([self plotScaleToPixelHorizontal:plotScale.x],
                       [self plotScaleToPixelVertical:plotScale.y]);
}

- (CGFloat)plotScaleToPixelHorizontal:(CGFloat)x {
    return self.frame.size.width * (x - visiblePlotMin.x) / (visiblePlotMax.x - visiblePlotMin.x);
}

- (CGFloat)plotScaleToPixelVertical:(CGFloat)y {
    
    if (axisScale == kMETScopeAxisScaleSemilogY)
        y = 20.0f * log10f(y + 10e-16);
    
    return self.frame.size.height * (y - visiblePlotMin.y) / (visiblePlotMax.y - visiblePlotMin.y);
}

/* Return plot scale units for a given pixel */
- (CGPoint)pixelToPlotScale:(CGPoint)pixel {
    return CGPointMake([self pixelToPlotScaleHorizontal:pixel.x],
                       [self pixelToPlotScaleVertical:pixel.y]);
}

- (CGFloat)pixelToPlotScaleHorizontal:(CGFloat)x {
    return visiblePlotMin.x + (x / self.frame.size.width) * (visiblePlotMax.x - visiblePlotMin.x);
}

- (CGFloat)pixelToPlotScaleVertical:(CGFloat)y {
    return visiblePlotMin.y + (y / self.frame.size.height) * (visiblePlotMax.y - visiblePlotMin.y);
}

#pragma mark Private Utility
- (CGPoint)tickSpacingInPixels {
    return CGPointMake(tickSpacing.x / unitsPerPixel.x, tickSpacing.y / unitsPerPixel.y);
}

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

/* Compute the single-sided magnitude spectrum using Accelerate's vDSP methods */
- (void)computeMagnitudeFFT:(Float32 *)inBuffer inBufferLength:(int)len outMagnitude:(float *)magnitude seWindow:(bool)doWindow {
    
    if (fftSetup == NULL) {
        printf("%s: Warning: must call [METScopeView setUpFFTWithSize] before enabling frequency domain mode\n", __PRETTY_FUNCTION__);
        return;
    }
    
    /* If the input signal is shorter than the fft size, zero-pad */
    if (len < fftSize) {
        
        /* Window and zero-pad */
        if (doWindow) {
            
            /* Compute the window with same length as the input signal */
            float *shortWindow = (float *)malloc(len * sizeof(float));
            vDSP_hann_window(shortWindow, len, vDSP_HANN_NORM);
            
            /* Window it */
            float *windowed = (float *)malloc(len * sizeof(float));
            vDSP_vmul(inBuffer, 1, shortWindow, 1, windowed, 1, len);
            
            /* Copy */
            for (int i = 0; i < len; i++)
                inRealBuffer[i] = windowed[i];
            
            /* Zero-pad */
            for (int i = len; i < fftSize; i++)
                inRealBuffer[i] = 0.0f;
            
            free(shortWindow);
            free(windowed);
        }
        
        /* Just copy and zero-pad */
        else {
            for (int i = 0; i < len; i++)
                inRealBuffer[i] = inBuffer[i];
            
            for (int i = len; i < fftSize; i++)
                inRealBuffer[i] = 0.0f;
        }
    }
    
    /* No zero-padding */
    else {
        
        /* Multiply by Hann window */
        if (doWindow)
            vDSP_vmul(inBuffer, 1, window, 1, inRealBuffer, 1, len);
        
        /* Otherwise just copy into the real input buffer */
        else
            cblas_scopy(fftSize, inBuffer, 1, inRealBuffer, 1);
    }
    
    /* Transform the real input data into the even-odd split required by vDSP_fft_zrip() explained in: https://developer.apple.com/library/ios/documentation/Performance/Conceptual/vDSP_Programming_Guide/UsingFourierTransforms/UsingFourierTransforms.html */
    vDSP_ctoz((COMPLEX *)inRealBuffer, 2, &splitBuffer, 1, fftSize/2);
    
    /* Computer the FFT */
    vDSP_fft_zrip(fftSetup, &splitBuffer, 1, log2f(fftSize), FFT_FORWARD);
    
    splitBuffer.imagp[0] = 0.0;     // ?? Shitty did this
    
    /* Convert the split complex data splitBuffer to an interleaved complex coordinate pairs */
    vDSP_ztoc(&splitBuffer, 1, (COMPLEX *)inRealBuffer, 2, fftSize/2);
    
    /* Convert the interleaved complex vector to interleaved polar coordinate pairs (magnitude, phase) */
    vDSP_polar(inRealBuffer, 2, outRealBuffer, 2, fftSize/2);
    
    /* Copy the even indices (magnitudes) */
    cblas_scopy(fftSize/2, outRealBuffer, 2, magnitude, 1);
    
    /* Normalize the magnitude */
    for (int i = 0; i < fftSize/2; i++)
        magnitude[i] *= scale;
    
    //    /* Copy the odd indices (phases) */
    //    cblas_scopy(fftSize/2, outRealBuffer+1, 2, phase, 1);
}


#pragma mark Gesture Handling
- (void)handlePan:(NSPanGestureRecognizer *)sender {
   
    CGPoint touchLoc = [sender locationInView:sender.view];
    
    if (sender.state == NSGestureRecognizerStateBegan) {
        previousPanLoc = touchLoc;
        currentPan = true;
        if (delegate)
            [delegate panBegan:self];
    }
    else if (sender.state == NSGestureRecognizerStateEnded) {
        currentPan = false;
        if (delegate)
            [delegate panEnded:self];
    }
    else {
        
        /* Get the relative change in location; convert to plot units (x) */
        CGPoint locChange;
        locChange.x = (previousPanLoc.x - touchLoc.x) * unitsPerPixel.x;
        
        /* Cap the new limits at the plot's hard limits */
        CGFloat newMin = visiblePlotMin.x + locChange.x;
        CGFloat newMax = visiblePlotMax.x + locChange.x;
        
        /* Rescale */
        if (newMin > minPlotMin.x && newMax < maxPlotMax.x) {
            [self setVisibleXLim:newMin max:newMax];
            
            if (delegate)
                [delegate panUpdate:self];
        }
        
        previousPanLoc = touchLoc;
    }
    
    [self performAutoScale];
    [self setNeedsDisplay:true];
}

- (void)handleMagnify:(NSMagnificationGestureRecognizer *)sender {
    
    if (sender.state == NSGestureRecognizerStateBegan) {
        previousMagnificationScale = sender.magnification;
        currentMagnify = true;
        if (delegate)
            [delegate magnifyBegan:self];
    }
    else if (sender.state == NSGestureRecognizerStateEnded) {
        currentMagnify = false;
        if (delegate)
            [delegate magnifyEnded:self];
    }
    else {
        /* Compute the change in scale and initialize the new x limits */
        CGFloat scaleChange = sender.magnification - previousMagnificationScale;
        CGFloat newMin = visiblePlotMin.x;
        CGFloat newMax = visiblePlotMax.x;
        
        /* Set the new plot bounds based on the mode */
        if (pinchZoomMode == kMETScopePinchZoomHoldCenter) {
            newMin = newMin + scaleChange/2.0f * newMin;
            newMax = newMax - scaleChange/2.0f * newMax;
        }
        else if (pinchZoomMode == kMETScopePinchZoomHoldMax)
            newMin = newMin + scaleChange * newMin;
        else if (pinchZoomMode == kMETScopePinchZoomHoldMin)
            newMax = newMax - scaleChange * newMax;
        
        /* Cap the limit changes at the hard limits */
        if (newMin < minPlotMin.x)
            newMin = minPlotMin.x;
        if (newMax > maxPlotMax.x)
            newMax = maxPlotMax.x;
        
        /* Rescale */
        [self setVisibleXLim:newMin max:newMax];
        
        previousMagnificationScale = sender.magnification;
        
        if (delegate)
            [delegate magnifyUpdate:self];
    }
    
    [self performAutoScale];
    [self setNeedsDisplay:true];
}

@end

#pragma mark - METScopeAxisView
@implementation METScopeAxisView
@synthesize parent;
@synthesize lineWidth;
@synthesize lineAlpha;
@synthesize lineColor;

/* Create a transparent subview using the parent's frame */
- (id)initWithParentView:(METScopeView *)parentView {
    
    CGRect frame = parentView.frame;
    frame.origin.x = frame.origin.y = 0;
    
    self = [super initWithFrame:frame];
    if (self) {
        [self.layer setBackgroundColor:[NSColor clearColor].CGColor];
        parent = parentView;
        lineWidth = 2.0;
        lineAlpha = 1.0;
        lineColor = [kDefaultGridColor colorWithAlphaComponent:lineAlpha];
    }
    return self;
}

/* Draw axes */
- (void)drawRect:(NSRect)rect {
    
//    [parent.backgroundColor setFill];
//    NSRectFill(rect);
    
    /* Draw x-axis only if y = 0 is within the vertical plot bounds */
    if (parent.visiblePlotMin.y <= 0.0 && parent.visiblePlotMax.y >= 0.0)
        [self drawXAxis];
    
    /* Draw y-axis only if x = 0 is within the horizontal plot bounds */
    if (parent.visiblePlotMin.x <= 0.0 && parent.visiblePlotMax.x >= 0.0)
        [self drawYAxis];
}

- (void)drawXAxis {
    
    CGPoint loc = CGPointMake(0.0, [parent plotScaleToPixelVertical:0.0]);
    CGPoint tickSpacingPixels = [parent tickSpacingInPixels];

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:lineWidth];
    
    /* -------------- */
    /* === X-Axis === */
    /* -------------- */
    [path setLineWidth:lineWidth];
    [path moveToPoint:loc];
    [path lineToPoint:CGPointMake(self.bounds.size.width, [parent plotScaleToPixelVertical:0.0])];
    
    /* ------------------ */
    /* === Tick Marks === */
    /* ------------------ */
    /* Starting at the plot origin, draw ticks in the positive x direction */
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    while (loc.x <= self.bounds.size.width) {
        [path moveToPoint:CGPointMake(loc.x, loc.y - 3.0)];
        [path lineToPoint:CGPointMake(loc.x, loc.y + 3.0)];
        loc.x += tickSpacingPixels.x;
    }
    
    /* Starting left of the plot origin, draw ticks in the negative x direction */
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    loc.x -= tickSpacingPixels.x;
    while (loc.x >= 0.0) {
        [path moveToPoint:CGPointMake(loc.x, loc.y - 3.0)];
        [path lineToPoint:CGPointMake(loc.x, loc.y + 3.0)];
        loc.x -= tickSpacingPixels.x;
    }
    
    [lineColor setStroke];
    [path stroke];
}

- (void)drawYAxis {
    
    CGPoint loc = CGPointMake([parent plotScaleToPixelHorizontal:0.0], 0.0);
    NSBezierPath *path = [NSBezierPath bezierPath];
    
    /* -------------- */
    /* === Y-Axis === */
    /* -------------- */
    [path setLineWidth:lineWidth];
    [path moveToPoint:loc];
    [path lineToPoint:CGPointMake([parent plotScaleToPixelHorizontal:0.0], self.bounds.size.height)];
    
    /* ------------------ */
    /* === Tick Marks === */
    /* ------------------ */
    CGPoint tickSpacingPixels = [parent tickSpacingInPixels];
    
    /* Starting at the plot origin, draw ticks in the positive y direction */
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    while (loc.y <= self.bounds.size.height) {
        [path moveToPoint:CGPointMake(loc.x - 3.0, loc.y)];
        [path lineToPoint:CGPointMake(loc.x + 3.0, loc.y)];
        loc.y += tickSpacingPixels.y;
    }
    
    /* Starting left of the plot origin, draw ticks in the negative y direction */
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    loc.y -= tickSpacingPixels.y;
    while (loc.y >= 0.0) {
        [path moveToPoint:CGPointMake(loc.x - 3.0, loc.y)];
        [path lineToPoint:CGPointMake(loc.x + 3.0, loc.y)];
        loc.y -= tickSpacingPixels.y;
    }
    
    [path stroke];
}

@end


#pragma mark - METScopeGridView
@implementation METScopeGridView
@synthesize parent;
@synthesize lineWidth;
@synthesize lineAlpha;
@synthesize dashLength;
@synthesize lineColor;

/* Create a transparent subview using the parent's frame */
- (id)initWithParentView:(METScopeView *)parentView {
    
    CGRect frame = parentView.frame;
    frame.origin.x = frame.origin.y = 0;
    
    self = [super initWithFrame:frame];
    if (self) {
        [self.layer setBackgroundColor:[NSColor clearColor].CGColor];
        parent = parentView;
        lineWidth = 0.3;
        lineAlpha = 0.5;
        dashLength = 5.0;
        lineColor = [kDefaultGridColor colorWithAlphaComponent:lineAlpha];
    }
    return self;
}

/* Draw axes */
- (void)drawRect:(NSRect)rect {
    
    [self drawXGrid];
    [self drawYGrid];
    
}

- (void)drawXGrid {
    
    CGPoint loc = CGPointMake(0.0, [parent plotScaleToPixelVertical:0.0]);
    CGPoint tickSpacingPixels = [parent tickSpacingInPixels];
    
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat dashLengths[2] = {dashLength, dashLength};
    [path setLineDash:dashLengths count:2 phase:0.0];
    [path setLineWidth:lineWidth];
    
    /* Draw in-bound vertical grid lines in positive x direction until we excede the frame width */
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    while (loc.x < 0.0) loc.x += tickSpacingPixels.x;   // Go to first tick location in-bounds
    while (loc.x <= self.bounds.size.width) {
        [path moveToPoint:CGPointMake(loc.x, 0.0)];
        [path lineToPoint:CGPointMake(loc.x, self.frame.size.height)];
        loc.x += tickSpacingPixels.x;
    }
    
    /* Draw in-bound vertical grid lines in negative x direction until we pass zero */
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    while (loc.x > self.bounds.size.width) loc.x -= tickSpacingPixels.x;
    while (loc.x >= 0.0) {
        [path moveToPoint:CGPointMake(loc.x, 0.0)];
        [path lineToPoint:CGPointMake(loc.x, self.frame.size.height)];
        loc.x -= tickSpacingPixels.x;
    }
    
    [lineColor setStroke];
    [path stroke];
}

- (void)drawYGrid {
    
    CGPoint loc = CGPointMake(0.0, [parent plotScaleToPixelVertical:0.0]);
    CGPoint tickSpacingPixels = [parent tickSpacingInPixels];
    
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat dashLengths[2] = {dashLength, dashLength};
    [path setLineDash:dashLengths count:2 phase:0.0];
    [path setLineWidth:lineWidth];
    
    /* Draw in-bound horizontal grid lines in positive y direction until we excede the frame height */
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    while (loc.y < 0.0) loc.y += tickSpacingPixels.y;
    while (loc.y <= self.bounds.size.height) {
        [path moveToPoint:CGPointMake(0.0, loc.y)];
        [path lineToPoint:CGPointMake(self.bounds.size.width, loc.y)];
        loc.y += tickSpacingPixels.y;
    }
    
    /* Starting left of the plot origin, draw ticks in the negative y direction */
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    while (loc.y > self.bounds.size.height) loc.y -= tickSpacingPixels.y;
    while (loc.y >= 0.0) {
        [path moveToPoint:CGPointMake(0.0, loc.y)];
        [path lineToPoint:CGPointMake(self.bounds.size.width, loc.y)];
        loc.y -= tickSpacingPixels.y;
    }
    
    [lineColor setStroke];
    [path stroke];
}

@end


#pragma mark - METScopeLabelView
@implementation  METScopeLabelView
@synthesize parent;
@synthesize labelFont;
@synthesize labelColor;

/* Create a transparent subview using the parent's frame */
- (id)initWithParentView:(METScopeView *)parentView {
    
    CGRect frame = parentView.frame;
    frame.origin.x = frame.origin.y = 0;
    
    self = [super initWithFrame:frame];
    
    if (self) {
        [self.layer setBackgroundColor:[NSColor clearColor].CGColor];
        parent = parentView;
        labelFont = [NSFont fontWithName:@"Arial" size:11];
        labelColor = kDefaultGridColor;
        labelAttributes = @{NSFontAttributeName:labelFont,
                            NSParagraphStyleAttributeName:[NSMutableParagraphStyle defaultParagraphStyle],
                            NSForegroundColorAttributeName:labelColor};
        pixelOffset = parentView.frame.origin;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    
    if (parent.xLabelsOn)   [self drawXLabels];
    if (parent.yLabelsOn)   [self drawYLabels];
}

- (void)drawXLabels {
    
    CGPoint loc;            // Current point in pixels
    NSString *label = [[NSString alloc] init];
    CGPoint tickSpacingPixels = [parent tickSpacingInPixels];
    
    /* If we're drawing labels on the axes and the x-axis isn't within the plot bounds, do nothing */
    if ((parent.xLabelPosition == kMETScopeXLabelPositionBelowAxis ||
         parent.xLabelPosition == kMETScopeXLabelPositionAboveAxis) &&
        (parent.visiblePlotMin.y > 0 || parent.visiblePlotMax.y < 0))
        return;
    
    /* ---------------------------- */
    /* === Positive x direction === */
    /* ---------------------------- */
    
    /* Determine starting point for drawing labels based on specified position */
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    loc.x += tickSpacingPixels.x;
    loc.y +=  2 * (parent.xLabelPosition == kMETScopeXLabelPositionBelowAxis);
    loc.y -= 13 * (parent.xLabelPosition == kMETScopeXLabelPositionAboveAxis);
    loc.y = (parent.xLabelPosition == kMETScopeXLabelPositionOutsideBelow) ? self.bounds.size.height - 13 : loc.y;
    loc.x += (parent.yLabelPosition == kMETScopeYLabelPositionOutsideLeft) ? METScopeview_YLabel_Outside_Extension : 0;
    loc.y = (parent.xLabelPosition == kMETScopeXLabelPositionOutsideAbove) ? self.bounds.origin.y : loc.y;
    
    int labelCenter = ((parent.xLabelPosition == kMETScopeXLabelPositionOutsideAbove) ||
                       (parent.xLabelPosition == kMETScopeXLabelPositionOutsideBelow)) ? -14 : 2;
    while(loc.x <= self.frame.size.width) {
        
        loc.x += self.frame.origin.x;
        label = [NSString stringWithFormat:parent.xLabelFormatString, [parent pixelToPlotScale:loc].x];
        loc.x -= self.frame.origin.x;
        loc.x += labelCenter;
        [label drawAtPoint:loc withAttributes:labelAttributes];
        loc.x -= labelCenter;
        loc.x += tickSpacingPixels.x;
    }
    
    /* ---------------------------- */
    /* === Negative x direction === */
    /* ---------------------------- */
    
    /* Determine starting point for drawing labels based on specified position */
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    loc.x -= tickSpacingPixels.x;
    loc.y +=  2 * (parent.xLabelPosition == kMETScopeXLabelPositionBelowAxis);
    loc.y -= 13 * (parent.xLabelPosition == kMETScopeXLabelPositionAboveAxis);
    loc.y = (parent.xLabelPosition == kMETScopeXLabelPositionOutsideBelow) ? self.bounds.size.height - 13 : loc.y;
    loc.x += (parent.yLabelPosition == kMETScopeYLabelPositionOutsideLeft) ? METScopeview_YLabel_Outside_Extension : 0;
    loc.y = (parent.xLabelPosition == kMETScopeXLabelPositionOutsideAbove) ? self.bounds.origin.y : loc.y;
    
    loc.y += 2;
    while(loc.x >= 0) {
        
        loc.x += self.frame.origin.x;
        label = [NSString stringWithFormat:parent.xLabelFormatString, [parent pixelToPlotScale:loc].x];
        loc.x -= self.frame.origin.x;
        loc.x += labelCenter;
        [label drawAtPoint:loc withAttributes:labelAttributes];
        loc.x -= labelCenter;
        loc.x -= tickSpacingPixels.x;
    }
}

- (void)drawYLabels {
    
    CGPoint loc;        // Current points in pixels
    NSString *label;
    CGPoint tickSpacingPixels = [parent tickSpacingInPixels];
    
    /* If we're drawing labels on the axes and the y-axis isn't within the plot bounds, do nothing */
    if ((parent.yLabelPosition == kMETScopeYLabelPositionLeftOfAxis   ||
         parent.yLabelPosition == kMETScopeYLabelPositionRightOfAxis) &&
        (parent.visiblePlotMin.x > 0 || parent.visiblePlotMax.x < 0))
        return;
    
    /* ---------------------------- */
    /* === Positive y direction === */
    /* ---------------------------- */
    
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    loc.y += tickSpacingPixels.y;
    loc.x += 10 * (parent.yLabelPosition == kMETScopeYLabelPositionRightOfAxis);
    loc.x -= 35 * (parent.yLabelPosition == kMETScopeYLabelPositionLeftOfAxis);
    loc.x = (parent.yLabelPosition == kMETScopeYLabelPositionOutsideLeft) ? self.bounds.origin.x : loc.x;
    loc.y += (parent.xLabelPosition == kMETScopeXLabelPositionOutsideAbove) ? METScopeView_XLabel_Outside_Extension : 0;
    loc.x = (parent.yLabelPosition == kMETScopeYLabelPositionOutsideRight) ? self.bounds.size.width - METScopeview_YLabel_Outside_Extension : loc.x;
    
    loc.x += 2;
    while(loc.y <= self.bounds.size.height) {
        
        loc.y += self.frame.origin.y;
        label = [NSString stringWithFormat:parent.yLabelFormatString, [parent pixelToPlotScale:loc].y];
        loc.y -= self.frame.origin.y;
        loc.y -= 7;
        [label drawAtPoint:loc withAttributes:labelAttributes];
        loc.y += 7;
        loc.y += tickSpacingPixels.y;
    }
    
    /* ---------------------------- */
    /* === Negative y direction === */
    /* ---------------------------- */
    
    loc = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    loc.y -= tickSpacingPixels.y;
    loc.x += 10 * (parent.yLabelPosition == kMETScopeYLabelPositionRightOfAxis);
    loc.x -= 35 * (parent.yLabelPosition == kMETScopeYLabelPositionLeftOfAxis);
    loc.x = (parent.yLabelPosition == kMETScopeYLabelPositionOutsideLeft) ? self.bounds.origin.x : loc.x;
    loc.y += (parent.xLabelPosition == kMETScopeXLabelPositionOutsideAbove) ? METScopeView_XLabel_Outside_Extension : 0;
    loc.x = (parent.yLabelPosition == kMETScopeYLabelPositionOutsideRight) ? self.bounds.size.width - METScopeview_YLabel_Outside_Extension : loc.x;
    
    
    loc.x += 2;
    while(loc.y >= 0) {
        
        loc.y += self.frame.origin.y;
        label = [NSString stringWithFormat:parent.yLabelFormatString, [parent pixelToPlotScale:loc].y];
        loc.y -= self.frame.origin.y;
        loc.y -= 7;
        [label drawAtPoint:loc withAttributes:labelAttributes];
        loc.y += 7;
        loc.y -= tickSpacingPixels.y;
    }
}
@end

#pragma mark - METScopePlotDataView
@implementation METScopePlotDataView

@synthesize parent;
@synthesize visible;
@synthesize resolution;
@synthesize plotMode;
@synthesize lineWidth;
@synthesize lineColor;

@synthesize plotUnits;

/* Create a transparent subview using the parent's frame and specified color and linewidth */
- (id)initWithParentView:(METScopeView *)pParent resolution:(int)pRes plotColor:(NSColor *)pColor lineWidth:(CGFloat)pWidth {
    
    CGRect frame = pParent.frame;
    frame.origin.x = frame.origin.y = 0;
    
    self = [super initWithFrame:frame];
    
    if (self) {
        [self setWantsLayer:true];
        [self.layer setBackgroundColor:[NSColor clearColor].CGColor];
        parent = pParent;
        lineColor = pColor;
        lineWidth = pWidth;
        [self setResolution:pRes];
        visible = true;
        pthread_mutex_init(&dataMutex, NULL);
        plotMode = kMETScopePlotModeLine;
    }
    return self;
}

/* Free any dynamically-allocated memory */
- (void)dealloc {
    
    pthread_mutex_lock(&dataMutex);
    
    if (inputXBuffer) free(inputXBuffer);
    if (inputYBuffer) free(inputYBuffer);
    if (resamplingIndices) free(resamplingIndices);
    if (plotUnits)  free(plotUnits);
    if (plotPixels) free(plotPixels);
    
    pthread_mutex_unlock(&dataMutex);
    pthread_mutex_destroy(&dataMutex);
}

/* Set whether this plot data gets drawn in the parent view */
- (void)setVisible:(bool)vis {
    visible = vis;
    [self setNeedsDisplay:true];
}

/* Set the plot resolution and (re-)allocate a plot buffer */
- (void)setResolution:(int)pRes {
    
    resolution = pRes;
    
    pthread_mutex_lock(&dataMutex);
    
    if (inputXBuffer) free(inputXBuffer);
    if (inputYBuffer) free(inputYBuffer);
    if (resamplingIndices) free(resamplingIndices);
    if (plotUnits) free(plotUnits);
    if (plotPixels) free(plotPixels);
    
    inputXBuffer = (float *)calloc(resolution, sizeof(float));
    inputYBuffer = (float *)calloc(resolution, sizeof(float));
    resamplingIndices = (float *)calloc(resolution, sizeof(float));
    plotUnits  = (CGPoint *)calloc(resolution, sizeof(CGPoint));
    plotPixels = (CGPoint *)calloc(resolution, sizeof(CGPoint));
    
    pthread_mutex_unlock(&dataMutex);
}

/* Set the plot data in plot units by sampling or interpolating */
- (void)setDataWithLength:(int)length xData:(float *)xx yData:(float *)yy {
    
    plotMode = kMETScopePlotModeLine;
    
    float* xBuffer = xx;
    float* yBuffer = yy;
    
    /* If the waveform has more samples than the plot resolution, resample the waveform */
    if (length > resolution) {
        
        /* Compute the down-sample factor */
        int inFramesPerPlotFrame = floorf((CGFloat)length / (CGFloat)resolution);
        
        /* If we're down-sampling past a threshold, sample the maximum waveform amplitude in a specified window length */
        if (inFramesPerPlotFrame > 12) {
            
            plotMode = kMETScopePlotModeFillSymmetrical;
            
            /* Compute a (length = resolution) buffer of x data */
            [parent linspace:xBuffer[0] max:xBuffer[length-1] numElements:resolution array:inputXBuffer];
            
            /* Sample the maximum value in (length = inFramesPerPlotFrame) window */
            float maxInWindow;
            for (int i = 0; i < resolution-1; i++) {
                
                maxInWindow = 0.0;
                for (int j = 0; j < inFramesPerPlotFrame; j++) {
                    if (fabs(yBuffer[i*inFramesPerPlotFrame+j]) > maxInWindow)
                        maxInWindow = fabs(yBuffer[i*inFramesPerPlotFrame+j]);
                }
                
                inputYBuffer[i] = maxInWindow;
            }
            inputYBuffer[resolution-1] = inputYBuffer[resolution-2];
            
            /* Copy the data */
            pthread_mutex_lock(&dataMutex);
            for (int i = 0; i < resolution; i++)
                plotUnits[i] = CGPointMake(inputXBuffer[i], inputYBuffer[i]);
            pthread_mutex_unlock(&dataMutex);
        }
        
        /* Otherwise, assume we can re-sample the waveform with minimal aliasing */
        else {
            
            /* Get query values for resampling the incoming waveform */
            [parent linspace:0 max:length-1 numElements:resolution array:resamplingIndices];
            
            /* Make sure drawRect doesn't access the data while we're updating it */
            pthread_mutex_lock(&dataMutex);
            
            int idx;
            for (int i = 0; i < resolution; i++) {
                idx = (int)resamplingIndices[i];
                plotUnits[i] = CGPointMake(xBuffer[idx], yBuffer[idx]);
            }
            
            pthread_mutex_unlock(&dataMutex);
        }
    }
    
    /* If the waveform has fewer samples than the plot resolution, interpolate the waveform */
    else if (length < resolution) {
        
        /* Get query values for interpolation */
        [parent linspace:xBuffer[0] max:xBuffer[length-1] numElements:resolution array:resamplingIndices];
        
        /* Make sure drawRect doesn't access the data while we're updating it */
        pthread_mutex_lock(&dataMutex);
        
        /* Interpolate */
        CGPoint current, next, target;
        CGFloat perc;
        int j = 0;
        for (int i = 0; i < length-1; i++) {
            
            current.x = xBuffer[i];
            current.y = yBuffer[i];
            next.x = xBuffer[i+1];
            next.y = yBuffer[i+1];
            target.x = resamplingIndices[j];
            
            while (target.x < next.x) {
                perc = (target.x - current.x) / (next.x - current.x);
                target.y = current.y * (1-perc) + next.y * perc;
                plotUnits[j] = target;
                j++;
                target.x = resamplingIndices[j];
            }
        }
        
        current.x = xBuffer[length-2];
        current.y = yBuffer[length-2];
        next.x = xBuffer[length-1];
        next.y = yBuffer[length-1];
        target.x = resamplingIndices[j];
        
        while (j < resolution-1) {
            j++;
            perc = (target.x - current.x) / (next.x - current.x);
            target.y = current.y * (1-perc) + next.y * perc;
            plotUnits[j] = target;
        }
        
        pthread_mutex_unlock(&dataMutex);
    }
    
    /* If waveform has number of samples == plot resolution, just copy */
    else {
        pthread_mutex_lock(&dataMutex);
        for (int i = 0; i < length; i++)
            plotUnits[i] = CGPointMake(xBuffer[i], yBuffer[i]);
        pthread_mutex_unlock(&dataMutex);
    }
    
    [self rescalePlotData];     // Convert sampled plot units to pixels
}

/* Convert plot units to pixels */
- (void)rescalePlotData {
    
    pthread_mutex_lock(&dataMutex);
    
    for (int i = 0; i < resolution; i++) //{
        plotPixels[i] = [parent plotScaleToPixel:plotUnits[i]];
    
    pthread_mutex_unlock(&dataMutex);
    
    [self setNeedsDisplay:true];     // Update
}

/* Add a constant value to all x data in plot units */
- (void)addToPlotXData:(CGFloat)value {
    
    pthread_mutex_lock(&dataMutex);
    for (int i = 0; i < resolution; i++)
        plotUnits[i].x += value;
    pthread_mutex_unlock(&dataMutex);
    
    [self setNeedsDisplay:true];     // Update
}

/* Add a constant value to all y data in plot units */
- (void)addToPlotYData:(CGFloat)value {
    
    pthread_mutex_lock(&dataMutex);
    for (int i = 0; i < resolution; i++)
        plotUnits[i].y += value;
    pthread_mutex_unlock(&dataMutex);
    
    [self setNeedsDisplay:true];     // Update
}

/* UIView subclass override. Main drawing method */
- (void)drawRect:(CGRect)rect {
    
    if (!visible)
        return;
    
    pthread_mutex_lock(&dataMutex);
    
    /* Set up Bezier path */
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:lineWidth];
    [lineColor setStroke];
    
    CGPoint current, previous;
    CGPoint originPixel = [parent plotScaleToPixel:CGPointMake(0.0, 0.0)];
    
    /* Find the first non-NaN pixel location */
    int startIdx = 0;
    while ((isnan((float)plotPixels[startIdx].x) || isnan((float)plotPixels[startIdx].y) ||
            (isinf((float)plotPixels[startIdx].x) || isinf((float)plotPixels[startIdx].x)))
           && startIdx < resolution-1)
        startIdx++;
    
    /* */
    if (plotMode == kMETScopePlotModeFillSymmetrical) {
        
        for (int i = startIdx+1; i < resolution-1; i++) {
            
            /* Skip any NaNs */
            if (isnan((float)plotPixels[i].x) || isnan((float)plotPixels[i].y))
                continue;
            
            
            if (parent.displayMode == kMETScopeDisplayModeTimeDomain) {
                
                /* Skip anything beyond the plot's temporal bounds */
                if (plotUnits[i].x < parent.visiblePlotMin.x ||
                    plotUnits[i].x > parent.visiblePlotMax.x)
                    continue;
                
                plotUnits[i].y = plotUnits[i].y > parent.visiblePlotMax.y ? parent.visiblePlotMax.y : plotUnits[i].y;
                plotUnits[i].y = plotUnits[i].y < parent.visiblePlotMin.y ? parent.visiblePlotMin.y : plotUnits[i].y;
            }
            
            current = plotPixels[i];
            
            [path moveToPoint:current];
            current.y -= 2 * (current.y - originPixel.y);
            [path lineToPoint:current];
        }
        
        [path stroke];
    }
    
    else {
        
        previous = plotPixels[startIdx];
        
        for (int i = startIdx+1; i < resolution-1; i++) {
            
            /* Skip any NaNs or Infs */
            if (isnan((float)plotPixels[i].x) || isnan((float)plotPixels[i].y) ||
                isinf((float)plotPixels[i].x) || isinf((float)plotPixels[i].y))
                continue;
        
            /* Skip anything beyond the plot bounds */
            if (parent.displayMode == kMETScopeDisplayModeTimeDomain &&
                (plotUnits[i].x < parent.visiblePlotMin.x || plotUnits[i].x > parent.visiblePlotMax.x ||
                 plotUnits[i].y < parent.visiblePlotMin.y || plotUnits[i].y > parent.visiblePlotMax.y))
                continue;
            
            [path moveToPoint:previous];
            [path lineToPoint:plotPixels[i]];
            previous = plotPixels[i];
        }
        
        [path stroke];
    }
    
    pthread_mutex_unlock(&dataMutex);
}

- (CGFloat)getAmplitudeAtXCoordinate:(CGFloat)x {
    
    CGFloat amp;
    CGFloat inc = (parent.visiblePlotMax.x - parent.visiblePlotMin.x) / (CGFloat)resolution;
    int idx = (x - parent.visiblePlotMin.x) / inc;
    
    amp = plotUnits[idx].y;
    
    int n = 1;
    if (idx > 0) {
        amp += plotUnits[idx-1].y;
        n += 1;
    }
    if (idx < resolution-1) {
        amp += plotUnits[idx+1].y;
        n += 1;
    }
    
    amp /= n;
    
    return amp;
}


@end
















