//
//  KeenClientTests.m
//  KeenClientTests
//
//  Created by Daniel Kador on 2/8/12.
//  Copyright (c) 2012 Keen Labs. All rights reserved.
//

#import "KeenClientTests.h"
#import "KeenClient.h"
#import <OCMock/OCMock.h>
#import "KeenConstants.h"
#import "KeenProperties.h"
#import "HTTPCodes.h"
#import "KIOUtil.h"
#import "KIOQuery.h"
#import "KIOFileStore.h"
#import "KIONetwork.h"
#import "KIOUploader.h"

NSString* kDefaultProjectID = @"id";
NSString* kDefaultWriteKey = @"wk";
NSString* kDefaultReadKey = @"rk";

@interface KIONetwork (Testable)

- (void)handleQueryAPIResponse:(NSURLResponse*)response
                       andData:(NSData*)responseData
                      andQuery:(KIOQuery*)query
                  andProjectID:(NSString*)projectID;

@end

@interface KIOUploader (Testable)

- (BOOL)isNetworkConnected;

@end

@interface KeenClient (testability)

// The project ID for this particular client.
@property (nonatomic, strong) NSString *projectID;
@property (nonatomic, strong) NSString *writeKey;
@property (nonatomic, strong) NSString *readKey;

@property (nonatomic) KIONetwork* network;

// If we're running tests.
@property (nonatomic) BOOL isRunningTests;

- (id)initWithProjectID:(NSString *)projectID
            andWriteKey:(NSString *)writeKey
             andReadKey:(NSString *)readKey
             andNetwork:(KIONetwork*)network
               andStore:(KIODBStore*)store
            andUploader:(KIOUploader*)uploader;

@end

@interface KeenClientTests ()

@property (nonatomic) NSTimeInterval asyncTimeInterval;

- (NSString *)cacheDirectory;
- (NSString *)keenDirectory;
- (NSString *)eventDirectoryForCollection:(NSString *)collection;
- (NSArray *)contentsOfDirectoryForCollection:(NSString *)collection;
- (NSString *)pathForEventInCollection:(NSString *)collection WithTimestamp:(NSDate *)timestamp;
- (BOOL)writeNSData:(NSData *)data toFile:(NSString *)file;
@end

@implementation KeenClientTests

- (void)setUp {
    [super setUp];

    // initialize is called automatically for a class, but
    // call it again to ensure static global state
    // is consistently set to defaults for each test
    // This relies on initialize being idempotent
    [KeenClient initialize];
    [KeenClient enableLogging];
    [KeenClient setLogLevel:KeenLogLevelVerbose];

    // Configure initial state for shared KeenClient instance
    [[KeenClient sharedClient] setCurrentLocation:nil];
    [[KeenClient sharedClient] setGlobalPropertiesBlock:nil];
    [[KeenClient sharedClient] setGlobalPropertiesDictionary:nil];
    [[KeenClient sharedClient] setReadKey:nil];
    [[KeenClient sharedClient] setWriteKey:nil];
    [[KeenClient sharedClient] setProjectID:nil];

    _asyncTimeInterval = 100;
}

- (void)tearDown {
    // Tear-down code here.
    NSLog(@"\n");
    [[KeenClient sharedClient] clearAllEvents];
    [[KeenClient sharedClient] clearAllQueries];

    [[KeenClient sharedClient] setWriteKey:nil];
    [[KeenClient sharedClient] setReadKey:nil];
    [[KeenClient sharedClient] setCurrentLocation:nil];
    [[KeenClient sharedClient] setGlobalPropertiesBlock:nil];
    [[KeenClient sharedClient] setGlobalPropertiesDictionary:nil];
    // Clear project key last since it makes sharedClient return nil
    [[KeenClient sharedClient] setProjectID:nil];

    // delete all collections and their events.
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[self keenDirectory]]) {
        [fileManager removeItemAtPath:[self keenDirectory] error:&error];
        if (error) {
            XCTFail(@"No error should be thrown when cleaning up: %@", [error localizedDescription]);
        }
    }
    [super tearDown];
}

- (void)testInitWithProjectID{
    KeenClient *client = [[KeenClient alloc] initWithProjectID:@"something" andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    XCTAssertEqualObjects(@"something", client.projectID, @"init with a valid project id should work");
    XCTAssertEqualObjects(kDefaultWriteKey, client.writeKey, @"init with a valid project id should work");
    XCTAssertEqualObjects(kDefaultReadKey, client.readKey, @"init with a valid project id should work");

    KeenClient *client2 = [[KeenClient alloc] initWithProjectID:@"another" andWriteKey:@"wk2" andReadKey:@"rk2"];
    XCTAssertEqualObjects(@"another", client2.projectID, @"init with a valid project id should work");
    XCTAssertEqualObjects(@"wk2", client2.writeKey, @"init with a valid project id should work");
    XCTAssertEqualObjects(@"rk2", client2.readKey, @"init with a valid project id should work");
    XCTAssertTrue(client != client2, @"Another init should return a separate instance");

    client = [[KeenClient alloc] initWithProjectID:nil andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    XCTAssertNil(client, @"init with a nil project ID should return nil");
}

- (void)testInstanceClient {
    KeenClient *client = [[KeenClient alloc] init];
    XCTAssertNil(client.projectID, @"a client's project id should be nil at first");
    XCTAssertNil(client.writeKey, @"a client's write key should be nil at first");
    XCTAssertNil(client.readKey, @"a client's read key should be nil at first");

    KeenClient *client2 = [[KeenClient alloc] init];
    XCTAssertTrue(client != client2, @"Another init should return a separate instance");
}

- (void)testSharedClientWithProjectID{
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    XCTAssertEqual(kDefaultProjectID, client.projectID, @"sharedClientWithProjectID with a non-nil project id should work.");
    XCTAssertEqualObjects(kDefaultWriteKey, client.writeKey, @"init with a valid project id should work");
    XCTAssertEqualObjects(kDefaultReadKey, client.readKey, @"init with a valid project id should work");

    KeenClient *client2 = [KeenClient sharedClientWithProjectID:@"other" andWriteKey:@"wk2" andReadKey:@"rk2"];
    XCTAssertEqualObjects(client, client2, @"sharedClient should return the same instance");
    XCTAssertEqualObjects(@"wk2", client2.writeKey, @"sharedClient with a valid project id should work");
    XCTAssertEqualObjects(@"rk2", client2.readKey, @"sharedClient with a valid project id should work");

    client = [KeenClient sharedClientWithProjectID:nil andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    XCTAssertNil(client, @"sharedClient with an invalid project id should return nil");
}

- (void)testSharedClient {
    KeenClient *client = [KeenClient sharedClient];
    XCTAssertNil(client.projectID, @"a client's project id should be nil at first");
    XCTAssertNil(client.writeKey, @"a client's write key should be nil at first");
    XCTAssertNil(client.readKey, @"a client's read key should be nil at first");

    KeenClient *client2 = [KeenClient sharedClient];
    XCTAssertEqualObjects(client, client2, @"sharedClient should return the same instance");
}

- (void)testAddEvent {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    KeenClient *clientI = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];

    // nil dict should should do nothing
    NSError *error = nil;
    XCTAssertFalse([client addEvent:nil toEventCollection:@"foo" error:&error], @"addEvent should fail");
    XCTAssertNotNil(error, @"nil dict should return NO");
    error = nil;

    XCTAssertFalse([clientI addEvent:nil toEventCollection:@"foo" error:&error], @"addEvent should fail");
    XCTAssertNotNil(error, @"nil dict should return NO");
    error = nil;

    // nil collection should do nothing
    XCTAssertFalse([client addEvent:[NSDictionary dictionary] toEventCollection:nil error:&error], @"addEvent should fail");
    XCTAssertNotNil(error, @"nil collection should return NO");
    error = nil;

    XCTAssertFalse([clientI addEvent:[NSDictionary dictionary] toEventCollection:nil error:&error], @"addEvent should fail");
    XCTAssertNotNil(error, @"nil collection should return NO");
    error = nil;

    // basic dict should work
    NSArray *keys = [NSArray arrayWithObjects:@"a", @"b", @"c", nil];
    NSArray *values = [NSArray arrayWithObjects:@"apple", @"bapple", [NSNull null], nil];
    NSDictionary *event = [NSDictionary dictionaryWithObjects:values forKeys:keys];
    XCTAssertTrue([client addEvent:event toEventCollection:@"foo" error:&error], @"addEvent should succeed");
    XCTAssertNil(error, @"no error should be returned");
    XCTAssertTrue([clientI addEvent:event toEventCollection:@"foo" error:&error], @"addEvent should succeed");
    XCTAssertNil(error, @"an okay event should return YES");
    error = nil;

    // dict with NSDate should work
    event = @{@"a": @"apple", @"b": @"bapple", @"a_date": [NSDate date]};
    XCTAssertTrue([client addEvent:event toEventCollection:@"foo" error:&error], @"addEvent should succeed");
    XCTAssertNil(error, @"no error should be returned");
    XCTAssertTrue([clientI addEvent:event toEventCollection:@"foo" error:&error], @"addEvent should succeed");
    XCTAssertNil(error, @"an event with a date should return YES");
    error = nil;

    // dict with non-serializable value should do nothing
    NSError *badValue = [[NSError alloc] init];
    event = @{@"a": @"apple", @"b": @"bapple", @"bad_key": badValue};
    XCTAssertFalse([client addEvent:event toEventCollection:@"foo" error:&error], @"addEvent should fail");
    XCTAssertNotNil(error, @"an event that can't be serialized should return NO");
    XCTAssertNotNil([[error userInfo] objectForKey:NSUnderlyingErrorKey], @"and event that can't be serialized should return the underlaying error");
    error = nil;

    XCTAssertFalse([clientI addEvent:event toEventCollection:@"foo" error:&error], @"addEvent should fail");
    XCTAssertNotNil(error, @"an event that can't be serialized should return NO");
    XCTAssertNotNil([[error userInfo] objectForKey:NSUnderlyingErrorKey], @"and event that can't be serialized should return the underlaying error");
    error = nil;

    // dict with root keen prop should do nothing
    badValue = [[NSError alloc] init];
    event = @{@"a": @"apple", @"keen": @"bapple"};
    XCTAssertFalse([client addEvent:event toEventCollection:@"foo" error:&error], @"addEvent should fail");
    XCTAssertNotNil(error, @"");
    error = nil;

    XCTAssertFalse([clientI addEvent:event toEventCollection:@"foo" error:&error], @"addEvent should fail");
    XCTAssertNotNil(error, @"");
    error = nil;

    // dict with non-root keen prop should work
    error = nil;
    event = @{@"nested": @{@"keen": @"whatever"}};
    XCTAssertTrue([client addEvent:event toEventCollection:@"foo" error:nil], @"addEvent should succeed");
    XCTAssertNil(error, @"no error should be returned");
    XCTAssertTrue([clientI addEvent:event toEventCollection:@"foo" error:nil], @"addEvent should succeed");
    XCTAssertNil(error, @"an okay event should return YES");
}

- (void)testAddEventNoWriteKey {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:nil andReadKey:nil];
    KeenClient *clientI = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:nil andReadKey:nil];

    NSArray *keys = [NSArray arrayWithObjects:@"a", @"b", @"c", nil];
    NSArray *values = [NSArray arrayWithObjects:@"apple", @"bapple", [NSNull null], nil];
    NSDictionary *event = [NSDictionary dictionaryWithObjects:values forKeys:keys];
    XCTAssertThrows([client addEvent:event toEventCollection:@"foo" error:nil], @"should throw an exception");
    XCTAssertThrows([clientI addEvent:event toEventCollection:@"foo" error:nil], @"should throw an exception");
}

- (void)testEventWithTimestamp {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    KeenClient *clientI = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];

    NSDate *date = [NSDate date];
    KeenProperties *keenProperties = [[KeenProperties alloc] init];
    keenProperties.timestamp = date;
    [client addEvent:@{@"a": @"b"} withKeenProperties:keenProperties toEventCollection:@"foo" error:nil];
    [clientI addEvent:@{@"a": @"b"} withKeenProperties:keenProperties toEventCollection:@"foo" error:nil];

    NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:@"foo"];
    // Grab the first event we get back
    NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
    NSError *error = nil;
    NSDictionary *deserializedDict = [NSJSONSerialization JSONObjectWithData:eventData
                                                                options:0
                                                                  error:&error];

    NSString *deserializedDate = deserializedDict[@"keen"][@"timestamp"];
    NSString *originalDate = [KIOUtil convertDate:date];
    XCTAssertEqualObjects(originalDate, deserializedDate, @"If a timestamp is specified it should be used.");
    originalDate = [KIOUtil convertDate:date];
    XCTAssertEqualObjects(originalDate, deserializedDate, @"If a timestamp is specified it should be used.");
}

- (void)testEventWithLocation {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    KeenClient *clientI = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];

    KeenProperties *keenProperties = [[KeenProperties alloc] init];
    CLLocation *location = [[CLLocation alloc] initWithLatitude:37.73 longitude:-122.47];
    keenProperties.location = location;
    [client addEvent:@{@"a": @"b"} withKeenProperties:keenProperties toEventCollection:@"foo" error:nil];
    [clientI addEvent:@{@"a": @"b"} withKeenProperties:keenProperties toEventCollection:@"foo" error:nil];

    NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:@"foo"];
    // Grab the first event we get back
    NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
    NSError *error = nil;
    NSDictionary *deserializedDict = [NSJSONSerialization JSONObjectWithData:eventData
                                                                     options:0
                                                                       error:&error];

    NSDictionary *deserializedLocation = deserializedDict[@"keen"][@"location"];
    NSArray *deserializedCoords = deserializedLocation[@"coordinates"];
    XCTAssertEqualObjects(@-122.47, deserializedCoords[0], @"Longitude was incorrect.");
    XCTAssertEqualObjects(@37.73, deserializedCoords[1], @"Latitude was incorrect.");
}

- (void)testEventWithDictionary {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    KeenClient *clientI = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];

    NSString* json = @"{\"test_str_array\":[\"val1\",\"val2\",\"val3\"]}";
    NSDictionary* eventDictionary = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];

    [client addEvent:eventDictionary toEventCollection:@"foo" error:nil];
    [clientI addEvent:eventDictionary toEventCollection:@"foo" error:nil];
    NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:@"foo"];
    // Grab the first event we get back
    NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
    NSError *error = nil;
    NSDictionary *deserializedDict = [NSJSONSerialization JSONObjectWithData:eventData
                                                                     options:0
                                                                       error:&error];

    XCTAssertEqualObjects(@"val1", deserializedDict[@"test_str_array"][0], @"array was incorrect");
    XCTAssertEqualObjects(@"val2", deserializedDict[@"test_str_array"][1], @"array was incorrect");
    XCTAssertEqualObjects(@"val3", deserializedDict[@"test_str_array"][2], @"array was incorrect");
}

- (void)testGeoLocation {
    // set up a client with a location
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    KeenClient *clientI = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];

    CLLocation *location = [[CLLocation alloc] initWithLatitude:37.73 longitude:-122.47];
    client.currentLocation = location;
    clientI.currentLocation = location;
    // add an event
    [client addEvent:@{@"a": @"b"} toEventCollection:@"foo" error:nil];
    [clientI addEvent:@{@"a": @"b"} toEventCollection:@"foo" error:nil];
    // now get the stored event
    NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:@"foo"];
    // Grab the first event we get back
    NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
    NSError *error = nil;
    NSDictionary *deserializedDict = [NSJSONSerialization JSONObjectWithData:eventData
                                                                     options:0
                                                                       error:&error];

    NSDictionary *deserializedLocation = deserializedDict[@"keen"][@"location"];
    NSArray *deserializedCoords = deserializedLocation[@"coordinates"];
    XCTAssertEqualObjects(@-122.47, deserializedCoords[0], @"Longitude was incorrect.");
    XCTAssertEqualObjects(@37.73, deserializedCoords[1], @"Latitude was incorrect.");
}

- (void)testGeoLocationDisabled {
    // now try the same thing but disable geo location
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    KeenClient *clientI = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];

    [KeenClient disableGeoLocation];
    // add an event
    [client addEvent:@{@"a": @"b"} toEventCollection:@"bar" error:nil];
    [clientI addEvent:@{@"a": @"b"} toEventCollection:@"bar" error:nil];
    // now get the stored event

    // Grab the first event we get back
    NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:@"bar"];
    // Grab the first event we get back
    NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
    NSError *error = nil;
    NSDictionary *deserializedDict = [NSJSONSerialization JSONObjectWithData:eventData
                                                                     options:0
                                                                       error:&error];

    NSDictionary *deserializedLocation = deserializedDict[@"keen"][@"location"];
    XCTAssertNil(deserializedLocation, @"No location should have been saved.");
}

- (void)testGeoLocationRequestDisabled {
  // now try the same thing but disable geo location
  KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
  KeenClient *clientI = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];

  [KeenClient disableGeoLocationDefaultRequest];
  // add an event
  [client addEvent:@{@"a": @"b"} toEventCollection:@"bar" error:nil];
  [clientI addEvent:@{@"a": @"b"} toEventCollection:@"bar" error:nil];
  // now get the stored event

  // Grab the first event we get back
  NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:@"bar"];
  // Grab the first event we get back
  NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
  NSError *error = nil;
  NSDictionary *deserializedDict = [NSJSONSerialization JSONObjectWithData:eventData
                                                                   options:0
                                                                     error:&error];

  NSDictionary *deserializedLocation = deserializedDict[@"keen"][@"location"];
  XCTAssertNil(deserializedLocation, @"No location should have been saved.");

  // To properly test this, you want to make sure that this triggers a real location authentication request,
  // to make sure that it returns a location.
}

- (void)testEventWithNonDictionaryKeen {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    KeenClient *clientI = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];

    NSDictionary *theEvent = @{@"keen": @"abc"};
    NSError *error = nil;
    [client addEvent:theEvent toEventCollection:@"foo" error:&error];
    [clientI addEvent:theEvent toEventCollection:@"foo" error:&error];
    XCTAssertNotNil(error, @"an event with a non-dict value for 'keen' should error");
}

- (void)testBasicAddon {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    KeenClient *clientI = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];

    NSDictionary *theEvent = @{
                               @"keen":@{
                                       @"addons" : @[
                                               @{
                                                   @"name" : @"addon:name",
                                                   @"input" : @{@"param_name" : @"property_that_contains_param"},
                                                   @"output" : @"property.to.store.output"
                                                   }
                                               ]
                                       },
                               @"a": @"b"
                               };

    // add the event
    NSError *error = nil;
    [client addEvent:theEvent toEventCollection:@"foo" error:&error];
    [clientI addEvent:theEvent toEventCollection:@"foo" error:&error];
    XCTAssertNil(error, @"event should add");

    // Grab the first event we get back
    NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:@"foo"];
    // Grab the first event we get back
    NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
    NSDictionary *deserializedDict = [NSJSONSerialization JSONObjectWithData:eventData
                                                                     options:0
                                                                       error:&error];

    NSDictionary *deserializedAddon = deserializedDict[@"keen"][@"addons"][0];
    XCTAssertEqualObjects(@"addon:name", deserializedAddon[@"name"], @"Addon name should be right");
}

# pragma mark - test mock request methods

- (NSDictionary *)buildResultWithSuccess:(BOOL)success
                            andErrorCode:(NSString *)errorCode
                          andDescription:(NSString *)description {
    NSDictionary *result = [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithBool:success]
                                                              forKey:@"success"];
    if (!success) {
        NSDictionary *error = [NSDictionary dictionaryWithObjectsAndKeys:errorCode, @"name",
                               description, @"description", nil];
        [result setValue:error forKey:@"error"];
    }
    return result;
}

- (NSDictionary *)buildResponseJsonWithSuccess:(BOOL)success
                                 AndErrorCode:(NSString *)errorCode
                               AndDescription:(NSString *)description {
    NSDictionary *result = [self buildResultWithSuccess:success
                                           andErrorCode:errorCode
                                         andDescription:description];
    NSArray *array = [NSArray arrayWithObject:result];
    return [NSDictionary dictionaryWithObject:array forKey:@"foo"];
}

- (id)createClientWithRequestValidator:(BOOL (^)(id obj))validator {
    return [self createClientWithResponseData:nil
                                andStatusCode:HTTPCode200OK
                          andNetworkConnected:@YES
                          andRequestValidator:validator];
}

- (id)createClientWithResponseData:(id)data
                     andStatusCode:(NSInteger)code {
    return [self createClientWithResponseData:data
                                andStatusCode:code
                          andNetworkConnected:@YES];
}

- (id)createClientWithResponseData:(id)data
                     andStatusCode:(NSInteger)code
               andNetworkConnected:(NSNumber*)isNetworkConnected {
    return [self createClientWithResponseData:data
                                andStatusCode:code
                          andNetworkConnected:isNetworkConnected
                          andRequestValidator:nil];
}

- (id)mockUrlSessionWithResponse:(NSHTTPURLResponse*)response
                 andResponseData:(NSData*)responseData
             andRequestValidator:(BOOL (^)(id requestObject))requestValidator {
    // Mock the NSURLSession to be used for the request
    id urlSessionMock = [OCMockObject partialMockForObject:[[NSURLSession alloc] init]];

    // Set up fake response data and request validation
    if (nil != requestValidator) {
        // Set up validation of the request
        [[urlSessionMock expect] dataTaskWithRequest:[OCMArg checkWithBlock:requestValidator]
                                   completionHandler:[OCMArg invokeBlockWithArgs:responseData, response, [NSNull null], nil]];
    } else {
        // We won't check that the request contained anything specific
        [[urlSessionMock stub] dataTaskWithRequest:[OCMArg any]
                                 completionHandler:[OCMArg invokeBlockWithArgs:responseData, response, [NSNull null], nil]];

    }

    return urlSessionMock;
}

- (id)createClientWithResponseData:(id)data
                     andStatusCode:(NSInteger)code
               andNetworkConnected:(NSNumber*)isNetworkConnected
               andRequestValidator:(BOOL (^)(id obj))requestValidator {

    // serialize the faked out response data
    if (!data) {
        data = [self buildResponseJsonWithSuccess:YES AndErrorCode:nil AndDescription:nil];
    }
    data = [KIOUtil handleInvalidJSONInObject:data];
    NSData *serializedData = [NSJSONSerialization dataWithJSONObject:data
                                                             options:0
                                                               error:nil];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@""]
                                                              statusCode:code
                                                             HTTPVersion:nil
                                                            headerFields:nil];

    // Get mock NSURLSession
    id mockSession = [self mockUrlSessionWithResponse:response
                                      andResponseData:serializedData
                                  andRequestValidator:requestValidator];

    // Create/get store
    KIODBStore* store = KIODBStore.sharedInstance;

    // Create network
    KIONetwork* network = [[KIONetwork alloc] initWithURLSession:mockSession
                                                        andStore:store];

    // Create uploader
    KIOUploader* uploader = [[KIOUploader alloc] initWithNetwork:network
                                                        andStore:store];
    // Mock the KIOUploader to be used for the upload
    id mockUploader = [OCMockObject partialMockForObject:uploader];

    // Mock network status on the KIOUploader object
    [[[mockUploader stub] andReturnValue:isNetworkConnected] isNetworkConnected];

    KeenClient* client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID
                                                   andWriteKey:kDefaultWriteKey
                                                    andReadKey:kDefaultReadKey
                                                    andNetwork:network
                                                      andStore:store
                                                   andUploader:mockUploader];

    client.isRunningTests = YES;

    return client;
}

- (void)addSimpleEventAndUploadWithMock:(id)mock andFinishedBlock:(void (^)())finishedBlock {
    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];

    // and "upload" it
    [mock uploadWithFinishedBlock:finishedBlock];
}

# pragma mark - test upload

-(void)testUploadWithNoEvents {
    XCTestExpectation* uploadFinishedBlockCalled = [self expectationWithDescription:@"Upload should finish."];
    
    id mock = [self createClientWithResponseData:nil andStatusCode:HTTPCode200OK];

    [mock uploadWithFinishedBlock:^{
        [uploadFinishedBlockCalled fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        XCTAssertEqual([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]],
                       0,
                       @"Upload method should return with message Request data is empty.");
    }];
}

- (void)testUploadSuccess {
    id mock = [self createClientWithResponseData:nil andStatusCode:HTTPCode2XXSuccess];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 0, @"There should be no files after a successful upload.");
    }];
}

- (void)testUploadSuccessInstanceClient {
    id mock = [self createClientWithResponseData:nil andStatusCode:HTTPCode2XXSuccess];

    // make sure the event was deleted from the store
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 0, @"There should be no files after a successful upload.");
    }];
}

- (void)testUploadFailedServerDown {
    id mock = [self createClientWithResponseData:nil andStatusCode:HTTPCode500InternalServerError];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file wasn't deleted from the store
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"There should be one file after a failed upload.");
    }];
}

- (void)testUploadFailedServerDownInstanceClient {
    id mock = [self createClientWithResponseData:nil andStatusCode:HTTPCode500InternalServerError];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file wasn't deleted from the store
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"There should be one file after a failed upload.");
    }];
}

- (void)testUploadFailedServerDownNonJsonResponse {
    id mock = [self createClientWithResponseData:@{} andStatusCode:HTTPCode500InternalServerError];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file wasn't deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"There should be one file after a failed upload.");
    }];
}

- (void)testUploadFailedServerDownNonJsonResponseInstanceClient {
    id mock = [self createClientWithResponseData:@{} andStatusCode:HTTPCode500InternalServerError];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file wasn't deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"There should be one file after a failed upload.");
    }];
}


- (void)testDeleteAfterMaxAttempts {
    id mock = [self createClientWithResponseData:nil andStatusCode:HTTPCode500InternalServerError];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    // and "upload" it
    [mock uploadWithFinishedBlock:^{
        // make sure the file wasn't deleted from the store
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"There should be one file after an unsuccessful attempts.");

        // add another event
        [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
        [mock uploadWithFinishedBlock:^{
            // make sure both files weren't deleted from the store
            XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 2, @"There should be two files after 2 unsuccessful attempts.");

            [mock uploadWithFinishedBlock:^{
                // make sure the first file was deleted from the store, but the second one remains
                XCTAssertTrue([[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:[mock projectID]] allKeys].count == 1, @"There should be one file after 3 unsuccessful attempts.");

                [mock uploadWithFinishedBlock:^{
                    [responseArrived fulfill];
                }];
            }];
        }];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure both files were deleted from the store
        XCTAssertTrue([[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:[mock projectID]] allKeys].count == 0, @"There should be no files after 3 unsuccessfull attempts.");
    }];
}

- (void)testIncrementEvenOnNoResponse {
    // mock an empty response from the server
    id mock = [self createClientWithResponseData:@{} andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    // and "upload" it
    [mock uploadWithFinishedBlock:^{
        // make sure the file wasn't deleted from the store
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"There should be one event after an unsuccessful attempt.");

        // add another event
        [mock uploadWithFinishedBlock:^{
            // make sure both files weren't deleted from the store
            XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"There should be one event after 2 unsuccessful attempts.");

            [mock uploadWithFinishedBlock:^{
                [responseArrived fulfill];
            }];
        }];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the event was incremented
        XCTAssertTrue([[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:[mock projectID]] allKeys].count == 0, @"There should be no events with less than 3 unsuccessful attempts.");
        XCTAssertTrue([[KIODBStore.sharedInstance getEventsWithMaxAttempts:4 andProjectID:[mock projectID]] allKeys].count == 1, @"There should be one event with less than 4 unsuccessful attempts.");
    }];
}

- (void)testUploadFailedBadRequest {
    id mock = [self createClientWithResponseData:[self buildResponseJsonWithSuccess:NO
                                                                       AndErrorCode:@"InvalidCollectionNameError"
                                                                     AndDescription:@"anything"]
                                   andStatusCode:HTTPCode200OK];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file was deleted locally
        // make sure the event was deleted from the store
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:nil] == 0,  @"An invalid event should be deleted after an upload attempt.");
    }];
}

- (void)testUploadFailedBadRequestInstanceClient {
    id mock = [self createClientWithResponseData:[self buildResponseJsonWithSuccess:NO
                                                                       AndErrorCode:@"InvalidCollectionNameError"
                                                                     AndDescription:@"anything"]
                                   andStatusCode:HTTPCode200OK];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file was deleted locally
        // make sure the event was deleted from the store
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:nil] == 0,  @"An invalid event should be deleted after an upload attempt.");
    }];
}

- (void)testUploadFailedBadRequestUnknownError {
    id mock = [self createClientWithResponseData:@{} andStatusCode:HTTPCode400BadRequest];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file wasn't deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"An upload that results in an unexpected error should not delete the event.");
    }];
}

- (void)testUploadFailedBadRequestUnknownErrorInstanceClient {
    id mock = [self createClientWithResponseData:@{} andStatusCode:HTTPCode400BadRequest];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file wasn't deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"An upload that results in an unexpected error should not delete the event.");
    }];
}

- (void)testUploadFailedRedirectionStatus {
    id mock = [self createClientWithResponseData:@{} andStatusCode:HTTPCode300MultipleChoices];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file wasn't deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"An upload that results in an unexpected error should not delete the event.");
    }];
}

- (void)testUploadFailedRedirectionStatusInstanceClient {
    id mock = [self createClientWithResponseData:@{} andStatusCode:HTTPCode300MultipleChoices];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file wasn't deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1, @"An upload that results in an unexpected error should not delete the event.");
    }];
}

- (void)testUploadSkippedNoNetwork {
    XCTestExpectation* uploadFinishedBlockCalled = [self expectationWithDescription:@"Upload finished block should be called."];

    id mock = [self createClientWithResponseData:nil andStatusCode:HTTPCode200OK andNetworkConnected:@NO];

    [self addSimpleEventAndUploadWithMock:mock andFinishedBlock:^{
        [uploadFinishedBlockCalled fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file wasn't deleted locally
        XCTAssertEqual([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]],
                       1,
                       @"An upload with no network should not delete the event.");
    }];
}

- (void)testUploadMultipleEventsSameCollectionSuccess {
    NSDictionary *result1 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result2 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result = [NSDictionary dictionaryWithObject:[NSArray arrayWithObjects:result1, result2, nil]
                                                       forKey:@"foo"];
    id mock = [self createClientWithResponseData:result andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple2" forKey:@"a"] toEventCollection:@"foo" error:nil];

    // and "upload" it
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [mock uploadWithFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the events were deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:nil] == 0,  @"There should be no files after a successful upload.");
    }];
}

- (void)testUploadMultipleEventsSameCollectionSuccessInstanceClient {
    NSDictionary *result1 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result2 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result = [NSDictionary dictionaryWithObject:[NSArray arrayWithObjects:result1, result2, nil]
                                                       forKey:@"foo"];
    id mock = [self createClientWithResponseData:result andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple2" forKey:@"a"] toEventCollection:@"foo" error:nil];

    // and "upload" it
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [mock uploadWithFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the events were deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:nil] == 0,  @"There should be no files after a successful upload.");
    }];
}

- (void)testUploadMultipleEventsDifferentCollectionSuccess {
    NSDictionary *result1 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result2 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSArray arrayWithObject:result1], @"foo",
                            [NSArray arrayWithObject:result2], @"bar", nil];
    id mock = [self createClientWithResponseData:result andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"bapple" forKey:@"b"] toEventCollection:@"bar" error:nil];

    // and "upload" it
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [mock uploadWithFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the files were deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:nil] == 0,  @"There should be no events after a successful upload.");
    }];
}

- (void)testUploadMultipleEventsDifferentCollectionSuccessInstanceClient {
    NSDictionary *result1 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result2 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSArray arrayWithObject:result1], @"foo",
                            [NSArray arrayWithObject:result2], @"bar", nil];
    id mock = [self createClientWithResponseData:result andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"bapple" forKey:@"b"] toEventCollection:@"bar" error:nil];

    // and "upload" it
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [mock uploadWithFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the files were deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:nil] == 0,  @"There should be no events after a successful upload.");
    }];
}

- (void)testUploadMultipleEventsSameCollectionOneFails {
    NSDictionary *result1 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result2 = [self buildResultWithSuccess:NO
                                            andErrorCode:@"InvalidCollectionNameError"
                                          andDescription:@"something"];
    NSDictionary *result = [NSDictionary dictionaryWithObject:[NSArray arrayWithObjects:result1, result2, nil]
                                                       forKey:@"foo"];
    id mock = [self createClientWithResponseData:result andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple2" forKey:@"a"] toEventCollection:@"foo" error:nil];

    // and "upload" it
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [mock uploadWithFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file were deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 0,  @"There should be no events after a successful upload.");
    }];
}

- (void)testUploadMultipleEventsSameCollectionOneFailsInstanceClient {
    NSDictionary *result1 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result2 = [self buildResultWithSuccess:NO
                                            andErrorCode:@"InvalidCollectionNameError"
                                          andDescription:@"something"];
    NSDictionary *result = [NSDictionary dictionaryWithObject:[NSArray arrayWithObjects:result1, result2, nil]
                                                       forKey:@"foo"];
    id mock = [self createClientWithResponseData:result andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple2" forKey:@"a"] toEventCollection:@"foo" error:nil];

    // and "upload" it
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [mock uploadWithFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the file were deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 0,  @"There should be no events after a successful upload.");
    }];
}

- (void)testUploadMultipleEventsDifferentCollectionsOneFails {
    NSDictionary *result1 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result2 = [self buildResultWithSuccess:NO
                                            andErrorCode:@"InvalidCollectionNameError"
                                          andDescription:@"something"];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSArray arrayWithObject:result1], @"foo",
                            [NSArray arrayWithObject:result2], @"bar", nil];
    id mock = [self createClientWithResponseData:result andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"bapple" forKey:@"b"] toEventCollection:@"bar" error:nil];

    // and "upload" it
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [mock uploadWithFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the files were deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 0,  @"There should be no events after a successful upload.");
    }];
}

- (void)testUploadMultipleEventsDifferentCollectionsOneFailsInstanceClient {
    NSDictionary *result1 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result2 = [self buildResultWithSuccess:NO
                                            andErrorCode:@"InvalidCollectionNameError"
                                          andDescription:@"something"];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSArray arrayWithObject:result1], @"foo",
                            [NSArray arrayWithObject:result2], @"bar", nil];
    id mock = [self createClientWithResponseData:result andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"bapple" forKey:@"b"] toEventCollection:@"bar" error:nil];

    // and "upload" it
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [mock uploadWithFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the files were deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 0,  @"There should be no events after a successful upload.");
    }];
}

- (void)testUploadMultipleEventsDifferentCollectionsOneFailsForServerReason {
    NSDictionary *result1 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result2 = [self buildResultWithSuccess:NO
                                            andErrorCode:@"barf"
                                          andDescription:@"something"];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSArray arrayWithObject:result1], @"foo",
                            [NSArray arrayWithObject:result2], @"bar", nil];
    id mock = [self createClientWithResponseData:result andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"bapple" forKey:@"b"] toEventCollection:@"bar" error:nil];

    // and "upload" it
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [mock uploadWithFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the files were deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1,  @"There should be 1 events after a partial upload.");
    }];
}

- (void)testUploadMultipleEventsDifferentCollectionsOneFailsForServerReasonInstanceClient {
    NSDictionary *result1 = [self buildResultWithSuccess:YES
                                            andErrorCode:nil
                                          andDescription:nil];
    NSDictionary *result2 = [self buildResultWithSuccess:NO
                                            andErrorCode:@"barf"
                                          andDescription:@"something"];
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSArray arrayWithObject:result1], @"foo",
                            [NSArray arrayWithObject:result2], @"bar", nil];
    id mock = [self createClientWithResponseData:result andStatusCode:HTTPCode200OK];

    // add an event
    [mock addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];
    [mock addEvent:[NSDictionary dictionaryWithObject:@"bapple" forKey:@"b"] toEventCollection:@"bar" error:nil];

    // and "upload" it
    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [mock uploadWithFinishedBlock:^{
        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        // make sure the files were deleted locally
        XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:[mock projectID]] == 1,  @"There should be 1 event after a partial upload.");
    }];
}

- (void)testTooManyEventsCached {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;
    NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:@"bar", @"foo", nil];
    // create 5 events
    for (int i=0; i<5; i++) {
        [client addEvent:event toEventCollection:@"something" error:nil];
    }
    XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:client.projectID] == 5,  @"There should be exactly five events.");
    // now do one more, should age out 1 old ones
    [client addEvent:event toEventCollection:@"something" error:nil];
    // so now there should be 4 left (5 - 2 + 1)
    XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:client.projectID] == 4, @"There should be exactly five events.");
}

- (void)testTooManyEventsCachedInstanceClient {
    KeenClient *client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;
    NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:@"bar", @"foo", nil];
    // create 5 events
    for (int i=0; i<5; i++) {
        [client addEvent:event toEventCollection:@"something" error:nil];
    }
    XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:client.projectID] == 5,  @"There should be exactly five events.");
    // now do one more, should age out 1 old ones
    [client addEvent:event toEventCollection:@"something" error:nil];
    // so now there should be 4 left (5 - 2 + 1)
    XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:client.projectID] == 4, @"There should be exactly five events.");
}

- (void)testGlobalPropertiesDictionary {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    NSDictionary * (^RunTest)(NSDictionary*, NSUInteger) = ^(NSDictionary *globalProperties,
                                                             NSUInteger expectedNumProperties) {
        NSString *eventCollectionName = [NSString stringWithFormat:@"foo%f", [[NSDate date] timeIntervalSince1970]];
        client.globalPropertiesDictionary = globalProperties;
        NSDictionary *event = @{@"foo": @"bar"};
        [client addEvent:event toEventCollection:eventCollectionName error:nil];
        NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:eventCollectionName];
        // Grab the first event we get back
        NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
        NSError *error = nil;
        NSDictionary *storedEvent = [NSJSONSerialization JSONObjectWithData:eventData
                                                                  options:0
                                                                    error:&error];

        XCTAssertEqualObjects(event[@"foo"], storedEvent[@"foo"]);
        XCTAssertEqual([storedEvent count], expectedNumProperties + 1, @"Stored event: %@", storedEvent);
        return storedEvent;
    };

    // a nil dictionary should be okay
    RunTest(nil, 1);

    // an empty dictionary should be okay
    RunTest(@{}, 1);

    // a dictionary that returns some non-conflicting property names should be okay
    NSDictionary *storedEvent = RunTest(@{@"default_name": @"default_value"}, 2);
    XCTAssertEqualObjects(@"default_value", storedEvent[@"default_name"], @"");

    // a dictionary that returns a conflicting property name should not overwrite the property on
    // the event
    RunTest(@{@"foo": @"some_new_value"}, 1);

    // a dictionary that contains an addon should be okay
    NSDictionary *theEvent = @{
                               @"keen":@{
                                       @"addons" : @[
                                               @{
                                                   @"name" : @"addon:name",
                                                   @"input" : @{@"param_name" : @"property_that_contains_param"},
                                                   @"output" : @"property.to.store.output"
                                                   }
                                               ]
                                       },
                               @"a": @"b"
                               };
    storedEvent = RunTest(theEvent, 2);
    NSDictionary *deserializedAddon = storedEvent[@"keen"][@"addons"][0];
    XCTAssertEqualObjects(@"addon:name", deserializedAddon[@"name"], @"Addon name should be right");
}

- (void)testGlobalPropertiesDictionaryInstanceClient {
    KeenClient *client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    NSDictionary * (^RunTest)(NSDictionary*, NSUInteger) = ^(NSDictionary *globalProperties,
                                                             NSUInteger expectedNumProperties) {
        NSString *eventCollectionName = [NSString stringWithFormat:@"foo%f", [[NSDate date] timeIntervalSince1970]];
        client.globalPropertiesDictionary = globalProperties;
        NSDictionary *event = @{@"foo": @"bar"};
        [client addEvent:event toEventCollection:eventCollectionName error:nil];
        NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:eventCollectionName];
        // Grab the first event we get back
        NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
        NSError *error = nil;
        NSDictionary *storedEvent = [NSJSONSerialization JSONObjectWithData:eventData
                                                                    options:0
                                                                      error:&error];

        XCTAssertEqualObjects(event[@"foo"], storedEvent[@"foo"], @"");
        XCTAssertTrue([storedEvent count] == expectedNumProperties + 1, @"");
        return storedEvent;
    };

    // a nil dictionary should be okay
    RunTest(nil, 1);

    // an empty dictionary should be okay
    RunTest(@{}, 1);

    // a dictionary that returns some non-conflicting property names should be okay
    NSDictionary *storedEvent = RunTest(@{@"default_name": @"default_value"}, 2);
    XCTAssertEqualObjects(@"default_value", storedEvent[@"default_name"], @"");

    // a dictionary that returns a conflicting property name should not overwrite the property on
    // the event
    RunTest(@{@"foo": @"some_new_value"}, 1);

    // a dictionary that contains an addon should be okay
    NSDictionary *theEvent = @{
                               @"keen":@{
                                       @"addons" : @[
                                               @{
                                                   @"name" : @"addon:name",
                                                   @"input" : @{@"param_name" : @"property_that_contains_param"},
                                                   @"output" : @"property.to.store.output"
                                                   }
                                               ]
                                       },
                               @"a": @"b"
                               };
    storedEvent = RunTest(theEvent, 2);
    NSDictionary *deserializedAddon = storedEvent[@"keen"][@"addons"][0];
    XCTAssertEqualObjects(@"addon:name", deserializedAddon[@"name"], @"Addon name should be right");
}

- (void)testGlobalPropertiesBlock {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    NSDictionary * (^RunTest)(KeenGlobalPropertiesBlock, NSUInteger) = ^(KeenGlobalPropertiesBlock block,
                                                                         NSUInteger expectedNumProperties) {
        NSString *eventCollectionName = [NSString stringWithFormat:@"foo%f", [[NSDate date] timeIntervalSince1970]];
        client.globalPropertiesBlock = block;
        NSDictionary *event = @{@"foo": @"bar"};
        [client addEvent:event toEventCollection:eventCollectionName error:nil];

        NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:eventCollectionName];
        // Grab the first event we get back
        NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
        NSError *error = nil;
        NSDictionary *storedEvent = [NSJSONSerialization JSONObjectWithData:eventData
                                                                    options:0
                                                                      error:&error];

        XCTAssertEqualObjects(event[@"foo"], storedEvent[@"foo"], @"");
        XCTAssertTrue([storedEvent count] == expectedNumProperties + 1, @"");
        return storedEvent;
    };

    // a block that returns nil should be okay
    RunTest(nil, 1);

    // a block that returns an empty dictionary should be okay
    RunTest(^NSDictionary *(NSString *eventCollection) {
        return [NSDictionary dictionary];
    }, 1);

    // a block that returns some non-conflicting property names should be okay
    NSDictionary *storedEvent = RunTest(^NSDictionary *(NSString *eventCollection) {
        return @{@"default_name": @"default_value"};
    }, 2);
    XCTAssertEqualObjects(@"default_value", storedEvent[@"default_name"], @"");

    // a block that returns a conflicting property name should not overwrite the property on the event
    RunTest(^NSDictionary *(NSString *eventCollection) {
        return @{@"foo": @"some new value"};
    }, 1);

    // a dictionary that contains an addon should be okay
    NSDictionary *theEvent = @{
                               @"keen":@{
                                       @"addons" : @[
                                               @{
                                                   @"name" : @"addon:name",
                                                   @"input" : @{@"param_name" : @"property_that_contains_param"},
                                                   @"output" : @"property.to.store.output"
                                                   }
                                               ]
                                       },
                               @"a": @"b"
                               };
    storedEvent = RunTest(^NSDictionary *(NSString *eventCollection) {
        return theEvent;
    }, 2);
    NSDictionary *deserializedAddon = storedEvent[@"keen"][@"addons"][0];
    XCTAssertEqualObjects(@"addon:name", deserializedAddon[@"name"], @"Addon name should be right");
}

- (void)testGlobalPropertiesBlockInstanceClient {
    KeenClient *client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    NSDictionary * (^RunTest)(KeenGlobalPropertiesBlock, NSUInteger) = ^(KeenGlobalPropertiesBlock block,
                                                                         NSUInteger expectedNumProperties) {
        NSString *eventCollectionName = [NSString stringWithFormat:@"foo%f", [[NSDate date] timeIntervalSince1970]];
        client.globalPropertiesBlock = block;
        NSDictionary *event = @{@"foo": @"bar"};
        [client addEvent:event toEventCollection:eventCollectionName error:nil];

        NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:eventCollectionName];
        // Grab the first event we get back
        NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
        NSError *error = nil;
        NSDictionary *storedEvent = [NSJSONSerialization JSONObjectWithData:eventData
                                                                    options:0
                                                                      error:&error];

        XCTAssertEqualObjects(event[@"foo"], storedEvent[@"foo"], @"");
        XCTAssertTrue([storedEvent count] == expectedNumProperties + 1, @"");
        return storedEvent;
    };

    // a block that returns nil should be okay
    RunTest(nil, 1);

    // a block that returns an empty dictionary should be okay
    RunTest(^NSDictionary *(NSString *eventCollection) {
        return [NSDictionary dictionary];
    }, 1);

    // a block that returns some non-conflicting property names should be okay
    NSDictionary *storedEvent = RunTest(^NSDictionary *(NSString *eventCollection) {
        return @{@"default_name": @"default_value"};
    }, 2);
    XCTAssertEqualObjects(@"default_value", storedEvent[@"default_name"], @"");

    // a block that returns a conflicting property name should not overwrite the property on the event
    RunTest(^NSDictionary *(NSString *eventCollection) {
        return @{@"foo": @"some new value"};
    }, 1);

    // a dictionary that contains an addon should be okay
    NSDictionary *theEvent = @{
                               @"keen":@{
                                       @"addons" : @[
                                               @{
                                                   @"name" : @"addon:name",
                                                   @"input" : @{@"param_name" : @"property_that_contains_param"},
                                                   @"output" : @"property.to.store.output"
                                                   }
                                               ]
                                       },
                               @"a": @"b"
                               };
    storedEvent = RunTest(^NSDictionary *(NSString *eventCollection) {
        return theEvent;
    }, 2);
    NSDictionary *deserializedAddon = storedEvent[@"keen"][@"addons"][0];
    XCTAssertEqualObjects(@"addon:name", deserializedAddon[@"name"], @"Addon name should be right");
}

- (void)testGlobalPropertiesTogether {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    // properties from the block should take precedence over properties from the dictionary
    // but properties from the event itself should take precedence over all
    client.globalPropertiesDictionary = @{@"default_property": @5, @"foo": @"some_new_value"};
    client.globalPropertiesBlock = ^NSDictionary *(NSString *eventCollection) {
        return @{ @"default_property": @6, @"foo": @"some_other_value"};
    };
    [client addEvent:@{@"foo": @"bar"} toEventCollection:@"apples" error:nil];

    NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:@"apples"];
    // Grab the first event we get back
    NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
    NSError *error = nil;
    NSDictionary *storedEvent = [NSJSONSerialization JSONObjectWithData:eventData
                                                                options:0
                                                                  error:&error];

    XCTAssertEqualObjects(@"bar", storedEvent[@"foo"], @"");
    XCTAssertEqualObjects(@6, storedEvent[@"default_property"], @"");
    XCTAssertTrue([storedEvent count] == 3, @"");
}

- (void)testGlobalPropertiesTogetherInstanceClient {
    KeenClient *client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    // properties from the block should take precedence over properties from the dictionary
    // but properties from the event itself should take precedence over all
    client.globalPropertiesDictionary = @{@"default_property": @5, @"foo": @"some_new_value"};
    client.globalPropertiesBlock = ^NSDictionary *(NSString *eventCollection) {
        return @{ @"default_property": @6, @"foo": @"some_other_value"};
    };
    [client addEvent:@{@"foo": @"bar"} toEventCollection:@"apples" error:nil];

    NSDictionary *eventsForCollection = [[KIODBStore.sharedInstance getEventsWithMaxAttempts:3 andProjectID:client.projectID] objectForKey:@"apples"];
    // Grab the first event we get back
    NSData *eventData = [eventsForCollection objectForKey:[[eventsForCollection allKeys] objectAtIndex:0]];
    NSError *error = nil;
    NSDictionary *storedEvent = [NSJSONSerialization JSONObjectWithData:eventData
                                                                options:0
                                                                  error:&error];

    XCTAssertEqualObjects(@"bar", storedEvent[@"foo"], @"");
    XCTAssertEqualObjects(@6, storedEvent[@"default_property"], @"");
    XCTAssertTrue([storedEvent count] == 3, @"");
}

- (void)testInvalidEventCollection {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    NSDictionary *event = @{@"a": @"b"};
    // collection can't start with $
    NSError *error = nil;
    [client addEvent:event toEventCollection:@"$asd" error:&error];
    XCTAssertNotNil(error, @"collection can't start with $");
    error = nil;

    // collection can't be over 256 chars
    NSMutableString *longString = [NSMutableString stringWithCapacity:257];
    for (int i=0; i<257; i++) {
        [longString appendString:@"a"];
    }
    [client addEvent:event toEventCollection:@"$asd" error:&error];
    XCTAssertNotNil(error, @"collection can't be longer than 256 chars");
}

- (void)testInvalidEventCollectionInstanceClient {
    KeenClient *client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    NSDictionary *event = @{@"a": @"b"};
    // collection can't start with $
    NSError *error = nil;
    [client addEvent:event toEventCollection:@"$asd" error:&error];
    XCTAssertNotNil(error, @"collection can't start with $");
    error = nil;

    // collection can't be over 256 chars
    NSMutableString *longString = [NSMutableString stringWithCapacity:257];
    for (int i=0; i<257; i++) {
        [longString appendString:@"a"];
    }
    [client addEvent:event toEventCollection:@"$asd" error:&error];
    XCTAssertNotNil(error, @"collection can't be longer than 256 chars");
}

- (void)testUploadMultipleTimes {
    XCTestExpectation* uploadFinishedBlockCalled1 = [self expectationWithDescription:@"Upload 1 should run to completion."];
    XCTestExpectation* uploadFinishedBlockCalled2 = [self expectationWithDescription:@"Upload 2 should run to completion."];
    XCTestExpectation* uploadFinishedBlockCalled3 = [self expectationWithDescription:@"Upload 3 should run to completion."];
    
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    [client uploadWithFinishedBlock:^{
        [uploadFinishedBlockCalled1 fulfill];
    }];
    [client uploadWithFinishedBlock:^{
        [uploadFinishedBlockCalled2 fulfill];
    }];
    [client uploadWithFinishedBlock:^ {
        [uploadFinishedBlockCalled3 fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:nil];
}

- (void)testUploadMultipleTimesInstanceClient {
    XCTestExpectation* uploadFinishedBlockCalled1 = [self expectationWithDescription:@"Upload 1 should run to completion."];
    XCTestExpectation* uploadFinishedBlockCalled2 = [self expectationWithDescription:@"Upload 2 should run to completion."];
    XCTestExpectation* uploadFinishedBlockCalled3 = [self expectationWithDescription:@"Upload 3 should run to completion."];

    KeenClient *client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    [client uploadWithFinishedBlock:^{
        [uploadFinishedBlockCalled1 fulfill];
    }];
    [client uploadWithFinishedBlock:^{
        [uploadFinishedBlockCalled2 fulfill];
    }];
    [client uploadWithFinishedBlock:^ {
        [uploadFinishedBlockCalled3 fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:nil];
}

- (void)testMigrateFSEvents {

    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    // make sure the directory we want to write the file to exists
    NSString *dirPath = [self eventDirectoryForCollection:@"foo"];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    [manager createDirectoryAtPath:dirPath withIntermediateDirectories:true attributes:nil error:&error];
    XCTAssertNil(error, @"created directory for events");

    // Write out a couple of events that we can import later!
    NSDictionary *event1 = [NSDictionary dictionaryWithObject:@"apple" forKey:@"a"];
    NSDictionary *event2 = [NSDictionary dictionaryWithObject:@"orange" forKey:@"b"];

    NSData *json1 = [NSJSONSerialization dataWithJSONObject:event1 options:0 error:&error];
    NSData *json2 =[NSJSONSerialization dataWithJSONObject:event2 options:0 error:&error];

    NSString *fileName1 = [self pathForEventInCollection:@"foo" WithTimestamp:[NSDate date]];
    NSString *fileName2 = [self pathForEventInCollection:@"foo" WithTimestamp:[NSDate date]];

    [self writeNSData:json1 toFile:fileName1];
    [self writeNSData:json2 toFile:fileName2];

    [KIOFileStore importFileDataWithProjectID:kDefaultProjectID];
    // Now we're gonna add an event and verify the events we just wrote to the fs
    // are added to the database and the files are cleaned up.
    error = nil;
    NSDictionary *event3 = @{@"nested": @{@"keen": @"whatever"}};
    [client addEvent:event3 toEventCollection:@"foo" error:nil];

    XCTAssertEqual(3,
                   [KIODBStore.sharedInstance getTotalEventCountWithProjectID:client.projectID],
                   @"There should be 3 events after an import.");
    XCTAssertFalse([manager fileExistsAtPath:[self keenDirectory] isDirectory:true],
                   @"The Keen directory should be gone.");
}

- (void)testMigrateFSEventsInstanceClient {
    KeenClient *client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    // make sure the directory we want to write the file to exists
    NSString *dirPath = [self eventDirectoryForCollection:@"foo"];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    [manager createDirectoryAtPath:dirPath withIntermediateDirectories:true attributes:nil error:&error];
    XCTAssertNil(error, @"created directory for events");

    // Write out a couple of events that we can import later!
    NSDictionary *event1 = [NSDictionary dictionaryWithObject:@"apple" forKey:@"a"];
    NSDictionary *event2 = [NSDictionary dictionaryWithObject:@"orange" forKey:@"b"];

    NSData *json1 = [NSJSONSerialization dataWithJSONObject:event1 options:0 error:&error];
    NSData *json2 =[NSJSONSerialization dataWithJSONObject:event2 options:0 error:&error];

    NSString *fileName1 = [self pathForEventInCollection:@"foo" WithTimestamp:[NSDate date]];
    NSString *fileName2 = [self pathForEventInCollection:@"foo" WithTimestamp:[NSDate date]];

    [self writeNSData:json1 toFile:fileName1];
    [self writeNSData:json2 toFile:fileName2];

    [KIOFileStore importFileDataWithProjectID:kDefaultProjectID];
    // Now we're gonna add an event and verify the events we just wrote to the fs
    // are added to the database and the files are cleaned up.
    error = nil;
    NSDictionary *event3 = @{@"nested": @{@"keen": @"whatever"}};
    [client addEvent:event3 toEventCollection:@"foo" error:nil];

    XCTAssertTrue([KIODBStore.sharedInstance getTotalEventCountWithProjectID:client.projectID] == 3,  @"There should be 3 events after an import.");
    XCTAssertFalse([manager fileExistsAtPath:[self keenDirectory] isDirectory:true], @"The Keen directory should be gone.");
}

- (void)testSDKVersion {
    KeenClient *client = [KeenClient sharedClientWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    // result from class method should equal the SDK Version constant
    XCTAssertTrue([[KeenClient sdkVersion] isEqual:kKeenSdkVersion],  @"SDK Version from class method equals the SDK Version constant.");
    XCTAssertFalse(![[KeenClient sdkVersion] isEqual:kKeenSdkVersion], @"SDK Version from class method doesn't equal the SDK Version constant.");
}

- (void)testSDKVersionInstanceClient {
    KeenClient *client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID andWriteKey:kDefaultWriteKey andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    // result from class method should equal the SDK Version constant
    XCTAssertTrue([[KeenClient sdkVersion] isEqual:kKeenSdkVersion],  @"SDK Version from class method equals the SDK Version constant.");
    XCTAssertFalse(![[KeenClient sdkVersion] isEqual:kKeenSdkVersion], @"SDK Version from class method doesn't equal the SDK Version constant.");
}

# pragma mark - test query

- (void)testCountQueryFailure {
    id mock = [self createClientWithResponseData:@{} andStatusCode:HTTPCode5XXServerError];

    KIOQuery *query = [[KIOQuery alloc] initWithQuery:@"count" andPropertiesDictionary:@{}];

    [mock runQuery:query completionHandler:^(NSData *queryResponseData, NSURLResponse *response, NSError *error) {
        KCLogInfo(@"error: %@", error);
        KCLogInfo(@"response: %@", response);

        XCTAssertNil(error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*) response;
        XCTAssertEqual([httpResponse statusCode], HTTPCode5XXServerError);

        NSDictionary *responseDictionary = [NSJSONSerialization
                                            JSONObjectWithData:queryResponseData
                                            options:kNilOptions
                                            error:&error];

        KCLogInfo(@"response: %@", responseDictionary);

        NSNumber *result = [responseDictionary objectForKey:@"result"];

        XCTAssertNil(result);
    }];
}

- (void)testCountQuerySuccess {
    id mock = [self createClientWithResponseData:@{@"result": @10} andStatusCode:HTTPCode200OK];

    KIOQuery *query = [[KIOQuery alloc] initWithQuery:@"count" andPropertiesDictionary:@{@"event_collection": @"event_collection"}];

    [mock runQuery:query completionHandler:^(NSData *queryResponseData, NSURLResponse *response, NSError *error) {
        KCLogInfo(@"error: %@", error);
        KCLogInfo(@"response: %@", response);

        XCTAssertNil(error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*) response;
        XCTAssertEqual([httpResponse statusCode], HTTPCode200OK);

        NSDictionary *responseDictionary = [NSJSONSerialization
                                            JSONObjectWithData:queryResponseData
                                            options:kNilOptions
                                            error:&error];

        KCLogInfo(@"response: %@", responseDictionary);

        NSNumber *result = [responseDictionary objectForKey:@"result"];

        XCTAssertEqual(result, [NSNumber numberWithInt:10]);
    }];
}

- (void)testCountQuerySuccessWithGroupByProperty {
    id mock = [self createClientWithResponseData:@{@"result": @[@{ @"result": @10, @"key": @"value" }]} andStatusCode:HTTPCode200OK];

    KIOQuery *query = [[KIOQuery alloc] initWithQuery:@"count" andPropertiesDictionary:@{@"event_collection": @"event_collection",
                                                                                         @"group_by": @"key"}];

    [mock runQuery:query completionHandler:^(NSData *queryResponseData, NSURLResponse *response, NSError *error) {
        KCLogInfo(@"error: %@", error);
        KCLogInfo(@"response: %@", response);

        XCTAssertNil(error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*) response;
        XCTAssertEqual([httpResponse statusCode], HTTPCode200OK);

        NSDictionary *responseDictionary = [NSJSONSerialization
                                            JSONObjectWithData:queryResponseData
                                            options:kNilOptions
                                            error:&error];

        KCLogInfo(@"response: %@", responseDictionary);

        NSNumber *result = [[responseDictionary objectForKey:@"result"][0] objectForKey:@"result"];

        XCTAssertEqual(result, [NSNumber numberWithInt:10]);
    }];
}

- (void)testCountQuerySuccessWithTimeframeAndIntervalProperties {
    id mock = [self createClientWithResponseData:@{@"result": @[@{@"value": @10,
                                                         @"timeframe": @{@"start": @"2015-06-19T00:00:00.000Z",
                                                                         @"end": @"2015-06-20T00:00:00.000Z"} }]} andStatusCode:HTTPCode200OK];

    KIOQuery *query = [[KIOQuery alloc] initWithQuery:@"count" andPropertiesDictionary:@{@"event_collection": @"event_collection",
                                                       @"interval": @"daily",
                                                       @"timeframe": @"last_1_days"}];

    [mock runQuery:query completionHandler:^(NSData *queryResponseData, NSURLResponse *response, NSError *error) {
        KCLogInfo(@"error: %@", error);
        KCLogInfo(@"response: %@", response);

        XCTAssertNil(error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*) response;
        XCTAssertEqual([httpResponse statusCode], HTTPCode200OK);

        NSDictionary *responseDictionary = [NSJSONSerialization
                                            JSONObjectWithData:queryResponseData
                                            options:kNilOptions
                                            error:&error];

        KCLogInfo(@"response: %@", responseDictionary);

        NSNumber *result = [[responseDictionary objectForKey:@"result"][0] objectForKey:@"value"];

        XCTAssertEqual(result, [NSNumber numberWithInt:10]);
    }];
}

- (void)testCountUniqueQueryWithMissingTargetProperty {
    id mock = [self createClientWithResponseData:@{} andStatusCode:HTTPCode400BadRequest];

    KIOQuery *query = [[KIOQuery alloc] initWithQuery:@"count" andPropertiesDictionary:@{@"event_collection": @"event_collection"}];

    [mock runQuery:query completionHandler:^(NSData *queryResponseData, NSURLResponse *response, NSError *error) {
        KCLogInfo(@"error: %@", error);
        KCLogInfo(@"response: %@", response);

        XCTAssertNil(error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*) response;
        XCTAssertEqual([httpResponse statusCode], HTTPCode400BadRequest);

        NSDictionary *responseDictionary = [NSJSONSerialization
                                            JSONObjectWithData:queryResponseData
                                            options:kNilOptions
                                            error:&error];

        KCLogInfo(@"response: %@", responseDictionary);

        NSNumber *result = [responseDictionary objectForKey:@"result"];

        XCTAssertNil(result);
    }];
}

- (void)testCountUniqueQuerySuccess {
    id mock = [self createClientWithResponseData:@{@"result": @10} andStatusCode:HTTPCode200OK];

    KIOQuery *query = [[KIOQuery alloc] initWithQuery:@"count" andPropertiesDictionary:@{@"event_collection": @"event_collection", @"target_property": @"something"}];

    [mock runQuery:query completionHandler:^(NSData *queryResponseData, NSURLResponse *response, NSError *error) {
        KCLogInfo(@"error: %@", error);
        KCLogInfo(@"response: %@", response);

        XCTAssertNil(error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*) response;
        XCTAssertEqual([httpResponse statusCode], HTTPCode200OK);

        NSDictionary *responseDictionary = [NSJSONSerialization
                                            JSONObjectWithData:queryResponseData
                                            options:kNilOptions
                                            error:&error];

        KCLogInfo(@"response: %@", responseDictionary);

        NSNumber *result = [responseDictionary objectForKey:@"result"];

        XCTAssertEqual(result, [NSNumber numberWithInt:10]);
    }];
}

- (void)testMultiAnalysisSuccess {
    id mock = [self createClientWithResponseData:@{@"result": @{@"query1": @10, @"query2": @1}} andStatusCode:HTTPCode200OK];

    KIOQuery *countQuery = [[KIOQuery alloc] initWithQuery:@"count" andPropertiesDictionary:@{@"event_collection": @"event_collection"}];

    KIOQuery *averageQuery = [[KIOQuery alloc] initWithQuery:@"count_unique" andPropertiesDictionary:@{@"event_collection": @"event_collection", @"target_property": @"something"}];

    [mock runMultiAnalysisWithQueries:@[countQuery, averageQuery] completionHandler:^(NSData *queryResponseData, NSURLResponse *response, NSError *error) {
        KCLogInfo(@"error: %@", error);
        KCLogInfo(@"response: %@", response);

        XCTAssertNil(error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*) response;
        XCTAssertEqual([httpResponse statusCode], HTTPCode200OK);

        NSDictionary *responseDictionary = [NSJSONSerialization
                                            JSONObjectWithData:queryResponseData
                                            options:kNilOptions
                                            error:&error];

        KCLogInfo(@"response: %@", responseDictionary);

        NSNumber *result = [[responseDictionary objectForKey:@"result"] objectForKey:@"query1"];

        XCTAssertEqual(result, [NSNumber numberWithInt:10]);
    }];
}

- (void)testFunnelQuerySuccess {
    id mock = [self createClientWithResponseData:@{@"result": @[@10, @5],
                                          @"steps":@[@{@"actor_property": @[@"user.id"],
                                                       @"event_collection": @"user_signed_up"},
                                                     @{@"actor_property": @[@"user.id"],
                                                       @"event_collection": @"user_completed_profile"}]} andStatusCode:HTTPCode200OK];

    KIOQuery *query = [[KIOQuery alloc] initWithQuery:@"funnel" andPropertiesDictionary:@{@"steps": @[@{@"event_collection": @"user_signed_up", @"actor_property": @"user.id"},
                                                                                                      @{@"event_collection": @"user_completed_profile", @"actor_property": @"user.id"}]}];

    [mock runQuery:query completionHandler:^(NSData *queryResponseData, NSURLResponse *response, NSError *error) {
        KCLogInfo(@"error: %@", error);
        KCLogInfo(@"response: %@", response);

        XCTAssertNil(error);

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*) response;
        XCTAssertEqual([httpResponse statusCode], HTTPCode200OK);

        NSDictionary *responseDictionary = [NSJSONSerialization
                                            JSONObjectWithData:queryResponseData
                                            options:kNilOptions
                                            error:&error];

        KCLogInfo(@"response: %@", responseDictionary);

        NSArray *result = [responseDictionary objectForKey:@"result"];
        NSArray *resultArray = @[@10, @5];

        KCLogInfo(@"result: %@", [result class]);
        KCLogInfo(@"resultArray: %@", [resultArray class]);

        XCTAssertEqual([result count], (NSUInteger)2);
        XCTAssertEqualObjects(result, resultArray);
    }];
}

- (void) testSuccessfulQueryAPIResponse {
    KeenClient *client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID
                                                   andWriteKey:kDefaultWriteKey
                                                    andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"url"]
                                                              statusCode:HTTPCode2XXSuccess
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{}];
    NSData *responseData = [@"query failed" dataUsingEncoding:NSUTF8StringEncoding];

    [client.network handleQueryAPIResponse:response
                                   andData:responseData
                                  andQuery:nil
                              andProjectID:kDefaultProjectID];

    // test that there are no entries in the query database
    XCTAssertEqual([KIODBStore.sharedInstance getTotalQueryCountWithProjectID:kDefaultProjectID],
                   (NSUInteger)0,
                   @"There should be no queries after a successful query API call");
}

- (void) testFailedQueryAPIResponse {
    KeenClient *client = [[KeenClient alloc] initWithProjectID:kDefaultProjectID
                                                   andWriteKey:kDefaultWriteKey
                                                    andReadKey:kDefaultReadKey];
    client.isRunningTests = YES;

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"url"]
                                                              statusCode:HTTPCode4XXClientError
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{}];
    NSData *responseData = [@"query failed" dataUsingEncoding:NSUTF8StringEncoding];

    // test that there is 1 entry in the query database after a failed query API call
    KIOQuery *query = [[KIOQuery alloc] initWithQuery:@"count"
                              andPropertiesDictionary:@{@"event_collection": @"collection"}];

    [client.network handleQueryAPIResponse:response
                           andData:responseData
                          andQuery:query
                      andProjectID:kDefaultProjectID];

    NSUInteger numberOfQueries = [KIODBStore.sharedInstance getTotalQueryCountWithProjectID:kDefaultProjectID];

    XCTAssertEqual(numberOfQueries,
                   (NSUInteger)1,
                   @"There should be 1 query in the database after a failed query API call");

    // test that there are 2 entries in the query database after two failed different query API calls
    KIOQuery *query2 = [[KIOQuery alloc] initWithQuery:@"count"
                               andPropertiesDictionary:@{@"event_collection": @"collection2"}];

    [client.network handleQueryAPIResponse:response
                                   andData:responseData
                                  andQuery:query2
                              andProjectID:kDefaultProjectID];

    numberOfQueries = [KIODBStore.sharedInstance getTotalQueryCountWithProjectID:kDefaultProjectID];
    XCTAssertEqual(numberOfQueries,
                   (NSUInteger)2,
                   @"There should be 2 queries in the database after two failed query API calls");

    // test that there is still 2 entries in the query database after the same query fails twice
    [client.network handleQueryAPIResponse:response
                                   andData:responseData
                                  andQuery:query2
                              andProjectID:kDefaultProjectID];

    numberOfQueries = [KIODBStore.sharedInstance getTotalQueryCountWithProjectID:kDefaultProjectID];
    XCTAssertEqual(numberOfQueries,
                   (NSUInteger)2,
                   @"There should still be 2 queries in the database after two of the same failed query API call");
}

- (void)validateSdkVersionHeaderFieldForRequest:(id)requestObject {
    XCTAssertTrue([requestObject isKindOfClass:[NSMutableURLRequest class]]);
    NSMutableURLRequest* request = requestObject;
    NSString* versionInfo = [request valueForHTTPHeaderField:kKeenSdkVersionHeader];
    XCTAssertNotNil(versionInfo, @"Request should have included SDK info header.");
    NSRange platformRange = [versionInfo rangeOfString:@"ios-"];
    XCTAssertEqual(platformRange.location, 0, @"SDK info header should start with the platform.");
    XCTAssertEqual(platformRange.length, 4, @"Unexpected SDK platform info.");
    NSRange versionRange = [versionInfo rangeOfString:kKeenSdkVersion];
    XCTAssertEqual(versionRange.location, 4, @"SDK version should be included in SDK platform info.");
}

- (void)testSdkTrackingHeadersOnUpload {
    // mock an empty response from the server

    KeenClient* client = [self createClientWithRequestValidator:^BOOL(id obj) {
        [self validateSdkVersionHeaderFieldForRequest:obj];
        return @YES;
    }];

    // Get the mock url session. We'll check the request it gets passed by sendEvents for the version header
    id urlSessionMock = client.network.urlSession;

    // add an event
    [client addEvent:[NSDictionary dictionaryWithObject:@"apple" forKey:@"a"] toEventCollection:@"foo" error:nil];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    // and "upload" it
    [client uploadWithFinishedBlock:^{
        // Check for the sdk version header
        [urlSessionMock verify];

        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        XCTAssertNil(error, @"Test should complete within expected interval.");
    }];
}

- (void)testSdkTrackingHeadersOnQuery {
    KeenClient* client = [self createClientWithResponseData:@{@"result": @10}
                                              andStatusCode:HTTPCode200OK
                                        andNetworkConnected:@YES
                                        andRequestValidator:^BOOL(id obj) {
        [self validateSdkVersionHeaderFieldForRequest:obj];
        return @YES;
    }];

    // Get the mock url session. We'll check the request it gets passed by sendEvents for the version header
    id urlSessionMock = client.network.urlSession;

    KIOQuery *query = [[KIOQuery alloc] initWithQuery:@"count" andPropertiesDictionary:@{@"event_collection": @"event_collection"}];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [client runQuery:query completionHandler:^(NSData *queryResponseData, NSURLResponse *response, NSError *error) {
        // Check for the sdk version header
        [urlSessionMock verify];

        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        XCTAssertNil(error, @"Test should complete within expected interval.");
    }];
}

- (void)testSdkTrackingHeadersOnMultiAnalysis {
    KeenClient* client = [self createClientWithResponseData:@{@"result": @{@"query1": @10, @"query2": @1}}
                                              andStatusCode:HTTPCode200OK
                                        andNetworkConnected:@YES
                                        andRequestValidator:^BOOL(id obj) {
        [self validateSdkVersionHeaderFieldForRequest:obj];
        return @YES;
    }];

    // Get the mock url session. We'll check the request it gets passed by sendEvents for the version header
    id urlSessionMock = client.network.urlSession;

    KIOQuery* countQuery = [[KIOQuery alloc] initWithQuery:@"count"
                                   andPropertiesDictionary:@{@"event_collection": @"event_collection"}];

    KIOQuery* averageQuery = [[KIOQuery alloc] initWithQuery:@"count_unique"
                                     andPropertiesDictionary:@{@"event_collection": @"event_collection", @"target_property": @"something"}];

    XCTestExpectation* responseArrived = [self expectationWithDescription:@"response of async request has arrived"];
    [client runMultiAnalysisWithQueries:@[countQuery, averageQuery]
                      completionHandler:^(NSData* queryResponseData, NSURLResponse* response, NSError* error) {
        // Check for the sdk version header
        [urlSessionMock verify];

        [responseArrived fulfill];
    }];

    [self waitForExpectationsWithTimeout:_asyncTimeInterval handler:^(NSError * _Nullable error) {
        XCTAssertNil(error, @"Test should complete within expected interval.");
    }];
}

# pragma mark - test filesystem utility methods

- (NSString *)cacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    return documentsDirectory;
}

- (NSString *)keenDirectory {
    return [[[self cacheDirectory] stringByAppendingPathComponent:@"keen"] stringByAppendingPathComponent:kDefaultProjectID];
}

- (NSString *)eventDirectoryForCollection:(NSString *)collection {
    return [[self keenDirectory] stringByAppendingPathComponent:collection];
}

- (NSArray *)contentsOfDirectoryForCollection:(NSString *)collection {
    NSString *path = [self eventDirectoryForCollection:collection];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *contents = [manager contentsOfDirectoryAtPath:path error:&error];
    if (error) {
        XCTFail(@"Error when listing contents of directory for collection %@: %@",
               collection, [error localizedDescription]);
    }
    return contents;
}

- (NSString *)pathForEventInCollection:(NSString *)collection WithTimestamp:(NSDate *)timestamp {
    // get a file manager.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // determine the root of the filename.
    NSString *name = [NSString stringWithFormat:@"%f", [timestamp timeIntervalSince1970]];
    // get the path to the directory where the file will be written
    NSString *directory = [self eventDirectoryForCollection:collection];
    // start a counter that we'll use to make sure that even if multiple events are written with the same timestamp,
    // we'll be able to handle it.
    uint count = 0;

    // declare a tiny helper block to get the next path based on the counter.
    NSString * (^getNextPath)(uint count) = ^(uint count) {
        return [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%i", name, count]];
    };

    // starting with our root filename.0, see if a file exists.  if it doesn't, great.  but if it does, then go
    // on to filename.1, filename.2, etc.
    NSString *path = getNextPath(count);
    while ([fileManager fileExistsAtPath:path]) {
        count++;
        path = getNextPath(count);
    }

    return path;
}

- (BOOL)writeNSData:(NSData *)data toFile:(NSString *)file {
    // write file atomically so we don't ever have a partial event to worry about.
    BOOL success = [data writeToFile:file atomically:YES];
    if (!success) {
        KCLogError(@"Error when writing event to file: %@", file);
        return NO;
    } else {
        KCLogInfo(@"Successfully wrote event to file: %@", file);
    }
    return YES;
}

@end
