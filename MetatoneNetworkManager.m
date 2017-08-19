//
//  MetatoneNetworkManager.m
//  Metatone
//
//  Created by Charles Martin on 10/04/13.
//  Copyright (c) 2013 Charles Martin. All rights reserved.
//  Modified January 2014 to work with F53OSC
//

#import "MetatoneNetworkManager.h"

#define USE_WEBSOCKET_CLASSIFIER @YES

#define DEFAULT_PORT 51200
#define DEFAULT_ADDRESS @"10.0.1.199"

#define METATONE_CLASSIFIER_HOSTNAME @"metatonetransfer.com"

#define METATONE_CLASSIFIER_PORT 8888
#define METACLASSIFIER_SERVICE_TYPE @"_metatoneclassifier._tcp."
#define METATONE_SERVICE_TYPE @"_metatoneapp._udp."
#define OSCLOGGER_SERVICE_TYPE @"_osclogger._udp."

#define SERVER_DISCONNECTED 0
#define SERVER_CONNECTING 1
#define SERVER_CONNECTED 2

@implementation MetatoneNetworkManager
// Designated Initialisers

// This initialiser just sets web classification to NO to preserve compatibility.
-(MetatoneNetworkManager *) initWithDelegate:(id<MetatoneNetworkManagerDelegate>)delegate shouldOscLog:(bool)osclogging {
    return [self initWithDelegate:delegate shouldOscLog:osclogging shouldConnectToWebClassifier:NO];
}


// This initialiser sets web classification by argument.
-(MetatoneNetworkManager *) initWithDelegate: (id<MetatoneNetworkManagerDelegate>) delegate shouldOscLog: (bool) osclogging shouldConnectToWebClassifier: (bool) connectToWeb {
    self = [super init];
    
    self.delegate = delegate;
    // if ios: [UIDevice currentDevice].name if mac: [[NSHost currentHost] localizedName]
#if TARGET_OS_IPHONE
    self.deviceID = [UIDevice currentDevice].name;
#else
    self.deviceID = [[NSHost currentHost] localizedName];
#endif
    
    self.appID = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    self.oscLogging = osclogging;
    self.connectToWebClassifier = connectToWeb;
    self.loggingIPAddress = DEFAULT_ADDRESS;
    self.loggingPort = DEFAULT_PORT;
    self.localIPAddress = [MetatoneNetworkManager getIPAddress];
    self.connectedToServer = SERVER_DISCONNECTED;
    self.connectedToLocalPerformanceServer = NO;

    // Setup OSC Client
    self.oscClient = [[F53OSCClient alloc] init];
    [self.oscClient setHost:self.loggingIPAddress];
    [self.oscClient setPort:self.loggingPort];
    [self.oscClient connect];
    
    // Setup OSC Server
    self.oscServer = [[F53OSCServer alloc] init];
    [self.oscServer setDelegate:self];
    [self.oscServer setPort:DEFAULT_PORT];
    [self.oscServer startListening];
    
    // Connect WebSocketClassifier
    //    if (USE_WEBSOCKET_CLASSIFIER) [self connectWebClassifierWebSocket];
    if (connectToWeb) [self connectWebClassifierWebSocket];
    
    // register with Bonjour
    // if ios: [UIDevice currentDevice].name if mac: [[NSHost currentHost] localizedName]
#if TARGET_OS_IPHONE
    self.metatoneNetService = [[NSNetService alloc]
                               initWithDomain:@""
                               type:METATONE_SERVICE_TYPE
                               name:[UIDevice currentDevice].name
                               port:DEFAULT_PORT];
#else
    self.metatoneNetService = [[NSNetService alloc]
                               initWithDomain:@""
                               type:METATONE_SERVICE_TYPE
                               name:[[NSHost currentHost] localizedName]
                               port:DEFAULT_PORT];
#endif
    if (self.metatoneNetService != nil) {
        [self.metatoneNetService setDelegate: self];
        [self.metatoneNetService publishWithOptions:0];
        // if ios: [UIDevice currentDevice].name if mac: [[NSHost currentHost] localizedName]
        
       // NSLog(@"NETWORK MANAGER: Metatone NetService Published - name: %@", [[NSHost currentHost] localizedName]);
        
    }
    
    
    if (self.oscLogging) {
        // try to find an OSC Logger to connect to (but only if "oscLogging" is set).
        NSLog(@"NETWORK MANAGER: Browsing for OSC Logger Services...");
        self.oscLoggerServiceBrowser  = [[NSNetServiceBrowser alloc] init];
        [self.oscLoggerServiceBrowser setDelegate:self];
        [self.oscLoggerServiceBrowser searchForServicesOfType:OSCLOGGER_SERVICE_TYPE
                                                     inDomain:@"local."];
    }
    
    // try to find Metatone Apps to connect to (always do this)
    NSLog(@"NETWORK MANAGER: Browsing for Metatone App Services...");
    self.metatoneServiceBrowser  = [[NSNetServiceBrowser alloc] init];
    [self.metatoneServiceBrowser setDelegate:self];
    [self.metatoneServiceBrowser searchForServicesOfType:METATONE_SERVICE_TYPE
                                                inDomain:@"local."];
    
    // try to find Metatone Web Classifier services locally
    NSLog(@"NETWORK MANAGER: Browsing for Metatone Web Classifier Services...");
    self.metatoneWebClassifierBrowser  = [[NSNetServiceBrowser alloc] init];
    [self.metatoneWebClassifierBrowser setDelegate:self];
    [self.metatoneWebClassifierBrowser searchForServicesOfType:METACLASSIFIER_SERVICE_TYPE
                                                inDomain:@"local."];
    return self;
}





#pragma mark WebSocket Life Cycle
//-(void)connectClassifierWebSocket {
//    [self.classifierWebSocket close];
//    self.classifierWebSocket.delegate = nil;
//    NSString* classifierUrl = [NSString stringWithFormat:@"ws://%@:%d/classifier",METATONE_CLASSIFIER_HOSTNAME,METATONE_CLASSIFIER_PORT];
//    self.classifierWebSocket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:classifierUrl]]];
//    [self.classifierWebSocket setDelegate:self];
//    NSLog(@"NETWORK MANAGER: Opening Classifier WebSocket.");
//    [self.classifierWebSocket open];
//
//}

#pragma mark - Main Web Classifier Connection Methods.

#pragma TODO these two connection methods are problematic - what if they are called when already connected?
- (void) startConnectingToWebClassifier {
    self.connectToWebClassifier = YES;
    if (self.connectedToServer == SERVER_DISCONNECTED)
    {
        NSLog(@"NETWORK MANAGER: startConnectingToWebClassifier was called.");
        NSLog(@"NETWORK MANAGER: WebSocket.readyState is %ld",(long)self.classifierWebSocket.readyState);
        if (self.classifierWebSocket.readyState == SR_CLOSED || self.classifierWebSocket.readyState == SR_CONNECTING)
        {
            NSLog(@"NETWORK MANAGER: Classifier is closed, now starting to connect to WebClassifier");
            [self connectWebClassifierWebSocket];
        }
    }
}


- (void) stopConnectingToWebClassifier {
    NSLog(@"NETWORK MANAGER: stopConnectingToWebClassifier was called.");
    self.connectToWebClassifier = NO;
    if (!self.connectedToLocalPerformanceServer) [self closeClassifierWebSocket];
}

- (bool) isClassifierConnected {
    // Check if web classifier is connected
    return (self.connectedToServer == SERVER_CONNECTED);
}

# pragma mark - internal Web Classifier Connection Methods.

-(void)connectWebClassifierWebSocket {
    [self connectClassifierWebSocketWithHostname:METATONE_CLASSIFIER_HOSTNAME andPort:METATONE_CLASSIFIER_PORT];
}

-(void)reconnectWebClassifierWebSocket {
    [self connectClassifierWebSocketWithHostname:self.webClassifierHostname andPort:self.webClassifierPort];
}

-(void)connectClassifierWebSocketWithHostname:(NSString *)hostname andPort:(int)port {
    [self.classifierWebSocket close];
    self.classifierWebSocket.delegate = nil;
    NSString* classifierUrl = [NSString stringWithFormat:@"ws://%@:%d/classifier",hostname,port];
    self.classifierWebSocket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:classifierUrl]]];
    [self.classifierWebSocket setDelegate:self];
    NSLog(@"NETWORK MANAGER: Opening Classifier WebSocket: %@:%d",hostname,port);
    self.connectedToServer = SERVER_CONNECTING;
    [self.classifierWebSocket open];
    self.webClassifierHostname = hostname; // set local variable to keep hostname
    self.webClassifierPort = port; // set local variable to keep port
}

-(void)closeClassifierWebSocket {
    NSLog(@"NETWORK MANAGER: closeClassifierWebSocket was called.");
    [self sendMessageOffline];
    [self.classifierWebSocket close];
    self.connectedToServer = SERVER_DISCONNECTED;
#pragma mark TODO There really should be a "web classifier closed" callback to the delegate.
    [self.delegate stoppedSearchingForLoggingServer]; // TODO: change to a more appropriately named method
}

-(void)webSocketDidOpen:(SRWebSocket *)webSocket {
    NSLog(@"NETWORK MANAGER: Classifier WebSocket Opened: %@", [webSocket description]);
    self.connectedToServer = SERVER_CONNECTED;
    [self sendMessageOnline];
    [self.delegate loggingServerFoundWithAddress:self.webClassifierHostname andPort:self.webClassifierPort andHostname:self.webClassifierHostname];
}

-(void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    NSLog(@"NETWORK MANAGER: Classifier WebSocket Closed: %@, Clean: %d", reason,wasClean);
    self.classifierWebSocket = nil;
    self.connectedToServer = SERVER_DISCONNECTED;
    [self.delegate stoppedSearchingForLoggingServer]; // TODO: change to a more appropriately named method
}

-(void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    NSLog(@"NETWORK MANAGER: Classifier WebSocket Failed: %@", [error description]);
    self.classifierWebSocket = nil;
    self.connectedToServer = SERVER_DISCONNECTED;
    [self.delegate stoppedSearchingForLoggingServer]; // TODO: change to a more appropriately named method
}

-(void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
    if ([message isKindOfClass:[NSData class]]) {
        NSData *messageData = [NSData dataWithBytes:[(NSData *)message bytes] length:[(NSData *)message length]];
        [F53OSCParser processOscData:messageData forDestination:self replyToSocket:nil]; // This should activate the "takeMessage" method
    }
}

# pragma mark TODO fix up logic about local and remote websockets.
-(void)sendToWebClassifier:(F53OSCMessage *)message {
    if (self.classifierWebSocket.readyState == SR_OPEN) {
        [self.classifierWebSocket send:[message packetData]];
    } else if (self.connectToWebClassifier) {
        NSLog(@"NETWORK MANAGER: Can't send to WebSocket - Closed.");
        if(USE_WEBSOCKET_CLASSIFIER) [self reconnectWebClassifierWebSocket];
    }
}

# pragma mark Searching Lifecycle
-(void) stopSearches
{
    [self.metatoneServiceBrowser stop];
    [self.oscLoggerServiceBrowser stop];
    [self.remoteMetatoneIPAddresses removeAllObjects];
    [self.remoteMetatoneNetServices removeAllObjects];
    [self.oscClient disconnect];
}

#pragma mark Instantiation
-(NSMutableArray *) remoteMetatoneNetServices {
    if (!_remoteMetatoneNetServices) _remoteMetatoneNetServices = [[NSMutableArray alloc] init];
    return _remoteMetatoneNetServices;
}

-(NSMutableArray *) remoteMetatoneIPAddresses {
    if (!_remoteMetatoneIPAddresses) _remoteMetatoneIPAddresses = [[NSMutableArray alloc] init];
    return _remoteMetatoneIPAddresses;
}

# pragma mark NetServiceBrowserDelegate Methods

-(void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didNotSearch:(NSDictionary *)errorDict {
    NSLog(@"NETWORK MANAGER: ERROR: Did not search for OSC Logger");
}

-(void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    
    if ([[aNetService type] isEqualToString:METATONE_SERVICE_TYPE]) {
        if ([aNetService isEqual:self.metatoneNetService]) {
            NSLog(@"NETWORK MANAGER: Found own metatone service - ignoring.");
            return;
        }
        [aNetService setDelegate:self];
        [aNetService resolveWithTimeout:5.0];
        [self.remoteMetatoneNetServices addObject:aNetService];
    }
    
    if ([[aNetService type] isEqualToString:OSCLOGGER_SERVICE_TYPE]) {
        self.oscLoggerService = aNetService;
        [self.oscLoggerService setDelegate:self];
        [self.oscLoggerService resolveWithTimeout:5.0];
        //TODO: sort out case of multiple OSC Loggers.
    }
    
    if ([[aNetService type] isEqualToString:METACLASSIFIER_SERVICE_TYPE]) {
        self.metatoneWebClassifierNetService = aNetService;
        [self.metatoneWebClassifierNetService setDelegate:self];
        [self.metatoneWebClassifierNetService resolveWithTimeout:5.0];
    }
}

-(void)netServiceDidResolveAddress:(NSNetService *)sender {
    NSString* firstAddress;
    int firstPort;
    
    for (NSData* data in [sender addresses]) {
        char addressBuffer[100];
        struct sockaddr_in* socketAddress = (struct sockaddr_in*) [data bytes];
        int sockFamily = socketAddress->sin_family;
        if (sockFamily == AF_INET || sockFamily == AF_INET6) {
            const char* addressStr = inet_ntop(sockFamily,
                                               &(socketAddress->sin_addr), addressBuffer,
                                               sizeof(addressBuffer));
            int port = ntohs(socketAddress->sin_port);
            if (addressStr && port) {
                NSLog(@"NETWORK MANAGER: Resolved service of type %@ at %s:%d - %@",
                      [sender type],
                      addressStr,
                      port,
                      sender.hostName);
                firstAddress = [NSString stringWithFormat:@"%s",addressStr];
                firstPort = port;
                break;
            }
        }
    }
    
    if ([sender.type isEqualToString:OSCLOGGER_SERVICE_TYPE] && firstAddress && firstPort) {
        self.loggingHostname = sender.hostName;
        self.loggingIPAddress = firstAddress;
        self.loggingPort = firstPort;
        
        [self.delegate loggingServerFoundWithAddress:self.loggingIPAddress
                                             andPort:(int)self.loggingPort
                                         andHostname:self.loggingHostname];
        [self sendMessageOnline];
        NSLog(@"NETWORK MANAGER: Resolved and Connected to an OSC Logger Service.");
    }
    
    if ([sender.type isEqualToString:METATONE_SERVICE_TYPE] && firstAddress && firstPort) {
        // Save the found address.
        // Need to also check if address is already in the array.
        if (![firstAddress isEqualToString:self.localIPAddress] && ![firstAddress isEqualToString:@"127.0.0.1"]) {
            [self.remoteMetatoneIPAddresses addObject:@[firstAddress,[NSNumber numberWithInt:firstPort]]];
            [self.delegate metatoneClientFoundWithAddress:firstAddress andPort:firstPort andHostname:sender.hostName];
            NSLog(@"NETWORK MANAGER: Resolved and Connected to a MetatoneApp Service.");
        }
    }
    
    if ([sender.type isEqualToString:METACLASSIFIER_SERVICE_TYPE] && firstAddress && firstPort) {
        // Connect to the webclassifier.
        [self connectClassifierWebSocketWithHostname:sender.hostName andPort:firstPort];
        self.connectedToLocalPerformanceServer = YES;
    }
}


#pragma TODO make sure the search and stop search delegate messages are working depending on server state.
-(void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)aNetServiceBrowser {
//    only run this is not currently connected to anything.
    NSLog(@"NETWORK MANAGER: Connection Status: %d", self.connectedToServer);
    if (self.connectedToServer == SERVER_DISCONNECTED) [self.delegate searchingForLoggingServer];
}

-(void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)aNetServiceBrowser {
    NSLog(@"NETWORK MANAGER: NetServiceBrowser stopped searching.");
    if (self.connectedToServer == SERVER_DISCONNECTED) [self.delegate stoppedSearchingForLoggingServer];
}


# pragma mark OSC Sending Methods
-(void)sendMessageWithAccelerationX:(double)x Y:(double)y Z:(double)z
{
    NSArray *contents = @[self.deviceID,
                          [NSNumber numberWithFloat:x],
                          [NSNumber numberWithFloat:y],
                          [NSNumber numberWithFloat:z]];
    F53OSCMessage *message = [F53OSCMessage messageWithAddressPattern:@"/metatone/acceleration"
                                                        arguments:contents];
    [self.oscClient sendPacket:message toHost:self.loggingIPAddress onPort:self.loggingPort];
    [self sendToWebClassifier:message]; // hope this works!
}

-(void)sendMessageWithTouch:(CGPoint)point Velocity:(CGFloat)vel
{
    NSArray *contents = @[self.deviceID,
                          [NSNumber numberWithFloat:point.x],
                          [NSNumber numberWithFloat:point.y],
                          [NSNumber numberWithFloat:vel]];
    F53OSCMessage *message = [F53OSCMessage messageWithAddressPattern:@"/metatone/touch"
                                                            arguments:contents];
    [self.oscClient sendPacket:message toHost:self.loggingIPAddress onPort:self.loggingPort];
    [self sendToWebClassifier:message];
}

-(void)sendMesssageSwitch:(NSString *)name On:(BOOL)on
{
    NSString *switchState = on ? @"T" : @"F";
    NSArray *contents = @[self.deviceID,
                          name,
                          switchState];
    F53OSCMessage *message = [F53OSCMessage messageWithAddressPattern:@"/metatone/switch" arguments:contents];
    [self.oscClient sendPacket:message toHost:self.loggingIPAddress onPort:self.loggingPort];
    [self sendToWebClassifier:message];
}

-(void)sendMessageTouchEnded
{
    NSArray *contents = @[self.deviceID];
    F53OSCMessage *message = [F53OSCMessage messageWithAddressPattern:@"/metatone/touch/ended" arguments:contents];
    [self.oscClient sendPacket:message toHost:self.loggingIPAddress onPort:self.loggingPort];
    [self sendToWebClassifier:message];
}

-(void)sendMessageOnline
{
    NSLog(@"Constructing Online Message.");
    NSArray *contents = @[self.deviceID,self.appID];
    F53OSCMessage *message = [F53OSCMessage messageWithAddressPattern:@"/metatone/online" arguments:contents];
    [self.oscClient sendPacket:message toHost:self.loggingIPAddress onPort:self.loggingPort];
    [self sendToWebClassifier:message];
}

-(void)sendMessageRemoteControl
{
    NSLog(@"Sending Remote Control Message.");
    NSArray *contents = @[self.deviceID, [self localIPAddress]];
    F53OSCMessage *message = [F53OSCMessage messageWithAddressPattern:@"/metatone/remote" arguments:contents];
    [self.oscClient sendPacket:message toHost:self.loggingIPAddress onPort:self.loggingPort];
    [self sendToWebClassifier:message];
}

-(void)sendMessageOffline
{
    NSArray *contents = @[self.deviceID,self.appID];
    F53OSCMessage *message = [F53OSCMessage messageWithAddressPattern:@"/metatone/offline"
                                                            arguments:contents];
    [self.oscClient sendPacket:message toHost:self.loggingIPAddress onPort:self.loggingPort];
    [self sendToWebClassifier:message]; // hope this works!
}


-(void)sendMetatoneMessage:(NSString *)name withState:(NSString *)state {
    NSArray *contents = @[self.deviceID,
                          name,
                          state];
    F53OSCMessage *message = [F53OSCMessage messageWithAddressPattern:@"/metatone/app"
                                                            arguments:contents];

    // Log the metatone messages as well.
    [self.oscClient sendPacket:message toHost:self.loggingIPAddress onPort:self.loggingPort];
    [self sendToWebClassifier:message]; // hope this works!
    
    // Send to each metatone app on the network.
    for (NSArray *address in self.remoteMetatoneIPAddresses) {
        [self.oscClient sendPacket:message
                            toHost:(NSString *)address[0]
                              onPort:[((NSNumber *)address[1]) integerValue]];
    }
}

- (void)sendMetatoneMessageViaServer:(NSString *)name withState:(NSString *)state {
    NSArray *contents = @[self.deviceID,
                          name,
                          state];
    F53OSCMessage *message = [F53OSCMessage messageWithAddressPattern:@"/metatone/app"
                                                            arguments:contents];
    [self.oscClient sendPacket:message toHost:self.loggingIPAddress onPort:self.loggingPort];
    [self sendToWebClassifier:message];
}

#pragma mark OSC Receiving Methods

/// Main method for receiving and parsing OSC Messages.
-(void)takeMessage:(F53OSCMessage *)message {
    if ([message.addressPattern isEqualToString:@"/metatone/app"]) {
        // InterAppmessage
        if ([message.arguments count] == 3) {
            if ([message.arguments[0] isKindOfClass:[NSString class]] &&
                [message.arguments[1] isKindOfClass:[NSString class]] &&
                [message.arguments[2] isKindOfClass:[NSString class]])
            {
                if (![((NSString *) message.arguments[0]) isEqualToString:self.deviceID]) { // ignore self metatone messages.
                    [self.delegate didReceiveMetatoneMessageFrom:message.arguments[0] withName:message.arguments[1] andState:message.arguments[2]];}
            }
        }
    } else if ([message.addressPattern isEqualToString:@"/metatone/classifier/gesture"]) {
        // Gesture Message
        if ([message.arguments count] == 2) [self.delegate didReceiveGestureMessageFor:message.arguments[0] withClass:message.arguments[1]];
    } else if ([message.addressPattern isEqualToString:@"/metatone/classifier/ensemble/state"]) {
        //Ensemble State
        if ([message.arguments count] == 3) [self.delegate didReceiveEnsembleState:message.arguments[0] withSpread:message.arguments[1] withRatio:message.arguments[2]];
    } else if ([message.addressPattern isEqualToString:@"/metatone/classifier/ensemble/event/new_idea"]) {
        if ([message.arguments count] == 2) [self.delegate didReceiveEnsembleEvent:@"new_idea" forDevice:message.arguments[0] withMeasure:message.arguments[1]];
    } else if ([message.addressPattern isEqualToString:@"/metatone/classifier/ensemble/event/solo"]) {
        [self.delegate didReceiveEnsembleEvent:@"solo" forDevice:message.arguments[0] withMeasure:message.arguments[1]];
    } else if ([message.addressPattern isEqualToString:@"/metatone/classifier/ensemble/event/parts"]) {
        [self.delegate didReceiveEnsembleEvent:@"parts" forDevice:message.arguments[0] withMeasure:message.arguments[1]];
    } else if ([message.addressPattern isEqualToString:@"/metatone/performance/start"]) {
        // performance start
        if ([message.arguments count] == 4) [self.delegate didReceivePerformanceStartEvent:message.arguments[0]
                                                                                 forDevice:message.arguments[1]
                                                                                  withType:message.arguments[2]
                                                                            andComposition:message.arguments[3]];
    } else if ([message.addressPattern isEqualToString:@"/metatone/performance/end"]) {
        // performance stop
        if ([message.arguments count] ==2) [self.delegate didReceivePerformanceEndEvent:message.arguments[0]
                                                                              forDevice:message.arguments[1]];
    } else if ([message.addressPattern isEqualToString:@"/metatone/classifier/hello"]) {
        NSLog(@"NETWORK MANAGER: Connection Handshake from Server Received.");
    } else if ([message.addressPattern isEqualToString:@"/metatone/playback/touch"]) {
        // A returned touch message from the classifier -- play it!
        //NSLog(@"Play back a touch of some kind");
        if ([message.arguments count] == 4) [self.delegate didReceiveTouchPlayMessageFor:message.arguments[0] X:message.arguments[1] Y:message.arguments[2] vel:message.arguments[3]];
        //[NSNumber numberWithFloat:point.x],
        //[NSNumber numberWithFloat:point.y],
        //[NSNumber numberWithFloat:vel]];
        // Message should have three arguments.
    } else if ([message.addressPattern isEqualToString:@"/metatone/playback/gesture"]) {
        // Gesture Message to be played back!
        if ([message.arguments count] == 2) [self.delegate didReceiveGesturePlayMessageFor:message.arguments[0] withClass:message.arguments[1]];
    } else {
        // Received unknown message:
        NSLog(@"NETWORK MANAGER: Received unknown message: %@", [message description]);
    }
}

// performance start events should be of the form:
// /metatone/performance/start (string) deviceID (int) type (composition) int
// the type should be
//#define PERFORMANCE_TYPE_LOCAL 0
//#define PERFORMANCE_TYPE_REMOTE 1
//#define EXPERIMENT_TYPE_BOTH 2
//#define EXPERIMENT_TYPE_NONE 3
//#define EXPERIMENT_TYPE_BUTTON 4
//#define EXPERIMENT_TYPE_SERVER 5
//
// the composition is an int that corresponds to one of the available compositions,
// for the experiment, the int can be random (as long as everybody has the same one).

#pragma mark IP Address Methods

/// Get IP Address
+ (NSString *)getIPAddress {
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    return address;
}

/// Attempt to find local broadcast address.
+ (NSString *)getLocalBroadcastAddress {
    NSArray *addressComponents = [[MetatoneNetworkManager getIPAddress] componentsSeparatedByString:@"."];
    NSString *address = nil;
    if ([addressComponents count] == 4)
    {
        address = @"";
        for (int i = 0; i<([addressComponents count] - 1); i++) {
            address = [address stringByAppendingString:addressComponents[i]];
            address = [address stringByAppendingString:@"."];
        }
        address = [address stringByAppendingString:@"255"];
    }
    return address;
}

@end
