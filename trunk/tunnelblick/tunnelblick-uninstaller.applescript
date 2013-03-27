------------------------------------------------------------------------------------------------------------------
--
--     This is the Uninstaller script for Tunnelblick. It is compiled into an application, which is put
--     on the disk image and can be run directly from there.
--
--     It may be double-clicked (which will uninstall /Applications/Tunnelblick.app), or accepts an
--     application dropped it. After doing minimal sanity checking, the 'tunnelblick-uninstaller.sh'
--     bash script is invoked with authorization to do the actual uninstall.
--
--     Copyright © 2013 Jonathan K. Bullard. All rights reserved
--
------------------------------------------------------------------------------------------------------------------


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
-- GetName: Function returns the name of the binary of an application at a POSIX path
------------------------------------------------------------------------------------------------------------------
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
-- GetMyScriptPath: Function returns the path of the uninstall-tunnelblick.sh script
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
		set myScriptPath to "/Users/Shared/TunnelblickReleasePrep/r2207z-Built-Uninstall-AppleScript/tunnelblick/tunnelblick-uninstaller.sh"
	end if
	
	-- Check that the script exists
	if FileExists(myScriptPath) then
		return POSIX path of myScriptPath
	end if
	
	display dialog ("There is a problem. The uninstaller shell script does not exist:" & return & myScriptPath)
	tell me to quit
	
end GetMyScriptPath


------------------------------------------------------------------------------------------------------------------
-- ProcessFile: Function uninstalls one Tunnelblick.app and displays results to the user
------------------------------------------------------------------------------------------------------------------
on ProcessFile(fullPath, myScriptPath) -- (POSIX path, POSIX path)
	
	-- Do some quick sanity checks
	if ((length of fullPath) < 6) Â
		or (text ((length of fullPath) - 4) through (length of fullPath) of fullPath ­ ".app/") Â
		or (not FileExists(fullPath)) Â
		or ((not FileExists(fullPath & "Contents/Resources/openvpn")) and (not FolderExists(fullPath & "Contents/Resources/openvpn/"))) then
		display alert Â
			"Uninstall failed" message "To uninstall Tunnelblick, drag and drop a Tunnelblick application onto the uninstaller, or double-click the installer to uninstall /Applications/Tunnelblick." as critical Â
			buttons {"OK"}
		return
	end if
	
	-- Remove .app/ from what we display, and remove the trailing / from what we send the shell script
	set displayPath to text 1 through ((length of fullPath) - 5) of fullPath
	set tbPath to text 1 through ((length of fullPath) - 1) of fullPath
	
	-- Get the program name from the binary in /Contents/MacOS
	set TBName to GetName(tbPath)
	if TBName = "" then
		display alert "Uninstall failed" message displayPath & return & "is not an application." as critical buttons {"OK"}
		return
	end if
	
	-- Confirm that the user wants to proceed, and whether to uninstall or to test
	set alertResult to display alert "Uninstall " & TBName & "?" message Â
		"CLICK 'Uninstall' to remove" & return & displayPath & return & return & Â
		"The " & TBName & " program and all " & TBName & " configuration data, passwords, and preferences for all users of this computer will be removed." & return & return & Â
		"You will not be able to recover them afterward." & return & return & return & Â
		"OR CLICK 'Test' to find out what would be removed in an actual uninstall." & return & return & return & Â
		"OR DROP a " & TBName & " application on the uninstaller." as critical Â
		buttons {"Uninstall", "Test", "Cancel"}
	if alertResult = {button returned:"Cancel"} then
		return
	end if
	
	-- Start the uninstaller script, using the -i option to force a non-error status even if there are errors, and the -t or -u option as directed by the user
	if alertResult = {button returned:"Uninstall"} then
		set doUninstall to true
		set arguments to " -i -u " & quoted form of tbPath & " " & quoted form of TBName
	else
		set doUninstall to false
		set arguments to " -i -t " & quoted form of tbPath & " " & quoted form of TBName
	end if
	set scriptOutput to do shell script (quoted form of myScriptPath) & arguments with administrator privileges
	
	-- Inform the user about immediate errors (indicated by "Error: " at the start of the shell script's stdout)
	-- and other errors (indicated by "Error: " anywhere else in the shell script's stdout)
	-- and successful uninstalls
	if text 1 through 7 of scriptOutput = "Error: " then
		set restOfMsg to text 8 through (length of scriptOutput) of scriptOutput
		set alertResult to display alert "Uninstall failed" message "An error occurred while trying to uninstall " & TBName & ":" & return & return & restOfMsg Â
			as critical Â
			buttons {"OK"}
	else
		if (scriptOutput contains "Problem removing ") or (scriptOutput contains "Error: ") then
			set alertResult to display alert "Uninstall failed" message Â
				"One or more errors occurred while uninstalling " & TBName & "." as critical Â
				buttons {"Details", "OK"}
		else
			if doUninstall then
				set alertResult to display dialog TBName & " was uninstalled successfully" buttons {"Details", "OK"}
			else
				set alertResult to display dialog "The " & TBName & " uninstall test succeeded." buttons {"Details", "OK"}
			end if
		end if
	end if
	
	-- If the user asked for details, store the log in /tmp and open the log in TextEdit
	if alertResult = {button returned:"Details"} then
		do shell script "echo " & quoted form of scriptOutput & " > /tmp/Tunnelblick-uninstaller-log.txt"
		delay 1 -- needed because sometimes log isn't closed quickly enough and TextEdit can't open it
		tell application "TextEdit"
		activate
		open "/tmp/Tunnelblick-uninstaller-log.txt"
		end tell
	end if
	
end ProcessFile


------------------------------------------------------------------------------------------------------------------
-- Process a single file dropped onto this app
------------------------------------------------------------------------------------------------------------------

on open theFileList
	set filesWereDropped to true
	if (count theFileList) = 1 then
		GetMyScriptPath()
		ProcessFile(POSIX path of (item 1 of theFileList), GetMyScriptPath())
	else
		display alert "Uninstall failed" message Â
			"Please drop only one application at a time onto this uninstaller." as critical Â
			buttons {"Details", "OK"}
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
	GetMyScriptPath()
	ProcessFile(POSIX path of "/Applications/Tunnelblick.app/", GetMyScriptPath())
end if
