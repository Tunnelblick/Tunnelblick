#!/bin/sh

#
# Copyright 2012 Jonathan Bullard
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

    if [ "$1" = "Clean Tunnelblick" ] ; then
        echo "error: Do not BUILD the 'Clean Tunnelblick' configuration -- only CLEAN it"
        exit 1
        
    elif [ "$1" = "Clean Third Party" ] ; then
        echo "error: Do not BUILD the 'Third Party' configuration -- only CLEAN it"
        exit 1
        
    elif [ "$1" = "Release" ] ; then
        # Remove the .app so the digital signature will be created on a fresh copy
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
        
    elif [ "$1" = "Unsigned Release" ] ; then
        echo "(No action required to build '$1' configuration)"
        
    else
        echo "error: Invalid argument to buildAction. Must be a configuration name"
        exit 1
    fi
    echo "Preparation done"

}

cleanAction () {

    # The only argument, which is required, is the name of the configuration to build
    echo "Preparing to clean $1 configuration ..."

    if [ "$1" = "Clean Tunnelblick" ] ; then
        if [ -d "build/Debug/${PROJECT_NAME}.app" ] ; then
            # Trash the .app because we can't 'rm -r' because of the possible ownership of some parts by root:wheel)
            ./trash.sh -f "build/Debug/${PROJECT_NAME}.app"
        fi
        cd "build"
            cd "Release"; rm -r -f *; cd ..
            cd "Unsigned Release"; rm -r -f *; cd ..
            cd "Debug"; rm -r -f *; cd ..
            if [ -d "Clean Tunnelblick" ] ; then
                rm -r -f "Clean Tunnelblick"
            fi
            if [ -d "Clean Third Party" ] ; then
                rm -r -f "Clean Third Party"
            fi
            cd ..
        echo "Removed everything except the ${PROJECT_NAME}.build folder, which Xcode would restore anyway"
        
    elif [ "$1" = "Clean Third Party" ] ; then
        rm "../third_party/built"
        echo "Removed 'third_party/built', so the third party components will be rebuilt"
        cd "../third_party"
        make clean
        cd "../tunnelblick"
        
    elif [ "$1" = "Release" ] ; then
        # Remove the .dmg and the staging folder
        if [ -e "build/$1/${PROJECT_NAME}.dmg" ] ; then
            rm "build/$1/${PROJECT_NAME}.dmg"
            echo "Removed the .dmg"
        else
            echo "(No action required because the .dmg does not exist)"
        fi
        if [ -d "build/$1/${PROJECT_NAME}" ] ; then
            rm -r "build/$1/${PROJECT_NAME}"
            echo "Removed the staging folder"
        else
            echo "(No action required because the staging folder does not exist)"
        fi
        
    elif [ "$1" = "Unsigned Release" ] ; then
        # Remove the .dmg and the staging folder
        if [ -a "build/$1/${PROJECT_NAME}.dmg" ] ; then
            rm "build/$1/${PROJECT_NAME}.dmg"
            echo "Removed the .dmg"
        else
            echo "(No action required because the .dmg does not exist)"
        fi
        if [ -d "build/$1/${PROJECT_NAME}" ] ; then
            rm -r "build/$1/${PROJECT_NAME}"
            echo "Removed the staging folder"
        else
            echo "(No action required because the staging folder does not exist)"
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



