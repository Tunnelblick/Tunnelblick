//
//  RouteManager.h
//  Tunnelblick
//
//  Created by Angelo Laub on 9/28/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

@interface RouteManager : NSObject {

}

+ (BOOL)addRoute:(NSString *)host net:(NSString *)net;
+ (BOOL)delRoute:(NSString *)host net:(NSString *)net;
@end
