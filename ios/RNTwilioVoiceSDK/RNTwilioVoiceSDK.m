//
//  RNTwilioVoiceSDK.m
//

#import "RNTwilioVoiceSDK.h"
#import <React/RCTLog.h>

@import AVFoundation;
@import CallKit;
@import PushKit;
@import TwilioVoice;

@interface RNTwilioVoiceSDK () <TVOCallDelegate, CXProviderDelegate, PKPushRegistryDelegate, TVONotificationDelegate>
@property (nonatomic, strong) NSString *deviceTokenString;
@property (nonatomic, strong) PKPushRegistry *voipRegistry;
@property (nonatomic, strong) void(^incomingPushCompletionCallback)(void);
@property (nonatomic, strong) NSMutableDictionary *activeCallInvites;
@property (nonatomic, strong) NSMutableDictionary *activeCalls;

@property (nonatomic, strong) TVOCall *call;

@property (nonatomic, strong) void(^callKitCompletionCallback)(BOOL);
@property (nonatomic, strong) CXProvider *callKitProvider;
@property (nonatomic, strong) CXCallController *callKitCallController;
@property (nonatomic, strong) TVODefaultAudioDevice *audioDevice;
@property (nonatomic, strong) NSString *twilioToken;
@property (nonatomic, strong) NSDictionary *twilioCallOptions;
@property (nonatomic, strong) RCTPromiseResolveBlock resolveBlock;

@end

@implementation RNTwilioVoiceSDK {
    NSString * _accessToken;
}

NSString * const StateConnecting = @"CONNECTING";
NSString * const StateConnected = @"CONNECTED";
NSString * const StateDisconnected = @"DISCONNECTED";
NSString * const StateReconnecting = @"RECONNECTING";
NSString * const StateRinging = @"RINGING";


- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"ringing", @"connect", @"connectFailure", @"reconnecting", @"reconnect", @"disconnect"];
}

@synthesize bridge = _bridge;

- (void)dealloc {
    if(self.call) {
        [self disconnect];
    }
    if (self.callKitProvider) {
      [self.callKitProvider invalidate];
    }
}

RCT_EXPORT_METHOD(initWithAccessToken:(NSString *)accessToken) {
  _accessToken = accessToken;
  [self initPushRegistry];
}

- (void)configureCallKit {
    CXProviderConfiguration *configuration = [[CXProviderConfiguration alloc] initWithLocalizedName:@"appName"];
    configuration.maximumCallGroups = 1;
    configuration.maximumCallsPerCallGroup = 1;
    _callKitProvider = [[CXProvider alloc] initWithConfiguration:configuration];
    [_callKitProvider setDelegate:self queue:nil];

    _callKitCallController = [[CXCallController alloc] init];
    self.audioDevice = [TVODefaultAudioDevice audioDevice];
    TwilioVoice.audioDevice = self.audioDevice;
    [self toggleAudioRoute:NO];
}

RCT_REMAP_METHOD(connect,
                 accessToken:(NSString *)accessToken
                 options:(NSDictionary *)options
                 connectResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
  if (self.call) {
    reject(@"already_connected",@"Calling connect while a call is connected",nil);
  } else {
      [self enableProximityMonitoring];
      [self configureCallKit];
      NSUUID *uuid = [NSUUID UUID];
      NSString *handle = @"Voice Bot";
      
      [self checkRecordPermission:^(BOOL permissionGranted) {
          if (!permissionGranted) {
              reject(@"permission_rejected", @"Calling needs microphone permission to be performed", nil);
          } else {
              self.twilioToken = accessToken;
              self.twilioCallOptions = options;
              self.resolveBlock = resolve;
              [self performStartCallActionWithUUID:uuid handle:handle];
          }
      }];
  }
}

RCT_EXPORT_METHOD(disconnect) {
  NSLog(@"Disconnecting call");
    self.call.muted = false;
    [self toggleAudioRoute:false];
    [self disableProximityMonitoring];
    if(self.call) {
        [self performEndCallActionWithUUID:self.call.uuid];
    }
}

RCT_EXPORT_METHOD(setMuted: (BOOL *)muted) {
  NSLog(@"Mute/UnMute call");
  self.call.muted = muted;
}

RCT_EXPORT_METHOD(setSpeakerPhone: (BOOL *)speaker) {
  [self toggleAudioRoute:speaker];
}

RCT_EXPORT_METHOD(sendDigits: (NSString *)digits){
  if (self.call && self.call.state == TVOCallStateConnected) {
    NSLog(@"SendDigits %@", digits);
    [self.call sendDigits:digits];
  }
}

RCT_REMAP_METHOD(getVersion,
                 getVersionResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject){
  resolve(TwilioVoice.sdkVersion);
}

RCT_REMAP_METHOD(getActiveCall,
                 activeCallResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject){

  if (self.call) {
    NSMutableDictionary *params = [self callParamsFor:self.call];
    resolve(params);
  } else{
    reject(@"no_call", @"There was no active call", nil);
  }
}

- (void)checkRecordPermission:(void(^)(BOOL permissionGranted))completion {
    AVAudioSessionRecordPermission permissionStatus = [[AVAudioSession sharedInstance] recordPermission];
    switch (permissionStatus) {
        case AVAudioSessionRecordPermissionGranted:
            // Record permission already granted.
            completion(YES);
            break;
        case AVAudioSessionRecordPermissionDenied:
            // Record permission denied.
            completion(NO);
            break;
        case AVAudioSessionRecordPermissionUndetermined:
        {
            // Requesting record permission.
            // Optional: pop up app dialog to let the users know if they want to request.
            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
                completion(granted);
            }];
            break;
        }
        default:
            completion(NO);
            break;
    }
}

- (NSString *)callStateFor:(TVOCall *)call {
    if (call.state == TVOCallStateConnected) {
        return StateConnected;
    } else if (call.state == TVOCallStateConnecting) {
        return StateConnecting;
    } else if (call.state == TVOCallStateDisconnected) {
        return StateDisconnected;
    } else if (call.state == TVOCallStateReconnecting) {
        return StateReconnecting;
    } else if (call.state == TVOCallStateRinging) {
        return StateRinging;
    }
    return @"INVALID";
}

- (NSMutableDictionary *)callParamsFor:(TVOCall *)call {
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    if (call.sid) {
        [params setObject:call.sid forKey:@"sid"];
    }
    if (call.to){
        [params setObject:call.to forKey:@"to"];
    }
    if (call.from){
        [params setObject:call.from forKey:@"from"];
    }
    [params setObject:[self callStateFor:call] forKey:@"state"];
    return params;
}

- (NSMutableDictionary *)paramsForError:(NSError *)error {
    NSMutableDictionary *params = [self callParamsFor:self.call];

    if (error) {
        NSMutableDictionary *errorParams = [[NSMutableDictionary alloc] init];
        if (error.code) {
            [errorParams setObject:[@([error code]) stringValue] forKey:@"code"];
        }
        if (error.domain) {
            [errorParams setObject:[error domain] forKey:@"domain"];
        }
        if (error.localizedDescription) {
            [errorParams setObject:[error localizedDescription] forKey:@"message"];
        }
        if (error.localizedFailureReason) {
            [errorParams setObject:[error localizedFailureReason] forKey:@"reason"];
        }
        [params setObject:errorParams forKey:@"error"];
    }
    return params;
}

- (void)enableProximityMonitoring {
    // Enable Proximity monitoring
    UIDevice* device = [UIDevice currentDevice];
    device.proximityMonitoringEnabled = YES;
}

- (void)disableProximityMonitoring {
    // Enable Proximity monitoring
    UIDevice* device = [UIDevice currentDevice];
    device.proximityMonitoringEnabled = NO;
}
#pragma mark - VoIP
- (void)initPushRegistry {
  self.voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
  self.voipRegistry.delegate = self;
  self.voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}


#pragma mark - PKPushRegistryDelegate
- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type {
    NSLog(@"pushRegistry:didUpdatePushCredentials:forType:");
    if ([type isEqualToString:PKPushTypeVoIP] && _accessToken) {
        const unsigned *tokenBytes = [credentials.token bytes];
        NSString *deviceTokenString = [NSString stringWithFormat:@"<%08x %08x %08x %08x %08x %08x %08x %08x>",
                                  ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                                  ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                                  ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];
        self.deviceTokenString = deviceTokenString;
        [TwilioVoice registerWithAccessToken:_accessToken deviceToken:deviceTokenString completion:^(NSError *error) {
            if (error) {
                NSLog(@"An error occurred while registering: %@", [error localizedDescription]);
            }
            else {
                NSLog(@"Successfully registered for VoIP push notifications.");
            }
        }];
    }
}

- (void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(PKPushType)type {
    NSLog(@"pushRegistry:didInvalidatePushTokenForType:");
    if ([type isEqualToString:PKPushTypeVoIP]) {
        [self sendEventWithName:@"invalidPushToken" body: nil];
    }
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(PKPushType)type{
    NSLog(@"pushRegistry:didReceiveIncomingPushWithPayload:forType:");
    if ([type isEqualToString:PKPushTypeVoIP]) {
        // The Voice SDK will use main queue to invoke `cancelledCallInviteReceived:error` when delegate queue is not passed
        if (![TwilioVoice handleNotification:payload.dictionaryPayload delegate:self delegateQueue:nil]) {
            NSLog(@"This is not a valid Twilio Voice notification.");
        }
    }
}

/**
 * This delegate method is available on iOS 11 and above. Call the completion handler once the
 * notification payload is passed to the `TwilioVoice.handleNotification()` method.
 */
- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(PKPushType)type withCompletionHandler:(void (^)(void))completion {
    NSLog(@"pushRegistry:didReceiveIncomingPushWithPayload:forType:withCompletionHandler:");

    // Save for later when the notification is properly handled.
    self.incomingPushCompletionCallback = completion;
    if ([type isEqualToString:PKPushTypeVoIP]) {
        // The Voice SDK will use main queue to invoke `cancelledCallInviteReceived:error` when delegate queue is not passed
        if (![TwilioVoice handleNotification:payload.dictionaryPayload delegate:self delegateQueue:nil]) {
            NSLog(@"This is not a valid Twilio Voice notification.");
        }
    }
    if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion < 13) {
        // Save for later when the notification is properly handled.
        self.incomingPushCompletionCallback = completion;
    } else {
        /**
        * The Voice SDK processes the call notification and returns the call invite synchronously. Report the incoming call to
        * CallKit and fulfill the completion before exiting this callback method.
        */
        completion();
    }
}

- (void)incomingPushHandled {
    if (self.incomingPushCompletionCallback) {
        self.incomingPushCompletionCallback();
        self.incomingPushCompletionCallback = nil;
    }
}

#pragma mark - TVONotificationDelegate
- (void)callInviteReceived:(TVOCallInvite *)callInvite {

    /**
     * Calling `[TwilioVoice handleNotification:delegate:]` will synchronously process your notification payload and
     * provide you a `TVOCallInvite` object. Report the incoming call to CallKit upon receiving this callback.
     */

    NSLog(@"callInviteReceived:");

    NSString *from = @"Voice Bot";
    if (callInvite.from) {
        from = [callInvite.from stringByReplacingOccurrencesOfString:@"client:" withString:@""];
    }

    // Always report to CallKit
    [self reportIncomingCallFrom:from withUUID:callInvite.uuid];
    self.activeCallInvites[[callInvite.uuid UUIDString]] = callInvite;
    if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion < 13) {
        [self incomingPushHandled];
    }
}

- (void)cancelledCallInviteReceived:(TVOCancelledCallInvite *)cancelledCallInvite error:(NSError *)error {

    /**
     * The SDK may call `[TVONotificationDelegate callInviteReceived:error:]` asynchronously on the dispatch queue
     * with a `TVOCancelledCallInvite` if the caller hangs up or the client encounters any other error before the called
     * party could answer or reject the call.
     */

    NSLog(@"cancelledCallInviteReceived:");

    TVOCallInvite *callInvite;
    for (NSString *uuid in self.activeCallInvites) {
        TVOCallInvite *activeCallInvite = [self.activeCallInvites objectForKey:uuid];
        if ([cancelledCallInvite.callSid isEqualToString:activeCallInvite.callSid]) {
            callInvite = activeCallInvite;
            break;
        }
    }

    if (callInvite) {
        [self performEndCallActionWithUUID:callInvite.uuid];
    }
}



#pragma mark - TVOCallDelegate
//return @[@"ringing", @"connected", @"connectFailure", @"reconnecting", @"reconnected", @"disconnected"];

- (void)callDidConnect:(TVOCall *)call {
  self.call = call;
  self.callKitCompletionCallback(YES);
  self.callKitCompletionCallback = nil;


  NSMutableDictionary *callParams = [self callParamsFor:call];
  [self sendEventWithName:@"connect" body:callParams];
}

- (void)call:(TVOCall *)call didFailToConnectWithError:(NSError *)error {
  NSLog(@"Call failed to connect: %@", error);

  self.call = call;
  NSMutableDictionary *callParams = [self paramsForError:error];
  [self sendEventWithName:@"connectFailure" body:callParams];
  self.call = nil;
  self.callKitCompletionCallback(NO);
  [self performEndCallActionWithUUID:call.uuid];
}

- (void)call:(TVOCall *)call didDisconnectWithError:(NSError *)error {
  NSLog(@"Call disconnected with error: %@", error);

  self.call = call;
  NSMutableDictionary *callParams = [self paramsForError:error];
  [self sendEventWithName:@"disconnect" body:callParams];
  [self disconnect];
  self.call = nil;
  self.callKitCompletionCallback = nil;
}

- (void)callDidStartRinging:(TVOCall *)call {
  self.call = call;

  NSMutableDictionary *callParams = [self callParamsFor:call];
  [self sendEventWithName:@"ringing" body:callParams];
}

- (void)call:(TVOCall *)call isReconnectingWithError:(NSError *)error {
  NSLog(@"Call is reconnecting with error: %@", error);

  self.call = call;
  NSMutableDictionary *callParams = [self paramsForError:error];
  [self sendEventWithName:@"reconnecting" body:callParams];
}

- (void)callDidReconnect:(TVOCall *)call {
  self.call = call;

  NSMutableDictionary *callParams = [self callParamsFor:call];
  [self sendEventWithName:@"reconnect" body:callParams];
}

#pragma mark - AVAudioSession
- (void)toggleAudioRoute: (BOOL *)toSpeaker {
  // The mode set by the Voice SDK is "VoiceChat" so the default audio route is the built-in receiver. Use port override to switch the route.
  self.audioDevice.block =  ^ {
      // We will execute `kDefaultAVAudioSessionConfigurationBlock` first.
      kTVODefaultAVAudioSessionConfigurationBlock();
      
      // Overwrite the audio route
      AVAudioSession *session = [AVAudioSession sharedInstance];
      NSError *error = nil;
      if (toSpeaker) {
          if (![session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error]) {
              NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
          }
      } else {
          if (![session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error]) {
              NSLog(@"Unable to reroute audio: %@", [error localizedDescription]);
          }
      }
  };
  self.audioDevice.block();
}

#pragma mark - CXProviderDelegate
- (void)providerDidReset:(CXProvider *)provider {
    NSLog(@"providerDidReset:");
    self.audioDevice.enabled = YES;
}

- (void)providerDidBegin:(CXProvider *)provider {
    NSLog(@"providerDidBegin:");
}

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession {
    NSLog(@"provider:didActivateAudioSession:");
    self.audioDevice.enabled = YES;
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession *)audioSession {
    NSLog(@"provider:didDeactivateAudioSession:");
}

- (void)provider:(CXProvider *)provider timedOutPerformingAction:(CXAction *)action {
    NSLog(@"provider:timedOutPerformingAction:");
}

- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action {
    NSLog(@"provider:performStartCallAction:");
    
    self.audioDevice.enabled = NO;
    self.audioDevice.block();
    
    [self.callKitProvider reportOutgoingCallWithUUID:action.callUUID startedConnectingAtDate:[NSDate date]];
    
    __weak typeof(self) weakSelf = self;
    [self performVoiceCallWithUUID:action.callUUID client:nil completion:^(BOOL success) {
        __strong typeof(self) strongSelf = weakSelf;
        if (success) {
            [strongSelf.callKitProvider reportOutgoingCallWithUUID:action.callUUID connectedAtDate:[NSDate date]];
            [action fulfill];
        } else {
            [action fail];
        }
    }];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action {
    NSLog(@"provider:performEndCallAction:");
    if (self.call) {
        [self.call disconnect];
    }

    self.audioDevice.enabled = YES;
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performSetHeldCallAction:(CXSetHeldCallAction *)action {
    if (self.call && self.call.state == TVOCallStateConnected) {
        [self.call setOnHold:action.isOnHold];
        [action fulfill];
    } else {
        [action fail];
    }
}

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action {
    NSLog(@"provider:performAnswerCallAction:");

    self.audioDevice.enabled = NO;
    self.audioDevice.block();

    [self performAnswerVoiceCallWithUUID:action.callUUID completion:^(BOOL success) {
        if (success) {
            [action fulfill];
        } else {
            [action fail];
        }
    }];

    [action fulfill];
}


#pragma mark - CallKit Actions
- (void)performStartCallActionWithUUID:(NSUUID *)uuid handle:(NSString *)handle {
    if (uuid == nil || handle == nil) {
        return;
    }

    CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:handle];
    CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:uuid handle:callHandle];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:startCallAction];

    [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
        if (error) {
            NSLog(@"StartCallAction transaction request failed: %@", [error localizedDescription]);
        } else {
            NSLog(@"StartCallAction transaction request successful");

            CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
            callUpdate.remoteHandle = callHandle;
            callUpdate.supportsDTMF = YES;
            callUpdate.supportsHolding = YES;
            callUpdate.supportsGrouping = NO;
            callUpdate.supportsUngrouping = NO;
            callUpdate.hasVideo = NO;

            [self.callKitProvider reportCallWithUUID:uuid updated:callUpdate];
        }
    }];
}

- (void)reportIncomingCallFrom:(NSString *) from withUUID:(NSUUID *)uuid {
    CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:from];

    CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
    callUpdate.remoteHandle = callHandle;
    callUpdate.supportsDTMF = YES;
    callUpdate.supportsHolding = YES;
    callUpdate.supportsGrouping = NO;
    callUpdate.supportsUngrouping = NO;
    callUpdate.hasVideo = NO;

    [self.callKitProvider reportNewIncomingCallWithUUID:uuid update:callUpdate completion:^(NSError *error) {
        if (!error) {
            NSLog(@"Incoming call successfully reported.");
        }
        else {
            NSLog(@"Failed to report incoming call successfully: %@.", [error localizedDescription]);
        }
    }];
}

- (void)performEndCallActionWithUUID:(NSUUID *)uuid {
    CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:uuid];
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];

    [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
        if (error) {
            NSLog(@"EndCallAction transaction request failed: %@", [error localizedDescription]);
        }
        else {
            NSLog(@"EndCallAction transaction request successful");
        }
    }];
}

- (void)performVoiceCallWithUUID:(NSUUID *)uuid
                          client:(NSString *)client
                      completion:(void(^)(BOOL success))completionHandler {
    __weak typeof(self) weakSelf = self;
    TVOConnectOptions *connectOptions = [TVOConnectOptions optionsWithAccessToken:self.twilioToken block:^(TVOConnectOptionsBuilder *builder) {
        __strong typeof(self) strongSelf = weakSelf;
        builder.params = self.twilioCallOptions;
        builder.uuid = uuid;
    }];
    self.call = [TwilioVoice connectWithOptions:connectOptions delegate:self];
    NSMutableDictionary *params = [self callParamsFor:self.call];
    self.resolveBlock(params);
    self.callKitCompletionCallback = completionHandler;
}

- (void)performAnswerVoiceCallWithUUID:(NSUUID *)uuid
                            completion:(void(^)(BOOL success))completionHandler {
    TVOCallInvite *callInvite = self.activeCallInvites[uuid.UUIDString];
    NSAssert(callInvite, @"No CallInvite matches the UUID");

    TVOAcceptOptions *acceptOptions = [TVOAcceptOptions optionsWithCallInvite:callInvite block:^(TVOAcceptOptionsBuilder *builder) {
        builder.uuid = callInvite.uuid;
    }];

    TVOCall *call = [callInvite acceptWithOptions:acceptOptions delegate:self];

    if (!call) {
        completionHandler(NO);
    } else {
        self.callKitCompletionCallback = completionHandler;
        self.call = call;
        self.activeCalls[call.uuid.UUIDString] = call;
    }

    [self.activeCallInvites removeObjectForKey:callInvite.uuid.UUIDString];

    if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion < 13) {
        [self incomingPushHandled];
    }
}


@end
