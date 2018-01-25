/*
 * Copyright 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017. All rights reserved.
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

@class AlertWindowController;

NSAttributedString * attributedStringFromHTML(NSString * html);

void           appendLog				 (NSString * msg);

BOOL           appHasValidSignature(void);

uint64_t       nowAbsoluteNanoseconds    (void);

NSString     * configPathFromTblkPath   (NSString * path);
NSString     * tblkPathFromConfigPath   (NSString * path);

NSString     * condensedConfigFileContentsFromString(NSString * fullString);

NSString     * configLocCodeStringForPath(NSString * configPath);

NSString     * credentialsGroupFromDisplayName (NSString * displayName);

BOOL           copyCredentials          (NSString * fromDisplayName,
                                         NSString * toDisplayName);

BOOL           moveCredentials          (NSString * fromDisplayName,
                                         NSString * toDisplayName);

BOOL           keychainHasPrivateKeyForDisplayName(NSString * name);
BOOL           keychainHasUsernameWithoutPasswordForDisplayName(NSString * name);
BOOL           keychainHasUsernameAndPasswordForDisplayName(NSString * name);

NSString     * copyrightNotice          (void);

NSString     * escaped                  (NSString * string);

BOOL okToUpdateConfigurationsWithoutAdminApproval(void);

NSMutableString * encodeSlashesAndPeriods(NSString * s);

NSString     * stringForLog             (NSString * outputString,
                                         NSString * header);

NSString     * displayNameForOpenvpnName(NSString * openvpnName);

NSString     * messageIfProblemInLogLine(NSString * line);

NSString     * firstPartOfPath          (NSString * thePath);
NSString     * lastPartOfPath           (NSString * thePath);
NSString     * displayNameFromPath      (NSString * thePath);
NSString     * firstPathComponent       (NSString * thePath);

NSString     * tunnelblickVersion       (NSBundle * bundle);
NSString     * localizeNonLiteral        (NSString * status,
                                         NSString * type);
NSString	 * defaultOpenVpnFolderName	(void);

// from http://clang-analyzer.llvm.org/faq.html#unlocalized_string
__attribute__((annotate("returns_localized_nsstring")))
static inline NSString * LocalizationNotNeeded(NSString *s) {
	return s;
}

NSString     * TBGetString				(NSString * msg,
										 NSString * nameToPrefill);

NSString     * TBGetDisplayName         (NSString * msg,
                                         NSString * sourcePath);

AlertWindowController * TBShowAlertWindow(NSString * title,
                                          id         msg); // NSString or NSAttributedString only

int            TBRunAlertPanel          (NSString * title,
                                         NSString * msg,
                                         NSString * defaultButtonLabel,
                                         NSString * alternateButtonLabel,
                                         NSString * otherButtonLabel);

int            TBRunAlertPanelExtended  (NSString * title,
                                         NSString * msg,
                                         NSString * defaultButtonLabel,
                                         NSString * alternateButtonLabel,
                                         NSString * otherButtonLabel,
                                         NSString * doNotShowAgainPreferenceKey,
                                         NSString * checkboxLabel,
                                         BOOL     * checkboxResult,
										 int		notShownReturnValue);

int            TBRunAlertPanelExtendedPlus  (NSString * title,
                                             NSString * msg,
                                             NSString * defaultButtonLabel,
                                             NSString * alternateButtonLabel,
                                             NSString * otherButtonLabel,
                                             NSString * doNotShowAgainPreferenceKey,
											 NSArray  * checkboxLabels,
											 NSArray  * * checkboxResults,
                                             int		notShownReturnValue,
                                             id         shouldCancelTarget,
                                             SEL        shouldCancelSelector);

void           TBCloseAllAlertPanels    (void);

OSStatus       runOpenvpnstart          (NSArray  * arguments,
                                         NSString ** stdoutString,
                                         NSString ** stderrString);

BOOL           isUserAnAdmin            (void);

BOOL           runningABetaVersion      (void);

BOOL           displaysHaveDifferentSpaces(void);
BOOL           mustPlaceIconInStandardPositionInStatusBar(void);
BOOL           shouldPlaceIconInStandardPositionInStatusBar(void);

BOOL           runningOnSnowLeopardPointEightOrNewer(void);
BOOL           runningOnLionOrNewer(void);
BOOL           runningOnMountainLionOrNewer(void);
BOOL           runningOnMavericksOrNewer(void);
BOOL           runningOnYosemiteOrNewer(void);
BOOL           runningOnElCapitanOrNewer(void);
BOOL           runningOnSierraOrNewer(void);
BOOL           runningOnHighSierraOrNewer(void);

BOOL           tunnelblickTestPrivateOnlyHasTblks(void);
BOOL           tunnelblickTestAppInApplications(void);
BOOL           tunnelblickTestDeployed(void);
BOOL           tunnelblickTestHasDeployBackups(void);

OSStatus       MyGotoHelpPage           (NSString * pagePath,
                                         NSString * anchorName);
