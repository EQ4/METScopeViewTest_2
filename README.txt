METScopeViewTest
================

This iOS app is a test app for the METScopeView class demonstrating functionality for plotting real-time audio input in both time and frequency domains and setting various properties. 


Adding Waveforms to the Plot
----------------------------

Waveforms exist as separate subviews, so a subview needs to be allocated for a waveform before setting plot data.

The property "plotResolution" specifies how many frames are sampled from incoming waveforms by default. The method 

- (int)addPlotWithColor:(UIColor *)color lineWidth:(float)width

creates a waveform plot with the default resolution, but multiple waveforms with different resolutions can be plotted using 

- (int)addPlotWithResolution:(int)res color:(UIColor *)color lineWidth:(float)width

These methods return the index of the waveform's subview, so we can use this index to set plot data using the method

- (void)setPlotDataAtIndex:(int)idx withLength:(int)len xData:(float *)xx yData:(float *)yy

Note: calling the method 

-(void)setPlotResolution:(int)res 

will set the plot resolution for all waveforms (but will not resample existing data). Resolutions, colors, and linewidths for specific waveforms can also be (re)set using the methods

- (void)setPlotColor:(UIColor *)color atIndex:(int)idx
- (void)setLineWidth:(float)width atIndex:(int)idx
- (void)setPlotResolution:(int)res atIndex:(int)idx


Frequency-Domain Mode
---------------------

METScopeView also has a built-in FFT. By default, the property "displayMode" is set to kMETScopeViewTimeDomainMode, but can also be changed to kMETScopeViewFrequencyDomainMode using

- (void)setDisplayMode:(DisplayMode)mode

If using frequency-domain mode, we have to first set up the FFT for a particular size using

- (void)setUpFFTWithSize:(int)size

If audio is being passed at a sampling rate other than the default 44.1kHz rate, then set the "samplingRate" property using 

- (void)setSamplingRate:(int)


Plot scaling
------------

The bounds of the x and y axes are not automatically determined, so they should be set appropriately using the methods 

- (void)setHardXLim:(float)xMin max:(float)xMax
- (void)setHardYLim:(float)yMin max:(float)yMax

These methods also constrain the built-in pinch-zoom gesture, which rescales by settin soft limits that are also settable using the methods 

- (void)setVisibleXLim:(float)xMin max:(float)xMax
- (void)setVisibleYLim:(float)yMin max:(float)yMax

The grid/tick line spacing can be scaled manually using 

- (void)setPlotUnitsPerXTick:(float)xTick
- (void)setPlotUnitsPerYTick:(float)yTick
- (void)setPlotUnitsPerTick:(float)xTick vertical:(float)yTick

in which case automatic grid scaling should be turned off by using 

- (void)setXGridAutoscale:(bool)
- (void)setYGridAutoscale:(bool)


Pinch Zoom
----------

METScopeView has a built-in pinch gesture recognizer that sets the visible limits of the plot, constrained by the hard limits. Pinch zooming is enabled by default, but can be enabled/disabled using 

- (void)setXPinchZoomEnabled:(bool)
- (void)setYPinchZoomEnabled:(bool)


Instantiation
-------------

To add a METScopeView object using interface builder, add a UIView object to the xib/storyboard, and in the "Identity Inspector" menu, change the "Class" property to "METScopeView". Add a instance of the object in the header file with "IBOutlet METScopeView *metScopeViewInstance", and connect the IBOutlet to the object in interface builder.

To create a METScopeView object programmatically, use [METScopeView initWithFrame:(CGRect)rect]. 

See METScopeView.h for a list of other settable properties and default values. 

Suggested Improvements
----------------------

	- Log scaling for frequency domain mode

	- Waveform triggering to stabilize periodic time-domain waveforms 

	- Automatically compute an appropriate precision for the plot axis labels given the order of magnitude of the plot data's x and y coordinates

	- Auto grid scaling should prioritize finding nicer, round numbers for grid spacing

