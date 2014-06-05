//
//  METScopeView.m
//  METScopeViewTest
//
//  Created by Jeff Gregorio on 5/7/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "METScopeView.h"

#pragma mark -
#pragma mark METScopePlotDataView
@interface METScopePlotDataView : UIView {
    CGPoint *plotUnits;     // Plot data in plot units
    CGPoint *plotPixels;    // Plot data in pixels
    pthread_mutex_t dataMutex;
}
@property (readonly) METScopeView *parent;
@property (readonly) int resolution;
@property CGFloat lineWidth;
@property UIColor *lineColor;
@end

@implementation  METScopePlotDataView
@synthesize parent;
@synthesize resolution;
@synthesize lineWidth;
@synthesize lineColor;

/* Create a transparent subview using the parent's frame and specified color and linewidth */
- (id)initWithParentView:(METScopeView *)pParent resolution:(int)pRes plotColor:(UIColor *)pColor lineWidth:(CGFloat)pWidth {
    
    CGRect frame = pParent.frame;
    frame.origin.x = frame.origin.y = 0;
    
    self = [super initWithFrame:frame];
    
    if (self) {
        [self setBackgroundColor:[UIColor clearColor]];
        parent = pParent;
        lineColor = pColor;
        lineWidth = pWidth;
        [self setResolution:pRes];
        pthread_mutex_init(&dataMutex, NULL);
    }
    return self;
}

/* Free any dynamically-allocated memory */
- (void)dealloc {
    
    pthread_mutex_lock(&dataMutex);
    
    if (plotUnits)
        free(plotUnits);
    
    if (plotPixels)
        free(plotPixels);
    
    pthread_mutex_unlock(&dataMutex);
    pthread_mutex_destroy(&dataMutex);
}

/* Set the plot resolution and (re-)allocate a plot buffer */
- (void)setResolution:(int)pRes {
    
    resolution = pRes;
    
    pthread_mutex_lock(&dataMutex);
    
    if (plotUnits)
        free(plotUnits);
    
    if (plotPixels)
        free(plotPixels);
    
    plotUnits  = (CGPoint *)calloc(resolution, sizeof(CGPoint));
    plotPixels = (CGPoint *)calloc(resolution, sizeof(CGPoint));
    
    pthread_mutex_unlock(&dataMutex);
}

/* Set the plot data in plot units by sampling or interpolating */
- (void)setDataWithLength:(int)length xData:(float *)xx yData:(float *)yy {
    
    /* Allocate buffers and copy the input data so we don't modify the original */
    float *xBuffer = (float *)calloc(length, sizeof(float));
    float *yBuffer = (float *)calloc(length, sizeof(float));
    memcpy(xBuffer, xx, length * sizeof(float));
    memcpy(yBuffer, yy, length * sizeof(float));
    
    /* If the waveform has more samples than the plot resolution, resample the waveform */
    if (length > resolution) {
        
        /* Get linearly-spaced indices to sample the incoming waveform */
        float *indices = (float *)calloc(resolution, sizeof(float));
        [self linspace:0 max:length numElements:resolution array:indices];
        
        /* Make sure drawRect doesn't access the data while we're updating it */
        pthread_mutex_lock(&dataMutex);
        
        int idx;
        for (int i = 0; i < resolution; i++) {
            idx = (int)indices[i];
            plotUnits[i] = CGPointMake(xBuffer[idx], yBuffer[idx]);
        }
        
        pthread_mutex_unlock(&dataMutex);
        free(indices);
    }
    
    /* If the waveform has fewer samples than the plot resolution, interpolate the waveform */
    else if (length < resolution) {
        
        /* Get $plotResolution$ linearly-spaced x-values */
        float *targetXVals = (float *)calloc(resolution, sizeof(float));
        [self linspace:xBuffer[0] max:xBuffer[length-1] numElements:resolution array:targetXVals];
        
        /* Make sure drawRect doesn't access the data while we're updating it */
        pthread_mutex_lock(&dataMutex);
        
        /* Interpolate */
        CGPoint current, next, target;
        float perc;
        int j = 0;
        for (int i = 0; i < length-1; i++) {
            
            current.x = xBuffer[i];
            current.y = yBuffer[i];
            next.x = xBuffer[i+1];
            next.y = yBuffer[i+1];
            target.x = targetXVals[j];
            
            while (target.x < next.x) {
                perc = (target.x - current.x) / (next.x - current.x);
                target.y = current.y * (1-perc) + next.y * perc;
                plotUnits[j] = target;
                j++;
                target.x = targetXVals[j];
            }
        }
        
        current.x = xBuffer[length-2];
        current.y = yBuffer[length-2];
        next.x = xBuffer[length-1];
        next.y = yBuffer[length-1];
        target.x = targetXVals[j];
        
        while (j < resolution-1) {
            j++;
            perc = (target.x - current.x) / (next.x - current.x);
            target.y = current.y * (1-perc) + next.y * perc;
            plotUnits[j] = target;
        }
        
        pthread_mutex_unlock(&dataMutex);
        free(targetXVals);
    }
    
    /* If waveform has number of samples == plot resolution, just copy */
    else {
        pthread_mutex_lock(&dataMutex);
        for (int i = 0; i < length; i++)
            plotUnits[i] = CGPointMake(xBuffer[i], yBuffer[i]);
        pthread_mutex_unlock(&dataMutex);
    }
    
    free(xBuffer);
    free(yBuffer);
    
    [self rescalePlotData];     // Convert sampled plot units to pixels
    [self setNeedsDisplay];     // Update
}

/* Convert plot units to pixels */
- (void)rescalePlotData {
    
    pthread_mutex_lock(&dataMutex);
    
    for (int i = 0; i < resolution; i++) {
        
        plotPixels[i] = [parent plotScaleToPixel:plotUnits[i]];
        
        /* Getting occasional crashes from very large plot y values, likely due to bad data from the audio controller */
        if (abs(plotPixels[i].y) > self.bounds.size.height || isnan(plotPixels[i].y)) {
            printf("Warning: bad plot data\n");
            plotPixels[i].y = plotPixels[i+1].y - plotPixels[i-1].y / 2;
        }
    }
    pthread_mutex_unlock(&dataMutex);
}

/* UIView subclass override. Main drawing method */
- (void)drawRect:(CGRect)rect {
    
    pthread_mutex_lock(&dataMutex);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(context, lineWidth);
    CGContextSetStrokeColorWithColor(context, lineColor.CGColor);
    
    CGPoint previous = plotPixels[0];
    
    for (int i = 1; i < resolution-1; i++) {
    
        CGContextBeginPath(context);
        CGContextMoveToPoint(context, previous.x, previous.y);
        CGContextAddLineToPoint(context, plotPixels[i].x, plotPixels[i].y);
        CGContextStrokePath(context);
        
        previous = plotPixels[i];
    }
    
    pthread_mutex_unlock(&dataMutex);
}

/* Generate a linearly-spaced set of indices for sampling an incoming waveform */
- (void)linspace:(float)minVal max:(float)maxVal numElements:(int)size array:(float*)array {
    
    float step = (maxVal - minVal) / (size-1);
    array[0] = minVal;
    for (int i = 1; i < size-1 ;i++) {
        array[i] = array[i-1] + step;
    }
    array[size-1] = maxVal;
}
@end

#pragma mark -
#pragma mark METScopeAxisView
@interface METScopeAxisView : UIView
@property METScopeView *parent;
@end

@implementation METScopeAxisView
@synthesize parent;

/* Create a transparent subview using the parent's frame */
- (id)initWithParentView:(METScopeView *)parentView {
    
    CGRect frame = parentView.frame;
    frame.origin.x = frame.origin.y = 0;

    self = [super initWithFrame:frame];

    if (self) {
        [self setBackgroundColor:[UIColor clearColor]];
        parent = parentView;
    }
    return self;
}

/* Draw axes */
- (void)drawRect:(CGRect)rect {
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGPoint loc;            // Reusable current location
    
    CGContextSetStrokeColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextSetAlpha(context, 1.0);
    CGContextSetLineWidth(context, 2.0);
    
    /* If the x-axis is within the plot's bounds */
    if(parent.visiblePlotMin.y <= 0 && parent.visiblePlotMax.y >= 0) {
        
        loc = [parent plotScaleToPixel:parent.visiblePlotMin.x y:0.0];
        
        /* Draw the x-axis */
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, self.frame.size.width, loc.y);
        CGContextStrokePath(context);
        
        /* Starting at the plot origin, draw ticks in the positive x direction */
        loc = parent.originPixel;
        while(loc.x <= self.bounds.size.width) {
            
            CGContextMoveToPoint(context, loc.x, loc.y - 3);
            CGContextAddLineToPoint(context, loc.x, loc.y + 3);
            CGContextStrokePath(context);
            
            loc.x += parent.tickPixels.x;
        }
        
        /* Draw ticks in negative x direction */
        loc = parent.originPixel;
        while(loc.x >= 0) {
            
            CGContextMoveToPoint(context, loc.x, loc.y - 3);
            CGContextAddLineToPoint(context, loc.x, loc.y + 3);
            CGContextStrokePath(context);
            
            loc.x -= parent.tickPixels.x;
        }
    }
    
    /* If the y-axis is within the plot's bounds */
    if(parent.visiblePlotMin.x <= 0 && parent.visiblePlotMax.x >= 0) {
        
        loc = [parent plotScaleToPixel:0.0 y:parent.visiblePlotMax.y];
        
        /* Draw the y-axis */
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, loc.x, self.frame.size.height);
        CGContextStrokePath(context);
        
        /* Starting at the plot origin, draw ticks in the positive y direction */
        loc = parent.originPixel;
        while(loc.y <= self.bounds.size.height) {
            
            CGContextMoveToPoint(context, loc.x - 3, loc.y);
            CGContextAddLineToPoint(context, loc.x + 3, loc.y);
            CGContextStrokePath(context);
            
            loc.y += parent.tickPixels.y;
        }
        
        /* Draw ticks in negative y direction */
        loc = parent.originPixel;
        while(loc.y >= 0) {
            
            CGContextMoveToPoint(context, loc.x - 3, loc.y);
            CGContextAddLineToPoint(context, loc.x + 3, loc.y);
            CGContextStrokePath(context);
            
            loc.y -= parent.tickPixels.y;
        }
    }
}
@end

#pragma mark -
#pragma mark METScopeGridView
@interface METScopeGridView : UIView {
    float gridDashLengths[2];
}
@property METScopeView *parent;
@end

@implementation METScopeGridView
@synthesize parent;

/* Create a transparent subview using the parent's frame */
- (id)initWithParentView:(METScopeView *)parentView {
    
    CGRect frame = parentView.frame;
    frame.origin.x = frame.origin.y = 0;
    
    self = [super initWithFrame:frame];
    
    if (self) {
        [self setBackgroundColor:[UIColor clearColor]];
        parent = parentView;
        gridDashLengths[0] = self.bounds.size.width  / 100;
        gridDashLengths[1] = self.bounds.size.height / 100;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGPoint loc;            // Reusable current location
    
    /* Dashed-line parameters */
    CGContextSetStrokeColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextSetAlpha(context, 0.5);
    CGContextSetLineWidth(context, 0.5);
    CGContextSetLineDash(context, M_PI, (CGFloat *)&gridDashLengths, 2);
    
    loc.y = 0;
    loc.x = parent.originPixel.x;
    
    /* Draw in-bound vertical grid lines in positive x direction until we excede the frame width */
    while (loc.x < 0) loc.x += parent.tickPixels.x;
    while (loc.x <= self.bounds.size.width) {
        
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, loc.x, self.bounds.size.height);
        CGContextStrokePath(context);
        
        loc.x += parent.tickPixels.x;
    }
    
    loc.y = 0;
    loc.x = parent.originPixel.x;
    
    /* Draw in-bound vertical grid lines in negative x direction until we pass zero */
    while (loc.x > self.bounds.size.width) loc.x -= parent.tickPixels.x;
    while (loc.x >= 0) {
        
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, loc.x, self.bounds.size.height);
        CGContextStrokePath(context);
        
        loc.x -= parent.tickPixels.x;
    }
    
    loc.x = 0;
    loc.y = parent.originPixel.y;
    
    /* Draw in-bound horizontal grid lines in negative y direction until we excede the frame height */
    while (loc.y < 0) loc.y += parent.tickPixels.y;
    while (loc.y <= self.bounds.size.height) {
        
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, self.bounds.size.width, loc.y);
        CGContextStrokePath(context);
        
        loc.y += parent.tickPixels.y;
    }
    
    loc.x = 0;
    loc.y = parent.originPixel.y;
    
    /* Draw in-bound horizontal grid lines in positive y direction until we excede 0 */
    while (loc.y > self.bounds.size.height) loc.y -= parent.tickPixels.y;
    while (loc.y >= 0) {
        
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, self.bounds.size.width, loc.y);
        CGContextStrokePath(context);
        
        loc.y -= parent.tickPixels.y;
    }
}
@end

#pragma mark -
#pragma mark METScopeLabelView
@interface METScopeLabelView : UIView {
    NSDictionary *labelAttributes;
    CGPoint pixelOffset;
}
@property METScopeView *parent;
@end

@implementation  METScopeLabelView
@synthesize parent;

/* Create a transparent subview using the parent's frame */
- (id)initWithParentView:(METScopeView *)parentView {
    
    CGRect frame = parentView.frame;
    frame.origin.x = frame.origin.y = 0;
    
    self = [super initWithFrame:frame];
    
    if (self) {
        [self setBackgroundColor:[UIColor clearColor]];
        parent = parentView;
        labelAttributes = @{NSFontAttributeName:[UIFont fontWithName:@"Arial" size:11],
                            NSParagraphStyleAttributeName:[NSMutableParagraphStyle defaultParagraphStyle],
                            NSForegroundColorAttributeName:[UIColor grayColor]};
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
    NSString *label;
    
    /* If the x-axis is within the plot's bounds */
    if(parent.visiblePlotMin.y <= 0 && parent.visiblePlotMax.y >= 0) {
        
        /* Starting at the plot origin, add labels in the positive x direction */
        loc = parent.originPixel;
        loc.y += 2;
        while(loc.x <= self.bounds.size.width) {
            
            loc.x += self.frame.origin.x;
            label = [NSString stringWithFormat:parent.xLabelFormatString, [parent pixelToPlotScale:loc withOffset:pixelOffset].x];
            loc.x -= self.frame.origin.x;
            loc.x += 2;
            [label drawAtPoint:loc withAttributes:labelAttributes];
            loc.x -= 2;
            loc.x += parent.tickPixels.x;
        }
        
        /* Add labels in negative x direction */
        loc = parent.originPixel;
        loc.y += 2;
        while(loc.x >= 0) {
            
            loc.x += self.frame.origin.x;
            label = [NSString stringWithFormat:parent.xLabelFormatString, [parent pixelToPlotScale:loc withOffset:pixelOffset].x];
            loc.x -= self.frame.origin.x;
            loc.x += 2;
            [label drawAtPoint:loc withAttributes:labelAttributes];
            loc.x -= 2;
            loc.x -= parent.tickPixels.x;
        }
    }
}

- (void)drawYLabels {
    
    CGPoint loc;        // Current points in pixels
    NSString *label;
    
    /* If the y-axis is within the plot's bounds */
    if(parent.visiblePlotMin.x <= 0 && parent.visiblePlotMax.x >= 0) {
        
        /* Starting at the plot origin, add labels in the positive y direction */
        loc = parent.originPixel;
        loc.x += 2;
        while(loc.y <= self.bounds.size.height) {
            
            loc.y += self.frame.origin.y;
            label = [NSString stringWithFormat:parent.yLabelFormatString, [parent pixelToPlotScale:loc withOffset:pixelOffset].y];
            loc.y -= self.frame.origin.y;
            loc.y -= 14;
            [label drawAtPoint:loc withAttributes:labelAttributes];
            loc.y += 14;
            loc.y += parent.tickPixels.y;
        }
        
        /* Add labels in negative y direction */
        loc = parent.originPixel;
        loc.x += 2;
        while(loc.y >= 0) {
            
            loc.y += self.frame.origin.y;
            label = [NSString stringWithFormat:parent.yLabelFormatString, [parent pixelToPlotScale:loc withOffset:pixelOffset].y];
            loc.y -= self.frame.origin.y;
            loc.y -= 14;
            [label drawAtPoint:loc withAttributes:labelAttributes];
            loc.y += 14;
            loc.y -= parent.tickPixels.y;
        }
    }
}
@end

#pragma mark -
#pragma mark METScopeView
@implementation METScopeView

@synthesize plotResolution;
@synthesize displayMode;
@synthesize visiblePlotMin;
@synthesize visiblePlotMax;
@synthesize minPlotMin;
@synthesize maxPlotMax;
@synthesize tickUnits;
@synthesize tickPixels;
@synthesize originPixel;
@synthesize axesOn;
@synthesize gridOn;
@synthesize labelsOn;
@synthesize samplingRate;
@synthesize xLabelFormatString;
@synthesize yLabelFormatString;
@synthesize xLabelsOn;
@synthesize yLabelsOn;
@synthesize xGridAutoScale;
@synthesize yGridAutoScale;
@synthesize xPinchZoomEnabled;
@synthesize yPinchZoomEnabled;

- (id)initWithFrame:(CGRect)frame {
    
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    self = [super initWithFrame:frame];
    
    if (self) {
        [self setDefaults];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    self = [super initWithCoder:aDecoder];
    
    if (self) {
        [self setDefaults];
    }
    return self;
}

- (void)dealloc {
    
    if (inRealBuffer != NULL)
        free(inRealBuffer);
    if (outRealBuffer != NULL)
        free(outRealBuffer);
    if (window != NULL)
        free(window);
}

- (void)setDefaults {
    
    [self setBackgroundColor:[UIColor whiteColor]];
    
    /* Default mode */
    displayMode = kMETScopeViewTimeDomainMode;
    
    /* ------------------ */
    /* == Plot Scaling == */
    /* ------------------ */
    
    [self setPlotResolution:METScopeView_Default_PlotResolution];
    minPlotMin = CGPointMake(METScopeView_Default_XMin_TD, METScopeView_Default_YMin_TD);
    maxPlotMax = CGPointMake(METScopeView_Default_XMax_TD, METScopeView_Default_YMax_TD);
    tickUnits  = CGPointMake(METScopeView_Default_XTick_TD, METScopeView_Default_YTick_TD);
    [self setVisibleXLim:minPlotMin.x max:maxPlotMax.x];
    [self setVisibleYLim:minPlotMin.y max:maxPlotMax.y];
    
    /* Frequency-domain mode needs sampling rate for x-axis scaling */
    samplingRate = METScopeView_Default_SamplingRate;
    
    /* ---------------- */
    /* == Pinch Zoom == */
    /* ---------------- */
    
    xPinchZoomEnabled = true;
    yPinchZoomEnabled = true;
    pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [self addGestureRecognizer:pinchRecognizer];

    /* ---------- */
    /* == Axes == */
    /* ---------- */
    
    axesOn = true;
    axesSubview = [[METScopeAxisView alloc] initWithParentView:self];
    [self addSubview:axesSubview];
    
    /* ---------- */
    /* == Grid == */
    /* ---------- */
    
    gridOn = true;
    xGridAutoScale = false;
    yGridAutoScale = false;
    gridSubview = [[METScopeGridView alloc] initWithParentView:self];
    [self addSubview:gridSubview];
    
    /* ------------ */
    /* == Labels == */
    /* ------------ */
    
    labelsOn = true;
    xLabelsOn = true;
    yLabelsOn = true;
    xLabelFormatString = METScopeView_Default_xLabelFormatString_TD;
    yLabelFormatString = METScopeView_Default_yLabelFormatString_TD;
    labelsSubview = [[METScopeLabelView alloc] initWithParentView:self];
    [self addSubview:labelsSubview];
    
    /* --------------- */
    /* == Plot Data == */
    /* --------------- */
    plotDataSubviews = [[NSMutableArray alloc] init];
}

#pragma mark -
#pragma mark Interface Methods
/* Set number of points sampled from incoming waveforms */
- (void)setPlotResolution:(int)res {
    
    plotResolution = res;   // Default plot resolution for new plot data subviews
    
    /* Update resoution for any existing subviews */
    for (int i = 0; i < plotDataSubviews.count; i++) {
        [((METScopePlotDataView *)plotDataSubviews[i]) setResolution:plotResolution];
    }
}

/* Set the display mode to time/frequency domain and automatically rescale to default limits */
- (void)setDisplayMode:(enum DisplayMode)mode {
    
    if (mode == kMETScopeViewTimeDomainMode) {
        printf("Time domain mode\n");
        minPlotMin = CGPointMake(METScopeView_Default_XMin_TD, METScopeView_Default_YMin_TD);
        maxPlotMax = CGPointMake(METScopeView_Default_XMax_TD, METScopeView_Default_YMax_TD);
        tickUnits  = CGPointMake(METScopeView_Default_XTick_TD, METScopeView_Default_YTick_TD);
        xLabelFormatString = METScopeView_Default_xLabelFormatString_TD;
        yLabelFormatString = METScopeView_Default_yLabelFormatString_TD;
        [self setVisibleXLim:minPlotMin.x max:maxPlotMax.x];
        [self setVisibleYLim:minPlotMin.y max:maxPlotMax.y];
        displayMode = mode;
    }
    
    else if (mode == kMETScopeViewFrequencyDomainMode) {
        printf("Frequency domain mode\n");
        minPlotMin = CGPointMake(METScopeView_Default_XMin_FD, METScopeView_Default_YMin_FD);
        maxPlotMax = CGPointMake(METScopeView_Default_XMax_FD, METScopeView_Default_YMax_FD);
        tickUnits  = CGPointMake(METScopeView_Default_XTick_FD, METScopeView_Default_YTick_FD);
        xLabelFormatString = METScopeView_Default_xLabelFormatString_FD;
        yLabelFormatString = METScopeView_Default_yLabelFormatString_FD;
        [self setVisibleXLim:minPlotMin.x max:maxPlotMax.x];
        [self setVisibleYLim:minPlotMin.y max:maxPlotMax.y];
        displayMode = mode;
    }
    
    /* Update the subviews */
    [axesSubview setNeedsDisplay];
    [gridSubview setNeedsDisplay];
    [labelsSubview setNeedsDisplay];
}

/* Initialize a vDSP fft struct, buffers, windows, etc. */
- (void)setUpFFTWithSize:(int)size {
    
    fftSize = size;
    
    scale = 1.0f / (float)(fftSize/2);     // Normalization constant
    
    /* Buffers */
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

/* Set x-axis hard limit constraining pinch zoom */
- (void)setHardXLim:(float)xMin max:(float)xMax {
    minPlotMin.x = xMin;
    maxPlotMax.x = xMax;
    [self setVisibleXLim:xMin max:xMax];
}
/* Set y-axis hard limit constraining pinch zoom */
- (void)setHardYLim:(float)yMin max:(float)yMax {
    minPlotMin.y = yMin;
    maxPlotMax.y = yMax;
    [self setVisibleYLim:yMin max:yMax];
}

/* Set the range of the x-axis */
- (void)setVisibleXLim:(float)xMin max:(float)xMax {
    
    if (xMin >= xMax) {
        NSLog(@"%s: Invalid x-axis limits", __PRETTY_FUNCTION__);
        return;
    }
    
    visiblePlotMin.x = xMin;
    visiblePlotMax.x = xMax;
    
    /* Horizontal units per pixel */
    unitsPerPixel.x = (visiblePlotMax.x - visiblePlotMin.x) / self.frame.size.width;
    
    /* Rescale the grid */
    [self setPlotUnitsPerTick:tickUnits.x vertical:tickUnits.y];
}

/* Set the range of the y-axis */
- (void)setVisibleYLim:(float)yMin max:(float)yMax {
    
    if (yMin >= yMax) {
        NSLog(@"%s: Invalid y-axis limits", __PRETTY_FUNCTION__);
        return;
    }
    
    visiblePlotMin.y = yMin;
    visiblePlotMax.y = yMax;
    
    /* Vertical units per pixel */
    unitsPerPixel.y = (visiblePlotMax.y - visiblePlotMin.y) / self.frame.size.height;
    
    /* Rescale the grid */
    [self setPlotUnitsPerTick:tickUnits.x vertical:tickUnits.y];
}

/* Set ticks and grid scale by specifying the input magnitude per tick/grid block */
- (void)setPlotUnitsPerXTick:(float)xTick {
    [self setPlotUnitsPerTick:xTick vertical:tickUnits.y];
}
- (void)setPlotUnitsPerYTick:(float)yTick {
    [self setPlotUnitsPerTick:tickUnits.x vertical:yTick];
}
- (void)setPlotUnitsPerTick:(float)xTick vertical:(float)yTick {
    
    if (xTick <= 0 || yTick <= 0) {
        NSLog(@"%s: Invalid grid scale", __PRETTY_FUNCTION__);
        return;
    }
    
    /* Rescale the grid to keep a specified number of ticks */
    CGPoint ticksInFrame;
    ticksInFrame.x = ((visiblePlotMax.x - visiblePlotMin.x) / xTick);
    ticksInFrame.y = ((visiblePlotMax.y - visiblePlotMin.y) / yTick);

    if (xGridAutoScale) {
        if (ticksInFrame.x > METScopeView_AutoGrid_MaxXTicksInFrame)
            tickUnits.x = xTick + (visiblePlotMax.x - visiblePlotMin.x) / 10;
        else if (ticksInFrame.x < METScopeView_AutoGrid_MinXTicksInFrame) {
            tickUnits.x = xTick - (visiblePlotMax.x - visiblePlotMin.x) / 10;
        }
        else tickUnits.x = xTick;
    }
    else
        tickUnits.x = xTick;

    if (yGridAutoScale) {
        if (ticksInFrame.y > METScopeView_AutoGrid_MaxYTicksInFrame)
            tickUnits.y = yTick + (visiblePlotMax.y - visiblePlotMin.y) / 10;
        else if (ticksInFrame.y < METScopeView_AutoGrid_MinYTicksInFrame) {
            tickUnits.y = yTick - (visiblePlotMax.y - visiblePlotMin.y) / 10;
        }
        else tickUnits.y = yTick;
    }
    else
        tickUnits.y = yTick;
    
    tickPixels.x = tickUnits.x / unitsPerPixel.x;
    tickPixels.y = tickUnits.y / unitsPerPixel.y;
    
    originPixel = [self plotScaleToPixel:0.0 y:0.0];
    
    /* Update all the subveiws */
    [axesSubview setNeedsDisplay];
    [gridSubview setNeedsDisplay];
    [labelsSubview setNeedsDisplay];
    
    for (int i = 0; i < plotDataSubviews.count; i++) {
        [((METScopePlotDataView *)plotDataSubviews[i]) rescalePlotData];
        [((METScopePlotDataView *)plotDataSubviews[i]) setNeedsDisplay];
    }
}

/* Set the axesOn property, adding or removing the subview if necessary */
- (void)setAxesOn:(bool)pAxesOn {
    
    if (axesOn == pAxesOn)
        return;
    
    axesOn = pAxesOn;
    
    if (!axesOn) {
        [axesSubview removeFromSuperview];
    }
    else {
        [self addSubview:axesSubview];
    }
}

/* Set the gridOn property, adding or removing the subview if necessary */
- (void)setGridOn:(bool)pGridOn {
    
    if (gridOn == pGridOn)
        return;
    
    gridOn = pGridOn;
    
    if (!gridOn) {
        [gridSubview removeFromSuperview];
    }
    else {
        [self addSubview:gridSubview];
    }
}

/* Set the labelsOn property, adding or removing the subview if necessary */
- (void)setLabelsOn:(bool)pLabelsOn {
    
    if (labelsOn == pLabelsOn)
        return;
    
    labelsOn = pLabelsOn;
    
    if (!labelsOn) {
        [labelsSubview removeFromSuperview];
    }
    else {
        [self addSubview:labelsSubview];
    }
}

/* Allocate a subview for new plot data with specified color/linewidth, return the index */
- (int)addPlotWithColor:(UIColor *)color lineWidth:(float)width {
    
    return [self addPlotWithResolution:self.plotResolution color:color lineWidth:width];
}

/* Allocate a subview with a specified resolution */
- (int)addPlotWithResolution:(int)res color:(UIColor *)color lineWidth:(float)width {
    
    METScopePlotDataView *newSub;
    newSub = [[METScopePlotDataView alloc] initWithParentView:self
                                                   resolution:res
                                                    plotColor:color
                                                    lineWidth:width];
    [plotDataSubviews addObject:newSub];
    [self addSubview:newSub];
    
    return (plotDataSubviews.count - 1);
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
    if (displayMode == kMETScopeViewTimeDomainMode)
        [subView setDataWithLength:len xData:xx yData:yy];
    
    /* Frequency-domain mode: perform FFT, pass magnitude */
    else if (displayMode == kMETScopeViewFrequencyDomainMode) {

        float *xBuffer = (float *)calloc(len, sizeof(float));
        float *yBuffer = (float *)calloc(len, sizeof(float));

        [self computeMagnitudeFFT:yy outMagnitude:yBuffer seWindow:false];
        [self linspace:0.0 max:samplingRate/2 numElements:fftSize/2 array:xBuffer];

        [subView setDataWithLength:len xData:xBuffer yData:yBuffer];
        
        free(xBuffer);
        free(yBuffer);
    }
}

/* Update plot color for a waveform at a specified index */
- (void)setPlotColor:(UIColor *)color atIndex:(int)idx {
    
    if (idx > 0 && idx < plotDataSubviews.count)
        ((METScopePlotDataView *)plotDataSubviews[idx]).lineColor = color;
    else
        NSLog(@"Invalid plot data index %d\nplotDataSubviews.count = %lu", idx, (unsigned long)plotDataSubviews.count);
}

/* Update line width for a waveform at a specified index */
- (void)setLineWidth:(float)width atIndex:(int)idx {
    
    if (idx > 0 && idx < plotDataSubviews.count)
        ((METScopePlotDataView *)plotDataSubviews[idx]).lineWidth = width;
    else
        NSLog(@"Invalid plot data index %d\nplotDataSubviews.count = %lu", idx, (unsigned long)plotDataSubviews.count);
}

/* Update line width for a waveform at a specified index */
- (void)setPlotResolution:(int)res atIndex:(int)idx {
    
    if (idx > 0 && idx < plotDataSubviews.count)
        ((METScopePlotDataView *)plotDataSubviews[idx]).resolution = res;
    else
        NSLog(@"Invalid plot data index %d\nplotDataSubviews.count = %lu", idx, (unsigned long)plotDataSubviews.count);
}

#pragma mark -
#pragma mark Gesture Handlers
- (void)handlePinch:(UIPinchGestureRecognizer *)sender {
    
    if (!xPinchZoomEnabled && !yPinchZoomEnabled)
        return;
    
    /* If the number of touches became 1, save the current remaining touch location at index 0 and wait until the number of touches goes from 1 to 2, and overwrite the old previous touch location at index 1 with a new incoming touch location to restart the pinch with the correct previous touch location */
    
    if ([sender numberOfTouches] == 1) {
        /* If the remaining touch is to the left of the previously lost second touch, store it at index 0 */
        if ([sender locationOfTouch:0 inView:sender.view].x)
        
        previousPinchTouches[0] = [sender locationOfTouch:0 inView:sender.view];
        previousNumPinchTouches = 1;
        return;
    }
    else if (previousNumPinchTouches == 1 && [sender numberOfTouches] == 2) {
        previousPinchTouches[1] = [sender locationOfTouch:1 inView:sender.view];
        previousNumPinchTouches = 2;
    }
    
    if ([sender numberOfTouches] != 2) {
        return;
    }
    
    /* Get the two touch locations */
    CGPoint touches[2];
    touches[0] = [sender locationOfTouch:0 inView:sender.view];
    touches[1] = [sender locationOfTouch:1 inView:sender.view];
    
    /* Get the distance between them */
    CGPoint pinchDistance;
    pinchDistance.x = abs(touches[0].x - touches[1].x);
    pinchDistance.y = abs(touches[0].y - touches[1].y);
    
    /* If this is the first touch, save the scale */
    if (sender.state == UIGestureRecognizerStateBegan) {
        previousNumPinchTouches = 2;
        previousPinchTouches[0] = touches[0];
        previousPinchTouches[1] = touches[1];
    }
    
    /* Otherwise, expand/contract the plot bounds */
    else {
        
        /* Maintain indices of which touch is left and which is lower */
        int currLeftIdx = (touches[0].x < touches[1].x) ? 0 : 1;
        int currLowIdx =  (touches[0].y > touches[1].y) ? 0 : 1;
        int prevLeftIdx = (previousPinchTouches[0].x < previousPinchTouches[1].x) ? 0 : 1;
        int prevLowIdx =  (previousPinchTouches[0].y > previousPinchTouches[1].y) ? 0 : 1;
        
        CGPoint pixelShift[2];
        pixelShift[0].x = previousPinchTouches[currLeftIdx].x - touches[prevLeftIdx].x;
        pixelShift[0].y = touches[currLowIdx].y - previousPinchTouches[prevLowIdx].y;
        pixelShift[1].x = previousPinchTouches[!currLeftIdx].x - touches[!prevLeftIdx].x;
        pixelShift[1].y = touches[!currLowIdx].y - previousPinchTouches[!prevLowIdx].y;
        
        float newXMin = visiblePlotMin.x + pixelShift[0].x * unitsPerPixel.x;
        float newXMax = visiblePlotMax.x + pixelShift[1].x * unitsPerPixel.x;
        float newYMin = visiblePlotMin.y + pixelShift[0].y * unitsPerPixel.y;
        float newYMax = visiblePlotMax.y + pixelShift[1].y * unitsPerPixel.y;
        
        /* Rescale if we're within the hard limit */
        if (xPinchZoomEnabled && newXMin > minPlotMin.x && newXMax < maxPlotMax.x)
            [self setVisibleXLim:newXMin max:newXMax];
        if (yPinchZoomEnabled && newYMin > minPlotMin.y && newYMax < maxPlotMax.y)
            [self setVisibleYLim:newYMin max:newYMax];
        
        previousPinchTouches[0] = touches[0];
        previousPinchTouches[1] = touches[1];
    }
}

/* UIGestureRecognizerDelegate method to enable simultaneous gesture recognition if any gesture recognizers are attached externally */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer{
    return YES;
}

#pragma mark -
#pragma mark Utility methods

/* Return a pixel location in the view for a given plot-scale value */
- (CGPoint)plotScaleToPixel:(float)pX y:(float)pY {
    
    CGPoint retVal;
    
    retVal.x = self.frame.size.width * (pX - visiblePlotMin.x) / (visiblePlotMax.x - visiblePlotMin.x);
    retVal.y = self.frame.size.height * (1 - (pY - visiblePlotMin.y) / (visiblePlotMax.y - visiblePlotMin.y));
    
    return retVal;
}

/* Return a pixel location in the view for a given plot-scale value */
- (CGPoint)plotScaleToPixel:(CGPoint)plotScale {
    
    CGPoint pixelVal;
    
    pixelVal.x = self.frame.size.width * (plotScale.x - visiblePlotMin.x) / (visiblePlotMax.x - visiblePlotMin.x);
    pixelVal.y = self.frame.size.height * (1 - (plotScale.y - visiblePlotMin.y) / (visiblePlotMax.y - visiblePlotMin.y));
    
    return pixelVal;
}

/* Return a plot-scale value for a given pixel location in the view */
- (CGPoint)pixelToPlotScale:(CGPoint)pixel {
    return [self pixelToPlotScale:pixel withOffset:CGPointMake(0.0, 0.0)];
}
- (CGPoint)pixelToPlotScale:(CGPoint)pixel withOffset:(CGPoint)pixelOffset {
    
    float px, py;
    px = (pixel.x - self.frame.origin.x + pixelOffset.x) / self.frame.size.width;
    py = (pixel.y - self.frame.origin.y + pixelOffset.y) / self.frame.size.height;
    py = 1 - py;
    
    CGPoint plotScale;
    plotScale.x = visiblePlotMin.x + px * (visiblePlotMax.x - visiblePlotMin.x);
    plotScale.y = visiblePlotMin.y + py * (visiblePlotMax.y - visiblePlotMin.y);
    
    return plotScale;
}

/* Generate a linearly-spaced set of indices for sampling an incoming waveform */
- (void)linspace:(float)minVal max:(float)maxVal numElements:(int)size array:(float*)array {
    
    float step = (maxVal - minVal) / (size-1);
    array[0] = minVal;
    for (int i = 1; i < size-1 ;i++) {
        array[i] = array[i-1] + step;
    }
    array[size-1] = maxVal;
}

/* Compute the single-sided magnitude spectrum using Accelerate's vDSP methods */
- (void)computeMagnitudeFFT:(float *)inBuffer outMagnitude:(float *)magnitude seWindow:(bool)doWindow {
    
    if (fftSetup == NULL) {
        printf("%s: Warning: must call [METScopeView setUpFFTWithSize] before enabling frequency domain mode\n", __PRETTY_FUNCTION__);
        return;
    }
    
    /* Multiply by Hann window */
    if (doWindow)
        vDSP_vmul(inBuffer, 1, window, 1, inRealBuffer, 1, fftSize);
    
    /* Otherwise just copy into the real input buffer */
    else
        cblas_scopy(fftSize, inBuffer, 1, inRealBuffer, 1);
    
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
    for (int i = 0; i < fftSize; i++)
        magnitude[i] *= scale;
    
//    /* Copy the odd indices (phases) */
//    cblas_scopy(fftSize/2, outRealBuffer+1, 2, phase, 1);
}

@end





















