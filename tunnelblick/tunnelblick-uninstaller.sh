#!/bin/bash
#
# tunnelblick-uninstaller.sh
#
# Copyright © 2013 Jonathan K. Bullard. All rights reserved

####################################################################################
#
# This script must be run as root via the sudo command.
#
# This script does everything to uninstall Tunnelblick or a rebranded version of Tunnelblick:
#
#    (Uses the appropriate CFBundleIdentifier if it is not net.tunnelblick.tunnelblick)
#
#    1. Removes the following files and folders:
#          /Applications/Tunnelblick.app (or other copy of Tunnelblick)
#          /Library/Application Support/Tunnelblick
#          /Library/Logs/CrashReporter/Tunnelblick_*.crash
#          /Library/Logs/CrashReporter/openvpnstart_*.crash
#		   /Library/LaunchDaemons/net.tunnelblick.startup.* (ONLY IF uninstalling a NON-REBRANDED version of Tunnelblick)
#		   /Library/LaunchDaemons/net.tunnelblick.tunnelblick.startup.*
#
#    2. Removes the following for each user:
#          Login items
#          Keychain items
#		   ~/Library/Application Support/Tunnelblick
#		   ~/Library/Preferences/net.tunnelblick.tunnelblick.plist.lock
#		   ~/Library/Preferences/net.tunnelblick.tunnelblick.plist
#          ~/Library/Caches/net.tunnelblick.tunnelblick
#		   ~/Library/Preferences/com.openvpn.tunnelblick.plist
#		   ~/Library/openvpn
#		   ~/Library/Logs/CrashReporter/Tunnelblick_*.crash
#		   ~/Library/Logs/CrashReporter/openvpnstart_*.crash
#
#
# For a usage message, run this script with no arguments.
#
####################################################################################


####################################################################################
#
# Routine that trims leading/trailing spaces from its arguments
#
# Arguments: content to be trimmed
#
####################################################################################
uninstall_tb_trim()
{
  echo ${@}
}


####################################################################################
#
# Routine that removes a file or folder
#
# Argument: path to item that is to be removed
#
# DOES NOT complain if item does not exist
#
####################################################################################
uninstall_tb_remove_item_at_path()
{
  if [ -e "$1" ] ; then
    if [ -d "$1" ] ; then
      recursive="-R"
    else
      recursive=""
    fi
    if [ "${uninstall_remove_data}" = "true" ] ; then
      rm -f -P ${recursive} "$1"
      status=$?
    else
      status="0"
    fi
    if [ "${status}" = "0" ]; then
      echo "Removed          $1"
    else
      echo "Problem removing $1"
      nonFatalError="true"
    fi
  fi
}

####################################################################################
#
# Routine that returns the name of an app from .app/Contents/MacOS
# WHEN THE APP IS IN /Users and must be accessed by a specific user
#
# THIS SCRIPT MUST BE RUN VIA 'SU user'
#
# Arguments: (none)
#
# Uses the following environment variables:
#      uninstall_tb_app_path

####################################################################################
uninstall_tb_get_name_from_user_binary()
{
  if [ "$EUID" != "" ] ; then
	if [ "$EUID" = "0" ] ; then
	  echo "Error: uninstall_tb_get_name_from_user_app_path must not be run as root"
	  exit ${error_exit_code}
	fi
  else
	if [ "$(id -u)" != "" ]; then
	  if [ "$(id -u)" = "0" ]; then
		echo "Error: uninstall_tb_get_name_from_user_app_path must not be run as root"
		exit ${error_exit_code}
	  fi
	else
	  echo "Error: uninstall_tb_get_name_from_user_app_path must not be run as root. Unable to determine if it is running as root"
	  exit ${error_exit_code}
	fi
  fi

  # Try to get the app name from the binary
  if [ "${uninstall_tb_app_path}" != "" -a -e "${uninstall_tb_app_path}/Contents/MacOS" ] ; then
    binary_path="`ls ${uninstall_tb_app_path}/Contents/MacOS`"
    name="${binary_path##*/}"
  else
    echo "Error: Unable to find ${uninstall_tb_app_path}/Contents/MacOS"
    exit ${error_exit_code}
  fi

  echo "${name}"
  exit 0
}

####################################################################################
#
# Routine that returns the CFBundleIdentifier of an app from .app/Contents/MacOS
# WHEN THE APP IS IN /Users and must be accessed by a specific user
#
# THIS SCRIPT MUST BE RUN VIA 'SU user'
#
# Arguments: (none)
#
# Uses the following environment variables:
#      uninstall_tb_app_path

####################################################################################
uninstall_tb_get_bundle_id_from_user_binary()
{
  if [ "$EUID" != "" ] ; then
	if [ "$EUID" = "0" ] ; then
	  echo "Error: uninstall_tb_get_bundle_id_from_user_binary must not be run as root"
	  exit ${error_exit_code}
	fi
  else
	if [ "$(id -u)" != "" ]; then
	  if [ "$(id -u)" = "0" ]; then
		echo "Error: uninstall_tb_get_bundle_id_from_user_binary must not be run as root"
		exit ${error_exit_code}
	  fi
	else
	  echo "Error: uninstall_tb_get_bundle_id_from_user_binary must not be run as root. Unable to determine if it is running as root"
	  exit ${error_exit_code}
	fi
  fi

  # Try to get the bundle id from the binary
  if [ "${uninstall_tb_app_path}" != "" -a -e "${uninstall_tb_app_path}/Contents/Info.plist" ] ; then
    bundle_id="`defaults read "${uninstall_tb_app_path}/Contents/Info" CFBundleIdentifier`"
    echo "${bundle_id}"
  else
    echo "Error: Unable to find ${uninstall_tb_app_path}/Contents/Info.plist"
    exit ${error_exit_code}
  fi

  exit 0
}


####################################################################################
#
# Routine that removes the application
# WHEN THE APP IS IN /Users and must be accessed by a specific user
#
# THIS SCRIPT MUST BE RUN VIA 'SU user'
#
# Arguments: (none)
#
# Uses the following environment variables:
#      uninstall_tb_app_path

####################################################################################
uninstall_tb_remove_user_app()
{
  if [ "$EUID" != "" ] ; then
	if [ "$EUID" = "0" ] ; then
	  echo "Error: uninstall_tb_remove_user_app must not be run as root"
	  exit 0
	fi
  else
	if [ "$(id -u)" != "" ]; then
	  if [ "$(id -u)" = "0" ]; then
		echo "Error: uninstall_tb_remove_user_app must not be run as root"
		exit 0
	  fi
	else
	  echo "Error: uninstall_tb_remove_user_app must not be run as root. Unable to determine if it is running as root"
	  exit 0
	fi
  fi
  
  # The following code is adapted from uninstall_tb_remove_item_at_path

  if [ "${uninstall_tb_app_path}" != "" ] ; then
    if [ -e "${uninstall_tb_app_path}" ] ; then
      if [ -d "${uninstall_tb_app_path}" ] ; then
        recursive="-R"
      else
        recursive=""
      fi
      if [ "${uninstall_remove_data}" = "true" ] ; then
        rm -f -P ${recursive} "$uninstall_tb_app_path}"
        status=$?
      else
        status="0"
	  fi
      if [ "${status}" = "0" ]; then
        echo "Removed          ${uninstall_tb_app_path}"
      else
        echo "Problem removing ${uninstall_tb_app_path}"
      fi
    fi
  fi
}

####################################################################################
#
# Routine that uninstalls per-user data (must be done by user, not root)
#
# Arguments: (none)
#
# Uses the following environment variables:
#      uninstall_tb_remove_item_at_path()
#      uninstall_remove_data
#      uninstall_tb_app_name
#      uninstall_tb_app_path

####################################################################################
uninstall_tb_per_user_data()
{
  if [ "$EUID" != "" ] ; then
	if [ "$EUID" = "0" ] ; then
	  echo "Error: uninstall_tb_per_user_data must not be run as root"
	  exit 0
	fi
  else
	if [ "$(id -u)" != "" ]; then
	  if [ "$(id -u)" = "0" ]; then
		echo "Error: uninstall_tb_per_user_data must not be run as root"
		exit 0
	  fi
	else
	  echo "Error: uninstall_tb_per_user_data must not be run as root. Unable to determine if it is running as root"
	  exit 0
	fi
  fi

  # Remove any and all items stored by Tunnelblick in all of the current user's Keychains
  #
  # Note: It is possible, although unlikely, that a non-Tunnelblick Keychain item would be deleted
  #       if its name starts with 'Tunnelblick-Auth-'. This is because the script assumes that any item
  #       if its 'Service' begins with 'Tunnelblick-Auth-' has been stored by Tunnelblick.

  if [ "${uninstall_tb_app_name}" != "" ] ; then

    # keychain_list is a list of all the user's keychains, separated by spaces
    readonly keychain_list="$(uninstall_tb_trim "$(security list-keychains | grep login.keychain | tr '\n' ' ' | tr -d '"')")"

    for keychain in ${keychain_list} ; do

      # keychain_contents is the dumped contents of the keychain (for security reasons we don't
      #                   use the "-d" option, thus decrypted passwords are not included in the dump)
      keychain_contents="$(security dump-keychain ${keychain})"

      # tb_service_list is a list, one per line, of the names of services in the contents whose names
      #                 begin with "Tunnelblick-Auth-"
      #                 Notes:
      #                      1. Each service name may be duplicated several times
      #                      2. Each service name is enclosed in double-quotes and may contain spaces
      tb_service_list="$(echo "${keychain_contents}" | grep "=\"${uninstall_tb_app_name}-Auth-" |  sed -e 's/.*<blob>=//' | tr -d '"')"

      # tb_service_array is an array containing the service list
      # (Temporarily change the token separator to consider only newlines as separators while reading from tb_service_list)
      saved_IFS=${IFS}
      IFS=$'\n'
      tb_service_array=(${tb_service_list})
      IFS=${saved_IFS}
  
      # Loop through the array, processing each different service only once

      # last_service is the name of the last service processed. It is used to process each service only once
      last_service="''"

      for service in "${tb_service_array[@]}" ; do
        if [ "${service}" != "${last_service}" ] ; then

          # Process any privateKey, username, or password accounts for the service
          for account in privateKey username password ; do

            # If an item for the account exists, delete that keychain item
            item="$(security find-generic-password -s "${service}" -a "${account}" 2> /dev/null)"
            if [ "${item}" != "" ] ; then
              if [ "${uninstall_remove_data}" = "true" ] ; then
                security delete-generic-password -s "${service}" -a "${account}" > /dev/null
                status=$?
              else
                status="0"
              fi
              if [ "${status}" = "0" ]; then
                echo "Removed          ${USER}'s ${account} for ${service}"
              else
                echo "Problem removing ${USER}'s ${account} for ${service}"
              fi
            fi
          done
          last_service="${service}"
        fi
      done
      
    done

  fi

}


####################################################################################
#
# Start of script
#
####################################################################################

usage_message="Usage:

      tunnelblick-uninstaller.sh  [ -u | -t ] [ -i ]   [ app-path [ app-name [ bundle-id ] ] ]

           app-path:  The path to the application.

           app-name:  The name of the application.
                      Defaults to the name of the file contained in app-path/Contents/MacOS.
                      If the Tunnelblick application has been rebuilt from source with a
                      new name (i.e., rebranded), app-name is the new name.
                     
           bundle-id: The CFBundleIdentifier for the application.
                      Defaults to the CFBundleIdentifier in app-path/Contents/Info.plist.

           -t:        Causes the script to perform a TEST, or \"dry run\": the program logs to
                      stdout what it would do if run with the -u option, but NO DATA IS REMOVED.

           -u:        Causes the script to perform an UNINSTALL, REMOVING DATA; the program logs
                      to stdout what it has done.

           -i:        Causes the installer to always exit with a status of 0. Otherwise, the
                      uninstaller will exit with a status of 1 if a critical error occurred.

     If neither the -u option nor the -t option is specified, this usage message is displayed.

     The app-path, app-name, and bundle-id arguments are optional and may be blank. If app-path
     is specified, the application is examined for the name of its binary (in
     app-path/Contents/MacOS) and that name is used as the app-name; the CFBundleIdentifier (in
     app-path/Contents/Info.plist) is used as the bundle-id; and the application at app-path is
     removed. If app-name is specified or  obtained from app-path, it is used in the path of
     files to remove. If bundle-id is specified or obtained from app-path, it is used in the
     name of the preferences and cache files to remove.

     Examples:

     ./tunnelblick-uninstaller.sh /User/joe/Applications/Tunnelblick.app
     This is the normal use. It will remove the application at PATH and all files and folders
     associated with the application.

     ./tunnelblick-uninstaller.sh "" NAME BUNDLE_ID
     This can be used if the application itself is not available. It will remove files and
     folders associated with NAME and preferences and cache files associated with BUNDLE_ID.

     ./tunnelblick-uninstaller.sh "" "" BUNDLE_ID
     This can be used if the application itself and its name are not available. It will remove
     preferences and cache files associated with BUNDLE_ID.
"

show_usage_message="false"

error_exit_code="1"

# Complain and exit if not running as root
if [ "$EUID" != "" ] ; then
  if [ "$EUID" != "0" ] ; then
    echo "Error: This program must be run as root"
    exit ${error_exit_code}
  fi
else
  if [ "$(id -u)" != "" ]; then
    if [ "$(id -u)" != "0" ]; then
      echo "Error: This program must be run as root"
      exit ${error_exit_code}
    fi
  else
    echo "Error: This program must be run as root. Unable to determine if it is running as root"
    exit ${error_exit_code}
  fi
fi

####################################################################################
#
# Process options and set uninstall_remove_data to either "true" or "false" ( for -u or -t, respectively)
#
####################################################################################

if [ $# != 0 ] ; then
  while [ "${1:0:1}" = "-" ] ; do

    if [ "$1" = "-u" ] ; then
      if [ "${uninstall_remove_data}" = "" ] ; then
        readonly uninstall_remove_data="true"
      else
        echo "Only one -t or -u option may be specified"
        show_usage_message="true"
      fi
    else
      if [ "$1" = "-t" ] ; then
        if [ "${uninstall_remove_data}" = "" ] ; then
          readonly uninstall_remove_data="false"
        else
        echo "Only one -t or -u option may be specified"
          show_usage_message="true"
        fi
      else
        if [ "$1" = "-i" ] ; then
          error_exit_code="0"
        else
          echo "Unknown option: ${1}"
          show_usage_message="true"
        fi
      fi
    fi
  
    shift
    
  done

fi

if [ "${uninstall_remove_data}" = "" ] ; then
  echo "One of -u or -t is required"
  show_usage_message="true"
fi


if [ "$#" -gt "3" ] ; then
  echo "Too many arguments"
  show_usage_message="true"
fi

if [ "${show_usage_message}" != "false" ] ; then
  echo "${usage_message}"
  exit ${error_exit_code}
fi

####################################################################################
#
# Process arguments and set up three variables:
#     uninstall_tb_app_path: The path to the file that contains the application.
#
#     uninstall_tb_app_name:  The name of the application.
#                   Default: read from the application binary.
#					If the Tunnelblick application has been rebuilt from source with a new name,
#					(i.e., rebranded), this is the new name.
#
#     uninstall_tb_bundle_identifier: The CFBundleIdentifier to use.
#                   Default: read from the application binary.
#					If the Tunnelblick application has been rebuilt from source with a new name,
#					(i.e., rebranded), this is the new bundle identifier.
#
####################################################################################

readonly uninstall_tb_app_path="${1}"

# Extract binary name and CFBundleIdentifier from the .app

if [ "${uninstall_tb_app_path}" != "" -a "${uninstall_tb_app_path:0:7}" = "/Users/" ] ; then
  readonly user_name_temp="${uninstall_tb_app_path:7}"
  readonly app_path_user_name="${user_name_temp%%/*}"
  
  export -f uninstall_tb_get_name_from_user_binary
  export -f uninstall_tb_get_bundle_id_from_user_binary
  export    uninstall_tb_app_path
  
  readonly app_name_from_binary="`/usr/bin/su "${app_path_user_name}" -c "/bin/bash -c uninstall_tb_get_name_from_user_binary"`"
  if [ "${app_name_from_binary:0:7}" = "Error: " ] ; then
    echo "${app_name_from_binary}"
    exit ${error_exit_code}
  fi

  readonly bundle_id_from_binary="`/usr/bin/su "${app_path_user_name}" -c "/bin/bash -c uninstall_tb_get_bundle_id_from_user_binary"`"
  if [ "${bundle_id_from_binary:0:7}" = "Error: " ] ; then
    echo "${bundle_id_from_binary}"
    exit ${error_exit_code}
  fi

else
  if [ "${uninstall_tb_app_path}" != "" ] ; then
    if [ ! -e "${uninstall_tb_app_path}" ] ; then
      echo "Error: No application at ${uninstall_tb_app_path}"
      exit ${error_exit_code}
    fi
    if [  ! -e "${uninstall_tb_app_path}/Contents/MacOS" ] ; then
      echo "Error: Invalid path to application; it is not an application"
      exit ${error_exit_code}
    fi
    if [  ! -e "${uninstall_tb_app_path}/Contents/Resources/openvpn" ] ; then
      echo "Error: Invalid path to application; it is not a Tunnelblick"
      exit ${error_exit_code}
    fi
    if [  ! -e "${uninstall_tb_app_path}/Contents/Info.plist" ] ; then
      echo "Error: Invalid path to application; it does not have an Info.plist"
      exit ${error_exit_code}
    fi
    readonly binary_path="`ls ${uninstall_tb_app_path}/Contents/MacOS`"
    readonly app_name_from_binary="${binary_path##*/}"
    readonly bundle_id_from_binary="`defaults read "${uninstall_tb_app_path}/Contents/Info" CFBundleIdentifier`"
    if [ "${bundle_id_from_binary}" = "" ] ; then
      echo "Error: Unable to read CFBundleIdentifier from ${uninstall_tb_app_path}/Contents/Info.plist"
      exit ${error_exit_code}
    fi
  fi
fi

uninstall_tb_app_name="${2}"

if [ "${uninstall_tb_app_name}" == "" ] ; then
  readonly uninstall_tb_app_name="${app_name_from_binary}"
else
  if [ "${app_name_from_binary}" != "" ] ; then
    if [ "${app_name_from_binary}" != "${uninstall_tb_app_name}" ] ; then
      echo "Error: Application name '${app_name_from_binary}' in ${uninstall_tb_app_path} does not match '${uninstall_tb_app_name}'"
      exit ${error_exit_code}
    fi
  fi

  readonly uninstall_tb_app_name
fi

uninstall_tb_bundle_identifier="${3}"

if [ "${uninstall_tb_bundle_identifier}" == "" ] ; then
  readonly uninstall_tb_bundle_identifier="${bundle_id_from_binary}"
else
  if [ "${bundle_id_from_binary}" != "" ] ; then
    if [ "${bundle_id_from_binary}" != "${uninstall_tb_bundle_identifier}" ] ; then
      echo "Error: Application CFBundleIdentifier '${bundle_id_from_binary}' in ${uninstall_tb_app_path} does not match '${uninstall_tb_bundle_identifier}'"
      exit ${error_exit_code}
    fi
  fi

  readonly uninstall_tb_bundle_identifier
fi

####################################################################################
#
# Finished processing arguments. Make sure no Tunnelblicks are currently running
# and output initial messages
#
####################################################################################

if [ "${uninstall_tb_app_name}" != "" ] ; then
  readonly instances="$(ps -x | grep ".app/Contents/MacOS/${uninstall_tb_app_name}" | grep -x grep)"
  if [ "${instances}" != "" ] ; then
    echo "Error: ${uninstall_tb_app_name} cannot be uninstalled while it is running"
    exit ${error_exit_code}
  fi
fi

echo -n "$(date '+%a %b %e %T %Y') Tunnelblick Uninstaller: Uninstalling"
if [ "${uninstall_tb_app_name}" != "" ] ; then
  echo " ${uninstall_tb_app_name}"
else
  echo ""
fi
if [ "${uninstall_tb_app_path}" != "" ] ; then
  echo "                         at ${uninstall_tb_app_path}"
fi
if [ "${uninstall_tb_bundle_identifier}" != "" ] ; then
  echo "                         with bundle ID '${uninstall_tb_bundle_identifier}'"
fi

if [ "${uninstall_remove_data}" != "true" ] ; then
  echo ""
  echo "Testing only -- NOT removing"
  echo ""
fi

####################################################################################
#
# Remove non-per-user files and folders
#
####################################################################################

# Remove the Application Support folder
if [ "${uninstall_tb_app_name}" != "" ] ; then
uninstall_tb_remove_item_at_path  "/Library/Application Support/${uninstall_tb_app_name}"
fi

# Remove Tunnelblick LaunchDaemons

# Special-case old startup launch daemons that use net.tunnelblick.startup as the prefix when removing a NON-REBRANDED Tunnelblick
# (Create tbBundleId variable so it does _not_ get changed by rebranding
tempTbBundleId="net.tunnelblick"
tempTbBundleId="${tbBundleId}.tunnelblick"
if [ "${uninstall_tb_bundle_identifier}" == "${tempTbBundleId}" ] ; then
  for path in `ls /Library/LaunchDaemons/net.tunnelblick.startup.* 2> /dev/null` ; do
    uninstall_tb_remove_item_at_path "${path}"
  done
fi

# Remove new startup launch daemons that use the (possibly rebranded) CFBundleIdentifier as the prefix
if [ "${uninstall_tb_bundle_identifier}" != "" ] ; then
  for path in `ls /Library/LaunchDaemons/${uninstall_tb_bundle_identifier}".startup.* 2> /dev/null` ; do
    uninstall_tb_remove_item_at_path "${path}"
  done
fi

# Remove tunnelblickd launch daemon
if [ "${uninstall_tb_bundle_identifier}" != "" ] ; then
  # Remove the socket
  path="/var/run/${uninstall_tb_bundle_identifier}.tunnelblickd.socket"
  uninstall_tb_remove_item_at_path "${path}"
  # Unload, then remove the .plist
  path="/Library/LaunchDaemons/${uninstall_tb_bundle_identifier}.tunnelblickd.plist"
  if [ -f "${path}" ] ; then
    launchctl unload "${path}"
    uninstall_tb_remove_item_at_path "${path}"
  fi
fi

# Remove tunnelblickd log(s)
uninstall_tb_remove_item_at_path "/var/log/Tunnelblick"

# Remove the installer log
uninstall_tb_remove_item_at_path "/Library/Application Support/Tunnelblick/tunnelblick-installer-log.txt"

# Remove non-per-user CrashReporter files
if [ "${uninstall_tb_app_name}" != "" ] ; then
  for path in `ls /Library/Logs/CrashReporter/${uninstall_tb_app_name}_* 2> /dev/null` ; do
    uninstall_tb_remove_item_at_path "${path}"
  done

  for path in `ls /Library/Logs/DiagnosticReports/${uninstall_tb_app_name}_* 2> /dev/null` ; do
    uninstall_tb_remove_item_at_path "${path}"
  done
fi

for path in `ls /Library/Logs/CrashReporter/openvpnstart_* 2> /dev/null` ; do
  uninstall_tb_remove_item_at_path "${path}"
done

for path in `ls /Library/Logs/DiagnosticReports/openvpnstart_* 2> /dev/null` ; do
  uninstall_tb_remove_item_at_path "${path}"
done

####################################################################################
#
# Remove per-user files and folders
#
####################################################################################

export -f uninstall_tb_trim
export -f uninstall_tb_remove_item_at_path
export -f uninstall_tb_per_user_data

export    uninstall_remove_data
export    uninstall_tb_app_path
export    uninstall_tb_app_name
export    uninstall_tb_bundle_identifier

for user in `dscl . list /users` ; do
  if [ "${user:0:1}" != "_" -a -e "/Users/${user}" ] ; then

    # Remove old preferences and configurations folder or symlink to the configurations folder
    uninstall_tb_remove_item_at_path "/Users/${user}/Library/Preferences/com.openvpn.tunnelblick.plist"
    uninstall_tb_remove_item_at_path "/Users/${user}/Library/openvpn"

    if [ "${uninstall_tb_app_name}" != "" ] ; then
      uninstall_tb_remove_item_at_path "/Users/${user}/Library/Application Support/${uninstall_tb_app_name}"
    fi

    if [ "${uninstall_tb_bundle_identifier}" != "" ] ; then
      uninstall_tb_remove_item_at_path "/Users/${user}/Library/Preferences/${uninstall_tb_bundle_identifier}.plist.lock"
      uninstall_tb_remove_item_at_path "/Users/${user}/Library/Preferences/${uninstall_tb_bundle_identifier}.plist"
      uninstall_tb_remove_item_at_path "/Users/${user}/Library/Caches/${uninstall_tb_bundle_identifier}"
      uninstall_tb_remove_item_at_path "/Users/${user}/Library/LaunchAgents/${uninstall_tb_bundle_identifier}.LaunchAtLogin.plist"
    fi

	# Remove per-user CrashReporter files
    if [ "${uninstall_tb_app_name}" != "" ] ; then
      for path in `ls /Users/${user}/Library/Logs/DiagnosticReports/${uninstall_tb_app_name}_*.crash 2> /dev/null` ; do
        uninstall_tb_remove_item_at_path "${path}"
      done

      for path in `ls /Users/${user}/Library/Logs/CrashReporter/${uninstall_tb_app_name}_*.crash 2> /dev/null` ; do
        uninstall_tb_remove_item_at_path "${path}"
      done
    fi

    for path in `ls /Users/${user}/Library/Logs/DiagnosticReports/openvpnstart_*.crash 2> /dev/null` ; do
      uninstall_tb_remove_item_at_path "${path}"
    done

    for path in `ls /Users/${user}/Library/Logs/CrashReporter/openvpnstart_*.crash 2> /dev/null` ; do
      uninstall_tb_remove_item_at_path "${path}"
    done

	# run the per-user routine to delete keychain items
    output="$(/usr/bin/su "${user}" -c "/bin/bash -c uninstall_tb_per_user_data")"
    if [ "${output}" != "" ] ; then
	  echo "${output}"
      if [ "${output:0:7}" = "Error: " ] ; then
        exit error_exit_code
      fi
    fi

  fi

done

# delete login items for this user only
if [ "{uninstall_remove_data}" = "true" ] ; then
  output=$(/usr/bin/su ${USER} -c "osascript -e 'set n to 0' -e 'tell application \"System Events\"' -e 'set login_items to the name of every login item whose name is \"${uninstall_tb_app_name}\"' -e 'tell me to set n to the number of login_items' -e 'repeat (the number of login_items) times' -e 'remove login item \"${uninstall_tb_app_name}\"' -e 'end repeat' -e 'end tell' -e 'n'")
else
  output=$(/usr/bin/su ${USER} -c "osascript -e 'set n to 0' -e 'tell application \"System Events\"' -e 'set login_items to the name of every login item whose name is \"${uninstall_tb_app_name}\"' -e 'tell me to set n to the number of login_items' -e 'end tell' -e 'n'")
fi
if [ "${output}" != "0" ] ; then
  echo "Removed ${output} of  ${USER}'s login items"
fi

# Remove the application itself
if [ "${uninstall_tb_app_path}" != "" ] ; then
  if [ "${uninstall_tb_app_path:0:7}" = "/Users/" ] ; then
    export -f uninstall_tb_remove_user_app
    output="$(/usr/bin/su "${app_path_user_name}" -c "/bin/bash -c uninstall_tb_remove_user_app")"
    if [ "${output:0:7}" = "Error: " ] ; then
      echo "output"
      exit error_exit_code
    fi
  else
    uninstall_tb_remove_item_at_path "${uninstall_tb_app_path}"
  fi
fi

if [ "${uninstall_remove_data}" != "true" ] ; then
  echo ""
  echo "Note:  NOTHING WAS REMOVED -- this was a test"
fi

exit 0
