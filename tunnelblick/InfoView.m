/*
 * Copyright 2011 Jonathan Bullard
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  Tunnelblick is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *  or see http://www.gnu.org/licenses/.
 */


#import "InfoView.h"
#import "helper.h"
#import "TBUserDefaults.h"


extern TBUserDefaults * gTbDefaults;


@implementation InfoView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

-(void) dealloc
{
    [logo release];
    [scrollTimer release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect {
    // Drawing code here.
	(void) dirtyRect;
}

- (void) substitute: (NSString *) newString
                 in: (NSMutableAttributedString *) attrString {
    NSRange range = [[attrString string] rangeOfString: @"@@STRING@@"];
    [attrString replaceCharactersInRange: range withString: newString];
}

- (void) replaceString: (NSString *)                  oldString
            withString: (NSString *)                  newString
             urlString: (NSString *)                  urlString
                    in: (NSMutableAttributedString *) target {
    
    // Create the new string with a link in it
    NSMutableAttributedString* newAttrString = [[[NSMutableAttributedString alloc] initWithString: newString] autorelease];
    
    NSURL * aURL = [NSURL URLWithString: urlString];
    if (  ! aURL  ) {
        NSLog(@"Invalid URL '%@'", urlString);
        return;
    }
    
    NSRange range = NSMakeRange(0, [newAttrString length]);
    
    [newAttrString beginEditing];
    
    [newAttrString addAttribute: NSLinkAttributeName value: [aURL absoluteString] range: range];
    
    // make the text appear in blue
    [newAttrString addAttribute: NSForegroundColorAttributeName value: [NSColor blueColor] range: range];
    
    // next make the text appear with an underline
    [newAttrString addAttribute: NSUnderlineStyleAttributeName value: [NSNumber numberWithInt: NSSingleUnderlineStyle] range: range];
    
    [newAttrString endEditing];
    
    // Now substitute that string for the old string
    range = [[target string] rangeOfString: oldString];
    if (  range.length == 0  ) {
        NSLog(@"Unable to find '%@' in '%@'", oldString, [target string]);
        return;
    }
    
    [target deleteCharactersInRange: range];
    [target insertAttributedString: newAttrString atIndex: range.location];
}

-(void) awakeFromNib
{
    NSString * logoPath = [[NSBundle mainBundle] pathForResource: @"tunnelblick" ofType: @"icns"];
    if (  logoPath  ) {
        [logo release];
        logo = [[NSImage alloc] initWithContentsOfFile: logoPath];
        [infoLogoIV setImage: logo];
    }
    
    // If Resources has an "about.html", use that as the base for the license description
    // Using [[NSBundle mainBundle] pathForResource: @"about" ofType: @"html"] doesn't always work -- it is apparently cached by OS X.
    // If it is used immediately after the installer creates and populates Resources/Deploy, nil is returned instead of the path
    // Using [[NSBundle mainBundle] resourcePath: ALSO seems to not work (don't know why, maybe the same reason)
    // The workaround is to create the path "by hand" and use that.
    NSString * aboutPath    = [[[NSBundle mainBundle] bundlePath] stringByAppendingString: @"/Contents/Resources/about.html"];
	NSString * htmlFromFile = [NSString stringWithContentsOfFile: aboutPath encoding:NSASCIIStringEncoding error:NULL];
    if (  htmlFromFile  ) {
        NSString * basedOnHtml  = NSLocalizedString(@"<br>Based on Tunnel" @"blick, free software available at<br><a href=\"http://code.google.com/p/tunnelblick\">http://code.google.com/p/tunnelblick</a>", @"Window text");
        NSString * html         = [NSString stringWithFormat:@"%@%@%@%@",
                                   @"<html><body><center><div style=\"font-family: Verdana, Arial, Helvetica, sans-serif; font-size: 10px\">",
                                   htmlFromFile,
                                   basedOnHtml,
                                   @"</div></center><body></html>"];
        NSData * data = [html dataUsingEncoding:NSASCIIStringEncoding];
        NSAttributedString * description = [[[NSAttributedString alloc] initWithHTML:data documentAttributes:NULL] autorelease];
        [[infoDescriptionTV textStorage] setAttributedString: description];
    } else {
        
        // Create HTML trailer and convert to an mutable attributed string
        NSString * trailingHTML = @"<br /><center><a href= \"http://www.tunnelblick.net\">http://www.tunnelblick.net</a><br /></center>";
        NSData * htmlData = [[[NSData alloc] initWithBytes: [trailingHTML UTF8String] length: [trailingHTML length]] autorelease];
        NSMutableAttributedString * descriptionString = [[[NSMutableAttributedString alloc] initWithHTML: htmlData documentAttributes: nil] autorelease];

        NSAttributedString * contents = [[[NSMutableAttributedString alloc] initWithString:
                                         NSLocalizedString(@"Tunnelblick is free software: you can redistribute it and/or modify it under the terms of the %1$@ as published by the %2$@.", @"Window text")] autorelease];
        
        // Insert the localized contents before the trailer
        [descriptionString insertAttributedString: contents atIndex: 0];
        
        // Replace the placeholders in the localized content with links
        [self replaceString: @"%1$@"
                 withString: @"GNU General Public License version 2"
                  urlString: @"https://www.gnu.org/licenses/gpl-2.0.html"
                         in: descriptionString];
        
        [self replaceString: @"%2$@"
                 withString: @"Free Software Foundation"
                  urlString: @"https://fsf.org"
                         in: descriptionString];
        
        [infoDescriptionTV setEditable: NO];
        [infoDescriptionSV setHasHorizontalScroller: NO];
        [infoDescriptionSV setHasVerticalScroller:   NO];
        
        // If Tunnelblick has been globally replaced with XXX, prefix the license description with "XXX is based on Tunnelblick. "
        // And change XXX back to Tunnelblick
        if (  ! [gTbDefaults boolForKey: @"doNotUnrebrandLicenseDescription"]  ) {
            if (   ! [@"Tunnelblick" isEqualToString: @"Tunnel" @"blick"]  ) {
                NSString * prefix = [NSString stringWithFormat:
                                     NSLocalizedString(@"Tunnelblick is based on %@. ", @"Window text"),
                                     @"Tunnel" @"blick"];
                
                NSMutableString * s = [descriptionString mutableString];
                [s replaceOccurrencesOfString: @"Tunnelblick" withString: @"Tunnel" @"blick" options: 0 range: NSMakeRange(0, [s length])];
                [descriptionString replaceCharactersInRange: NSMakeRange(0, 0) withString: prefix];
            }
        }
        
        [infoDescriptionTV replaceCharactersInRange:NSMakeRange( 0, [[infoDescriptionTV string] length] )
                                            withRTF:[descriptionString RTFFromRange:
                                                     NSMakeRange( 0, [descriptionString length] )
                                                                 documentAttributes:nil]];
    }

	// Credits: create HTML, convert to an NSMutableAttributedString, substitute localized strings, and display
	//
    // Credits data comes from the following arrays:
    
    NSArray * mainCredits = [NSArray arrayWithObjects:
                             [NSArray arrayWithObjects: @"Angleo Laub",      NSLocalizedString(@"Founder, original program and documentation", @"Credit description"), nil],
                             [NSArray arrayWithObjects: @"James Yonan",      @"OpenVPN", nil],
                             [NSArray arrayWithObjects: @"Dirk Theisen",     NSLocalizedString(@"Contributed much to the early code", @"Credit description"), nil],
                             [NSArray arrayWithObjects: @"Jonathan Bullard", NSLocalizedString(@"Program and documentation enhancements and maintenance after version 3.0b10", @"Credit description"), nil],
                             
                             [NSArray arrayWithObjects:
                              NSLocalizedString(@"LEAD_TRANSLATORS",      @"Names of lead translators"),
                              NSLocalizedString(@"LANGUAGE_LOCALIZATION", @"[name of your language] localization"),
                              nil],
                             nil];
    
    NSArray * pgmCredits = [NSArray arrayWithObjects:
                            [NSArray arrayWithObjects: @"Dave Batton",                  @"DBPrefsWindowController", nil],
                            [NSArray arrayWithObjects: @"Michael Schloh von Bennewit",  NSLocalizedString(@"64-bit enabling and testing",           @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Stefan Bethke",                NSLocalizedString(@"Localization code tweaks",              @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Michael Bianco",               NSLocalizedString(@"Button images",                         @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Waldemar Brodkorb",            NSLocalizedString(@"Contributed to early code",             @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Math Campbell",                NSLocalizedString(@"Button images",                         @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Raal Goff",                    NSLocalizedString(@"Animation and icon sets code",          @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Benji Greig",                  NSLocalizedString(@"Tunnelblick icon",                      @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mohammad A. Haque",            NSLocalizedString(@"Xcode help and OpenSSL integration",    @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Uli Kusterer",                 NSLocalizedString(@"UKKQueue and UKLoginItemRegistry",      @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Xaver Loppenstedt",            NSLocalizedString(@"PKCS#11 support",                       @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Andy Matuschak",               @"Sparkle", nil],
                            [NSArray arrayWithObjects: @"Dustin Mierau",                @"Netsocket", nil],
                            [NSArray arrayWithObjects: @"Harold Molina-Bulla",          NSLocalizedString(@"OpenVPN 2.3 and 64-bit integration",    @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mattias Nissler",              @"Tuntap", nil],
                            [NSArray arrayWithObjects: @"Markus F. X. J. Oberhumer",    @"LZO", nil],
                            [NSArray arrayWithObjects: @"Jens Ohlig",                   NSLocalizedString(@"Contributed to early code",             @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Diego Rivera",                 NSLocalizedString(@"Up and Down scripts",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Michael Williams",             NSLocalizedString(@"Multiple configuration folders",        @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Nick Williams",                NSLocalizedString(@"Up and Down scripts",                   @"Credit description"), nil],
                            nil];
    
    NSArray * locCredits = [NSArray arrayWithObjects:
                            [NSArray arrayWithObjects: @"Stefan Bethke",                 NSLocalizedString(@"German localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Olivier Borowski",              NSLocalizedString(@"French localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Sergio Andrés Castro Cárdenas", NSLocalizedString(@"Spanish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Zhanchong Chen",                NSLocalizedString(@"Chinese (simplified) localization",    @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mats Cronqvist",                NSLocalizedString(@"Swedish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Grzegorz Danecki",              NSLocalizedString(@"Polish localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Aleix Dorca",                   NSLocalizedString(@"Catalan localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Andreas Finke",                 NSLocalizedString(@"German localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Simone Gianni",                 NSLocalizedString(@"Italian localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Nail Gilmanov",                 NSLocalizedString(@"Russian localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Ricardo Guijt",                 NSLocalizedString(@"Dutch localization",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Pierpaolo Gulla",               NSLocalizedString(@"Italian localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Oliver Hill",                   NSLocalizedString(@"French localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"'Dr Hok'",                      NSLocalizedString(@"German localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Jesse Hulkko",                  NSLocalizedString(@"Finnish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Jarmo Isotalo",                 NSLocalizedString(@"Finnish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Dewey Kang",                    NSLocalizedString(@"Korean localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Kalle Kärkkäinen",              NSLocalizedString(@"Finnish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Yoshihisa Kawamoto",            NSLocalizedString(@"Japanese localization",                @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Kyoungmin Kim",                 NSLocalizedString(@"Korean localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Daniel Kvist",                  NSLocalizedString(@"Swedish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Aming Lau",                     NSLocalizedString(@"Chinese (traditional) localization",   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Jon Luberth",                   NSLocalizedString(@"Norwegian localization",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Łukasz M",                      NSLocalizedString(@"Polish localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Tim Malmström",                 NSLocalizedString(@"Swedish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Denis Volpato Martins",         NSLocalizedString(@"Portuguese localization",              @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Johan Nilsson",                 NSLocalizedString(@"Swedish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Feetu Nyrhine",                 NSLocalizedString(@"Finnish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Peter K. O'Connor",             NSLocalizedString(@"Chinese (simplified) localization",    @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Petra Penttila",                NSLocalizedString(@"Finnish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Matteo Pillon",                 NSLocalizedString(@"Italian localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Victor Ptichkin",               NSLocalizedString(@"Russian localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Diego Rivera",                  NSLocalizedString(@"Spanish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Nicolas Rodriguez (Tupaca)",    NSLocalizedString(@"Spanish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Markus Schneider",              NSLocalizedString(@"German localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Janek Schwarz",                 NSLocalizedString(@"German localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Emma Segev",                    NSLocalizedString(@"Dutch localization",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Jeremy Sherman",                NSLocalizedString(@"French localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Tjalling Soldaat",              NSLocalizedString(@"Dutch localization",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Petr Šrajer",                   NSLocalizedString(@"Czech localization",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Wojtek Sromek",                 NSLocalizedString(@"Polish localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Marcell Szabo",                 NSLocalizedString(@"Hungarian localization",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Erwann Thoraval",               NSLocalizedString(@"French localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mikko Toivola",                 NSLocalizedString(@"Finnish localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Eugene Trufanov",               NSLocalizedString(@"Russian localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Dennis Ukhanov",                NSLocalizedString(@"Russian localization",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"François Varas",                NSLocalizedString(@"French localization",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Magdelena Zajac",               NSLocalizedString(@"Polish localization",                  @"Credit description"), nil],
                            
// NEW TRANSLATORS FOR 3.3, must be verified and then inserted above in alphabetical order:

                            [NSArray arrayWithObjects: @"Massimo",                       NSLocalizedString(@"Italian localization",                 @"Credit description"), nil],
							
                            [NSArray arrayWithObjects: @"Evandro Hora",                  NSLocalizedString(@"Portuguese localization",              @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Michel Jansen",                 NSLocalizedString(@"Portuguese localization",              @"Credit description"), nil],
                            
                            [NSArray arrayWithObjects: @"Matej Bačík",                   NSLocalizedString(@"Slovak localization",                  @"Credit description"), nil],
							
                            [NSArray arrayWithObjects: @"Aleksey Likholob",              NSLocalizedString(@"Ukrainian localization",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Artem Logvyn",                  NSLocalizedString(@"Ukrainian localization",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Vitalii Skakun",                NSLocalizedString(@"Ukrainian localization",               @"Credit description"), nil],
							
                            [NSArray arrayWithObjects: @"Pompin Wu",                     NSLocalizedString(@"Chinese (traditional) localization",   @"Credit description"), nil],
                            nil];
	
    // Construct an HTML page with the dummy credits, consisting of a table.
    NSString * htmlHead = (@"<font face=\"Arial, Georgia, Garamond\">"
						   @"<table width=\"100%\">"
						   @"<tr><td colspan=\"2\">&nbsp;</td></tr>\n"
						   @"<tr><td colspan=\"2\"><strong><center>"
                           @"@@STRING@@"  // "TUNNELBLICK is brought to you by"
                           @"</strong></td></tr>\n<tr><td colspan=\"2\">&nbsp;</td></tr>\n");
	
    NSString * htmlMainTb = (@"<tr><td width=\"40%\" align=\"right\" valign=\"top\"><strong>"
                             @"@@STRING@@&nbsp;&nbsp;"  // Localization people
                             @"</center></strong></td><td width=\"60%\" valign=\"top\">"
                             @"@@STRING@@"				// <Language> localization
                             @"</td></tr>\n");
    	    
    NSString * htmlAfterMain = (@"<tr><td colspan=\"2\">&nbsp;</td></tr>\n"
								@"<tr><td colspan=\"2\">&nbsp;</td></tr>\n"
								@"<tr><td colspan=\"2\">&nbsp;</td></tr>\n"
								@"<tr><td colspan=\"2\"><strong><center>"
                                @"@@STRING@@"  // "Additional contributions by"
                                @"</center></strong></td></tr>\n<tr><td colspan=\"2\">&nbsp;</td></tr>\n");
    
    NSString * htmlPgmTb = (@"<tr><td width=\"40%\" align=\"right\" valign=\"top\"><strong>"
                            @"@@STRING@@&nbsp;&nbsp;"
                            @"</strong></td><td width=\"60%\" valign=\"top\">"
                            @"@@STRING@@"
                            @"</td></tr>\n");
    
    NSString * htmlAfterPgm = (@"<tr><td colspan=\"2\">&nbsp;</td></tr>\n<tr><td colspan=\"2\">&nbsp;</td></tr>\n<tr><td colspan=\"2\"><strong><center>"
                               @"@@STRING@@"  // "Localization by"
                               @"</center></strong></td></tr>\n<tr><td colspan=\"2\">&nbsp;</td></tr>\n");
	
    NSString * htmlLocTb = (@"<tr><td width=\"40%\" align=\"right\" valign=\"top\"><strong>"
							@"@@STRING@@&nbsp;&nbsp;"
							@"</strong></td><td width=\"60%\" valign=\"top\">"
							@"@@STRING@@"
							@"</td></tr>\n");
    
    NSString * htmlTail = @"</table></font>";

    NSMutableString * creditsHTML = [NSMutableString stringWithCapacity:1000];

    unsigned i;
    
    // Create HTML containing @@STRING@@ dummies
    
    [creditsHTML appendString: htmlHead];
    
    for (  i=0; i<[mainCredits count]; i++  ) {
        [creditsHTML appendString: htmlMainTb];
    }
    
    [creditsHTML appendString: htmlAfterMain];
    
    for (  i=0; i<[pgmCredits count]; i++  ) {
        [creditsHTML appendString: htmlPgmTb];
    }
    
    [creditsHTML appendString: htmlAfterPgm];
    
    for (  i=0; i<[locCredits count]; i++  ) {
        [creditsHTML appendString: htmlLocTb];
    }
    
    [creditsHTML appendString: htmlTail];
    
    // Create an NSMutableAttributedString from the HTML
    NSData * htmlData = [[[NSData alloc] initWithBytes: [creditsHTML UTF8String] length: [creditsHTML length]] autorelease];
    NSMutableAttributedString * creditsString = [[[NSMutableAttributedString alloc] initWithHTML: htmlData documentAttributes: nil] autorelease];
    
    // Make substitutions in the NSMutableAttributedString

    [self substitute: NSLocalizedString(@"TUNNELBLICK is brought to you by", @"Window text") in: creditsString];
    
    NSEnumerator * e = [mainCredits objectEnumerator];
    NSArray * row;
    while (  (row = [e nextObject])  ) {
        
        NSString * name = [row objectAtIndex: 0];
        NSString * role = [row objectAtIndex: 1];
        
        if (  [name isEqualToString: @"LEAD_TRANSLATORS"]  ) {
            name = @" ";
            role = @" ";
        } else if (  [role isEqualToString: @"LANGUAGE_LOCALIZATION"]  ) {
            role = @"Localization leaders";
        }
        
        [self substitute: name in: creditsString];
        [self substitute: role in: creditsString];
    }
    
    [self substitute: NSLocalizedString(@"Additional contributions by", @"Window text") in: creditsString];
    
    e = [pgmCredits objectEnumerator];
    while (  (row = [e nextObject])  ) {
        NSString * name = [row objectAtIndex: 0];
        NSString * role = [row objectAtIndex: 1];
        [self substitute: name in: creditsString];
        [self substitute: role in: creditsString];
    }
    
    [self substitute: NSLocalizedString(@"Localization by", @"Window text") in: creditsString];
    
    e = [locCredits objectEnumerator];
    while (  (row = [e nextObject])  ) {
        NSString * name = [row objectAtIndex: 0];
        NSString * role = [row objectAtIndex: 1];
        [self substitute: name in: creditsString];
        [self substitute: role in: creditsString];
    }
    
    // Convert the NSMutableAttributedString to RTF
    NSData * rtfData = [creditsString RTFFromRange: NSMakeRange(0, [creditsString length])
                                documentAttributes:nil];
    
    // Display the RTF
    [infoCreditSV setHasHorizontalScroller: NO];
    [infoCreditSV setHasVerticalScroller:   NO];
    
    [infoCreditTV setEditable:              NO];
    [infoCreditTV replaceCharactersInRange: NSMakeRange( 0, 0 ) withRTF: rtfData];

    [infoCopyrightTFC setTitle: copyrightNotice()];
}

-(void) oldViewWillDisappear: (NSView *) view identifier: (NSString *) identifier
{
	(void) view;
	(void) identifier;
	
    [scrollTimer invalidate];
}


-(void) newViewWillAppear: (NSView *) view identifier: (NSString *) identifier
{
	(void) view;
	(void) identifier;
	
    requestedPosition = 0.0;
    restartAtTop = YES;
    startTime = [NSDate timeIntervalSinceReferenceDate] + 2.0;  // Time between initial display and start of scrolling (but it also
                                                                // takes time to scroll to the bottom of the display before moving the text)
    [infoCreditTV scrollPoint:NSMakePoint( 0.0, 0.0 )];
    
    scrollTimer = [NSTimer scheduledTimerWithTimeInterval: 0.03 
                                                   target: self 
                                                 selector: @selector(scrollCredits:) 
                                                 userInfo: nil 
                                                  repeats: YES];
}


- (void)scrollCredits:(NSTimer *)timer
{
	(void) timer;
	
    if ([NSDate timeIntervalSinceReferenceDate] >= startTime) {
        if (  restartAtTop  ) {
            // Reset the startTime
            startTime = [NSDate timeIntervalSinceReferenceDate] + 1.0;  // Time to allow for fade in at top before scrolling
            restartAtTop = NO;
            
            // Fade back in
            if (   [infoCreditSV respondsToSelector: @selector(animator)]
                && [[infoCreditSV animator] respondsToSelector: @selector(setAlphaValue:)]  ) {
                [[infoCreditSV animator] setAlphaValue: 1.0];
            }
            // Set the position
            [infoCreditTV scrollPoint:NSMakePoint( 0.0, 0.0 )];
            
            return;
        }
        
        CGFloat actualPosition = [[infoCreditSV contentView] bounds].origin.y;
        if (  requestedPosition > actualPosition + 200.0  ) {
            // Reset the startTime
            startTime = [NSDate timeIntervalSinceReferenceDate] + 1.0;  // Time from fading out at end to fade in at top
            
            // Reset the position
            requestedPosition = 0.0;
            restartAtTop = YES;
            
            // Fade out quietly
            if (   [infoCreditSV respondsToSelector: @selector(animator)]
                && [[infoCreditSV animator] respondsToSelector: @selector(setAlphaValue:)]  ) {
                [[infoCreditSV animator] setAlphaValue: 0.0];
            }
        } else {
            // Scroll to the position
            [infoCreditTV scrollPoint:NSMakePoint( 0.0, requestedPosition )];
            
            // Increment the scroll position
            requestedPosition += 1.0;
        }
    }
}

TBSYNTHESIZE_OBJECT_GET(retain, NSButton        *, infoHelpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, infoVersionTFC)

@end
