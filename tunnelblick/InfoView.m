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

    NSArray * mainCredits = @[
                             @[@"Angelo Laub",      NSLocalizedString(@"Founder, original program and documentation",  @"Credit description")],
                             @[@"James Yonan",      @"OpenVPN"],
                             @[@"Dirk Theisen",     NSLocalizedString(@"Contributed much to the early code",           @"Credit description")],
                             @[@"Jonathan Bullard", NSLocalizedString(@"Program and documentation enhancements and maintenance after version 3.0b10", @"Credit description")],

                             @[
                              NSLocalizedString(@"LEAD_TRANSLATORS",      @"Names of lead translators"),
                              NSLocalizedString(@"LANGUAGE_TRANSLATION",  @"[name of your language] translation")]
							 ];

    NSArray * pgmCredits = @[
                            @[@"Dave Batton",                  @"DBPrefsWindowController"],
                            @[@"Michael Schloh von Bennewit",  NSLocalizedString(@"64-bit enabling and testing",           @"Credit description")],
                            @[@"Stefan Bethke",                NSLocalizedString(@"Localization code tweaks",              @"Credit description")],
                            @[@"Michael Bianco",               NSLocalizedString(@"Button images",                         @"Credit description")],
                            @[@"Waldemar Brodkorb",            NSLocalizedString(@"Contributed to early code",             @"Credit description")],
                            @[@"Math Campbell",                NSLocalizedString(@"Button images",                         @"Credit description")],
                            @[@"William Faulk",                NSLocalizedString(@"Icon set including Retina images",      @"Credit description")],
                            @[@"Matt Gemmell",                                   @"NSAttachedWindow"],
                            @[@"Raal Goff",                    NSLocalizedString(@"Animation and icon sets code",          @"Credit description")],
                            @[@"Benji Greig",                  NSLocalizedString(@"Tunnelblick icon",                      @"Credit description")],
                            @[@"Mohammad A. Haque",            NSLocalizedString(@"Xcode help and OpenSSL integration",    @"Credit description")],
                            @[@"Wyatt Kirby",                  NSLocalizedString(@"Icon set including Retina images",      @"Credit description")],
                            @[@"Uli Kusterer",                 NSLocalizedString(@"UKKQueue and UKLoginItemRegistry",      @"Credit description")],
                            @[@"Xaver Loppenstedt",            NSLocalizedString(@"PKCS#11 support",                       @"Credit description")],
                            @[@"Andy Matuschak",                                 @"Sparkle"],
                            @[@"Dustin Mierau",                                  @"Netsocket"],
                            @[@"Harold Molina-Bulla",          NSLocalizedString(@"OpenVPN 2.3 and 64-bit integration",    @"Credit description")],
                            @[@"Mattias Nissler",                                @"Tuntap"],
                            @[@"Markus F. X. J. Oberhumer",                      @"LZO"],
                            @[@"Jens Ohlig",                   NSLocalizedString(@"Contributed to early code",             @"Credit description")],
                            @[@"Diego Rivera",                 NSLocalizedString(@"Up and Down scripts",                   @"Credit description")],
                            @[@"Michael Williams",             NSLocalizedString(@"Multiple configuration folders",        @"Credit description")],
                            @[@"Nick Williams",                NSLocalizedString(@"Up and Down scripts",                   @"Credit description")]
							];

    NSArray * locCredits = @[
							@[@"Sobhi Abufool",                 NSLocalizedString(@"Arabic translation",                   @"Credit description")],
                            @[@"Khalid Alhumud",                NSLocalizedString(@"Arabic translation",                   @"Credit description")],
							@[@"Ali#",							 NSLocalizedString(@"Persian translation",                 @"Credit description")],
							@[@"Vittorio Anselmo",				 NSLocalizedString(@"Italian translation",                 @"Credit description")],
							@[@"Felin Arch",					 NSLocalizedString(@"Hungarian translation",               @"Credit description")],
							@[@"Alejandro Azadte",              NSLocalizedString(@"Spanish translation",                  @"Credit description")],
                            @[@"b123400",                       NSLocalizedString(@"Chinese (traditional) translation",    @"Credit description")],
                            @[@"Matej Bačík",                   NSLocalizedString(@"Slovak translation",                   @"Credit description")],
                            @[@"Ian Barnes",                    NSLocalizedString(@"Afrikaans translation",                @"Credit description")],
                            @[@"Stefan Bethke",                 NSLocalizedString(@"German translation",                   @"Credit description")],
                            @[@"Simon Biber",					 NSLocalizedString(@"Chinese (traditional) translation",   @"Credit description")],
							@[@"Simon Biber",					 NSLocalizedString(@"Chinese (simplified) translation",    @"Credit description")],
                            @[@"Rachid BM",                     NSLocalizedString(@"Dutch translation",                    @"Credit description")],
							@[@"Dariusz Bogdanski",             NSLocalizedString(@"Polish translation",                   @"Credit description")],
                            @[@"Olivier Borowski",              NSLocalizedString(@"French translation",                   @"Credit description")],
                            @[@"Martin Bratteng",               NSLocalizedString(@"Norwegian translation",                @"Credit description")],
                            @[@"Charlie Brown",                 NSLocalizedString(@"Vietnamese translation",               @"Credit description")],
                            @[@"Miguel C.",                     NSLocalizedString(@"Portuguese translation",               @"Credit description")],
							@[@"Alican Cakil",                  NSLocalizedString(@"Turkish translation",                  @"Credit description")],
                            @[@"Sergio Andrés Castro Cárdenas", NSLocalizedString(@"Spanish translation",                  @"Credit description")],
							@[@"Adam Černý",                    NSLocalizedString(@"Czech translation",                    @"Credit description")],
                            @[@"cert.lv",                       NSLocalizedString(@"Latvian translation",                  @"Credit description")],
							@[@"Teerapap Changwichukarn",       NSLocalizedString(@"Thai translation",    				   @"Credit description")],
							@[@"Zhanchong Chen",                NSLocalizedString(@"Chinese (simplified) translation",     @"Credit description")],
                            @[@"Vadim Chumachenko",             NSLocalizedString(@"Ukrainian translation",                @"Credit description")],
                            @[@"Iris Coeligena",                NSLocalizedString(@"Turkish translation",                  @"Credit description")],
							@[@"Diego Silva Cogo",              NSLocalizedString(@"Portuguese (Brazilian) translation",   @"Credit description")],
                            @[@"Catalin Comanici",              NSLocalizedString(@"Romanian translation",                 @"Credit description")],
                            @[@"Mats Cronqvist",                NSLocalizedString(@"Swedish translation",                  @"Credit description")],
                            @[@"Grzegorz Danecki",              NSLocalizedString(@"Polish translation",                   @"Credit description")],
							@[@"Mohamad Deek",                  NSLocalizedString(@"Arabic translation",                   @"Credit description")],
							@[@"Martin Doktár",                 NSLocalizedString(@"Swedish translation",                  @"Credit description")],
							@[@"Sergiy Dolnyy",                 NSLocalizedString(@"Ukrainian translation",                @"Credit description")],
                            @[@"Aleix Dorca",                   NSLocalizedString(@"Catalan translation",                  @"Credit description")],
                            @[@"Andreas Finke",                 NSLocalizedString(@"German translation",                   @"Credit description")],
							@[@"Marco Firsching",               NSLocalizedString(@"German translation",                   @"Credit description")],
							@[@"FoghDesign",                    NSLocalizedString(@"Danish translation",                   @"Credit description")],
                            @[@"Emīls Gailišs",                 NSLocalizedString(@"Latvian translation",                  @"Credit description")],
                            @[@"Simone Gianni",                 NSLocalizedString(@"Italian translation",                  @"Credit description")],
                            @[@"Nail Gilmanov",                 NSLocalizedString(@"Russian translation",                  @"Credit description")],
                            @[@"Igor Gojkovic",                 NSLocalizedString(@"Croatian translation",                 @"Credit description")],
                            @[@"Igor Gojkovic",                 NSLocalizedString(@"Serbian (Latin) translation",          @"Credit description")],
							@[@"Oleksandr Golubets",            NSLocalizedString(@"Ukrainian translation",                @"Credit description")],
                            @[@"Massimo Grassi",                NSLocalizedString(@"Italian translation",                  @"Credit description")],
                            @[@"Ricardo Guijt",                 NSLocalizedString(@"Dutch translation",                    @"Credit description")],
                            @[@"Pierpaolo Gulla",               NSLocalizedString(@"Italian translation",                  @"Credit description")],
							@[@"Robbert Hamburg CISA, CISSP, CEH", NSLocalizedString(@"Dutch translation",                 @"Credit description")],
							@[@"Robbert Hamburg CISA, CISSP, CEH", NSLocalizedString(@"Flemish translation",               @"Credit description")],
                            @[@"Takatoh Herminghaus",           NSLocalizedString(@"German translation",                   @"Credit description")],
                            @[@"Oliver Hill",                   NSLocalizedString(@"French translation",                   @"Credit description")],
							@[@"Cam Hoang",                     NSLocalizedString(@"Vietnamese translation",               @"Credit description")],
                            @[@"'Dr Hok'",                      NSLocalizedString(@"German translation",                   @"Credit description")],
                            @[@"Evandro Curvelo Hora",          NSLocalizedString(@"Portuguese (Brazilian) translation",   @"Credit description")],
							@[@"Johan Hornof",                  NSLocalizedString(@"Czech translation",                    @"Credit description")],
                            @[@"Igor Hrček",                    NSLocalizedString(@"Serbian (Latin) translation",          @"Credit description")],
							@[@"Jesse Hulkko",                  NSLocalizedString(@"Finnish translation",                  @"Credit description")],
							@[@"Christophe Icard",              NSLocalizedString(@"French translation",                   @"Credit description")],
							@[@"Bogdan I. Iorga",               NSLocalizedString(@"Romanian translation",                 @"Credit description")],
                            @[@"Jarmo Isotalo",                 NSLocalizedString(@"Finnish translation",                  @"Credit description")],
							@[@"Vlad Iuga",              		NSLocalizedString(@"Romanian translation",                 @"Credit description")],
							@[@"Ronny Jordalen",                NSLocalizedString(@"Norwegian translation",                @"Credit description")],
                            @[@"Dewey Kang",                    NSLocalizedString(@"Korean translation",                   @"Credit description")],
                            @[@"Yunseok Kang",                  NSLocalizedString(@"Korean translation",                   @"Credit description")],
							@[@"Tuomo Karhu",                   NSLocalizedString(@"Finnish translation",                  @"Credit description")],
							@[@"Kalle Kärkkäinen",              NSLocalizedString(@"Finnish translation",                  @"Credit description")],
							@[@"Yoshihisa Kawamoto",            NSLocalizedString(@"Japanese translation",                 @"Credit description")],
                            @[@"Alexander Kaydannik",           NSLocalizedString(@"Ukrainian translation",                @"Credit description")],
                            @[@"Kornél Keszthelyi",             NSLocalizedString(@"Hungarian translation",                @"Credit description")],
                            @[@"Kyoungmin Kim",                 NSLocalizedString(@"Korean translation",                   @"Credit description")],
                            @[@"Laurens de Knijff",             NSLocalizedString(@"Dutch translation",                    @"Credit description")],
							@[@"Matti Kohtala",                 NSLocalizedString(@"Finnish translation",                  @"Credit description")],
                            @[@"Mikael Kolkinn",                NSLocalizedString(@"Norwegian translation",                @"Credit description")],
                            @[@"Andrejs Kotovs",                NSLocalizedString(@"Latvian translation",                  @"Credit description")],
                            @[@"Andreas Kromke",                NSLocalizedString(@"German translation",                   @"Credit description")],
                            @[@"kskmt",                         NSLocalizedString(@"Japanese translation",                 @"Credit description")],
                            @[@"Henry Kuo",                     NSLocalizedString(@"Chinese (traditional) translation",    @"Credit description")],
                            @[@"Emin Kura",                     NSLocalizedString(@"Turkish translation",                  @"Credit description")],
                            @[@"Daniel Kvist",                  NSLocalizedString(@"Swedish translation",                  @"Credit description")],
                            @[@"Isaac Kwan",                    NSLocalizedString(@"Chinese (traditional) translation",    @"Credit description")],
                            @[@"Aming Lau",                     NSLocalizedString(@"Chinese (traditional) translation",    @"Credit description")],
                            @[@"Aleksey Likholob",              NSLocalizedString(@"Ukrainian translation",                @"Credit description")],
                            @[@"Débora Lima",                   NSLocalizedString(@"Portuguese translation",               @"Credit description")],
							@[@"Débora Lima",                   NSLocalizedString(@"Portuguese (Brazilian) translation",   @"Credit description")],
							@[@"Yen-Ting Liu",                  NSLocalizedString(@"Chinese (traditional) translation",    @"Credit description")],
                            @[@"Jon Luberth",                   NSLocalizedString(@"Norwegian translation",                @"Credit description")],
                            @[@"Łukasz M",                      NSLocalizedString(@"Polish translation",                   @"Credit description")],
                            @[@"Jakob Bo Søndergaard Madsen",   NSLocalizedString(@"Danish translation",                   @"Credit description")],
                            @[@"Mehrad Mahmoudian",             NSLocalizedString(@"Persian translation",                  @"Credit description")],
							@[@"Tim Malmström",                 NSLocalizedString(@"Swedish translation",                  @"Credit description")],
							@[@"Dušan Marjanović",              NSLocalizedString(@"Serbian (Latin) translation",          @"Credit description")],
							@[@"Luigi Martini",                 NSLocalizedString(@"Italian translation",                  @"Credit description")],
                            @[@"Denis Volpato Martins",         NSLocalizedString(@"Portuguese (Brazilian) translation",   @"Credit description")],
							@[@"Klaus Marx",                    NSLocalizedString(@"German translation",                   @"Credit description")],
							@[@"Dr. Joseph Mbowe",              NSLocalizedString(@"Swahili (Tanzania) translation",       @"Credit description")],
							@[@"Gema Megantara",            	 NSLocalizedString(@"Indonesian translation",              @"Credit description")],
							@[@"Rustam Mehmandarov",            NSLocalizedString(@"Azerbaijani translation",              @"Credit description")],
							@[@"Rustam Mehmandarov",            NSLocalizedString(@"Norwegian translation",                @"Credit description")],
							@[@"Rustam Mehmandarov",            NSLocalizedString(@"Russian translation",                  @"Credit description")],
                            @[@"Atakan Meray",                  NSLocalizedString(@"Turkish translation",                  @"Credit description")],
                            @[@"Boian Mihailov",                NSLocalizedString(@"Bulgarian translation",                @"Credit description")],
							@[@"Robin De Mol",                  NSLocalizedString(@"Flemish translation",                  @"Credit description")],
                            @[@"Richárd Murvai",                NSLocalizedString(@"Hungarian translation",                @"Credit description")],
                            @[@"Andrejs Mors-Jaroslavcevs",     NSLocalizedString(@"Latvian translation",                  @"Credit description")],
							@[@"Max Naylor",                    NSLocalizedString(@"Icelandic translation",                @"Credit description")],
                            @[@"Kurt Jarusutthirak Nielsen",    NSLocalizedString(@"Danish translation",                   @"Credit description")],
							@[@"Nikki",                         NSLocalizedString(@"Azerbaijani translation",              @"Credit description")],
                            @[@"Johan Nilsson",                 NSLocalizedString(@"Swedish translation",                  @"Credit description")],
							@[@"Mattias Nilsson",               NSLocalizedString(@"Swedish translation",                  @"Credit description")],
                            @[@"Feetu Nyrhinen",                NSLocalizedString(@"Finnish translation",                  @"Credit description")],
                            @[@"Kenji Obata",                   NSLocalizedString(@"Japanese translation",                 @"Credit description")],
                            @[@"Peter K. O'Connor",             NSLocalizedString(@"Chinese (simplified) translation",     @"Credit description")],
                            @[@"Tzvika Ofek",					 NSLocalizedString(@"Hebrew translation",                  @"Credit description")],
                            @[@"Stig A. Olsen",                 NSLocalizedString(@"Norwegian translation",                @"Credit description")],
                            @[@"Tzanos Panagiotis",             NSLocalizedString(@"Greek translation",                    @"Credit description")],
							@[@"La Pegunta Foundation",         NSLocalizedString(@"Catalan translation",                  @"Credit description")],
                            @[@"Petra Penttila",                NSLocalizedString(@"Finnish translation",                  @"Credit description")],
                            @[@"Matteo Pillon",                 NSLocalizedString(@"Italian translation",                  @"Credit description")],
                            @[@"Ioannis Pinakoulakis",          NSLocalizedString(@"Greek translation",                    @"Credit description")],
                            @[@"Lionel Pinkhard",               NSLocalizedString(@"Afrikaans translation",                @"Credit description")],
                            @[@"Victor Ptichkin",               NSLocalizedString(@"Russian translation",                  @"Credit description")],
                            @[@"Ricardo Rezende",               NSLocalizedString(@"Portuguese (Brazilian) translation",   @"Credit description")],
                            @[@"Diego Rivera",                  NSLocalizedString(@"Spanish translation",                  @"Credit description")],
                            @[@"Nicolas Rodriguez (Tupaca)",    NSLocalizedString(@"Spanish translation",                  @"Credit description")],
							@[@"Minho Ryang",                   NSLocalizedString(@"Korean translation",                   @"Credit description")],
							@[@"Darek Rzeźnicki",               NSLocalizedString(@"Polish translation",                   @"Credit description")],
							@[@"Murat Salma",               	NSLocalizedString(@"Turkish translation",                  @"Credit description")],
							@[@"Michoel Samuels",               NSLocalizedString(@"Hebrew translation",                   @"Credit description")],
                            @[@"Saulo Santos",                  NSLocalizedString(@"Portuguese translation",               @"Credit description")],
                            @[@"Ranal Saron",                   NSLocalizedString(@"Estonian translation",                 @"Credit description")],
                            @[@"Markus Schneider",              NSLocalizedString(@"German translation",                   @"Credit description")],
                            @[@"Janek Schwarz",                 NSLocalizedString(@"German translation",                   @"Credit description")],
                            @[@"Emma Segev",                    NSLocalizedString(@"Dutch translation",                    @"Credit description")],
                            @[@"Jeremy Sherman",                NSLocalizedString(@"French translation",                   @"Credit description")],
                            @[@"Þór Sigurðsson",                NSLocalizedString(@"Icelandic translation",                @"Credit description")],
							@[@"D. Simeonidis",                 NSLocalizedString(@"Greek translation",                    @"Credit description")],
                            @[@"Stjepan Siljac",                NSLocalizedString(@"Swedish translation",                  @"Credit description")],
                            @[@"Emīls Skujiņš",                 NSLocalizedString(@"Latvian translation",                  @"Credit description")],
                            @[@"Tjalling Soldaat",              NSLocalizedString(@"Dutch translation",                    @"Credit description")],
							@[@"Arne Solheim",                  NSLocalizedString(@"Norwegian translation",                @"Credit description")],
							@[@"Xavier Spirlet (Petitpoisson)", NSLocalizedString(@"French translation",                   @"Credit description")],
                            @[@"Petr Šrajer",                   NSLocalizedString(@"Czech translation",                    @"Credit description")],
                            @[@"Wojciech Sromek",               NSLocalizedString(@"Polish translation",                   @"Credit description")],
                            @[@"Ann-Charlotte Storer",          NSLocalizedString(@"Swedish translation",                  @"Credit description")],
                            @[@"Mihail Stoynov",                NSLocalizedString(@"Bulgarian translation",                @"Credit description")],
							@[@"Alexander Strashilov",          NSLocalizedString(@"Bulgarian translation",                @"Credit description")],
							@[@"Zack Strulovitch",              NSLocalizedString(@"Hebrew translation",                   @"Credit description")],
                            @[@"Allan Sun",                     NSLocalizedString(@"Chinese (traditional) translation",    @"Credit description")],
                            @[@"Benedek Szabó",                 NSLocalizedString(@"Hungarian translation",                @"Credit description")],
                            @[@"Marcell Szabo",                 NSLocalizedString(@"Hungarian translation",                @"Credit description")],
                            @[@"Paul Taykalo",                  NSLocalizedString(@"Ukrainian translation",                @"Credit description")],
                            @[@"TheFrog",                       NSLocalizedString(@"Slovak translation",                   @"Credit description")],
                            @[@"Erwann Thoraval",               NSLocalizedString(@"French translation",                   @"Credit description")],
                            @[@"Mikko Toivola",                 NSLocalizedString(@"Finnish translation",                  @"Credit description")],
                            @[@"André Torres",                  NSLocalizedString(@"Portuguese translation",               @"Credit description")],
                            @[@"Andika Triwidada",              NSLocalizedString(@"Indonesian translation",               @"Credit description")],
							@[@"Roman Truba",					 NSLocalizedString(@"Russian translation",                 @"Credit description")],
                            @[@"Eugene Trufanov",               NSLocalizedString(@"Russian translation",                  @"Credit description")],
                            @[@"Dennis Ukhanov",                NSLocalizedString(@"Russian translation",                  @"Credit description")],
                            @[@"Caglar Ulkuderner",             NSLocalizedString(@"Turkish translation",                  @"Credit description")],
							@[@"Levi Ustinov",                  NSLocalizedString(@"Russian translation",                  @"Credit description")],
                            @[@"François Varas",                NSLocalizedString(@"French translation",                   @"Credit description")],
                            @[@"Jorge Daniel Sampayo Vargas",   NSLocalizedString(@"Spanish translation",                  @"Credit description")],
                            @[@"Cristiano Verondini",           NSLocalizedString(@"Italian translation",                  @"Credit description")],
                            @[@"Zoltan Lanyi Webmegoldasok",    NSLocalizedString(@"Hungarian translation",                @"Credit description")],
                            @[@"Pomin Wu",                      NSLocalizedString(@"Chinese (traditional) translation",    @"Credit description")],
                            @[@"Kun Xi",                        NSLocalizedString(@"Chinese (simplified) translation",     @"Credit description")],
                            @[@"Sho Yano",                      NSLocalizedString(@"Japanese translation",                 @"Credit description")],
                            @[@"Andrew Ying",                   NSLocalizedString(@"Chinese (traditional) translation",    @"Credit description")],
							@[@"Abraham van der Vyver",         NSLocalizedString(@"Afrikaans translation",                @"Credit description")],
                            @[@"游精展",                         NSLocalizedString(@"Chinese (traditional) translation",    @"Credit description")],
							@[@"Cagri Yucel",                   NSLocalizedString(@"Turkish translation",                  @"Credit description")],
                            @[@"Magdelena Zajac",               NSLocalizedString(@"Polish translation",                   @"Credit description")],
                            @[@"ZaTi",                          NSLocalizedString(@"Romanian translation",                 @"Credit description")],
                            @[@"Nikolay Zhelev",                NSLocalizedString(@"Bulgarian translation",                @"Credit description")],
							@[@"Zozzi",                         NSLocalizedString(@"Slovak translation",                   @"Credit description")]
                            ];

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

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *, infoVersionTFC)
TBSYNTHESIZE_OBJECT(retain, NSTimer *, scrollTimer, setScrollTimer)

@end
