//
//  TBChallengeTextView.h
//  Tunnelblick
//
//  Created by Roman Belyakovsky on 06/06/2019.
//

#import <Cocoa/Cocoa.h>

@interface TBChallengeTextView : NSTextField
@property (nonatomic) NSAlert *alert;
@property (nonatomic, retain) NSButton *secretButton;
@end

@interface TBChallengeSecureTextView : NSSecureTextField
@property (nonatomic) NSAlert *alert;
@property (nonatomic, retain) NSButton *secretButton;
@end
