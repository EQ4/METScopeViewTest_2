//
//  ViewController.h
//  METScopeViewTest_2
//
//  Created by Jeff Gregorio on 6/3/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "AudioController.h"
#import "METScopeView.h"

@interface ViewController : UIViewController {
    
    AudioController *audioController;
    
    IBOutlet METScopeView *kObjectScopeView;
    int dryIdx, wetIdx;
    
    IBOutlet UIButton *kObjectDisplayModeButton;
    
    IBOutlet UIStepper *kObjectPlotResolutionStepper;
    IBOutlet UIStepper *kObjectXGridScaleStepper;
    IBOutlet UIStepper *kObjectYGridScaleStepper;
    IBOutlet UIStepper *kObjectXMaxStepper;
    IBOutlet UIStepper *kObjectYMaxStepper;
    IBOutlet UIStepper *kObjectXMinStepper;
    IBOutlet UIStepper *kObjectYMinStepper;
    
    IBOutlet UILabel *kObjectPlotResolutionLabel;
    IBOutlet UILabel *kObjectXGridScaleLabel;
    IBOutlet UILabel *kObjectYGridScaleLabel;
    IBOutlet UILabel *kObjectXMaxLabel;
    IBOutlet UILabel *kObjectYMaxLabel;
    IBOutlet UILabel *kObjectXMinLabel;
    IBOutlet UILabel *kObjectYMinLabel;
    
    IBOutlet UISwitch *kObjectAxesSwitch;
    IBOutlet UISwitch *kObjectGridSwitch;
    IBOutlet UISwitch *kObjectLabelsSwitch;
    IBOutlet UISwitch *kObjectPinchZoomXSwitch;
    IBOutlet UISwitch *kObjectPinchZoomYSwitch;
    IBOutlet UISwitch *kObjectAutoGridXSwitch;
    IBOutlet UISwitch *kObjectAutoGridYSwitch;
    
    IBOutlet UISlider *kObjectGainSlider;
}

@end
