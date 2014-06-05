//
//  AudioController.m
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 5/11/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "AudioController.h"

/* Main render callback method */
static OSStatus processingCallback(void *inRefCon, // Reference to the calling object
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp 		*inTimeStamp,
                                 UInt32 					inBusNumber,
                                 UInt32 					inNumberFrames,
                                 AudioBufferList 			*ioData)
{
    OSStatus status;
    
	/* Cast the void userdata to the player object */
    AudioPlayer *player = (AudioPlayer *)inRefCon;
    
    /* If the buffer length has changed, we should reallocate internal buffers */
    if (player->bufferSizeFrames == inNumberFrames) {
        
        player->bufferSizeFrames = inNumberFrames;
        
        pthread_mutex_lock(&player->inputBufferMutex);
        free(player->inputBuffer);
        player->inputBuffer = (Float32 *)malloc(player->bufferSizeFrames * sizeof(Float32));
        pthread_mutex_unlock(&player->inputBufferMutex);
        
        pthread_mutex_lock(&player->outputBufferMutex);
        free(player->outputBuffer);
        player->outputBuffer = (Float32 *)malloc(player->bufferSizeFrames * sizeof(Float32));
        pthread_mutex_unlock(&player->outputBufferMutex);
    }
    
    /* Copy samples from input bus into the ioData (buffer to output) */
    status = AudioUnitRender(player->remoteIOUnit,
                             ioActionFlags,
                             inTimeStamp,
                             1, // Input bus
                             inNumberFrames,
                             ioData);
    if (status != noErr)
        printf("Error rendering from remote IO unit\n");
    
    /* Allocate a buffer for processing samples and copy the ioData into it */
    Float32 *procBuffer = (Float32 *)calloc(inNumberFrames, sizeof(Float32));
    memcpy(procBuffer, (Float32 *)ioData->mBuffers[0].mData, sizeof(Float32) * inNumberFrames);
    
    /* Update the pre-processing (dry) buffer */
    pthread_mutex_lock(&player->inputBufferMutex);
    memcpy(player->inputBuffer, procBuffer, player->bufferSizeFrames * sizeof(Float32));
    pthread_mutex_unlock(&player->inputBufferMutex);
    
    /* Apply the input gain */
    for (int i = 0; i < inNumberFrames; i++)
        procBuffer[i] *= player->gain;
    
    /* Update the post-processing (wet) buffer */
    pthread_mutex_lock(&player->outputBufferMutex);
    memcpy(player->outputBuffer, procBuffer, player->bufferSizeFrames * sizeof(Float32));
    pthread_mutex_unlock(&player->outputBufferMutex);
    
    /* Copy the processing buffer into the left and right output channels */
    memcpy((Float32 *)ioData->mBuffers[0].mData, procBuffer, inNumberFrames * sizeof(Float32));
    memcpy((Float32 *)ioData->mBuffers[1].mData, procBuffer, inNumberFrames * sizeof(Float32));
    
    free(procBuffer);
	return status;
}

/* Interrupt handler to stop/start audio for incoming notifications/alarms/calls */
void interruptListener(void *inUserData, UInt32 inInterruptionState) {
    
    AudioController *audioController = (__bridge AudioController *)inUserData;
    
    if (inInterruptionState == kAudioSessionBeginInterruption)
        [audioController stopAUGraph];
    else if (inInterruptionState == kAudioSessionEndInterruption)
        [audioController startAUGraph];
}

@implementation AudioController

@synthesize inputEnabled;
@synthesize outputEnabled;
@synthesize isRunning;
@synthesize isInitialized;

- (id)init {
    
    self = [super init];
    
    if (self) {
        
        /* Set flags */
        inputEnabled = false;
        outputEnabled = false;
        isInitialized = false;
        isRunning = false;
        
        /* Struct setup */
        player.gain = 1.0;
        player.bufferSizeFrames = 1024;
        pthread_mutex_init(&player.inputBufferMutex,  NULL);
        pthread_mutex_init(&player.outputBufferMutex, NULL);
        player.inputBuffer  = (Float32 *)malloc(player.bufferSizeFrames * sizeof(Float32));
        player.outputBuffer = (Float32 *)malloc(player.bufferSizeFrames * sizeof(Float32));
        [self setUpAUGraph];
    }
    
    return self;
}

- (void)dealloc {
    
}

- (void)setUpAUGraph {
    
    OSStatus status;
    
    /* ------------------------ */
    /* == Create the AUGraph == */
    /* ------------------------ */
    
    status = NewAUGraph(&player.graph);
    if (status != noErr) {
        [self printErrorMessage:@"NewAUGraph failed" withStatus:status];
    }
    
    /* ----------------------- */
    /* == Add RemoteIO Node == */
    /* ----------------------- */
    
    AudioComponentDescription IOUnitDescription;    // Description
    IOUnitDescription.componentType          = kAudioUnitType_Output;
    IOUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
    IOUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    IOUnitDescription.componentFlags         = 0;
    IOUnitDescription.componentFlagsMask     = 0;
    
    AUNode IONode;
    status = AUGraphAddNode(player.graph, &IOUnitDescription, &IONode);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphAddNode[RemoteIO] failed" withStatus:status];
    }
    
    /* ---------------------- */
    /* == Open the AUGraph == */
    /* ---------------------- */
    
    status = AUGraphOpen(player.graph);    // Instantiates audio units, but doesn't initialize
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphOpen failed" withStatus:status];
    }
    
    /* ----------------------------------------------------- */
    /* == Get AudioUnit instances from the opened AUGraph == */
    /* ----------------------------------------------------- */
    
    status = AUGraphNodeInfo(player.graph, IONode, NULL, &player.remoteIOUnit);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphNodeInfo[RemoteIO] failed" withStatus:status];
    }
    
    /* ------------------------------------------------------------ */
    /* ==== Set up render callback instead of connections ========= */
    /* ------------------------------------------------------------ */
    
    AudioUnitElement outputBus = 0;
    AURenderCallbackStruct inputCallbackStruct;
    inputCallbackStruct.inputProc = processingCallback;
    inputCallbackStruct.inputProcRefCon = &player;
    
    status = AudioUnitSetProperty(player.remoteIOUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  outputBus,
                                  &inputCallbackStruct,
                                  sizeof(inputCallbackStruct));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_SetRenderCallback] failed" withStatus:status];
    }
    
    /* ------------------------------------ */
    /* == Set Stream Formats, Parameters == */
    /* ------------------------------------ */
    
    [self setOutputEnabled:true];       // Enable output on the remoteIO unit
    [self setInputEnabled:true];        // Enable input on the remoteIO unit
    [self setIOStreamFormat];           // Set up stream format on input/output of the remoteIO
    
    /* ------------------------ */
    /* == Initialize and Run == */
    /* ------------------------ */
    
    [self initializeGraph];     // Initialize the AUGraph (allocates resources)
    [self startAUGraph];        // Start the AUGraph
    
    CAShow(player.graph);
}

/* Set the stream format on the remoteIO audio unit */
- (void)setIOStreamFormat {
    
    OSStatus status;
    
    /* Set up the stream format for the I/O unit */
    memset(&IOStreamFormat, 0, sizeof(IOStreamFormat));
    IOStreamFormat.mSampleRate = kAudioSampleRate;
    IOStreamFormat.mFormatID = kAudioFormatLinearPCM;
    IOStreamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    IOStreamFormat.mBytesPerPacket = kAudioBytesPerPacket;
    IOStreamFormat.mFramesPerPacket = kAudioFramesPerPacket;
    IOStreamFormat.mBytesPerFrame = kAudioBytesPerPacket / kAudioFramesPerPacket;
    IOStreamFormat.mChannelsPerFrame = kAudioChannelsPerFrame;
    IOStreamFormat.mBitsPerChannel = 8 * kAudioBytesPerPacket;
    
    /* Set the stream format for the input bus */
    status = AudioUnitSetProperty(player.remoteIOUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &IOStreamFormat,
                                  sizeof(IOStreamFormat));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_StreamFormat - Input] failed" withStatus:status];
    }
    
    /* Set the stream format for the output bus */
    status = AudioUnitSetProperty(player.remoteIOUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  1,
                                  &IOStreamFormat,
                                  sizeof(IOStreamFormat));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_StreamFormat - Output] failed" withStatus:status];
    }
}

/* Initialize the AUGraph (allocates resources) */
- (void)initializeGraph {
    
    OSStatus status = AUGraphInitialize(player.graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphInitialize failed" withStatus:status];
    }
    else
        isInitialized = true;
}

/* Uninitialize the AUGraph in case we need to set properties that require an uninitialized graph */
- (void)uninitializeGraph {
    
    OSStatus status = AUGraphUninitialize(player.graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphUninitialize failed" withStatus:status];
    }
    else
        isInitialized = false;
}

#pragma mark -
#pragma mark Interface Methods

/* Update the input gain */
- (void)setGain:(Float32)gain {
    player.gain = gain;
}

- (UInt32)getBufferLength {
    return player.bufferSizeFrames;
}

/* Run audio */
- (void)startAUGraph {
    
    OSStatus status = AUGraphStart(player.graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphStart failed" withStatus:status];
    }
    else
        isRunning = true;
}

/* Stop audio */
- (void)stopAUGraph {
    
    OSStatus status = AUGraphStop(player.graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphStop failed" withStatus:status];
    }
    else
        isRunning = false;
}

/* Enable/disable audio input */
- (void)setInputEnabled:(bool)enabled {
    
    OSStatus status;
    UInt32 enableInput = (UInt32)enabled;
    AudioUnitElement inputBus = 1;
    bool wasInitialized = false;
    bool wasRunning = false;
    
    /* Stop if running */
    if (isRunning) {
        [self stopAUGraph];
        wasRunning = true;
    }
    /* Uninitialize if initialized */
    if (isInitialized) {
        [self uninitializeGraph];
        wasInitialized = true;
    }
    
    /* Set up the remoteIO unit to enable/disable input */
    status = AudioUnitSetProperty(player.remoteIOUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  inputBus,
                                  &enableInput,
                                  sizeof(enableInput));
    if (status != noErr) {
        [self printErrorMessage:@"Enable/disable input failed" withStatus:status];
    }
    else
        inputEnabled = enabled;
    
    /* Reinitialize if needed */
    if (wasInitialized)
        [self initializeGraph];
    
    /* Restart if needed */
    if (wasRunning)
        [self startAUGraph];
}

/* Enable/disable audio output */
- (void)setOutputEnabled:(bool)enabled {
    
    OSStatus status;
    UInt32 enableOutput = (UInt32)enabled;
    AudioUnitElement outputBus = 0;
    bool wasInitialized = false;
    bool wasRunning = false;
    
    /* Stop if running */
    if (isRunning) {
        [self stopAUGraph];
        wasRunning = true;
    }
    /* Uninitialize if initialized */
    if (isInitialized) {
        [self uninitializeGraph];
        wasInitialized = true;
    }
    
    /* Set up the remoteIO unit to enable/disable output */
    status = AudioUnitSetProperty(player.remoteIOUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output,
                                  outputBus,
                                  &enableOutput,
                                  sizeof(enableOutput));
    if (status != noErr) {
        [self printErrorMessage:@"Enable/disable output failed" withStatus:status];
    }
    else outputEnabled = enabled;
    
    /* Reinitialize if needed */
    if (wasInitialized)
        [self initializeGraph];
    
    /* Restart if needed */
    if (wasRunning)
        [self startAUGraph];
}

/* Internal pre/post processing buffer setters/getters */
- (void)updateInputBuffer:(Float32 *)inBuffer {
    
    pthread_mutex_lock(&player.inputBufferMutex);
    free(player.inputBuffer);
    player.inputBuffer = (Float32 *)malloc(player.bufferSizeFrames * sizeof(Float32));
    memcpy(player.inputBuffer, inBuffer, player.bufferSizeFrames * sizeof(Float32));
    pthread_mutex_unlock(&player.inputBufferMutex);
}
- (void)updateOutputBuffer:(Float32 *)inBuffer {
    
    pthread_mutex_lock(&player.outputBufferMutex);
    free(player.outputBuffer);
    player.outputBuffer = (Float32 *)malloc(player.bufferSizeFrames * sizeof(Float32));
    memcpy(player.outputBuffer, inBuffer, player.bufferSizeFrames * sizeof(Float32));
    pthread_mutex_unlock(&player.outputBufferMutex);
}
- (void)getInputBuffer:(Float32 *)outBuffer {
    
    pthread_mutex_lock(&player.inputBufferMutex);
    memcpy(outBuffer, player.inputBuffer, player.bufferSizeFrames * sizeof(Float32));
    pthread_mutex_unlock(&player.inputBufferMutex);
}
- (void)getOutputBuffer:(Float32 *)outBuffer {
    
    pthread_mutex_lock(&player.outputBufferMutex);
    memcpy(outBuffer, player.outputBuffer, player.bufferSizeFrames * sizeof(Float32));
    pthread_mutex_unlock(&player.outputBufferMutex);
}

#pragma mark Utility Methods
- (void)printErrorMessage:(NSString *)errorString withStatus:(OSStatus)result {
    
    char errorDetail[20];
    
    /* Check if the error is a 4-character code */
    *(UInt32 *)(errorDetail + 1) = CFSwapInt32HostToBig(result);
    if (isprint(errorDetail[1]) && isprint(errorDetail[2]) && isprint(errorDetail[3]) && isprint(errorDetail[4])) {
        
        errorDetail[0] = errorDetail[5] = '\'';
        errorDetail[6] = '\0';
    }
    else /* Format is an integer */
        sprintf(errorDetail, "%d", (int)result);
    
    fprintf(stderr, "Error: %s (%s)\n", [errorString cStringUsingEncoding:NSASCIIStringEncoding], errorDetail);
}

@end



















