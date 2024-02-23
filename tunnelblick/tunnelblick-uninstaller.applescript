------------------------------------------------------------------------------------------------------------------
--
--     This is the Uninstaller for Tunnelblick. It is compiled into an application.
--
--     Copyright © 2013, 2015, 2018, 2020 Jonathan K. Bullard. All rights reserved
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
			message LocalizedFormattedString("There is a problem. The path to this script (%s) does not contain any colons.\n\nPlease see https://tunnelblick.net/e1", {path}) Â
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
		message LocalizedFormattedString("There is a problem. The uninstaller shell script does not exist at %s.\n\nPlease see https://tunnelblick.net/e1", Â
										 {myScriptPath}) Â
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
				message LocalizedFormattedString("%s\n\nis damaged (it does not include 'openvpnstart') or is not a Tunnelblick-based application.\n\nDo you wish to continue, and try to uninstall items associated with '%s'?", Â
												 {fullPath, TBName}) Â
				as critical Â
				buttons {localized string of "Continue", localized string of "Cancel"}
			if alertResult = {button returned:localized string of "Cancel"} then
				return ""
			end if
		end if
		return TBName
	else
		display alert (localized string of "Tunnelblick Uninstaller FAILED") Â
			message LocalizedFormattedString("Internal error: %s\n\ndoes not exist or is not a folder", {fullPath}) Â
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
				message LocalizedFormattedString("%s\n\nis damaged (it does not have a 'CFBundleIdentifier') or not present.\n\nDo you wish to continue, and try to uninstall items associated with '%s' and macOS identifier 'net.tunnelblick.tunnelblick'?", Â
												 {fullPath, TBName}) Â
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
			message LocalizedFormattedString("Internal error: %s\n\ndoes not exist or is not a folder", {fullPath}) Â
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
			message (LocalizedFormattedString("%s cannot be uninstalled while it is running.\n\n" & Â
											  "Please disconnect all configurations, quit %s, and try again.\n\n", Â
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
			message (LocalizedFormattedString("%s cannot be uninstalled while OpenVPN is running.\n\n" & Â
											  "OpenVPN is running but %s is not. Probably a configuration is set to connect when the computer starts -- " & Â
											  "such configurations are not disconnected when you quit %s.\n\n" & Â
											  "Please launch %s, disconnect all configurations, quit %s, and try again.\n\n", Â
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
			message (LocalizedFormattedString("'%s'\nwith macOS identifier '%s'\nat '%s'\n\n" & Â
											  "and all its configuration data, passwords, and preferences for all users of this computer will be removed.\n\n" & Â
											  "You will not be able to recover them afterward.\n\n" & Â
											  "CLICK 'Test' to find out what would be removed in an actual uninstall\n\n" & Â
											  "OR CLICK 'Uninstall' to uninstall %s\n\n" & Â
											  "OR CLICK 'Cancel'.", Â
											  {TBName, TBIdentifier, fullPath, TBName})) Â
			as critical Â
			buttons {localized string of "Uninstall", localized string of "Test", localized string of "Cancel"}
	else
		set alertResult to display alert (localized string of "Tunnelblick Uninstaller") Â
		message (LocalizedFormattedString("'%s'\nwith macOS identifier '%s'\n\nand all its configuration data, passwords, and preferences for all users of this computer will be removed.\n\n" & Â
										  "You will not be able to recover them afterward.\n\n" & Â
										  "CLICK 'Test' to find out what would be removed in an actual uninstall\n\n" & Â
										  "OR CLICK 'Uninstall' to uninstall %s\n\n" & Â
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
-- WriteTextToFile: Function writes text to a file
--
-- Adapted from https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/ReadandWriteFiles.html
------------------------------------------------------------------------------------------------------------------
on WriteTextToFile(theText, theFile)
    try

        -- Convert the file to a string
        set theFile to theFile as string

        -- Open the file for writing
        set theOpenedFile to open for access file theFile with write permission

        -- Clear the file
        set eof of theOpenedFile to 0

        -- Write the new content to the file
        write theText to theOpenedFile starting at eof

        -- Close the file
        close access theOpenedFile

        -- Return a boolean indicating that writing was successful
        return true

    -- Handle a write error
    on error errorMessage number errorNumber

        -- Close the file
        try
            close access file theFile
        end try

        display alert "Error " & errorNumber &  " (" & errorMessage & ") writing to /tmp/UninstallDetails.txt\n\nPlease see https://tunnelblick.net/e1"
        return false
    end try
end WriteTextToFile



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
	on error errorMessage number errorNumber
		set blessOutput to ""
		set ssdDetectionErrorMessage to "The uninstaller could not determine whether the boot volume is an SSD or an HDD, which can happen on Hackintoshes and on systems with corrupt NVRAM.\n\nBecause of this, 'secure' erase will be used (files will be overwritten before they are deleted), which will take a long time.\n\nThe error message from 'bless --info --getboot' was '" & errorMessage & "'.\n\n"
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

    if myScriptPath = "/Applications/Tunnelblick.app/Contents/Resources/tunnelblick-uninstaller.sh" then
        set osascriptMessage to localized string of "\n\nThe authorization request will be made by the macOS program 'osascript' because that program is being used to run the uninstaller."
    else
        set osascriptMessage to ""
    end if

    if testFlag then
		
		display dialog LocalizedFormattedString("Although the next window will ask for a one-time authorization from a computer administrator and say \"%s Uninstaller wants to make changes\",\n\nNO CHANGES WILL BE MADE; the authorization is needed to read the %s preferences of other users.%s", Â
												{theName, theName, osascriptMessage})
		
	else
		if secureEraseOption = "-s" then
			
			display dialog LocalizedFormattedString("The next window will ask for a one-time authorization from a computer administrator.\n\nThe authorization is needed to make the changes required to uninstall %s.%s\n\nUninstalling may take SEVERAL MINUTES because files will be overwritten before being deleted.\n\nWhile the uninstall is being done there will be no indication that anything is happening. Please be patient; a window will appear when the uninstall is complete.", Â
													{theName, osascriptMessage})
			
		else
			display dialog LocalizedFormattedString("The next window will ask for a one-time authorization from a computer administrator.\n\nThe authorization is needed to make the changes required to uninstall %s.%s\n\nWhile the uninstall is being done there will be no indication that anything is happening. Please be patient; a window will appear when the uninstall is complete.", Â
													{theName, osascriptMessage})
			
		end if
	end if

    if myScriptPath = "/Applications/Tunnelblick.app/Contents/Resources/tunnelblick-uninstaller.sh" then
        set uninstallingFromWithinTunnelblick to true
    else
        set uninstallingFromWithinTunnelblick to false
    end if

	-- Prepare arguments for the uninstaller script
    -- Use the -t or -u option as directed by the user.
    -- If the script is located inside of Tunnelblick.app, use the -a and -i options
    --    * Use the -a option to allow the script to run while Tunnelblick is running.
    --    * Use the -i option to force the script to use the 'rm' command without the '-P' option, so it will only unlink the file. That's necessary
    --      because if the -P option is used an error with code 2 occurs when Tunnelblick.app is erased.
    if testFlag then
        set executionOption to " -t "
    else
        set executionOption to " -u "
    end if
    if uninstallingFromWithinTunnelblick then
        set allowTunnelblickToBeRunningOption to " -a "
        set secureEraseOption to " -i  "
    else
        set allowTunnelblickToBeRunningOption to " "
    end if

 	set argumentString to allowTunnelblickToBeRunningOption & secureEraseOption & executionOption & quoted form of theName & " " & quoted form of theBundleId
	if FileOrFolderExists(thePath) then
		set argumentString to argumentString & " " & quoted form of thePath
	end if
	
	try
		set scriptOutput to do shell script (quoted form of myScriptPath) & argumentString with administrator privileges
	on error errorMessage number errorNumber
        if errorNumber ­ -128 then
            display alert "Error " & errorNumber &  " (" & errorMessage & ") in shell script: " & (quoted form of myScriptPath) & argumentString & " with administrator privileges.\n\nPlease see https://tunnelblick.net/e1"
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
	set timeoutValue to 60 * 60 * 100000
	
	activate me
	
    if (scriptOutput contains "Problem: ") Â
    or (scriptOutput contains "Error: ") then
        set failed to true
    else
        set failed to false
    end if

    if failed then
        if testFlag then
            set theMessage to LocalizedFormattedString("The test of uninstalling %s FAILED.", {theName})
        else
            set theMessage to LocalizedFormattedString("Uninstall of %s FAILED.", {theName})
        end if
    else
        if testFlag then
            set theMessage to LocalizedFormattedString("The test of uninstalling %s succeeded.", {theName})
        else
            set theMessage   to LocalizedFormattedString("%s was uninstalled.", {theName})
        end if
    end if

    -- If uninstalling from within Tunnelblick, store the script output in a file and tell user to see details in the Console log.
    -- (The Tunnelblick application that invoked this script will put the contents of the file into the system log and delete the file.)
    if uninstallingFromWithinTunnelblick then
        WriteTextToFile(scriptOutput, posix file "/tmp/UninstallDetails.txt")
        set theButtons to {localized string of "OK"}
        set theMessage to theMessage & "\n\nSee the Console Log for details."
    else
        set theButtons  to {localized string of "Details", localized string of "OK"}
    end if

    if failed then
        set alertResult to display dialog theMessage with title theName buttons theButtons giving up after timeoutValue with icon stop
    else
        set alertResult to display dialog theMessage with title theName buttons theButtons giving up after timeoutValue
    end if

	-- If the user asked for details, open the log in TextEdit
	if the button returned of alertResult = (localized string of "Details") then
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
	
    set scriptPath to GetMyScriptPath()

    if scriptPath = "" then
        return
    end if
    
    if scriptPath ­ "/Applications/Tunnelblick.app/Contents/Resources/tunnelblick-uninstaller.sh" then
        if not QuitApplication(TBName) then
            return
        end if
	end if
	
	if not QuitOpenVPN(TBName) then
		return
	end if
	
	try
		set confirmString to UserConfirmation(fullPath, TBName, TBIdentifier)
	on error errorMessage number errorNumber
		display alert "Error in UserConfirmation(): '" & errorMessage & "' (" & errorNumber & ")\n\nPlease see https://tunnelblick.net/e1"
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
					message LocalizedFormattedString("An internal error occurred: UserConfirmation('%s','%s','%s') returned '%s'.\n\nPlease see https://tunnelblick.net/e1", {fullPath, TBName, TBIdentifier, confirmString}) Â
					as critical Â
					buttons {localized string of "OK"}
			on error errorMessage number errorNumber
				display alert "Error in ProcessFile(): '" & errorMessage & "' (" & errorNumber & ")\n\nPlease see https://tunnelblick.net/e1"
				return
			end try
			return
		end if
	end if
	
	try
		DoProcessing(TBName, TBIdentifier, fullPath, testFlag, scriptPath)
	on error errorMessage number errorNumber
        if errorNumber ­ -128 then
            display alert "Error in DoProcessing(): '" & errorMessage & "' (" & errorNumber & ")\n\nPlease see https://tunnelblick.net/e1"
        end if
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
		if (fpLen < 6) Â
		or ((text (fpLen - 4) through fpLen of pathWithTrailingSlash) ­ ".app/") then
			display alert (localized string of "Tunnelblick Uninstaller") Â
				message (LocalizedFormattedString("Only Tunnelblick or rebranded Tunnelblick applications may be uninstalled.\n\n'%s'\n\nis not an application", pathWithTrailingSlash)) Â
				as critical Â
				buttons {localized string of "Cancel"}
			return
		end if
		
		set pathWithoutTrailingSlash to text 1 through (fpLen - 1) of pathWithTrailingSlash
		
		if FileOrFolderExists(pathWithoutTrailingSlash) then
			ProcessFile(pathWithoutTrailingSlash)
		else
			display alert (localized string of "Tunnelblick Uninstaller") Â
				message (LocalizedFormattedString("Only Tunnelblick or rebranded Tunnelblick applications may be uninstalled.\n\n'%s'\n\nis not an application (not a folder)", pathWithTrailingSlash)) Â
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
        if errorNumber ­ -128 then
            display alert "Error in ProcessFile(): '" & errorMessage & "' (" & errorNumber & ")\n\nPlease see https://tunnelblick.net/e1"
        end if
	end try
end if
