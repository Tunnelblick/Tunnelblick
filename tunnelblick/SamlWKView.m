//
//  SamlWKView.m
//  Tunnelblick
//
//  Created by Elias Sun on 2/22/20.
//
#import <Foundation/NSURLAuthenticationChallenge.h>
#import "SamlWKView.h"
#import "VPNConnection.h"
#import "MyPrefsWindowController.h"

@interface SamlWKView ()<WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>

@end

@implementation SamlWKView

TBSYNTHESIZE_OBJECT_SET(VPNConnection *, vpnConnection, setVpnConnection)
TBSYNTHESIZE_OBJECT_SET(id, vpnConnectionSender, setVpnConnectionSender)
TBSYNTHESIZE_NONOBJECT(BOOL, trustedServer,  setTrustedServer)
TBSYNTHESIZE_NONOBJECT(NSString*, samlURL,  setSamlURL)

- (void)windowDidLoad {
    [super windowDidLoad];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [self setup];
    [self.window makeKeyAndOrderFront:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)windowShouldClose:(id)sender {
    [[self window] orderOut:self];
    return NO;
}

- (void)setup {
    [self setupWebView];
    [self setURL: samlURL];
}

- (void)setupWebView {
    self.webView = [[WKWebView alloc] initWithFrame: CGRectZero
                                      configuration: [self setJS]];
    self.webView.UIDelegate = self;
    self.webView.navigationDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;
    [self.baseView addSubview: self.webView];
    [self setupWKWebViewConstain: self.webView];
    
}

- (void)setURL:(NSString *)requestURLString {
    NSURL *url = [[NSURL alloc] initWithString: requestURLString];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL: url
                                                  cachePolicy: NSURLRequestUseProtocolCachePolicy
                                              timeoutInterval: 5];
    [self.webView loadRequest: request];
}

- (WKWebViewConfiguration *)setJS {
    NSString *jsString = @"";
    WKUserScript *userScript = [[WKUserScript alloc] initWithSource: jsString
                                                      injectionTime: WKUserScriptInjectionTimeAtDocumentEnd
                                                   forMainFrameOnly:YES];
    WKUserContentController *wkUController = [WKUserContentController new];
    [wkUController addUserScript: userScript];
    [wkUController addScriptMessageHandler:self name:@"callbackHandler"];
    
    WKWebViewConfiguration *wkWebConfig = [WKWebViewConfiguration new];
    wkWebConfig.userContentController = wkUController;
    
    return wkWebConfig;
}

- (void)triggerJS:(NSString *)jsString webView:(WKWebView *)webView {
    [webView evaluateJavaScript:jsString
              completionHandler:^(NSString *result, NSError *error){
                  if (error != nil) {
                      NSLog(@"Fail to get saml username and pwd: %@", error.localizedDescription);
                      return;
                  }
                  NSLog(@"OK to get saml username and pwd: %@", result);
              }];
}

- (void)setupWKWebViewConstain: (WKWebView *)webView {
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSLayoutConstraint *topConstraint =
    [NSLayoutConstraint constraintWithItem: webView
                                 attribute: NSLayoutAttributeTop
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: self.baseView
                                 attribute: NSLayoutAttributeTop
                                multiplier: 1.0
                                  constant: 0];
    
    NSLayoutConstraint *bottomConstraint =
    [NSLayoutConstraint constraintWithItem: webView
                                 attribute: NSLayoutAttributeBottom
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: self.baseView
                                 attribute: NSLayoutAttributeBottom
                                multiplier: 1.0
                                  constant: 0];
    
    NSLayoutConstraint *leftConstraint =
    [NSLayoutConstraint constraintWithItem: webView
                                 attribute: NSLayoutAttributeLeft
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: self.baseView
                                 attribute: NSLayoutAttributeLeft
                                multiplier: 1.0
                                  constant: 0];
    
    NSLayoutConstraint *rightConstraint =
    [NSLayoutConstraint constraintWithItem: webView
                                 attribute: NSLayoutAttributeRight
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: self.baseView
                                 attribute: NSLayoutAttributeRight
                                multiplier: 1.0
                                  constant: 0];
    
    NSArray *constraints = @[
                             topConstraint,
                             bottomConstraint,
                             leftConstraint,
                             rightConstraint
                             ];
    
    [self.baseView addConstraints:constraints];
}


#pragma mark - UIWebViewDelegate Methods
- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
    
    if (navigationAction.targetFrame != nil &&
        !navigationAction.targetFrame.mainFrame) {
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL: [[NSURL alloc] initWithString: navigationAction.request.URL.absoluteString]];
        [webView loadRequest: request];
        
        return nil;
    }
    return nil;
}

#pragma mark - WKNavigationDelegate Methods
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSLog(@"decidePolicyForNavigationAction：%@", navigationAction.request.URL.absoluteString);
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"didFinishNavigation");
    [NSApp activateIgnoringOtherApps:YES];
    NSURL* url = [NSURL URLWithString:samlURL];
    NSString* samlFlaskURL = [NSString stringWithFormat:@"https://%@/flask", url.host];
    if ([[webView.URL absoluteString] isEqualToString:samlFlaskURL]) {
        [self.window orderOut:self];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self getSamlTokens: webView];
        });
    }
}

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
    if (trustedServer) {
        trustedServer = FALSE;
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    }
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    
}

- (NSString*)getCurrentTime
{
    //Get current MacOS time
    NSDate *today = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    NSString *currentTime = [dateFormatter stringFromDate:today];
    return currentTime;
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"Fail to connect the server %@", error);
    if (trustedServer) {
        [[self window] orderOut:self];
        if (error && error.code == NSURLErrorNotConnectedToInternet) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Network Offline"];
            NSString *info = [[NSString alloc] initWithFormat:@"%@ The Internet connection appears to be offline.", self.getCurrentTime];
            [alert setInformativeText:info];
            [alert addButtonWithTitle:@"Ok"];
            [alert runModal];
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Connection Failure"];
            NSString *info = [[NSString alloc] initWithFormat:@"%@ %@", self.getCurrentTime, error];
            [alert setInformativeText:info];
            [alert addButtonWithTitle:@"Ok"];
            [alert runModal];
        }
        return;
    }
    BOOL isTrusted = false;
    if (error && error.code == NSURLErrorServerCertificateUntrusted) {
        NSArray *cert = [error.userInfo objectForKey:@"NSErrorPeerCertificateChainKey"];
        if (cert) {
            NSString *certStr = [NSString stringWithFormat:@"%@", cert[0]];
            if ([certStr containsString:@"s: carmelosystems"]
                && [certStr containsString:@"i: carmelosystems"]) {
                isTrusted = true;
            }
        }
        if (!isTrusted) {
            NSAlert *alert = [[NSAlert alloc] init];
            NSArray *cert = [error.userInfo objectForKey:@"NSErrorPeerCertificateChainKey"];
            NSString *urlStr = [error.userInfo objectForKey:@"NSErrorFailingURLStringKey"];
            NSURL* url = [NSURL URLWithString:urlStr];
            [alert setMessageText:@"Untrusted Server Certificate"];
            NSString *info = [[NSString alloc] initWithFormat:@""\
                              "The certificate for this server is invalid. "\
                              "You might be connecting to a server that is "\
                              "pretending to be %@  which could put your confidential "\
                              "information at risk. Would you like to connect to the "\
                              "server anyway?", url.host];
            [alert setInformativeText:info];
            [alert addButtonWithTitle:@"Cancel"];
            [alert addButtonWithTitle:@"Continue"];
            NSModalResponse buttonValue = [alert runModal];
            if ( NSAlertSecondButtonReturn == buttonValue ) {
                isTrusted = true;
                NSLog(@"The website %@ is trusted", url.host);

            } else {
                [[self window] orderOut:self];
                NSLog(@"The website %@ is untrusted", url.host);
            }
            [info release];
        }
        
        trustedServer = isTrusted;
        
        if (isTrusted) {
            NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:samlURL]];
            [webView loadRequest:urlRequest];
        }
        
    }
    else if (error && error.code == NSURLErrorNotConnectedToInternet) {
        [[self window] orderOut:self];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Network Offline"];
        NSString *info = [[NSString alloc] initWithFormat:@"%@ The Internet connection appears to be offline.", self.getCurrentTime];
        [alert setInformativeText:info];
        [alert addButtonWithTitle:@"Ok"];
        [alert runModal];
    }
    else {
        [[self window] orderOut:self];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Connection Failure"];
        NSString *info = [[NSString alloc] initWithFormat:@"%@ %@", self.getCurrentTime, error];
        [alert setInformativeText:info];
        [alert addButtonWithTitle:@"Ok"];
        [alert runModal];
    }
    
}

//#pragma mark - WKScriptMessageHandler Methods
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if([message.name  isEqual: @"callbackHandler"]) {
        NSLog(@"%@", [NSString stringWithFormat:@"%@", message.body]);
        NSString* emailid = message.body[@"emailid"];
        NSString* keystr = message.body[@"key"];
        NSLog(@"emailid: %@", emailid);
        NSLog(@"key: %@", keystr);
        if ( !emailid || !keystr) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Network Error"];
            NSString *info = [[NSString alloc] initWithFormat:@"%@ SAML authentication is failed due to a network problem. Please disconnect and reconnect VPN again.", self.getCurrentTime];
            [alert setInformativeText:info];
            [alert addButtonWithTitle:@"Ok"];
            [alert runModal];
            return;
        }
        if (vpnConnection && ![vpnConnection isConnected]) {
            vpnConnection.samlUserName = emailid;
            vpnConnection.samlPassword = keystr;
            NSLog(@"VPN state=%@", [vpnConnection state]);
            if (vpnConnectionSender) {
                if ([[vpnConnection state] isEqualToString:@"EXITING"]) {
                    [vpnConnection connect: vpnConnectionSender userKnows: YES];
                    NSLog(@"Connnecting VPN from the main UI or the tray menu with SAML");
                }
            } else {
                if ([[vpnConnection state] isEqualToString:@"PASSWORD_WAIT"]) {
                    NSString* retryLineStr = @">PASSWORD:Need 'Auth' username/password";
                    NSString* retryParameterstr = @"Need 'Auth' username/password";
                    [vpnConnection provideCredentials: retryParameterstr line: retryLineStr];
                    NSLog(@"Reconnnecting VPN with SAML");
                } else if ([[vpnConnection state] isEqualToString:@"EXITING"]){
                    [vpnConnection connect: self userKnows: YES];
                    NSLog(@"Connecting VPN from the tray menu with SAML");
                } else {
                    NSLog(@"Error: It doesn't support to start a VPN connection from VPN state=%@ with SAML", [vpnConnection state]);
                }
            }
        }
    }
}

-(void)getSamlTokens:(WKWebView*)webView
{
    NSString *tokenStr =@"\n"\
    "var tonameCallNativeFunc = function(emailid, keystring) {\n"\
    "    var messgeToPost = {'emailid':emailid, 'key':keystring};\n"\
    "    window.webkit.messageHandlers.callbackHandler.postMessage(messgeToPost);\n"\
    "};\n"\
    "var table1 = document.getElementById('SAMLTable');\n"\
    "var emailid = '';\n"\
    "var flag = 0;\n"\
    "for(i=0;i<table1.rows.length;i++)\n"\
    "{\n"\
    "    row_name = table1.rows[i].cells[0].innerText.trim();\n"\
    "    row_val = table1.rows[i].cells[1].innerText.trim();\n"\
    "    if(row_name=='Email' || row_name=='email')\n"\
    "    {\n"
    "        flag = 1;\n"\
    "        emailid = row_val;\n"\
    "    }\n"\
    "}\n"\
    "if (flag != 0)\n"\
    "{\n"\
    "    var row1 =document.getElementById('TokenField');\n"\
    "    var Cells = row1.getElementsByTagName(\"td\");"\
    "    var keystring = Cells[1].innerText.trim();"\
    "    tonameCallNativeFunc(emailid, keystring)"\
    "}\n";
    
    [self triggerJS:tokenStr webView:webView];
}

@end
