//
//  ViewController.m
//  METScopeViewTest_2
//
//  Created by Jeff Gregorio on 6/3/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "ViewController.h"

@implementation ViewController

- (void)viewDidLoad {
    
    [super viewDidLoad];
    [self.view setBackgroundColor:[UIColor whiteColor]];
    
    /* Set the FFT size before setting the frequency domain mode */
    [kObjectScopeView setUpFFTWithSize:1024];
    [kObjectScopeView setSamplingRate:kAudioSampleRate];
    
    /* Allocate subviews for wet (pre-processing) and dry (post-processing) waveforms */
    dryIdx = [kObjectScopeView addPlotWithColor:[UIColor blueColor] lineWidth:2.0];
    wetIdx = [kObjectScopeView addPlotWithColor:[UIColor  redColor] lineWidth:2.0];
    
    /* Set the interface controls to METScopeView's current values (defaults) */
    [self getInterfaceValuesFromScopeView];
    
    /* ----------------- */
    /* == Audio Setup == */
    /* ----------------- */
    audioController = [[AudioController alloc] init];
    [self updateGain];
    
    /* Update the scope views on a timer by querying AudioController's wet/dry signal buffers */
    [NSTimer scheduledTimerWithTimeInterval:0.002 target:self selector:@selector(updateWaveforms) userInfo:nil repeats:YES];
}

- (void)viewDidUnload {
    
    [super viewDidUnload];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/* Query the Scope View to get interface object values and states */
- (void)getInterfaceValuesFromScopeView {
    
    kObjectXMinStepper.value = [kObjectScopeView minPlotMin].x;
    kObjectXMaxStepper.value = [kObjectScopeView maxPlotMax].x;
    kObjectYMinStepper.value = [kObjectScopeView minPlotMin].y;
    kObjectYMaxStepper.value = [kObjectScopeView maxPlotMax].y;
    kObjectXGridScaleStepper.value = [kObjectScopeView tickUnits].x;
    kObjectYGridScaleStepper.value = [kObjectScopeView tickUnits].y;
    kObjectPlotResolutionStepper.value = log2([kObjectScopeView plotResolution]);
    [kObjectAxesSwitch setOn:[kObjectScopeView axesOn]];
    [kObjectGridSwitch setOn:[kObjectScopeView gridOn]];
    [kObjectLabelsSwitch setOn:[kObjectScopeView labelsOn]];
    [kObjectPinchZoomXSwitch setOn:[kObjectScopeView xPinchZoomEnabled]];
    [kObjectPinchZoomYSwitch setOn:[kObjectScopeView yPinchZoomEnabled]];
    [kObjectAutoGridXSwitch setOn:[kObjectScopeView xGridAutoScale]];
    [kObjectAutoGridYSwitch setOn:[kObjectScopeView yGridAutoScale]];
    
    /* Update labels */
    kObjectPlotResolutionLabel.text = [NSString stringWithFormat:@"%d", [kObjectScopeView plotResolution]];
    kObjectXMinLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectXMinStepper.value];
    kObjectXMaxLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectXMaxStepper.value];
    kObjectYMinLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectYMinStepper.value];
    kObjectYMaxLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectYMaxStepper.value];
    kObjectXGridScaleLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectXGridScaleStepper.value];
    kObjectYGridScaleLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectYGridScaleStepper.value];
    
    kObjectDisplayModeButton.titleLabel.text = kObjectScopeView.displayMode == kMETScopeViewTimeDomainMode ? @"View Spectrum" : @"View Waveform";
    kObjectDisplayModeButton.titleLabel.adjustsFontSizeToFitWidth = true;
}

- (IBAction)toggleXZoom:(id)sender {
    
    if (![kObjectScopeView xPinchZoomEnabled])
        [kObjectScopeView setXPinchZoomEnabled:true];
    else
        [kObjectScopeView setXPinchZoomEnabled:false];
}

- (IBAction)toggleYZoom:(id)sender {
    
    if (![kObjectScopeView yPinchZoomEnabled])
        [kObjectScopeView setYPinchZoomEnabled:true];
    else
        [kObjectScopeView setYPinchZoomEnabled:false];
}

- (IBAction)toggleAutoXGrid:(id)sender {
    
    if ([kObjectScopeView xGridAutoScale]) {
        [kObjectScopeView setXGridAutoScale:false];
        [kObjectXGridScaleStepper setEnabled:true];
        [kObjectXGridScaleStepper setAlpha:1.0];
        [kObjectXGridScaleLabel setAlpha:1.0];
        [kObjectScopeView setPlotUnitsPerXTick:kObjectXGridScaleStepper.value];
    }
    else {
        [kObjectScopeView setXGridAutoScale:true];
        [kObjectXGridScaleStepper setEnabled:false];
        [kObjectXGridScaleStepper setAlpha:0.2];
        [kObjectXGridScaleLabel setAlpha:0.2];
    }
}

- (IBAction)toggleAutoYGrid:(id)sender {
    
    if ([kObjectScopeView yGridAutoScale]) {
        [kObjectScopeView setYGridAutoScale:false];
        [kObjectYGridScaleStepper setEnabled:true];
        [kObjectYGridScaleStepper setAlpha:1.0];
        [kObjectYGridScaleLabel setAlpha:1.0];
        [kObjectScopeView setPlotUnitsPerYTick:kObjectYGridScaleStepper.value];
    }
    else {
        [kObjectScopeView setYGridAutoScale:true];
        [kObjectYGridScaleStepper setEnabled:false];
        [kObjectYGridScaleStepper setAlpha:0.2];
        [kObjectYGridScaleLabel setAlpha:0.2];
    }
}

- (IBAction)toggleAxes:(id)sender {
    
    if (![kObjectScopeView axesOn])
        [kObjectScopeView setAxesOn:true];
    else
        [kObjectScopeView setAxesOn:false];
}

- (IBAction)toggleGrid:(id)sender {
    
    if (![kObjectScopeView gridOn])
        [kObjectScopeView setGridOn:true];
    else
        [kObjectScopeView setGridOn:false];
}

- (IBAction)toggleLabels:(id)sender {
    
    if (![kObjectScopeView labelsOn])
        [kObjectScopeView setLabelsOn:true];
    else
        [kObjectScopeView setLabelsOn:false];
}

- (IBAction)updateXLim:(id)sender {
    
    [kObjectScopeView setHardXLim:kObjectXMinStepper.value max:kObjectXMaxStepper.value];
    
    kObjectXMinLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectXMinStepper.value];
    kObjectXMaxLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectXMaxStepper.value];
}

- (IBAction)updateYLim:(id)sender {
    
    [kObjectScopeView setHardYLim:kObjectYMinStepper.value max:kObjectYMaxStepper.value];
    
    kObjectYMinLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectYMinStepper.value];
    kObjectYMaxLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectYMaxStepper.value];
}

- (IBAction)updateGridScale:(id)sender {
    
    [kObjectScopeView setPlotUnitsPerTick:kObjectXGridScaleStepper.value vertical:kObjectYGridScaleStepper.value];
    
    kObjectXGridScaleLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectXGridScaleStepper.value];
    kObjectYGridScaleLabel.text = [NSString stringWithFormat:@"%5.3f", (float)kObjectYGridScaleStepper.value];
}

- (IBAction)updatePlotResolution:(id)sender {
    
    int resolution = pow(2, [kObjectPlotResolutionStepper value]);
    [kObjectScopeView setPlotResolution:resolution];
    [kObjectPlotResolutionLabel setText:[NSString stringWithFormat:@"%d", resolution]];
}

- (IBAction)updateDisplayMode:(id)sender {
    
    if (kObjectScopeView.displayMode == kMETScopeViewTimeDomainMode) {
        [kObjectScopeView setDisplayMode:kMETScopeViewFrequencyDomainMode];
        [kObjectXGridScaleStepper setMaximumValue:20000];
        [kObjectXGridScaleStepper setStepValue:1000];
        [kObjectXGridScaleStepper setMaximumValue:10000];
        [kObjectXGridScaleStepper setStepValue:500];
        [self getInterfaceValuesFromScopeView];
    }
    else if (kObjectScopeView.displayMode == kMETScopeViewFrequencyDomainMode) {
        [kObjectScopeView setDisplayMode:kMETScopeViewTimeDomainMode];
        [kObjectXGridScaleStepper setMaximumValue:0.05];
        [kObjectXGridScaleStepper setStepValue:0.001];
        [kObjectXGridScaleStepper setMaximumValue:0.01];
        [kObjectXGridScaleStepper setStepValue:0.001];
        [self getInterfaceValuesFromScopeView];
    }
}

- (IBAction)updateGain {
    [audioController setGain:kObjectGainSlider.value];
}

#pragma mark -
#pragma mark Plot update callback
- (void)updateWaveforms {
    
    /* Allocate buffer of time values for each sample */
    float *inputXBuffer = (float *)malloc([audioController getBufferLength] * sizeof(float));
    [self linspace:0.0 max:[audioController getBufferLength]/kAudioSampleRate numElements:[audioController getBufferLength] array:inputXBuffer];

    /* Allocate wet/dry signal buffers */
    float *dryYBuffer = (float *)malloc([audioController getBufferLength] * sizeof(float));
    float *wetYBuffer = (float *)malloc([audioController getBufferLength] * sizeof(float));
    
    /* Get current buffer values from the audio controller */
    [audioController getInputBuffer:dryYBuffer];
    [audioController getOutputBuffer:wetYBuffer];
    
    /* Update the plots */
    [kObjectScopeView setPlotDataAtIndex:dryIdx
                              withLength:[audioController getBufferLength]
                                   xData:inputXBuffer
                                   yData:dryYBuffer];
    
    [kObjectScopeView setPlotDataAtIndex:wetIdx
                              withLength:[audioController getBufferLength]
                                   xData:inputXBuffer
                                   yData:wetYBuffer];
    free(inputXBuffer);
    free(dryYBuffer);
    free(wetYBuffer);
}

#pragma mark -
#pragma mark Utility
/* Generate a linearly-spaced set of indices for sampling an incoming waveform */
- (void)linspace:(float)minVal max:(float)maxVal numElements:(int)size array:(float*)array {
    
    float step = (maxVal-minVal)/(size-1);
    array[0] = minVal;
    int i;
    for (i = 1;i<size-1;i++) {
        array[i] = array[i-1]+step;
    }
    array[size-1] = maxVal;
}


@end
