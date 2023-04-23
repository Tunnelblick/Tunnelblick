#!/bin/bash -e
#
# sign-tunnelblick-app-or-dmg.sh
#
# Copyright © 2021 by Jonathan K. Bullard. All rights reserved.
#
# This file is part of Tunnelblick.
#
# Tunnelblick is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2
# as published by the Free Software Foundation.
#
# Tunnelblick is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file COPYING included with this
# distribution); if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# or see http://www.gnu.org/licenses/.
#
#
# This script signs a Tunnelblick.app or a Tunnelblick .dmg with a signing identity of "-"
# and verifies the signature.
#
# 		sign-tunnelblick-app-or-dmg.sh    path    [ signing_identity ]
#
#			path is the path to a Tunnelblick.app or to a .dmg containing Tunnelblck.
#
#			signing_identity is optional. If not provided, a signing identity of "-"
#			will be used, to create and ad-hoc
#
# Coding convention:
#		UPPERCASE variables are globals.
#		lowercase variables are used only locally or in routines.
#
# Note: All variables used in the main section are technically global, but lowercase
# variables are used only in the main section and are not used in routines.


full_path () {

	# Echos the full path of $1.

	echo "$(cd "$(dirname "$1")"; pwd -P)/$(basename "$1")"
}

path_suffix () {

	# Echos the path of $1 after stripping a prefix of "$ITEM_DIR"
	#	* The folder enclosing $1 must exist.
	#	* "$ITEM_DIR" must be an absolute path ending in a "/".

	# GLOBAL ITEM_DIR

	local path; path=$(  full_path "$1" )
	echo "${path#"$ITEM_DIR"}"
}

codesign_v_t_or () {

    # Sign an item (file, app, .dmg, or framework) with --timestamp and --options runtime
    #
    # codesign_v_t_or $1 [ $2 ]
    #   $1 = path
    #   $2 = flags (optional) - WILL NOT be quoted
    #
    # Does 'codesign    --verbose    --timestamp    --options runtime    --sign "$SIGNING_IDENTITY"    $2    "$1"'

    # GLOBAL TMP_FILE_PATH
    # GLOBAL EXIT_VALUE
    # GLOBAL SIGNING_IDENTITY

    local status; status=0
    set +e
        local command; command="--verbose    --timestamp    --options runtime    --sign \"$SIGNING_IDENTITY\"    $2    \"$1\""
		# shellcheck disable=SC2086
        codesign                --verbose    --timestamp    --options runtime    --sign "$SIGNING_IDENTITY"    $2    "$1" > "$TMP_FILE_PATH" 2>&1
        status=$?
    set -e

    local name; name=$( path_suffix "$1" )

    if [  $status -eq 0 ] ; then
		echo "Signed $name; command = '$command'"
	else
        cat "$TMP_FILE_PATH"
        echo "Error: Failed to sign $name; status = $status; command = '$command'"
        EXIT_VALUE=1
	fi
}

sign_app () {

    # If not signed yet, sign the binary tools, including each version of OpenvVPN and openvpn-down-root,
    #                         the Sparkle.framework, and
    #                         the .app_path itself.
    #
    # Sets EXIT_VALUE to 1 if an error occurs.

    # GLOBAL EXIT_VALUE

    local app_path; app_path="$1"

    if [ ! -e "$app_path/Contents/_CodeSignature" ] ; then

        echo "Signing with signing identity '$SIGNING_IDENTITY': '$app_path'"

        codesign_v_t_or "$app_path/Contents/Resources/atsystemstart"
        codesign_v_t_or "$app_path/Contents/Resources/installer"
        codesign_v_t_or "$app_path/Contents/Resources/openvpnstart"
        codesign_v_t_or "$app_path/Contents/Resources/process-network-changes"
        codesign_v_t_or "$app_path/Contents/Resources/standardize-scutil-output"
        codesign_v_t_or "$app_path/Contents/Resources/tunnelblickd"
        codesign_v_t_or "$app_path/Contents/Resources/tunnelblick-helper"
        codesign_v_t_or "$app_path/Contents/Resources/Tunnelblick-LaunchAtLogin"

        # Sign the openvpn and openvpn-down-root.so binaries
        local openvpn_version_dir
        for openvpn_version_dir in "$app_path/Contents/Resources/openvpn"/* ; do
            if [ "${openvpn_version_dir: -7}" != "default" ] ; then
            	if [ -e "$openvpn_version_dir/openvpn" ] \
            	&& [ -e "$openvpn_version_dir/openvpn-down-root.so" ] ; then
                	codesign_v_t_or "$openvpn_version_dir/openvpn"
                	codesign_v_t_or "$openvpn_version_dir/openvpn-down-root.so"
            	else
                	echo "Error: Missing binaries to codesign in $app_path/Contents/Resources/openvpn/$openvpn_version_dir"
                	EXIT_VALUE=1
            	fi
            fi
        done

   		local sparkle_framework; sparkle_framework="$app_path/Contents/Frameworks/Sparkle.framework"

		if [ -d "${sparkle_framework}" ] ; then

			local tunnelblickUpdater_app_path; tunnelblickUpdater_app_path="${sparkle_framework}/Versions/A/Resources/TunnelblickUpdater.app"
			if [ -d "${tunnelblickUpdater_app_path}" ] ; then
				codesign_v_t_or "${tunnelblickUpdater_app_path}" "--deep --force"
			else
				echo "Error: Does not exist: '${tunnelblickUpdater_app_path}'"
				EXIT_VALUE=1
			fi

			# Must sign fileop separately because signing TunnelblickUpdater.app does not sign it:
			local fileop_path; fileop_path="${tunnelblickUpdater_app_path}/Contents/MacOS/fileop"
			if [ -f  "${fileop_path}" ] ; then
				codesign_v_t_or "${fileop_path}" "--force"
			else
				echo "Error: Does not exist: '${fileop_path}'"
				EXIT_VALUE=1
			fi

			codesign_v_t_or "${sparkle_framework}" "--deep --force"

		else
			echo "Error: Does not exist: '${sparkle_framework}'"
			EXIT_VALUE=1
		fi

		# Sign the application itself
		codesign_v_t_or "$app_path"

        echo "Finished signing $app_path..."
	else
		echo "Error: Already signed: '$app_path'"
		EXIT_VALUE=1
	fi
}

codesign_verify_verbose () {

    # Does 'codesign --verify --verbose $2 "$1"' and outputs errors only

	# GLOBAL TMP_FILE_PATH
	# GLOBAL EXIT_VALUE

    local status; status=0
    set +e
        local command; command="codesign --verify --verbose $2 \"$1\""
        # shellcheck disable=SC2086
        codesign --verify --verbose $2 "$1" > "$TMP_FILE_PATH" 2>&1
        status=$?
    set -e

    local name; name=$( path_suffix "$1")

    if [  $status -ne 0 ] ; then
		cat "$TMP_FILE_PATH"
        echo "Error: Signature check of $name failed with status $status: 'codesign --verify --verbose $2 \"$1\"'"
        EXIT_VALUE=1
	else
		echo "Verified signature of $name"
    fi
}

check_app_signature () {

    # Checks codesign signatures of Tunnelblick application at $1 and does spctl to check it, too.
    #
    # Checks signatures of the application, all of its binaries, and the Sparkle framework.
    #
    # Outputs a line for each problem encountered, having filtered "success" lines.

    # GLOBAL EXIT_VALUE

    local app_path; app_path="$1"

    codesign_verify_verbose "$app_path" --deep

    # Check individual binaries
    for f in tun-notarized.kext tap-notarized.kext atsystemstart installer openvpnstart process-network-changes standardize-scutil-output tunnelblickd tunnelblick-helper Tunnelblick-LaunchAtLogin ; do
        codesign_verify_verbose "$app_path/Contents/Resources/$f"
    done

    # Check OpenVPN binaries
    local openvpn_version_dir
    for openvpn_version_dir in "$app_path/Contents/Resources/openvpn"/* ; do
        if [ "${openvpn_version_dir: -7}" != "default" ] ; then
            if [ -e "$openvpn_version_dir" ] ; then
                local filename
                for filename in openvpn openvpn-down-root.so ; do
                    codesign_verify_verbose "${openvpn_version_dir}/$filename"
                done
            else
                echo "Error: No versions of OpenVPN to codesign in Resources/openvpn"
                echo "       openvpn_version_dir = '$openvpn_version_dir'"
                echo "       openvpn_version_dir: -7 = '${openvpn_version_dir: -7}'"
                EXIT_VALUE=1
            fi
        fi
    done

    # Check Sparkle framework:
    local sparkle_framework;           sparkle_framework="$app_path/Contents/Frameworks/Sparkle.framework"
	local tunnelblickUpdater_app_path; tunnelblickUpdater_app_path="${sparkle_framework}/Versions/A/Resources/TunnelblickUpdater.app"
	local fileop_path;                 fileop_path="${tunnelblickUpdater_app_path}/Contents/MacOS/fileop"
	if [ -d "${tunnelblickUpdater_app_path}" ] ; then
		if [ -f "${fileop_path}" ] ; then
			codesign_verify_verbose  "${fileop_path}"
		else
			echo "Error: Does not exist: '${fileop_path}'"
			EXIT_VALUE=1
		fi
		codesign_verify_verbose  "${tunnelblickUpdater_app_path}"
	else
		echo "Error: Does not exist: '${tunnelblickUpdater_app_path}'"
		EXIT_VALUE=1
	fi
	codesign_verify_verbose "${sparkle_framework}"

    set +e
        spctl --assess --verbose --no-cache "$app_path"
        local status=$?
        if [  status = 0 ] ; then
            echo "Passed spctl assessment: '$app_path'"
        else
            echo "Error: Failed spctl assessment: '$app_path'"
            EXIT_VALUE=1
        fi
    set -e
}

##########################################################################################
### BEGINNING OF SCRIPT                                                                ###
##########################################################################################

	# Set 'EXIT_VALUE' global. Set non-zero by routines to indicate that an error occurred.
	EXIT_VALUE=0

	# Set 'ITEM_DIR' global. Used in path_suffix routine to shorten the path displayed in messages
	item_path="$1";                readonly item_path
	ITEM_DIR=$( full_path "$( dirname "$1" )" )/; readonly ITEM_DIR

	# Set 'TMP_FILE_PATH' global in a temporary directory and keep the directory path to delete it when done
	tmp_dir_path=$( mktemp -d "${TMPDIR:-/tmp/}$(basename "$0").XXXXXXXXXXXX" ); readonly tmp_dir_path
	TMP_FILE_PATH="$tmp_dir_path/temp-file.txt";                                 readonly TMP_FILE_PATH

    # Set 'SIGN_IDENTITY' global to the signing identity to be used, from argument to command,
    # or from the CODE_SIGN_IDENTITY variable, or as "-" if neither of those are supplied.
    if [ -n "$2" ] ; then
    	SIGNING_IDENTITY="$2"
    else
		if [ -z "$CODE_SIGN_IDENTITY" ] ; then
			SIGNING_IDENTITY="-"
		else
			SIGNING_IDENTITY="$CODE_SIGN_IDENTITY"
		fi
	fi

	if [ "${item_path: -4}" = ".app" ] ; then
		signing_an_app=true;  readonly signing_an_app
	elif [ "${item_path: -4}" = ".dmg" ] ; then
		signing_an_app=false; readonly signing_an_app
	else
		echo "Can only sign an .app or a .dmg, not $item_path"
		exit 1
	fi

	if $signing_an_app ; then
		sign_app "$item_path"
		if [  $EXIT_VALUE = 0 ] ; then
			check_app_signature "$item_path"
		fi
	else
		codesign_v_t_or "$item_path" --deep
		if [  $EXIT_VALUE = 0 ] ; then
			codesign_verify_verbose "$item_path" --deep
		fi
	fi

	rm -rf "$tmp_dir_path"

	exit $EXIT_VALUE
