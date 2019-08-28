/*
 * Copyright 2011, 2012, 2013, 2014, 2015, 2016, 2018 Jonathan K. Bullard. All rights reserved.
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
#import "sharedRoutines.h"

#import "UIHelper.h"
#import "NSTimer+TB.h"
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

-(void) dealloc {
	
	[logo release];           logo        = nil;
	[scrollTimer invalidate];
	[scrollTimer release];    scrollTimer = nil;
	
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
    NSMutableAttributedString* newAttrString = [[[NSMutableAttributedString alloc] initWithString: LocalizationNotNeeded(newString)] autorelease];
    
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
    // Using [[NSBundle mainBundle] pathForResource: @"about" ofType: @"html"] doesn't always work -- it is apparently cached by macOS.
    // If it is used immediately after the installer creates and populates Resources/Deploy, nil is returned instead of the path
    // Using [[NSBundle mainBundle] resourcePath: ALSO seems to not work (don't know why, maybe the same reason)
    // The workaround is to create the path "by hand" and use that.
    NSString * aboutPath    = [[[NSBundle mainBundle] bundlePath] stringByAppendingString: @"/Contents/Resources/about.html"];
	NSString * htmlFromFile = [NSString stringWithContentsOfFile: aboutPath encoding:NSASCIIStringEncoding error:NULL];
    if (  htmlFromFile  ) {
        NSString * basedOnHtml  = NSLocalizedString(@"<br>Based on Tunnel" @"blick, free software available at<br><a href=\"https://tunnelblick.net\">https://tunnelblick.net</a><br><br>OpenVPN is a registered trademark of OpenVPN Inc.", @"Window text");
        NSString * html         = [NSString stringWithFormat:@"%@%@%@%@",
                                   @"<html><body><center><div style=\"font-family: Verdana, Arial, Helvetica, sans-serif; font-size: 10px\">",
                                   htmlFromFile,
                                   basedOnHtml,
                                   @"</div></center><body></html>"];
        NSData * data = [html dataUsingEncoding:NSASCIIStringEncoding];
		if (  ! data  ) {
			NSLog(@"Cannot get dataUsingEncoding:NSASCIIStringEncoding for html; stack trace = %@", callStack());
			data = [NSData data];
		}
        NSMutableAttributedString * description = [[[NSMutableAttributedString alloc] initWithHTML:data documentAttributes:NULL] autorelease];
		[description addAttribute: NSForegroundColorAttributeName value:[NSColor textColor]           range: NSMakeRange(0, [description length])];
		[description addAttribute: NSBackgroundColorAttributeName value:[NSColor textBackgroundColor] range: NSMakeRange(0, [description length])];
        [[infoDescriptionTV textStorage] setAttributedString: description];
    } else {
        
        // Create the base string with localized content (the leading space is needed to keep the prefix from becoming a link; it is removed if the prefix is not needed)
		NSString * localizedContent = NSLocalizedString(@" %1$@ is free software: you can redistribute it and/or modify it under the terms of the %2$@ as published by the %3$@.\n\n%4$@ is a registered trademark of OpenVPN Inc.", @"Window text");
        NSMutableAttributedString * descriptionString = [[[NSMutableAttributedString alloc] initWithString: localizedContent] autorelease];
        
        // Replace the placeholders in the localized content with links
        [self replaceString: @"%1$@"
                 withString: @"Tunnel" @"blick"
                  urlString: @"https://www.tunnelblick.net"
                         in: descriptionString];
        
        [self replaceString: @"%2$@"
                 withString: @"GNU General Public License version 2"
                  urlString: @"https://www.gnu.org/licenses/gpl-2.0.html"
                         in: descriptionString];
        
        [self replaceString: @"%3$@"
                 withString: @"Free Software Foundation"
                  urlString: @"https://fsf.org"
                         in: descriptionString];
        
        [self replaceString: @"%4$@"
                 withString: @"OpenVPN"
                  urlString: @"https://openvpn.net/"
                         in: descriptionString];
		
        [infoDescriptionTV setEditable: NO];
        [infoDescriptionSV setHasHorizontalScroller: NO];
        [infoDescriptionSV setHasVerticalScroller:   NO];
        
        // If Tunnelblick has been globally replaced with XXX, prefix the license description with "XXX is based on Tunnelblick."
        if (   ( ! [gTbDefaults boolForKey: @"doNotUnrebrandLicenseDescription"]  )
			&& ( ! [@"Tunnelblick" isEqualToString: @"Tunnel" @"blick"]  )
			) {
			NSString * prefix = [NSString stringWithFormat:
								 NSLocalizedString(@"Tunnelblick is based on %@.", @"Window text"),
								 @"Tunnel" @"blick"];
			[descriptionString replaceCharactersInRange: NSMakeRange(0, 0) withString: prefix];
        } else {
			[descriptionString deleteCharactersInRange: NSMakeRange(0, 1)];	// Remove leading space
        }
		
		[descriptionString addAttribute: NSForegroundColorAttributeName value:[NSColor textColor]           range: NSMakeRange(0, [descriptionString length])];
		[descriptionString addAttribute: NSBackgroundColorAttributeName value:[NSColor textBackgroundColor] range: NSMakeRange(0, [descriptionString length])];
        NSDictionary * attributes = [NSDictionary dictionaryWithObject: NSRTFTextDocumentType forKey: NSDocumentTypeDocumentAttribute];
        [infoDescriptionTV replaceCharactersInRange: NSMakeRange( 0, [[infoDescriptionTV string] length] )
                                            withRTF: [descriptionString RTFFromRange: NSMakeRange( 0, [descriptionString length] ) documentAttributes: attributes]];
    }
	
	// Credits: create HTML, convert to an NSMutableAttributedString, substitute localized strings, and display
	//
    // Credits data comes from the following arrays:
    
    NSArray * mainCredits = [NSArray arrayWithObjects:
                             [NSArray arrayWithObjects: @"Angelo Laub",      NSLocalizedString(@"Founder, original program and documentation", @"Credit description"), nil],
                             [NSArray arrayWithObjects: @"James Yonan",      @"OpenVPN", nil],
                             [NSArray arrayWithObjects: @"Dirk Theisen",     NSLocalizedString(@"Contributed much to the early code", @"Credit description"), nil],
                             [NSArray arrayWithObjects: @"Jonathan Bullard", NSLocalizedString(@"Program and documentation enhancements and maintenance after version 3.0b10", @"Credit description"), nil],
                             
                             [NSArray arrayWithObjects:
                              NSLocalizedString(@"LEAD_TRANSLATORS",      @"Names of lead translators"),
                              NSLocalizedString(@"LANGUAGE_TRANSLATION",  @"[name of your language] translation"),
                              nil],
                             nil];
    
    NSArray * pgmCredits = [NSArray arrayWithObjects:
                            [NSArray arrayWithObjects: @"Dave Batton",                  @"DBPrefsWindowController", nil],
                            [NSArray arrayWithObjects: @"Michael Schloh von Bennewit",  NSLocalizedString(@"64-bit enabling and testing",           @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Stefan Bethke",                NSLocalizedString(@"Localization code tweaks",              @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Michael Bianco",               NSLocalizedString(@"Button images",                         @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Waldemar Brodkorb",            NSLocalizedString(@"Contributed to early code",             @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Math Campbell",                NSLocalizedString(@"Button images",                         @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"William Faulk",                NSLocalizedString(@"Icon set including Retina images",      @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Matt Gemmell",                                   @"NSAttachedWindow",                                              nil],
                            [NSArray arrayWithObjects: @"Raal Goff",                    NSLocalizedString(@"Animation and icon sets code",          @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Benji Greig",                  NSLocalizedString(@"Tunnelblick icon",                      @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mohammad A. Haque",            NSLocalizedString(@"Xcode help and OpenSSL integration",    @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Wyatt Kirby",                  NSLocalizedString(@"Icon set including Retina images",      @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Uli Kusterer",                 NSLocalizedString(@"UKKQueue and UKLoginItemRegistry",      @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Xaver Loppenstedt",            NSLocalizedString(@"PKCS#11 support",                       @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Andy Matuschak",                                 @"Sparkle",                                                       nil],
                            [NSArray arrayWithObjects: @"Dustin Mierau",                                  @"Netsocket",                                                     nil],
                            [NSArray arrayWithObjects: @"Harold Molina-Bulla",          NSLocalizedString(@"OpenVPN 2.3 and 64-bit integration",    @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mattias Nissler",                                @"Tuntap",                                                        nil],
                            [NSArray arrayWithObjects: @"Markus F. X. J. Oberhumer",                      @"LZO",                                                           nil],
                            [NSArray arrayWithObjects: @"Jens Ohlig",                   NSLocalizedString(@"Contributed to early code",             @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Diego Rivera",                 NSLocalizedString(@"Up and Down scripts",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Michael Williams",             NSLocalizedString(@"Multiple configuration folders",        @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Nick Williams",                NSLocalizedString(@"Up and Down scripts",                   @"Credit description"), nil],
                            nil];
    
    NSArray * locCredits = [NSArray arrayWithObjects:
							[NSArray arrayWithObjects: @"Sobhi Abufool",                 NSLocalizedString(@"Arabic translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Khalid Alhumud",                NSLocalizedString(@"Arabic translation",                  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Ali#",							 NSLocalizedString(@"Persian translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Vittorio Anselmo",				 NSLocalizedString(@"Italian translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Felin Arch",					 NSLocalizedString(@"Hungarian translation",               @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Alejandro Azadte",              NSLocalizedString(@"Spanish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"b123400",                       NSLocalizedString(@"Chinese (traditional) translation",   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Matej Bačík",                   NSLocalizedString(@"Slovak translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Stefan Bethke",                 NSLocalizedString(@"German translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Simon Biber",					 NSLocalizedString(@"Chinese (traditional) translation",   @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Simon Biber",					 NSLocalizedString(@"Chinese (simplified) translation",    @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Dariusz Bogdanski",             NSLocalizedString(@"Polish translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Olivier Borowski",              NSLocalizedString(@"French translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Martin Bratteng",               NSLocalizedString(@"Norwegian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Miguel C.",                     NSLocalizedString(@"Portuguese translation",              @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Alican Cakil",                  NSLocalizedString(@"Turkish translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Charlie Brown",                 NSLocalizedString(@"Vietnamese translation",              @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Sergio Andrés Castro Cárdenas", NSLocalizedString(@"Spanish translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Adam Černý",                    NSLocalizedString(@"Czech translation",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"cert.lv",                       NSLocalizedString(@"Latvian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Zhanchong Chen",                NSLocalizedString(@"Chinese (simplified) translation",    @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Vadim Chumachenko",             NSLocalizedString(@"Ukrainian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Iris Coeligena",                NSLocalizedString(@"Turkish translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Diego Silva Cogo",              NSLocalizedString(@"Portuguese (Brazilian) translation",  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Catalin Comanici",              NSLocalizedString(@"Romanian translation",                @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mats Cronqvist",                NSLocalizedString(@"Swedish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Grzegorz Danecki",              NSLocalizedString(@"Polish translation",                  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Mohamad Deek",                  NSLocalizedString(@"Arabic translation",                  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Sergiy Dolnyy",                 NSLocalizedString(@"Ukrainian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Aleix Dorca",                   NSLocalizedString(@"Catalan translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Andreas Finke",                 NSLocalizedString(@"German translation",                  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Marco Firsching",               NSLocalizedString(@"German translation",                  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"FoghDesign",                    NSLocalizedString(@"Danish translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Emīls Gailišs",                 NSLocalizedString(@"Latvian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Simone Gianni",                 NSLocalizedString(@"Italian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Nail Gilmanov",                 NSLocalizedString(@"Russian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Igor Gojkovic",                 NSLocalizedString(@"Croatian translation",                @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Igor Gojkovic",                 NSLocalizedString(@"Serbian (Latin) translation",         @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Oleksandr Golubets",            NSLocalizedString(@"Ukrainian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Massimo Grassi",                NSLocalizedString(@"Italian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Ricardo Guijt",                 NSLocalizedString(@"Dutch translation",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Pierpaolo Gulla",               NSLocalizedString(@"Italian translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Robbert Hamburg CISA, CISSP, CEH", NSLocalizedString(@"Dutch translation",                @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Robbert Hamburg CISA, CISSP, CEH", NSLocalizedString(@"Flemish translation",              @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Takatoh Herminghaus",           NSLocalizedString(@"German translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Oliver Hill",                   NSLocalizedString(@"French translation",                  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Cam Hoang",                     NSLocalizedString(@"Vietnamese translation",              @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"'Dr Hok'",                      NSLocalizedString(@"German translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Evandro Curvelo Hora",          NSLocalizedString(@"Portuguese (Brazilian) translation",  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Johan Hornof",                  NSLocalizedString(@"Czech translation",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Igor Hrček",                    NSLocalizedString(@"Serbian (Latin) translation",         @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Jesse Hulkko",                  NSLocalizedString(@"Finnish translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Christophe Icard",              NSLocalizedString(@"French translation",                  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Bogdan I. Iorga",               NSLocalizedString(@"Romanian translation",                @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Jarmo Isotalo",                 NSLocalizedString(@"Finnish translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Ronny Jordalen",                NSLocalizedString(@"Norwegian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Dewey Kang",                    NSLocalizedString(@"Korean translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Yunseok Kang",                  NSLocalizedString(@"Korean translation",                  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Tuomo Karhu",                   NSLocalizedString(@"Finnish translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Kalle Kärkkäinen",              NSLocalizedString(@"Finnish translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Yoshihisa Kawamoto",            NSLocalizedString(@"Japanese translation",                @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Alexander Kaydannik",           NSLocalizedString(@"Ukrainian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Kornél Keszthelyi",             NSLocalizedString(@"Hungarian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Kyoungmin Kim",                 NSLocalizedString(@"Korean translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Laurens de Knijff",             NSLocalizedString(@"Dutch translation",                   @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Matti Kohtala",                 NSLocalizedString(@"Finnish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mikael Kolkinn",                NSLocalizedString(@"Norwegian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Andrejs Kotovs",                NSLocalizedString(@"Latvian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"kskmt",                         NSLocalizedString(@"Japanese translation",                @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Henry Kuo",                     NSLocalizedString(@"Chinese (traditional) translation",   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Emin Kura",                     NSLocalizedString(@"Turkish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Daniel Kvist",                  NSLocalizedString(@"Swedish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Isaac Kwan",                    NSLocalizedString(@"Chinese (traditional) translation",   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Aming Lau",                     NSLocalizedString(@"Chinese (traditional) translation",   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Aleksey Likholob",              NSLocalizedString(@"Ukrainian translation",               @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Yen-Ting Liu",                  NSLocalizedString(@"Chinese (traditional) translation",   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Jon Luberth",                   NSLocalizedString(@"Norwegian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Łukasz M",                      NSLocalizedString(@"Polish translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Jakob Bo Søndergaard Madsen",   NSLocalizedString(@"Danish translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mehrad Mahmoudian",             NSLocalizedString(@"Persian translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Tim Malmström",                 NSLocalizedString(@"Swedish translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Dušan Marjanović",              NSLocalizedString(@"Serbian (Latin) translation",         @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Luigi Martini",                 NSLocalizedString(@"Italian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Denis Volpato Martins",         NSLocalizedString(@"Portuguese (Brazilian) translation",  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Klaus Marx",                    NSLocalizedString(@"German translation",                  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Rustam Mehmandarov",            NSLocalizedString(@"Azerbaijani translation",             @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Rustam Mehmandarov",            NSLocalizedString(@"Norwegian translation",               @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Rustam Mehmandarov",            NSLocalizedString(@"Russian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Atakan Meray",                  NSLocalizedString(@"Turkish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Boian Mihailov",                NSLocalizedString(@"Bulgarian translation",               @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Robin De Mol",                  NSLocalizedString(@"Flemish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Richárd Murvai",                NSLocalizedString(@"Hungarian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Andrejs Mors-Jaroslavcevs",     NSLocalizedString(@"Latvian translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Max Naylor",                    NSLocalizedString(@"Icelandic translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Kurt Jarusutthirak Nielsen",    NSLocalizedString(@"Danish translation",                  @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Nikki",                         NSLocalizedString(@"Azerbaijani translation",             @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Johan Nilsson",                 NSLocalizedString(@"Swedish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Feetu Nyrhinen",                NSLocalizedString(@"Finnish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Kenji Obata",                   NSLocalizedString(@"Japanese translation",                @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Peter K. O'Connor",             NSLocalizedString(@"Chinese (simplified) translation",    @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Tzvika Ofek",					 NSLocalizedString(@"Hebrew translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Tzanos Panagiotis",             NSLocalizedString(@"Greek translation",                   @"Credit description"), nil],
							[NSArray arrayWithObjects: @"La Pegunta Foundation",         NSLocalizedString(@"Catalan translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Petra Penttila",                NSLocalizedString(@"Finnish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Matteo Pillon",                 NSLocalizedString(@"Italian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Ioannis Pinakoulakis",          NSLocalizedString(@"Greek translation",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Lionel Pinkhard",               NSLocalizedString(@"Afrikaans translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Victor Ptichkin",               NSLocalizedString(@"Russian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Ricardo Rezende",               NSLocalizedString(@"Portuguese (Brazilian) translation",  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Diego Rivera",                  NSLocalizedString(@"Spanish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Nicolas Rodriguez (Tupaca)",    NSLocalizedString(@"Spanish translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Michoel Samuels",               NSLocalizedString(@"Hebrew translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Saulo Santos",                  NSLocalizedString(@"Portuguese translation",              @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Ranal Saron",                   NSLocalizedString(@"Estonian translation",                @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Markus Schneider",              NSLocalizedString(@"German translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Janek Schwarz",                 NSLocalizedString(@"German translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Emma Segev",                    NSLocalizedString(@"Dutch translation",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Jeremy Sherman",                NSLocalizedString(@"French translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Þór Sigurðsson",                NSLocalizedString(@"Icelandic translation",               @"Credit description"), nil],
							[NSArray arrayWithObjects: @"D. Simeonidis",                 NSLocalizedString(@"Greek translation",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Stjepan Siljac",                NSLocalizedString(@"Swedish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Emīls Skujiņš",                 NSLocalizedString(@"Latvian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Tjalling Soldaat",              NSLocalizedString(@"Dutch translation",                   @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Arne Solheim",                  NSLocalizedString(@"Norwegian translation",               @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Xavier Spirlet (Petitpoisson)", NSLocalizedString(@"French translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Petr Šrajer",                   NSLocalizedString(@"Czech translation",                   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Wojciech Sromek",               NSLocalizedString(@"Polish translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Ann-Charlotte Storer",          NSLocalizedString(@"Swedish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mihail Stoynov",                NSLocalizedString(@"Bulgarian translation",               @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Alexander Strashilov",          NSLocalizedString(@"Bulgarian translation",               @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Zack Strulovitch",              NSLocalizedString(@"Hebrew translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Marcell Szabo",                 NSLocalizedString(@"Hungarian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Paul Taykalo",                  NSLocalizedString(@"Ukrainian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"TheFrog",                       NSLocalizedString(@"Slovak translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Erwann Thoraval",               NSLocalizedString(@"French translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Mikko Toivola",                 NSLocalizedString(@"Finnish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"André Torres",                  NSLocalizedString(@"Portuguese translation",              @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Andika Triwidada",              NSLocalizedString(@"Indonesian translation",              @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Roman Truba",					 NSLocalizedString(@"Russian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Eugene Trufanov",               NSLocalizedString(@"Russian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Dennis Ukhanov",                NSLocalizedString(@"Russian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Caglar Ulkuderner",             NSLocalizedString(@"Turkish translation",                 @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Levi Ustinov",                  NSLocalizedString(@"Russian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"François Varas",                NSLocalizedString(@"French translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Jorge Daniel Sampayo Vargas",   NSLocalizedString(@"Spanish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Cristiano Verondini",           NSLocalizedString(@"Italian translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Zoltan Lanyi Webmegoldasok",    NSLocalizedString(@"Hungarian translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Pomin Wu",                      NSLocalizedString(@"Chinese (traditional) translation",   @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Kun Xi",                        NSLocalizedString(@"Chinese (simplified) translation",    @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Sho Yano",                      NSLocalizedString(@"Japanese translation",                @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Andrew Ying",                   NSLocalizedString(@"Chinese (traditional) translation",   @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Abraham van der Vyver",         NSLocalizedString(@"Afrikaans translation",               @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"游精展",                         NSLocalizedString(@"Chinese (traditional) translation",   @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Cagri Yucel",                   NSLocalizedString(@"Turkish translation",                 @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Magdelena Zajac",               NSLocalizedString(@"Polish translation",                  @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"ZaTi",                          NSLocalizedString(@"Romanian translation",                @"Credit description"), nil],
                            [NSArray arrayWithObjects: @"Nikolay Zhelev",                NSLocalizedString(@"Bulgarian translation",               @"Credit description"), nil],
							[NSArray arrayWithObjects: @"Zozzi",                         NSLocalizedString(@"Slovak translation",                  @"Credit description"), nil],
                            nil];
	
    BOOL rtl = [UIHelper languageAtLaunchWasRTL];
    
    // Construct an HTML page with the dummy credits, consisting of a table.
    NSString * htmlHead = (@"<font face=\"Arial, Georgia, Garamond\">"
                           @"<table width=\"100%\">"
                           @"<tr><td colspan=\"2\">&nbsp;</td></tr>\n"
                           @"<tr><td colspan=\"2\"><strong><center>"
                           @"@@STRING@@"  // "TUNNELBLICK is brought to you by"
                           @"</center></strong></td></tr>\n<tr><td colspan=\"2\">&nbsp;</td></tr>\n");
    
    NSString * htmlMainTb = (  rtl
                             ? (@"<tr><td width=\"60%\" align=\"right\" valign=\"top\">"
                                @"@@STRING@@&nbsp;&nbsp;"                   // What the person contributed
                                @"</td>"
                                @"<td width=\"40%\" valign=\"top\">"
                                @"<strong>@@STRING@@</strong>"				// Main contribution people
                                @"</td></tr>\n")
                             : (@"<tr><td width=\"40%\" align=\"right\" valign=\"top\">"
                                @"<strong>@@STRING@@&nbsp;&nbsp;</strong>"  // Main contribution people
                                @"</td><td width=\"60%\" valign=\"top\">"
                                @"@@STRING@@"                               // What the person contributed
                                @"</td></tr>\n"));
    
    NSString * htmlAfterMain = (@"<tr><td colspan=\"2\">&nbsp;</td></tr>\n"
                                @"<tr><td colspan=\"2\">&nbsp;</td></tr>\n"
                                @"<tr><td colspan=\"2\">&nbsp;</td></tr>\n"
                                @"<tr><td colspan=\"2\"><strong><center>"
                                @"@@STRING@@"  // "Additional contributions by"
                                @"</center></strong></td></tr>\n<tr><td colspan=\"2\">&nbsp;</td></tr>\n");
    
    NSString * htmlPgmTb = (  rtl
                            ? (@"<tr><td width=\"60%\" align=\"right\" valign=\"top\">"
                               @"@@STRING@@&nbsp;&nbsp;"                    // What the person contributed
                               @"</td><td width=\"40%\" valign=\"top\">"
                               @"<strong>@@STRING@@</strong>"				// Program contribution people
                               @"</td></tr>\n")
                            : (@"<tr><td width=\"40%\" align=\"right\" valign=\"top\">"
                               @"<strong>@@STRING@@&nbsp;&nbsp;</strong>"   // Program contribution people
                               @"</td>"
                               @"<td width=\"60%\" valign=\"top\">"
                               @"@@STRING@@"                                // What the person contributed
                               @"</td></tr>\n"));
    
    NSString * htmlAfterPgm = (@"<tr><td colspan=\"2\">&nbsp;</td></tr>\n"
                               @"<tr><td colspan=\"2\">&nbsp;</td></tr>\n"
                               @"<tr><td colspan=\"2\">"
                               @"<strong><center>@@STRING@@</center></strong>"  // "Localization by"
                               @"</td></tr>\n"
                               @"<tr><td colspan=\"2\">&nbsp;</td></tr>\n");
    
    NSString * htmlLocTb = (  rtl
                            ? (@"<tr><td width=\"60%\" align=\"right\" valign=\"top\">"
                               @"@@STRING@@&nbsp;&nbsp;"                    // <Language> localization
                               @"</td>"
                               @"<td width=\"40%\" valign=\"top\">"
                               @"<strong>@@STRING@@</strong>"				// Localization people
                               @"</td></tr>\n")
                            : (@"<tr><td width=\"40%\" align=\"right\" valign=\"top\">"
                               @"<strong>@@STRING@@&nbsp;&nbsp;</strong>"	// Localization people
                               @"</td>"
                               @"<td width=\"60%\" valign=\"top\">"
                               @"@@STRING@@"                                // <Language> localization
                               @"</td></tr>\n"));
    
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
    const char * bytes = [creditsHTML UTF8String];
    NSData * htmlData = [[[NSData alloc] initWithBytes: bytes length: strlen(bytes)] autorelease];
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
        } else if (  [role isEqualToString: @"LANGUAGE_TRANSLATION"]  ) {
            role = @"Translation leaders";
        }
        
		if (  [UIHelper languageAtLaunchWasRTL]  ) {
			[self substitute: role in: creditsString];
			[self substitute: name in: creditsString];
		} else {
			[self substitute: name in: creditsString];
			[self substitute: role in: creditsString];
		}
    }
    
    [self substitute: NSLocalizedString(@"Additional contributions by", @"Window text") in: creditsString];
    
    e = [pgmCredits objectEnumerator];
    while (  (row = [e nextObject])  ) {
        NSString * name = [row objectAtIndex: 0];
        NSString * role = [row objectAtIndex: 1];
		if (  [UIHelper languageAtLaunchWasRTL]  ) {
			[self substitute: role in: creditsString];
			[self substitute: name in: creditsString];
		} else {
			[self substitute: name in: creditsString];
			[self substitute: role in: creditsString];
		}
    }
    
    [self substitute: NSLocalizedString(@"Translation by", @"Window text") in: creditsString];
    
    e = [locCredits objectEnumerator];
	NSString * previousName = nil;
    while (  (row = [e nextObject])  ) {
        NSString * name = [row objectAtIndex: 0];
		if (  [previousName isEqualToString: name]  ) {
			name = @" ";
		} else {
			previousName = name;
		}
        NSString * role = [row objectAtIndex: 1];
		if (  [UIHelper languageAtLaunchWasRTL]  ) {
			[self substitute: role in: creditsString];
			[self substitute: name in: creditsString];
		} else {
			[self substitute: name in: creditsString];
			[self substitute: role in: creditsString];
		}
    }
    
	[creditsString addAttribute: NSForegroundColorAttributeName value:[NSColor textColor]           range: NSMakeRange(0, [creditsString length])];
	[creditsString addAttribute: NSBackgroundColorAttributeName value:[NSColor textBackgroundColor] range: NSMakeRange(0, [creditsString length])];

	// Convert the NSMutableAttributedString to RTF
    NSDictionary * attributes = [NSDictionary dictionaryWithObject: NSRTFTextDocumentType forKey: NSDocumentTypeDocumentAttribute];
    NSData * rtfData = [creditsString RTFFromRange: NSMakeRange(0, [creditsString length])
                                documentAttributes: attributes];
    
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
    [self setScrollTimer: nil];
}


-(void) newViewDidAppear: (NSView *) view
{
	(void) view;
	
    requestedPosition = 0.0;
    restartAtTop = YES;
    startTime = [NSDate timeIntervalSinceReferenceDate] + 2.0;  // Time between initial display and start of scrolling (but it also
                                                                // takes time to scroll to the bottom of the display before moving the text)
    [infoCreditTV scrollPoint:NSMakePoint( 0.0, 0.0 )];
    
    [scrollTimer invalidate];
    [self setScrollTimer: [NSTimer scheduledTimerWithTimeInterval: 0.03
                                                           target: self
                                                         selector: @selector(scrollCredits:)
                                                         userInfo: nil
                                                          repeats: YES]];
    [scrollTimer tbSetTolerance: -1.0];
}


-(void) newViewWillAppear: (NSView *) view identifier: (NSString *) identifier
{
    (void) identifier;
    
    [self newViewDidAppear: view];
}

- (void)scrollCredits:(NSTimer *)timer
{
	(void) timer;
    
    if (  lastPosition != [[infoCreditSV contentView] bounds].origin.y  ) {
        // Manual scroll has occurred. Pause the auto-scroll for at least a second.
        startTime = [NSDate timeIntervalSinceReferenceDate] + 1.0;
        
        requestedPosition = lastPosition;
        restartAtTop = NO;
    }
	
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
        } else if (  requestedPosition > [infoCreditTV bounds].size.height + 200.0  ) {
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
    
    lastPosition = [[infoCreditSV contentView] bounds].origin.y;
}

TBSYNTHESIZE_OBJECT_GET(retain, NSButton        *, infoHelpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, infoVersionTFC)
TBSYNTHESIZE_OBJECT(retain, NSTimer *, scrollTimer, setScrollTimer)

@end
