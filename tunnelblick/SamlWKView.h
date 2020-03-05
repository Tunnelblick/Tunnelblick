//
//  SamlWKView.h
//  Tunnelblick
//
//  Created by Elias Sun on 2/22/20.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "defines.h"
@class VPNConnection;

NS_ASSUME_NONNULL_BEGIN

@interface SamlWKView : NSWindowController {
    VPNConnection* vpnConnection;
    id vpnConnectionSender;
    BOOL trustedServer;
    NSString* samlURL;
}
@property (assign) IBOutlet NSView *baseView;
@property (assign) IBOutlet WKWebView *webView;

- (void)setURL:(NSString *)requestURLString;

TBPROPERTY(VPNConnection*, vpnConnection, setVpnConnection)
TBPROPERTY(id, vpnConnectionSender, setVpnConnectionSender)
TBPROPERTY(BOOL, trustedServer, setTrustedServer)
TBPROPERTY(NSString*, samlURL, setSamlURL)

@end

NS_ASSUME_NONNULL_END
