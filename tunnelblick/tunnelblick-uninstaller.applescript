------------------------------------------------------------------------------------------------------------------
--
--     This is the Uninstaller for Tunnelblick. It is compiled into an application.
--
--     Copyright © 2013, 2015, 2018 Jonathan K. Bullard. All rights reserved
--
--     This AppleScript is compiled into an application. The application includes the
--     'tunnelblick-uninstaller.sh' bash script. This AppleScript acts as a "front end" for that
--     bash script, which is invoked by this AppleScript "with authorization" so it runs as root.
--
--     The application may be double-clicked to uninstall /Applications/Tunnelblick.app, or
--     a Tunnelblick (or rebranded) application may be dropped on it.
--
------------------------------------------------------------------------------------------------------------------



------------------------------------------------------------------------------------------------------------------
-- LocalizedFormattedString: Function returns a localized string.
--
-- Inputs are a printf-style string, and an array of arguments
-- Use '%s' in the string for each argument
--
-- from http://www.tow.com/2006/10/12/applescript-stringwithformat
--
------------------------------------------------------------------------------------------------------------------
on LocalizedFormattedString(key_string, parameters) -- (String, Array) as String
	
	set cmd to "printf " & quoted form of (localized string key_string from table "Localizable")
	repeat with i from 1 to count parameters
		set cmd to cmd & space & quoted form of ((item i of parameters) as string)
	end repeat
	
	return do shell script cmd
	
end LocalizedFormattedString


------------------------------------------------------------------------------------------------------------------
-- FileOrFolderExists: Function returns true if a file or folder exists at a POSIX path
------------------------------------------------------------------------------------------------------------------
on FileOrFolderExists(theItem) -- (String) as Boolean
	
	tell application "System Events"
		if exists file theItem then
			return true
		else
			if exists folder theItem then
				return true
			else
				return false
			end if
		end if
	end tell
	
end FileOrFolderExists


------------------------------------------------------------------------------------------------------------------
-- FolderExists: Function returns true if a file or folder exists at a POSIX path
------------------------------------------------------------------------------------------------------------------
on FolderExists(myFolder) -- (String) as Boolean
	
	tell application "System Events"
		if exists folder myFolder then
			return true
		else
			return false
		end if
	end tell
	
end FolderExists


------------------------------------------------------------------------------------------------------------------
-- GetName: Function returns the name of the file in Contents/MacOS of an application at a POSIX path
------------------------------------------------------------------------------------------------------------------
--
-- Returns an empty string if there is not exactly one file in Contents/MacOS
on GetName(appPath) -- (String) as String
	
	set folderPath to appPath & "/Contents/MacOS"
	if FolderExists(folderPath) then
		tell application "Finder"
			set fileList to get name of files of folder (folderPath as POSIX file)
		end tell
		if (fileList count) = 1 then
			return item 1 of fileList
		end if
	end if
	
	return ""
	
end GetName


------------------------------------------------------------------------------------------------------------------
-- GetIdentifier: Function returns the CFBundleIdentifer from the Info.plist of an application at a POSIX path
------------------------------------------------------------------------------------------------------------------
--
-- Returns an empty string if there is no CFBundleIdentifier or the Info.plist does not exist
on GetIdentifier(appPath) -- (String) as String
	
	set infoPath to appPath & "/Contents/Info"
	try
		set defaultsOutput to do shell script "defaults read " & quoted form of infoPath & " CFBundleIdentifier"
	on error
		set defaultsOutput to ""
	end try
	
	return defaultsOutput
	
end GetIdentifier


------------------------------------------------------------------------------------------------------------------
-- RemoveDotApp: Returns a string with any ".app" extension removed
------------------------------------------------------------------------------------------------------------------
--
on RemoveDotApp(path) -- (String) as String
	
	set thePath to path as text
	set pLen to length of thePath
	if (pLen > 4) then
		set e to text (pLen - 3) through pLen of thePath
		if (e = ".app") then
			return text 1 through (pLen - 4) of thePath
		end if
	end if
	
	return path
end RemoveDotApp


------------------------------------------------------------------------------------------------------------------
-- GetLastPathComponentWithoutDotApp: Function returns the last component of the path after removing an optional ".app" extension
------------------------------------------------------------------------------------------------------------------
--
-- Returns an empty string if an error occurred, after displaying an error dialog to the user
on GetLastPathComponentWithoutDotApp(path) -- (String) as String
	
	set lastSlashIx to -1
	repeat with ix from 1 to count of path
		if item ix of path as string = "/" then
			set lastSlashIx to ix
		end if
	end repeat
	
	if (lastSlashIx = -1) then
		set lastSlashIx to 0
	end if
	
	set thePath to path as text
	set lastComponent to text (lastSlashIx + 1) through (length of thePath) of thePath
	return RemoveDotApp(lastComponent)
	
end GetLastPathComponentWithoutDotApp


------------------------------------------------------------------------------------------------------------------
-- ReplaceLastPathComponent: Function returns a path with the last component of the path replaced
------------------------------------------------------------------------------------------------------------------
--
-- Returns an empty string if an error occurred, after displaying an error dialog to the user
on ReplaceLastPathComponent(path, newLastComponent) -- (String,String) as String
	
	set lastColonIx to -1
	repeat with ix from 1 to count of path
		if item ix of path as string = ":" then
			set lastColonIx to ix
		end if
	end repeat
	
	if lastColonIx = -1 then
		display alert (localized string of "Tunnelblick Uninstaller FAILED") Â
			message LocalizedFormattedString("There is a problem. The path to this script (%s) does not contain any colons.\n\nPlease email developers@tunnelblick.net for help.", {path}) Â
			as critical
		return ""
	end if
	
	set thePath to path as text
	set containerPath to text (1) through (lastColonIx) of path
	return containerPath & newLastComponent
	
end ReplaceLastPathComponent


------------------------------------------------------------------------------------------------------------------
-- GetMyScriptPath: Function returns the path of the uninstall-tunnelblick.sh script
--
-- Returns an empty string if an error occurred, after displaying an error dialog to the user
------------------------------------------------------------------------------------------------------------------
on GetMyScriptPath() -- As POSIX path
	
	set myPath to path to me as text
	
	-- When running as an app, a ":" is at the end of the path, so we remove it
	if text (length of myPath) through (length of myPath) of myPath = ":" then
		set myPath to text 1 through ((length of myPath) - 1) of myPath
	end if
	
	-- Get last four characters of path to decide if being invoked from a .app or a .scpt/.applescript
	set lastFour to text ((length of myPath) - 3) through ((length of myPath)) of myPath
	
	-- Set myScriptPath
	if lastFour = ".app" then
		set myScriptPath to myPath & ":Contents:Resources:tunnelblick-uninstaller.sh"
	else
		set myScriptPath to ReplaceLastPathComponent(myPath, "tunnelblick-uninstaller.sh")
		if myScriptPath = "" then
			return ""
		end if
	end if
	
	-- Check that the script exists
	if FileOrFolderExists(myScriptPath) then
		return POSIX path of myScriptPath
	end if
	
	display alert (localized string of "Tunnelblick Uninstaller FAILED") Â
		message LocalizedFormattedString("There is a problem. The uninstaller shell script does not exist at %s.\n\nPlease email developers@tunnelblick.net for help.", {myScriptPath}) Â
		as critical
	return ""
	
end GetMyScriptPath


------------------------------------------------------------------------------------------------------------------
--NameToUninstall: function returns name of application to uninstall, or an empty string to cancel
------------------------------------------------------------------------------------------------------------------
on NameToUninstall(fullPath) -- (String) as String
	
	if FileOrFolderExists(fullPath) then
		-- Get the program name from the binary in /Contents/MacOS, or use the last path component
		-- And verify that this is a Tunnelblick app -- that is, that it contains openvpnstart
		set TBName to GetName(fullPath)
		if (TBName = "") Â
			or (not FileOrFolderExists(fullPath & "/Contents/Resources/openvpnstart")) then
			if (TBName = "") then
				set TBName to GetLastPathComponentWithoutDotApp(fullPath)
			end if
			set alertResult to display alert (localized string of "Tunnelblick Uninstaller") Â
				message LocalizedFormattedString("%s

is damaged (it does not include 'openvpnstart') or is not a Tunnelblick-based application.

Do you wish to continue, and try to uninstall items associated with '%s'?", {fullPath, TBName}) Â
				as critical Â
				buttons {localized string of "Continue", localized string of "Cancel"}
			if alertResult = {button returned:localized string of "Cancel"} then
				return ""
			end if
		end if
		return TBName
	else
		display alert (localized string of "Tunnelblick Uninstaller FAILED") Â
			message LocalizedFormattedString("Internal error: %s

does not exist or is not a folder", {fullPath}) Â
			as critical Â
			buttons {localized string of "OK"}
		return ""
	end if
	
end NameToUninstall


------------------------------------------------------------------------------------------------------------------
--IdentifierToUninstall: function returns CFBundleIdentifer to uninstall, or an empty string to cancel
------------------------------------------------------------------------------------------------------------------
on IdentifierToUninstall(fullPath, TBName) -- (String, String) as String
	
	if FileOrFolderExists(fullPath) then
		-- Get the CFBundleIdentifier from /Contents/Info.plist, or use net.tunnelblick.tunnelblick
		set TBIdentifier to GetIdentifier(fullPath)
		if (TBIdentifier = "") then
			set alertResult to display alert (localized string of "Tunnelblick Uninstaller") Â
				message LocalizedFormattedString("%s

is damaged (it does not have a 'CFBundleIdentifier') or not present.

Do you wish to continue, and try to uninstall items associated with '%s' and OS X identifier 'net.tunnelblick.tunnelblick'?", {fullPath, TBName}) Â
				as critical Â
				buttons {localized string of "Continue", localized string of "Cancel"}
			if alertResult = {button returned:localized string of "Cancel"} then
				return ""
			end if
			return "net.tunnelblick.tunnelblick"
		end if
		return TBIdentifier
	else
		display alert (localized string of "Tunnelblick Uninstaller FAILED") Â
			message LocalizedFormattedString("Internal error: %s

does not exist or is not a folder", {fullPath}) Â
			as critical Â
			buttons {localized string of "OK"}
		return ""
	end if
	
end IdentifierToUninstall




------------------------------------------------------------------------------------------------------------------
--IsAppRunning: function returns true if a user process with the specified name exists
------------------------------------------------------------------------------------------------------------------
on IsAppRunning(appName) -- (String) as Boolean
	
	tell application "System Events" to (name of processes) contains appName
end IsAppRunning


------------------------------------------------------------------------------------------------------------------
--QuitApplication: function returns true if there are no user processes named "openvpn" running.
--
--             Allows the user to retry after they quit any running OpenVPN processes.
------------------------------------------------------------------------------------------------------------------
on QuitApplication(applicationName) -- (String) as Boolean
	
	repeat while IsAppRunning(applicationName)
		set alertResult to display alert (localized string of "Tunnelblick Uninstaller") Â
			message (LocalizedFormattedString("%s cannot be uninstalled while it is running.

" & Â
			"Please disconnect all configurations, quit %s, and try again.

", Â
			{applicationName, applicationName})) Â
			as critical Â
			buttons {localized string of "Try again", localized string of "Cancel"}
		if alertResult = {button returned:localized string of "Cancel"} then
			return false
		end if
	end repeat
	
	return true
end QuitApplication


------------------------------------------------------------------------------------------------------------------
--IsOpenvpnRunning: function returns true if a process named 'openvpn*' exists
------------------------------------------------------------------------------------------------------------------
on IsOpenvpnRunning() -- () as Boolean
	
	try
		set psOutput to do shell script "ps -cA -o command | egrep -c '^openvpn$'"
	on error
		set psOutput to "0"
	end try
	
	return (psOutput ­ "0")
	
end IsOpenvpnRunning


------------------------------------------------------------------------------------------------------------------
--QuitOpenVPN: function returns true if there are no processes named "openvpn" running.
--
--             Allows the user to retry after they quit any running OpenVPN processes.
------------------------------------------------------------------------------------------------------------------
on QuitOpenVPN(TBName) -- (String) as Boolean
	
	repeat while IsOpenvpnRunning()
		set alertResult to display alert (localized string of "Tunnelblick Uninstaller") Â
			message (LocalizedFormattedString("%s cannot be uninstalled while OpenVPN is running.

" & Â
			"OpenVPN is running but %s is not. Probably a configuration is set to connect when the computer starts -- " & Â
			"such configurations are not disconnected when you quit %s.

" & Â
			"Please launch %s, disconnect all configurations, quit %s, and try again.

", Â
			{TBName, TBName, TBName, TBName, TBName})) Â
			as critical Â
			buttons {localized string of "Try again", localized string of "Cancel"}
		if alertResult = {button returned:localized string of "Cancel"} then
			return false
		end if
	end repeat
	
	return true
end QuitOpenVPN

------------------------------------------------------------------------------------------------------------------
-- UserConfirmation: function asks user what action to take and returns "cancel", "test", or "uninstall".
------------------------------------------------------------------------------------------------------------------
on UserConfirmation(fullPath, TBName, TBIdentifier) -- (String, String, String) as String
	
	if FileOrFolderExists(fullPath) then
		set alertResult to display alert (localized string of "Tunnelblick Uninstaller") Â
			message (LocalizedFormattedString("'%s'
	with OS X identifier '%s'
	at '%s'

	and all its configuration data, passwords, and " & Â
			"preferences for all users of this computer will be removed.

	" & Â
			"You will not be able to recover them afterward.

	" & Â
			"CLICK 'Test' to find out what would be removed in an actual uninstall

	" & Â
			"OR CLICK 'Uninstall' to uninstall %s

	" & Â
			"OR CLICK 'Cancel'.", Â
			{TBName, TBIdentifier, fullPath, TBName})) Â
			as critical Â
			buttons {localized string of "Uninstall", localized string of "Test", localized string of "Cancel"}
	else
		set alertResult to display alert (localized string of "Tunnelblick Uninstaller") Â
			message (LocalizedFormattedString("'%s'
	with OS X identifier '%s'

	and all its configuration data, passwords, and " & Â
			"preferences for all users of this computer will be removed.

	" & Â
			"You will not be able to recover them afterward.

	" & Â
			"CLICK 'Test' to find out what would be removed in an actual uninstall

	" & Â
			"OR CLICK 'Uninstall' to uninstall %s

	" & Â
			"OR CLICK 'Cancel'.", Â
			{TBName, TBIdentifier, TBName})) Â
			as critical Â
			buttons {localized string of "Uninstall", localized string of "Test", localized string of "Cancel"}
	end if
	
	if alertResult = {button returned:localized string of "Cancel"} then
		return "cancel"
	end if
	
	if alertResult = {button returned:localized string of "Test"} then
		return "test"
	end if
	
	return "uninstall"
end UserConfirmation

------------------------------------------------------------------------------------------------------------------
-- ProcessFile: Function uninstalls one Tunnelblick.app and displays results to the user
------------------------------------------------------------------------------------------------------------------
on DoProcessing(theName, theBundleId, thePath, testFlag, myScriptPath) -- (String, String, String, Boolean, String)
	
	-- Decide whether to use a "secure" erase or a normal erase. A "secure" erase writes over a file's data one or more times before deleting
	-- the file's directory entry.
	-- We want to do a "secure" erase on hard drives, but on SSDs we don't: it takes a lot more time and doesn't really do anything on an SSD
	-- because of the way SSDs work.

	set ssdDetectionErrorMessage to ""

	-- Try to use the "bless" command to get the boot volume's ID. This fails on some Hackintoshes and in some other situations where the NVRAM is corrupt.
	try
		set blessOutput to do shell script "bless --info --getboot"
	on error  errorMessage number errorNumber
		set blessOutput to ""
		set ssdDetectionErrorMessage to "The uninstaller could not determine whether the boot volume is an SSD or an HDD, which can happen on Hackintoshes and on systems with corrupt NVRAM.
Because of this, 'secure' erase will be used (files will be overwritten before they are deleted), which will take a long time.
The error message from 'bless --info --getboot' was '" & errorMessage & "'.

"
	end try
	
	if blessOutput = "" then
		set secureEraseOption to "-s"
	else
		-- Ignore errors by executing "true" command at end (if grep does not find string, it returns an error)
		set diskutilOutput to do shell script "diskutil info '" & blessOutput & "' | grep 'Solid State:' | grep 'Yes' ; true"
		if diskutilOutput = "" then
			set secureEraseOption to "-s"
		else
			set secureEraseOption to "-i"
		end if
	end if
	
	if testFlag then

		set dialogContents to LocalizedFormattedString("Although a window will ask for authorization from a computer administrator and say \"%s Uninstaller wants to make changes\", NO CHANGES WILL BE MADE.

The uninstaller needs administrator authorization so it can read the %s preferences of other users.", { theName, theName })

	else
		if secureEraseOption = "-s" then

			set dialogContents to LocalizedFormattedString("A window will ask for authorization from a computer administrator.

The uninstaller needs the authorization so it can make the changes required to uninstall %s.

Uninstalling may take SEVERAL MINUTES because files will be overwritten before being deleted.

While the uninstall is being done there will be no indication that anything is happening. Please be patient; a window will appear when the uninstall is complete.", {theName})

		else
			set dialogContents to LocalizedFormattedString("A window will ask for authorization from a computer administrator.
		
The uninstaller needs the authorization so it can make the changes required to uninstall %s.

While the uninstall is being done there will be no indication that anything is happening. Please be patient; a window will appear when the uninstall is complete.", {theName})
		
		end if
	end if
	
	set osMajor to system attribute "sys1"
	if osMajor ­ 10 then
		display alert "Not OS version 10."
	end if
	set osMinor to system attribute "sys2"
	if osMinor > 13 then
		set mojaveMessage to LocalizedFormattedString("
		
		macOS Mojave will pop up three warning boxes, saying that the uninstaller wants access to control Finder and System Events and to access your contacts. Although it does control Finder and System Events to remove files and folders related to %s, the warning box about contacts is incorrect: THE UNINSTALLER DOES NOT ACCESS YOUR CONTACTS. For more information see https://tunnelblick.net/cUninstall.html#uninstalling-on-macos-mojave.", { theName })
	else
		set mojaveMessage to ""
	end if

	try
		set alertResult to display dialog dialogContents & mojaveMessage
	on error  errorMessage number errorNumber
		set alertResult to "Cancelled"
		if errorNumber ­ -128 then
			display dialog "DoProcessing(): Error #" & errorNumber & " occurred: " & errorMessage
		end if
	end try

	if alertResult = "Cancelled" then
		return
	end if
	
	-- Start the uninstaller script, using the -t or -u option as directed by the user
	if testFlag then
		set argumentString to " " & secureEraseOption & " -t " & quoted form of theName & " " & quoted form of theBundleId
	else
		set argumentString to " " & secureEraseOption & " -u " & quoted form of theName & " " & quoted form of theBundleId
	end if
	if FileOrFolderExists(thePath) then
		set argumentString to argumentString & " " & quoted form of thePath
	end if

	try
		set scriptOutput to do shell script (quoted form of myScriptPath) & argumentString with administrator privileges
	on error errorMessage number errorNumber
		if errorNumber ­ -128 then
			display alert "Error in shell script: " & (quoted form of myScriptPath) & argumentString & "with administrator privileges.\n\nPlease email developers@tunnelblick.net for help."
		end if
		return
	end try

	-- If SSD detection failed, prepend a message about that to the script output
	if (ssdDetectionErrorMessage ­ "") then
		set scriptOutput to ssdDetectionErrorMessage & scriptOutput
	end if
	
	-- Inform the user about errors (indicated by "Error: " or "Problem: " anywhere in the shell script's stdout)
	-- and successful tests or uninstalls

	-- Set timeout to 10,000 hours, so the dialog never times out
	set timeoutValue to 60*60*100000

	activate me

	if (scriptOutput contains "Problem: ") Â
		or (scriptOutput contains "Error: ") then
		if testFlag then
			set alertResult to display dialog Â
				LocalizedFormattedString("One or more errors occurred during the %s uninstall test.", {theName}) Â
				with title (localized string of "Tunnelblick Uninstaller TEST FAILED") Â
				with icon stop Â
				buttons {localized string of "Details", localized string of "OK"} Â
				giving up after timeoutValue
		else
			set alertResult to display dialog Â
				LocalizedFormattedString("One or more errors occurred while uninstalling %s.", {theName}) Â
				with title (localized string of "Tunnelblick Uninstaller FAILED") Â
				with icon  stop Â
				buttons {localized string of "Details", localized string of "OK"} Â
				giving up after timeoutValue
		end if

	else
		if testFlag then
			set alertResult to display dialog Â
				LocalizedFormattedString("The %s uninstall test succeeded.", {theName}) Â
				with title (localized string of "Tunnelblick Uninstall test succeeded") Â
				buttons {localized string of "Details", localized string of "OK"} Â
				giving up after timeoutValue
		else
			set alertResult to display dialog Â
				LocalizedFormattedString("%s was uninstalled successfully", {theName}) Â
				with title (localized string of "Tunnelblick was Uninstalled") Â
				buttons {localized string of "Details", localized string of "OK"} Â
				giving up after timeoutValue
		end if
	end if

-- If the user asked for details, open the log in TextEdit
	if the button returned of alertResult = localized string of "Details" then
		tell application "TextEdit"
			activate
			set the clipboard to scriptOutput
			make new document
			tell front document to set its text to the clipboard
		end tell
	end if
	
end DoProcessing


------------------------------------------------------------------------------------------------------------------
-- ProcessFile: Function uninstalls one Tunnelblick.app and displays results to the user
------------------------------------------------------------------------------------------------------------------
on ProcessFile(fullPath) -- (POSIX path)
	
	if FileOrFolderExists(fullPath) then
		set TBName to NameToUninstall(fullPath)
		if TBName = "" then
			return
		end if
		
		set TBIdentifier to IdentifierToUninstall(fullPath, TBName)
		if TBIdentifier = "" then
			return
		end if
	else
		set TBName to "Tunnelblick"
		set TBIdentifier to "net.tunnelblick.tunnelblick"
	end if
	
	if not QuitApplication(TBName) then
		return
	end if
	
	if not QuitOpenVPN(TBName) then
		return
	end if
	
	try
		set confirmString to UserConfirmation(fullPath, TBName, TBIdentifier)
	on error errorMessage number errorNumber
		display alert "Error in UserConfirmation(): '" & errorMessage & "' (" & errorNumber & ")\n\nPlease email developers@tunnelblick.net for help."
		return
	end try
	if confirmString = "cancel" then
		return
	end if
	if confirmString = "test" then
		set testFlag to true
	else
		if confirmString = "uninstall" then
			set testFlag to false
		else
			try
				display alert (localized string of "Tunnelblick Uninstaller TEST FAILED") Â
					message LocalizedFormattedString("An internal error occurred: UserConfirmation('%s','%s','%s') returned '%s'.\n\nPlease email developers@tunnelblick.net for help.", {fullPath, TBName, TBIdentifier, confirmString}) Â
					as critical Â
					buttons {localized string of "OK"}
			on error errorMessage number errorNumber
				display alert "Error in ProcessFile(): '" & errorMessage & "' (" & errorNumber & ")\n\nPlease email developers@tunnelblick.net for help."
				return
			end try
			return
		end if
	end if
	
	set scriptPath to GetMyScriptPath()
	if scriptPath = "" then
		return
	end if

	try
		DoProcessing(TBName, TBIdentifier, fullPath, testFlag, scriptPath)
	on error errorMessage number errorNumber
		display alert "Error in DoProcessing(): '" & errorMessage & "' (" & errorNumber & ")\n\nPlease email developers@tunnelblick.net for help."
	end try

end ProcessFile


------------------------------------------------------------------------------------------------------------------
-- Process a single file dropped onto this app
--
-- This routine is invoked by Finder BEFORE the main script is executed (below), when a file or folder is dropped onto this app.
-- It sets 'filesWereDropped' to indicate that files were dropped and processed, and that the main script shouldn't do anything.
------------------------------------------------------------------------------------------------------------------
on open theFileList
	set filesWereDropped to true
	if (count theFileList) = 1 then
		
		set pathWithTrailingSlash to POSIX path of (item 1 of theFileList)
		
		-- Verify that the path ends in ".app/"; complain and exit if it doesn't
		set fpLen to length of pathWithTrailingSlash
		if (fpLen < 6) or Â
			((text (fpLen - 4) through fpLen of pathWithTrailingSlash) ­ ".app/") then
			display alert (localized string of "Tunnelblick Uninstaller") Â
				message (LocalizedFormattedString("Only Tunnelblick or rebranded Tunnelblick applications may be uninstalled.

'%s'

is not an application", pathWithTrailingSlash)) Â
				as critical Â
				buttons {localized string of "Cancel"}
			return
		end if
		
		set pathWithoutTrailingSlash to text 1 through (fpLen - 1) of pathWithTrailingSlash
		
		if FileOrFolderExists(pathWithoutTrailingSlash) then
			ProcessFile(pathWithoutTrailingSlash)
		else
			display alert (localized string of "Tunnelblick Uninstaller") Â
				message (LocalizedFormattedString("Only Tunnelblick or rebranded Tunnelblick applications may be uninstalled.

'%s'

is not an application (not a folder)", pathWithTrailingSlash)) Â
				as critical Â
				buttons {localized string of "Cancel"}
		end if
	else
		display alert (localized string of "Tunnelblick Uninstaller") Â
			message (localized string of "Please drop only one Tunnelblick or rebranded Tunnelblick application at a time onto this uninstaller.") Â
			as critical Â
			buttons {localized string of "Cancel"}
	end if
end open

------------------------------------------------------------------------------------------------------------------
-- Start of script: If no file was dropped, uninstall /Applications/Tunnelblick.app
------------------------------------------------------------------------------------------------------------------

activate

set IsDefined to true
try
	get filesWereDropped
on error
	set IsDefined to false
end try

if not IsDefined then
	try
		ProcessFile(POSIX path of "/Applications/Tunnelblick.app")
	on error errorMessage number errorNumber
		display alert "Error in ProcessFile(): '" & errorMessage & "' (" & errorNumber & ")\n\nPlease email developers@tunnelblick.net for help."
	end try
end if
