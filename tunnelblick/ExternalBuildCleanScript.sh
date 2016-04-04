#!/bin/sh

#
# Copyright 2012 Jonathan K. Bullard. All rights reserved.
#
#  This file is part of Tunnelblick.
#
#  Tunnelblick is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2
#  as published by the Free Software Foundation.
#
#  Tunnelblick is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program (see the file COPYING included with this
#  distribution); if not, write to the Free Software Foundation, Inc.,
#  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#  or see http://www.gnu.org/licenses/.
#

# The following script is modified from the model at http://yeahrightkeller.com/2009/run-script-while-cleaning-in-xcode/

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# ACTIONS
# These are implemented as functions, and just called by the
# short MAIN section below

buildAction () {

    # The only argument, which is required, is the name of the configuration to build
    echo "Preparing to build $1 configuration ..."

    if [ "$1" = "Release" ] ; then
        # Remove the .app so the digital signature will be created on a fresh copy
		# Don't need to remove Tunnelblick Uninstaller.app; it is always freshly compiled
        if [ -e "build/$1/${PROJECT_NAME}.app" ] ; then
            rm -r "build/$1/${PROJECT_NAME}.app"
            echo "Removed the .app"
        else
            echo "(No action required because the .app does not exist)"
        fi
        
    elif [ "$1" = "Debug" ] ; then
        if [ -d "build/$1/${PROJECT_NAME}.app" ] ; then
            # Trash the .app so the digital signature will be created on a clean copy of the .app
            # (We can't 'rm -r -f' because of the possible ownership of some parts by root:wheel)
cat > /tmp/tunnelblick-trash.scpt <<_EOF
on run(arguments)
set filename to POSIX file (first item of arguments) as alias
tell application "Finder"
delete filename
end tell
end run
_EOF
/usr/bin/osascript /tmp/tunnelblick-trash.scpt "build/${CONFIGURATION}/${PROJECT_NAME}.app"
rm -f /tmp/tunnelblick-trash.scpt
        else
            echo "(No action required because the .app does not exist)"
        fi
        
    else
        echo "error: Invalid argument to buildAction. Must be a configuration name"
        exit 1
    fi
    echo "Preparation done"

}

cleanAction () {

    # The only argument, which is required, is the name of the configuration to build
    echo "Preparing to clean $1 configuration ..."

    if [ "$1" = "Release" ] ; then
        # Remove the .dmgs and Tunnelblick Uninstaller.app and the staging folders
        if [ -e "build/$1/${PROJECT_NAME}.dmg" ] ; then
            rm "build/$1/${PROJECT_NAME}.dmg"
            echo "Removed the .dmg"
        else
            echo "(No action required because the .dmg does not exist)"
        fi
        if [ -e "build/$1/${PROJECT_NAME} Uninstaller.dmg" ] ; then
            rm "build/$1/${PROJECT_NAME} Uninstaller.dmg"
            echo "Removed the Uninstaller .dmg"
        else
            echo "(No action required because the Uninstaller .dmg does not exist)"
        fi
        if [ -d "build/$1/${PROJECT_NAME} Uninstaller.app" ] ; then
            rm -r "build/$1/${PROJECT_NAME} Uninstaller.app"
            echo "Removed ${PROJECT_NAME} Uninstaller.app"
        else
            echo "(No action required because ${PROJECT_NAME} Uninstaller.app does not exist)"
        fi
        if [ -d "build/$1/${PROJECT_NAME}" ] ; then
            rm -r "build/$1/${PROJECT_NAME}"
            echo "Removed the staging folder"
        else
            echo "(No action required because the staging folder does not exist)"
        fi
        if [ -d "build/$1/${PROJECT_NAME} Uninstaller" ] ; then
            rm -r "build/$1/${PROJECT_NAME} Uninstaller"
            echo "Removed the Uninstaller staging folder"
        else
            echo "(No action required because the Uninstaller staging folder does not exist)"
        fi
        
    elif [ "$1" = "Debug" ] ; then
        if [ -d "build/Debug/${PROJECT_NAME}.app" ] ; then
            # Trash the .app so the digital signature will be created on a clean copy of the .app
            # (We can't 'rm -r -f' because of the possible ownership of some parts by root:wheel)
cat > /tmp/tunnelblick-trash.scpt <<_EOF
on run(arguments)
set filename to POSIX file (first item of arguments) as alias
tell application "Finder"
delete filename
end tell
end run
_EOF
/usr/bin/osascript /tmp/tunnelblick-trash.scpt "build/${CONFIGURATION}/${PROJECT_NAME}.app"
rm -f /tmp/tunnelblick-trash.scpt
        else
            echo "(No action required because the .app does not exist)"
        fi
        # Remove Tunnelblick Uninstaller.app
        if [ -d "build/$1/${PROJECT_NAME} Uninstaller.app" ] ; then
            rm -r "build/$1/${PROJECT_NAME} Uninstaller.app"
            echo "Removed ${PROJECT_NAME} Uninstaller.app"
        else
            echo "(No action required because ${PROJECT_NAME} Uninstaller.app does not exist)"
        fi

    else
        echo "error: Invalid argument ('$1') to cleanAction. Must be a configuration name"
        exit 1
    fi
    echo "Preparation done"

}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# MAIN

case $ACTION in
    # NOTE: for some reason, it gets set to "" rather than "build" when
    # doing a build.
    "")
        buildAction "${CONFIGURATION}"
        ;;

    "clean")
        cleanAction "${CONFIGURATION}"
        ;;
        
    *)
        echo "error: Invalid action. Must be empty or 'clean'"
        exit 1
        ;;
esac

exit 0



