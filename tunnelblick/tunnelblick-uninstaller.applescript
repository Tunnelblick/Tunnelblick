------------------------------------------------------------------------------------------------------------------
--
--     This is the Uninstaller script for Tunnelblick. It is compiled into an application.
--
--     It may be double-clicked (which will uninstall /Applications/Tunnelblick.app), or accepts an
--     application dropped on it. After doing minimal sanity checking, the 'tunnelblick-uninstaller.sh'
--     bash script is invoked with authorization to do the actual uninstall.
--
--     Copyright © 2013 Jonathan K. Bullard. All rights reserved
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
on LocalizedFormattedString(key_string, parameters)
	
	set cmd to "printf " & quoted form of (localized string key_string from table "Localizable")
	repeat with i from 1 to count parameters
		set cmd to cmd & space & quoted form of ((item i of parameters) as string)
	end repeat
	
	return do shell script cmd
	
end LocalizedFormattedString


------------------------------------------------------------------------------------------------------------------
-- FileExists: Function returns true if a file or folder exists at a POSIX path
------------------------------------------------------------------------------------------------------------------
on FileExists(myFile) -- (String) as Boolean
	
	tell application "System Events"
		if exists file myFile then
			return true
		else
			return false
		end if
	end tell
	
end FileExists


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
-- ChangeLastPathComponent: Function returns a path with the last component of the path replaced
------------------------------------------------------------------------------------------------------------------
--
-- Returns an empty string if an error occurred, after displaying an error dialog to the user
on ChangeLastPathComponent(path, newLastComponent) -- (String) as Boolean
	
	set lastColonIx to -1
	repeat with ix from 1 to count of path
		if item ix of path as string = ":" then
			set lastColonIx to ix
		end if
	end repeat
	
	if lastColonIx = -1 then
		display alert (localized string of "Uninstall failed") Â
    		message LocalizedFormattedString("There is a problem. The path to this script (%s) does not contain any colons", {path}) Â
    		as critical
		return ""
	end if
	
	set thePath to path as text
	set containerPath to text (1) through (lastColonIx) of path
	return containerPath & newLastComponent
	
end ChangeLastPathComponent


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
		set myScriptPath to ChangeLastPathComponent(myPath, "tunnelblick-uninstaller.sh")
		if myScriptPath = "" then
			return ""
		end if
	end if
	
	-- Check that the script exists
	if FileExists(myScriptPath) then
		return POSIX path of myScriptPath
	end if
	
	display alert (localized string of "Uninstall failed") Â
    	message LocalizedFormattedString("There is a problem. The uninstaller shell script does not exist at %s", {myScriptPath}) Â
    	as critical
	return ""
	
end GetMyScriptPath


------------------------------------------------------------------------------------------------------------------
-- ProcessFile: Function uninstalls one Tunnelblick.app and displays results to the user
------------------------------------------------------------------------------------------------------------------
on ProcessFile(fullPath, myScriptPath) -- (POSIX path, POSIX path)
	
	-- Remove ".app/" or final "/" from what we display
	set displayPath to text 1 through ((length of fullPath) - 5) of fullPath
	set fullPathWithoutFinalSlash to text 1 through ((length of fullPath) - 1) of fullPath

	-- Do some quick sanity checks
	
	if ((fullPath = "/Applications/Tunnelblick.app/") Â
		and (not FileExists(fullPath))) then
		display alert ((localized string of "Uninstall failed")) Â
			message LocalizedFormattedString("There is no application named 'Tunnelblick' in %s (/Applications).\n\nTo uninstall a Tunnelblick-based application, drag and drop it onto the uninstaller.", {"Applications"}) Â
			as critical Â
			buttons {localized string of "OK"}
		return
	end if
	
	if (not FileExists(fullPath)) then
		display alert (localized string of "Uninstall failed") Â
			message LocalizedFormattedString("%s\n\ndoes not exist.\n\nTo uninstall a Tunnelblick-based application, drag and drop it onto the uninstaller, or double-click the installer to uninstall /Applications/Tunnelblick.", {fullPathWithoutFinalSlash}) Â
			as critical Â
			buttons {localized string of "OK"}
		return
	end if
	
	-- Get the program name from the binary in /Contents/MacOS
	-- See if this is a Tunnelblick app -- that is, that it contains openvpnstart
	set TBName to GetName(fullPath)
	if (TBName = "") Â
        or (not FileExists(fullPath & "Contents/Resources/openvpnstart")) then
		set alertResult to display alert LocalizedFormattedString("Uninstall %s?", {TBName}) Â
			message LocalizedFormattedString("%s\n\nis damaged or is not a Tunnelblick-based application.\n\nDo you wish to use the Tunnelblick Uninstaller to try to uninstall it?", {fullPathWithoutFinalSlash}) Â
			as critical Â
			buttons {localized string of "Continue", localized string of "Cancel"}
	    if alertResult = {button returned: localized string of "Cancel"} then
		    return
	    end if
	end if
	
	-- Confirm that the user wants to proceed, and whether to uninstall or to test
	set alertResult to display alert LocalizedFormattedString("Uninstall %s?", {TBName}) Â
		message (LocalizedFormattedString("The program at\n\n%s\n\nand all its configuration data, passwords, and preferences for all users of this computer will be removed.\n\n" & Â
			"You will not be able to recover them afterward.\n\n" & Â
			"CLICK 'Test' to find out what would be removed in an actual uninstall\n\n" & Â
			"OR CLICK 'Uninstall' to uninstall %s\n\n" & Â
			"OR CLICK 'Cancel' and drop a different %s application on the uninstaller.\n\n" & Â
			"Testing or uninstalling may take a long time -- up to several MINUTES -- during which time there will be no indication that anything is happening. Please be patient; a window will appear when the uninstall or test is complete.", Â
			{displayPath, TBName, TBName})) Â
		as critical  Â
		buttons {localized string of "Uninstall", localized string of "Test", localized string of "Cancel"}
	
	if alertResult = {button returned: localized string of "Cancel"} then
		return
	end if
	
	if alertResult = {button returned: localized string of "Test"} then
		display dialog LocalizedFormattedString("Although the next window will ask for a computer administrator username and password and say \"Tunnelblick Uninstaller wants to make changes\", no changes will be made.\n\nThe uninstaller needs \"root\" access so it can read the %s preferences of other users.", {TBName})
	else
		display dialog LocalizedFormattedString("The next window will ask for a computer administrator username and password.\n\nThe uninstaller needs \"root\" access so it can make the changes required to uninstall %s.", {TBName})
	end if
	
	-- Start the uninstaller script, using the -i option to force a non-error status even if there are errors, and the -t or -u option as directed by the user
	if alertResult = {button returned:localized string of "Uninstall"} then
		set doUninstall to true
		set arguments to " -i -u " & quoted form of fullPathWithoutFinalSlash & " " & quoted form of TBName
	else
		set doUninstall to false
		set arguments to " -i -t " & quoted form of fullPathWithoutFinalSlash & " " & quoted form of TBName
	end if
	set scriptOutput to do shell script (quoted form of myScriptPath) & arguments with administrator privileges
	
	-- Inform the user about errors (indicated by "Error: " or "Problem removing " anywhere in the shell script's stdout)
	-- and successful tests or uninstalls
	if    (scriptOutput contains "Problem removing ") Â
	   or (scriptOutput contains "Error: ") then
        if doUninstall then
            set alertResult to display alert (localized string of "Uninstall failed") Â
                message LocalizedFormattedString("One or more errors occurred while uninstalling %s.", {TBName}) Â
                as critical Â
                buttons {localized string of "Details", localized string of "OK"}
        else
            set alertResult to display alert (localized string of "Uninstall failed") Â
                message LocalizedFormattedString("One or more errors occurred during the %s uninstall test.", {TBName}) Â
                as critical Â
                buttons {localized string of "Details", localized string of "OK"}
        end if


	else
		if doUninstall then
			set alertResult to display dialog LocalizedFormattedString("%s was uninstalled successfully", {TBName}) Â
				buttons {localized string of "Details", localized string of "OK"}
		else
			set alertResult to display dialog LocalizedFormattedString("The %s uninstall test succeeded.", {TBName}) Â
				buttons {localized string of "Details", localized string of "OK"}
		end if
	end if
	
	-- If the user asked for details, store the log in /tmp and open the log in TextEdit
	if alertResult = {button returned: localized string of "Details"} then
		tell application "TextEdit"
			activate
			set the clipboard to scriptOutput
			make new document
			tell front document to set its text to the clipboard
		end tell
	end if
	
end ProcessFile


------------------------------------------------------------------------------------------------------------------
-- Process a single file dropped onto this app
------------------------------------------------------------------------------------------------------------------
on open theFileList
	set filesWereDropped to true
	if (count theFileList) = 1 then
		set scriptPath to GetMyScriptPath()
		if scriptPath ­ "" then
			ProcessFile(POSIX path of (item 1 of theFileList), GetMyScriptPath())
		end if
	else
		display alert (localized string of "Uninstall failed") Â
			message (localized string of "Please drop only one application at a time onto this uninstaller.") Â
			as critical Â
			buttons {localized string of "Details", localized string of "OK"}
	end if
end open

------------------------------------------------------------------------------------------------------------------
-- Start of script: If no file was dropped, uninstall /Applications/Tunnelblick.apph
------------------------------------------------------------------------------------------------------------------

set IsDefined to true
try
	get filesWereDropped
on error
	set IsDefined to false
end try

if not IsDefined then
	set scriptPath to GetMyScriptPath()
	if scriptPath ­ "" then
		ProcessFile(POSIX path of "/Applications/Tunnelblick.app/", GetMyScriptPath())
	end if
end if
