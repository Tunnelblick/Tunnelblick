/*
 * Copyright 2005, 2006, 2007, 2008, 2009 Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020. All rights reserved.
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

NSString * rgbValues(BOOL foreground);

NSAttributedString * attributedLightDarkStringFromHTML(NSString * html);

NSAttributedString * attributedStringFromHTML(NSString * html);

void           appendLog				 (NSString * msg);

BOOL           appHasValidSignature(void);

NSString	 * base64Encode(NSData   * input);
NSData       * base64Decode(NSString * input);

uint64_t       nowAbsoluteNanoseconds    (void);

NSString     * configPathFromTblkPath   (NSString * path);
NSString     * tblkPathFromConfigPath   (NSString * path);
NSString     * configPathFromDisplayName(NSString * name);

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
BOOL displayNameIsValid(NSString * newName, BOOL doBeepOnError);

NSMutableString * encodeSlashesAndPeriods(NSString * s);

NSString     * stringForLog             (NSString * outputString,
                                         NSString * header);

NSString     * displayNameForOpenvpnName(NSString * openvpnName,
										 NSString * nameToReturnIfError);

NSString     * messageIfProblemInLogLine(NSString * line);

NSString     * firstPartOfPath          (NSString * thePath);
NSString     * lastPartOfPath           (NSString * thePath);
NSString     * displayNameFromPath      (NSString * thePath);
NSString     * firstPathComponent       (NSString * thePath);
NSString     * secureTblkPathForTblkPath(NSString * path);
NSString     * pathWithNumberSuffixIfItemExistsAtPath(NSString * path, BOOL includeCopyInNewName);
NSString     * tunnelblickVersion       (NSBundle * bundle);
NSString     * localizeNonLiteral        (NSString * status,
                                         NSString * type);
NSString	 * defaultOpenVpnFolderName	(void);

// from http://clang-analyzer.llvm.org/faq.html#unlocalized_string
__attribute__((annotate("returns_localized_nsstring")))
static inline NSString * LocalizationNotNeeded(NSString *s) {
	return s;
}

AlertWindowController * TBShowAlertWindow(NSString * title,
                                          id         msg); // NSString or NSAttributedString only

AlertWindowController * TBShowAlertWindowOnce(NSString * title,
                                              id         msg); // NSString or NSAttributedString only

AlertWindowController * TBShowAlertWindowExtended(NSString * title,
												  id				   msg, // NSString or NSAttributedString only
												  NSString			 * preferenceToSetTrue,
												  NSString			 * preferenceName,
												  id				   preferenceValue, // any object
												  NSString			 * checkboxTitle,
												  NSAttributedString * checkboxInfoTitle,
												  BOOL				   checkboxIsOn);

void TBShowAlertWindowClearCache(void);

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

BOOL           runningATunnelblickBeta  (void);

BOOL           displaysHaveDifferentSpaces(void);
BOOL           mustPlaceIconInStandardPositionInStatusBar(void);
BOOL           shouldPlaceIconInStandardPositionInStatusBar(void);

BOOL           runningOnMountainLionOrNewer(void);
BOOL           runningOnMavericksOrNewer(void);
BOOL           runningOnYosemiteOrNewer(void);
BOOL           runningOnElCapitanOrNewer(void);
BOOL           runningOnSierraOrNewer(void);
BOOL           runningOnHighSierraOrNewer(void);
BOOL           runningOnMojaveOrNewer(void);
BOOL           runningOnCatalinaOrNewer(void);
BOOL           runningOnBigSurOrNewer(void);
BOOL           runningOnTen_Fourteen_FiveOrNewer(void);

BOOL           runningOnMacosBeta(void);

BOOL           tunnelblickTestPrivateOnlyHasTblks(void);
BOOL           tunnelblickTestAppInApplications(void);
BOOL           tunnelblickTestDeployed(void);
BOOL           tunnelblickTestHasDeployBackups(void);
BOOL           localAuthenticationIsAvailable(void);

OSStatus       MyGotoHelpPage           (NSString * pagePath,
                                         NSString * anchorName);
