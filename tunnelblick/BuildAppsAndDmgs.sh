#!/bin/bash
#
# Copyright (c) 2015, 2016, 2018, 2020, 2021 by Jonathan K. Bullard. All rights reserved.
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
# This script is the final step in creating Tunnelblick. It creates Tunnelblick.app and the Tunnelblick disk image.

changeEntry() {

    # Changes a string in an Info.plist (or other file)
    # Replaces all occurances of $2 to $3 in file $1
    #
    # @param String, path to Info.plist or other file that should be modified
    # @param String, name of variable to be replaced (TBVERSIONSTRING, TBBUILDNUMBER, or TBCONFIGURATION)
    # @param String, version or build number

    if [ -e "$1" ] ; then
        sed -e "s|${2}|${3}|g" "${1}" > "${1}.tmp"
        mv -f "${1}.tmp" "${1}"
    else
        echo "warning: cannot change '$2' to '$3' because '$1' does not exist"
    fi
}

VerifyAppWasBuiltWhereExpected() {

    # If Xcode has built Tunnelblick.app in somewhere unexpected, complain and quit
    if [ ! -d "${APP_PATH}" ] ; then
        if [ "$ACTION" = "install" ] ; then
            echo "You must 'Build' Tunnelblick before doing an 'Archive'"
        else
            echo "An Xcode preference must be set to put build products in the"
            echo "'tunnelblick/build' folder."
            echo "Please set Xcode preference > Locations > Advanced to 'Legacy'"
        fi
        exit 1
    fi
}

VerifyLprojFoldersExist() {

    # Make sure that all .lproj folders have been copied to Tunnelblick.app/Contents/Resources
    # (They should be put in Xcode's "Resources" so they will be copied automatically)

    local lprojs_in_source
    local lprojs_in_app

    lprojs_in_source="$(ls -l | grep .lproj | wc -l | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    lprojs_in_app="$(ls -l "${APP_PATH}/Contents/Resources" | grep .lproj | wc -l | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [ "$lprojs_in_source" != "$lprojs_in_app" ] ; then
        echo "error: There are $lprojs_in_source .lproj folders in the source code, but"
        echo "       there are $lprojs_in_app in the application as built."
        echo "       Clean the build folder and rebuild, or"
        echo "       Add missing .lproj folders to the project's Resources so they"
        echo "       will copied into the application"
        exit 1
    fi
}

IndexHelpFiles() {

    # Index the help files
    hiutil -Caf "${APP_PATH}/Contents/Resources/help/help.helpindex" "${APP_PATH}/Contents/Resources/help"
}

CopyEasyRsaIntoResources() {

    # Copy easy-rsa-tunnelblick, removing .DS_Store files
    rm -r -f "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick"
    cp -R "../third_party/products/easy-rsa-tunnelblick/" "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick"
    rm -rf "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick/keys/.svn"
    rm -rf "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3/.svn"
    rm -rf "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3/doc/.svn"
    rm -rf "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3/easyrsa3/.svn"
    rm -rf "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3/easyrsa3/x509-types/.svn"
    rm -rf "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3/Licensing/.svn"
    rm -rf "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3.svn"
    rm -rf "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick/.svn"
    rm -rf "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick/.svn"
    find   "${APP_PATH}/Contents/Resources/easy-rsa-tunnelblick"   -name .DS_Store -exec rm -f  '{}' ';'
}

CopyInstallerScriptsIntoResources() {

    # Copy the uninstaller scripts into Resources
    cp -p -f tunnelblick-uninstaller.sh          "${APP_PATH}/Contents/Resources/tunnelblick-uninstaller.sh"
    cp -p -f tunnelblick-uninstaller.applescript "${APP_PATH}/Contents/Resources/tunnelblick-uninstaller.applescript"
}

CopyHelpersIntoResources() {

    # Copy helpers into Resources
    cp -a "build/${CONFIGURATION}/atsystemstart"              "${APP_PATH}/Contents/Resources/"
    cp -a "build/${CONFIGURATION}/TunnelblickUpdateHelper"    "${APP_PATH}/Contents/Resources/"
    cp -a "build/${CONFIGURATION}/installer"                  "${APP_PATH}/Contents/Resources/"
    cp -a "build/${CONFIGURATION}/openvpnstart"               "${APP_PATH}/Contents/Resources/"
    cp -a "build/${CONFIGURATION}/process-network-changes"    "${APP_PATH}/Contents/Resources/"
    cp -a "build/${CONFIGURATION}/standardize-scutil-output"  "${APP_PATH}/Contents/Resources/"
    cp -a "build/${CONFIGURATION}/tunnelblickd"               "${APP_PATH}/Contents/Resources/"
    cp -a "build/${CONFIGURATION}/tunnelblick-helper"         "${APP_PATH}/Contents/Resources/"
}

CopyKextsIntoResources() {

    # Copy tun & tap kexts into the Resources folder
    cp -a "$BUILT_KEXTS_FOLDER/$TAP_NAME" "${APP_PATH}/Contents/Resources/"
    cp -a "$BUILT_KEXTS_FOLDER/$TUN_NAME" "${APP_PATH}/Contents/Resources/"
}

CopyLauncherAppIntoLoginItems() {

    # Copy Tunnelblick Launcher.app into Contents/Library/LoginItems

    if [ ! -d "${APP_PATH}/Contents/Library" ] ; then
        mkdir -m 755 "${APP_PATH}/Contents/Library"
    fi

    mkdir -m 755 "${APP_PATH}/Contents/Library/LoginItems"
    cp -a "build/${CONFIGURATION}/Tunnelblick Launcher.app"   "${APP_PATH}/Contents/Library/LoginItems"
}

SetupShortVersionStringInInfoPlist() {

    # Set the type of configuration ("Debug" or "Unsigned") (inside CFBundleShortVersionString) for the app (only the app
    changeEntry "${APP_PATH}/Contents/Info.plist" TBCONFIGURATION "${CONFIG_TYPE}"
}

SetVersionAndBuildInInfoPlist() {

    # Set the version number (e.g. '3.6.2beta02') from TBVersionString.txt (inside CFBundleShortVersionString) for the app
    changeEntry "${APP_PATH}/Contents/Info.plist" TBVERSIONSTRING "${VERSION_STRING}"

    # Set the build number (CFBundleVersion) from TBBuildNumber.txt (inside CFBundleShortVersionString) in the app
    changeEntry "${APP_PATH}/Contents/Info.plist"         TBBUILDNUMBER "${BUILD_STRING}"
}

CopyGitInformationToInfoPlist() {

    # Copy git information into Info.plist: the hash and the git status (uncommitted changes)

    local git_hash
    local git_status

    # Warn about uncommitted changes except for Debug builds
    if [ -e "../.git" -a  "$(which git)" != "" ] ; then
        git_hash="$(git rev-parse HEAD)"
        git_status="$(git status -s | tr '\n' ' ' )"
        if [  "$git_status" != "" -a "${CONFIGURATION}" != "Debug" ] ; then
            echo "warning: uncommitted changes:"
            echo "$git_status"
        fi
        changeEntry "${APP_PATH}/Contents/Info.plist" TBGITHASH   "${git_hash}"
        changeEntry "${APP_PATH}/Contents/Info.plist" TBGITSTATUS "${git_status}"
    fi
}

SetBuildDateAndTimeInInfoPlist() {

    # Set the build date and time
    changeEntry "${APP_PATH}/Contents/Info.plist" TBBUILDTIMESTAMP   "$( date -j +%s )"
}

SetVersionNumberInNonNotarizedKexts() {

    # Set the CFBundleVersion from TBKextVersionNumber.txt in any kexts that have not been notarized
    # Kexts must have small numbers as the second and optional 3rd part of CFBundleVersion.

    local kextbn
    local k
    local f

    kextbn="$(cat TBKextVersionNumber.txt)"

    for k in "${APP_PATH}/Contents/Resources/"*.kext ; do
        if [ -e "$k" ] ; then
            f="$(basename "$k" )"
            if [ "$f" != "tap-notarized.kext" ] \
            && [ "$f" != "tun-notarized.kext" ] ; then
                changeEntry "${APP_PATH}/Contents/Resources/$f/Contents/Info.plist" TBBUILDNUMBER     "${BUILD_STRING}"
                changeEntry "${APP_PATH}/Contents/Resources/$f/Contents/Info.plist" TBKEXTBUILDNUMBER "${kextbn}"
            fi
        fi
    done
}

BuildTunAndTapPackages() {

    # Create a tuntap .pkg in the build folder except if Debug

    local pkg_target_dir
    local pkg_src_folder
    local ttv
    local tuntap_version

    if [ "${CONFIGURATION}" == "Debug" ] ; then
        return
    fi

    # Set up source and target folders
    mkdir -p "build/${CONFIGURATION}/tuntap_pkg"
    pkg_target_dir="$( cd build/${CONFIGURATION}/tuntap_pkg ; pwd )"
    pkg_src_folder="$( cd ../third_party/build/tuntap/tuntap-20141104/tuntap/pkg ; pwd )"

    # Determine tuntap_version (e.g. "20141104") from name of folder
    ttv="$( ls ../third_party/build/tuntap)"
    tuntap_version="${ttv:(-8)}"

    # Remove target folder and .tar.gz if they exist
    rm -f -R "$pkg_target_dir"
    rm -f "$pkg_target_dir/../tunnelblick_tuntap_$tuntap_version.tar.gz"

    # Create Library/Extensions folders and copy the .kexts into it
    mkdir -p "$pkg_target_dir/pkgbuild/tap_root/Library/Extensions"
    mkdir -p "$pkg_target_dir/pkgbuild/tun_root/Library/Extensions"
    cp -pR "$BUILT_KEXTS_FOLDER/$TAP_NAME" "$pkg_target_dir/pkgbuild/tap_root/Library/Extensions/tap.kext"
    cp -pR "$BUILT_KEXTS_FOLDER/$TUN_NAME" "$pkg_target_dir/pkgbuild/tun_root/Library/Extensions/tun.kext"

    # Create Library/LaunchDaemons folders and copy the .plists into then
    mkdir -p "$pkg_target_dir/pkgbuild/tap_root/Library/LaunchDaemons"
    mkdir -p "$pkg_target_dir/pkgbuild/tun_root/Library/LaunchDaemons"
    cp -p "$pkg_src_folder/launchd/net.sf.tuntaposx.tap.plist" "$pkg_target_dir/pkgbuild/tap_root/Library/LaunchDaemons/tap.plist"
    cp -p "$pkg_src_folder/launchd/net.sf.tuntaposx.tun.plist" "$pkg_target_dir/pkgbuild/tun_root/Library/LaunchDaemons/tun.plist"

    # Build the separate tap and tun packages
    pkgbuild 	--root				"$pkg_target_dir/pkgbuild/tap_root" \
                --component-plist	"$pkg_src_folder/components/tap.plist" \
                --scripts			"$pkg_src_folder/scripts/tap" \
                --identifier        "net.tunnelblick.tuntappkg" \
                --timestamp \
                "$pkg_target_dir/tap.pkg"
    pkgbuild 	--root				"$pkg_target_dir/pkgbuild/tun_root" \
                --component-plist	"$pkg_src_folder/components/tun.plist" \
                --scripts			"$pkg_src_folder/scripts/tun" \
                --identifier        "net.tunnelblick.tuntappkg" \
                --timestamp \
                "$pkg_target_dir/tun.pkg"

    # Build the tuntap package
    # Don't put any resources into it, we'll copy them later (don't know why, but this is the way the tuntaposx makefiles do it)
    pushd "$pkg_target_dir" > /dev/null
    productbuild	--distribution	"$pkg_src_folder/distribution.xml" \
                    --package-path	"$pkg_target_dir/pkgbuild" \
                    --resources		"$pkg_src_folder/res.dummy" \
                    "$pkg_target_dir/tuntap_$tuntap_version.pkg"
    popd

    # Add the actual resources to the package
    pkgutil --expand "$pkg_target_dir/tuntap_$tuntap_version.pkg" "$pkg_target_dir/pkgbuild/tuntap_pkg.d"
    cp -pR "$pkg_src_folder/res/" "$pkg_target_dir/pkgbuild/tuntap_pkg.d/Resources"
    pkgutil --flatten "$pkg_target_dir/pkgbuild/tuntap_pkg.d" "$pkg_target_dir/tuntap_$tuntap_version.pkg"

    # Create a.tar.gz of the tuntap package
    mkdir "$pkg_target_dir/tunnelblick_tuntap_$tuntap_version"
    pushd "$pkg_target_dir/tunnelblick_tuntap_$tuntap_version" > /dev/null
    cp -a "$pkg_src_folder/../README"                  "README"
    cp -a "$pkg_src_folder/../README.installer"        "README.installer"
    cp -a "$pkg_target_dir/tuntap_$tuntap_version.pkg" "tuntap_$tuntap_version.pkg"
    tar czf "$pkg_target_dir/../tunnelblick_tuntap_$tuntap_version.tar.gz" .
    popd
}

CreateOpenvpnDirectoryStructure() {

    # Create the openvpn directory structure:
    # ...Contents/Resources/openvpn contains a folder for each version of OpenVPN.
    # The folder for each vesion of OpenVPN is named "openvpn-x.x.x".
    # Each "openvpn-x.x.x"folder contains the openvpn binary and the openvpn-down-root.so binary

    local default_openvpn
    local d
    local t
    local u

    mkdir -p "${APP_PATH}/Contents/Resources/openvpn"
    default_openvpn="z"

    # DEFAULT OpenVPN will be the lowest version linked to OpenSSL with the following prefix:
    default_openvpn_version_prefix="openvpn-2.6"
    default_openssl_version_prefix="openssl-3.0"

    for d in $( ls "../third_party/products/openvpn" ) ; do

        # Include this version of OpenVPN if it is not a beta, rc, or git version, or it's a debug build of Tunnelblick, or it is a Tunnelblick beta
        # In other words, remove beta/rc/git versions of OpenVPN from non-debug builds of stable releases of Tunnelblick.
        t="${d/_beta/}"
        t="${t/_git/}"
        t="${t/_rc/}"
        u="${VERSION_STRING/beta/}"
        if [ "$d" == "$t" ] || [ "${CONFIGURATION}" = "Debug" ] || [ "$u" != "$VERSION_STRING" ] ; then
            mkdir -p "${APP_PATH}/Contents/Resources/openvpn/${d}"
            cp "../third_party/products/openvpn/${d}/openvpn-executable" "${APP_PATH}/Contents/Resources/openvpn/${d}/openvpn"
            cp "../third_party/products/openvpn/${d}/openvpn-down-root.so" "${APP_PATH}/Contents/Resources/openvpn/${d}/openvpn-down-root.so"
            chmod 744 "${APP_PATH}/Contents/Resources/openvpn/${d}/openvpn-down-root.so"
            if [ "${d}" \< "${default_openvpn}" ] ; then
                if [ "${d}" != "${d/$default_openssl_version_prefix/xx}" ] ; then
                    dovp_len=${#default_openvpn_version_prefix}
                    if [ "${d:0:$dovp_len}" = "$default_openvpn_version_prefix" ] ; then
                        echo "Setting default OpenVPN version to $d"
                        default_openvpn="${d}"
                    fi
                fi
            fi
        else
            echo "warning: Not including '$d' because it is not a stable release and this is not a Debug build and this is not a Tunnelblick beta"
        fi
    done

    if [ "${default_openvpn}" != "z" ] ; then
        rm -f "${APP_PATH}/Contents/Resources/openvpn/default"
        ln -s "${default_openvpn}/openvpn" "${APP_PATH}/Contents/Resources/openvpn/default"
    else
        echo "error: Could not find a version of OpenVPN to use by default; default_openvpn_version_prefix = '$default_openvpn_version_prefix'"
    fi
}

CreateLocalizedInfoPlistStringsFiles() {

    # Create a UTF-8 InfoPlist.strings file in each .lproj folder of the built app which has a translation of the copyright notice (but not in en.lproj).
    # The file will have a single line like the following (except the string to the right of the equal sign will be the translated line):
    #   NSHumanReadableCopyright = "Copyright © 2004-TUNNELBLICK_COPYRIGHT_NOTICE_YEAR Angelo Laub, Jonathan Bullard, and others. All rights reserved."
    #
    # If there is no translation, we don't create the file. macOS will use the English version.
    #
    # Do nothing for the en.lproj folder. Xcode copies tunnelblick/en.lproj/InfoPlist.strings there, converted to UTF-16LE, because, for English,
    #  Finder >> File >> Get Info displays the copyright notice only for UTF-16LE files.
    #
    # We create the file for languages other than English as UTF-8 because for those languages Finder >> File >> Get Info displays the copyright notice only for UTF-8 files.
    #
    # >>>>> Yes, that's correct: The English InfoPlist.strings file must be UTF-16LE, but for all other languages it must be UTF-8 !!!!!

    local d
    local outPath
    local temp
    local outputLine

    for d in *.lproj ; do

        outPath="${APP_PATH}/Contents/Resources/$d/InfoPlist.strings"

        if [ "$d" != "en.lproj" ] ; then

            # Read $d/Localizable.strings and get the **LAST** line with TUNNELBLICK_COPYRIGHT_NOTICE_YEAR into $temp
            grep 'TUNNELBLICK_COPYRIGHT_NOTICE_YEAR' < "$d/Localizable.strings" | tail -n 1 > "temp.strings"
            temp="$( cat "temp.strings" )"

            # If there is a translation, copy it to the InfoPlist.strings file
            if [ -n "$temp" ] ; then

                # Remove everything except the translation (remove the double-quotes around the translation, too)
                temp="${temp#*\=}"  # Remove everything up to and including the first (only) equal-sign
                temp="${temp#*\"}"  # Remove everything up to and including the first double-quote
                temp="${temp%\"*}"  # Remove the last double-quote and everything after it

                # Set outputLine to the new contents of the localized InfoPlist.strings file without a terminating LF
                outputLine="NSHumanReadableCopyright = \"$temp\";"

                # Write out the contents plus a terminating LF to Resources/$d/InfoPlist.strings file in the built app
                echo "$outputLine" > "$outPath"
            fi
        fi

        rm -f "temp.strings"
    done
}

UpdateAllInfoPlistStringsFilesWithCurrentYear() {

    # Replace TUNNELBLICK_COPYRIGHT_NOTICE_YEAR with the current 4-digit year
    # in Resources/*.lproj/InfoPlist.strings files in the built app.
    #
    # The file in en.lproj/InfoPlist.strings is created by Xcode as a UTF-16LE file,
    # and Finder >> File >> Get Info displays the copyright info from it ONLY if it is a UTF-16LE file.
    #
    # We create (in createLocalizedInfoPlistStringsFiles) all other InfoPlist.strings files as UTF-8 files,
    # and Finder >> File >> Get Info displays the copyright info from them ONLY if they are UTF-8 files.
    #
    # sed only edits UTF-8 files
    #
    # So, to edit en.lproj/InfoPlist.strings, we convert it to UTF-8, edit that UTF-8 file with sed, then convert it back to UTF-16LE.
    #
    # For all other InfoPlist.strings files, we just edit them in sed as they are (UTF-8).

    local yyyy
    local filePath

    yyyy="$( date -j +%Y )"

    pushd "${APP_PATH}/Contents/Resources" > /dev/null

    for d in *.lproj ; do

        filePath="$d/InfoPlist.strings"

        if [  -f "$filePath" ] ; then

            if [ "$d" = "en.lproj" ] ; then
                iconv -f UTF-16LE -t UTF-8-MAC "$filePath" > temp.strings
                mv -f temp.strings "$filePath"
            fi

            # Note: the -i '' on macOS edits the file in place.
            sed -i '' -e "s|TUNNELBLICK_COPYRIGHT_NOTICE_YEAR|$yyyy|g" "$filePath"

            if [ "$d" = "en.lproj" ] ; then
                iconv -f UTF-8-MAC -t UTF-16LE "$filePath" > temp.strings
                mv -f temp.strings "$filePath"
            fi
        fi
    done
    popd
}

RenameTunnelblickdPlistFileIfRebrandedVersion() {

    # Rename the tunnelblickd .plist file if this is a rebranded version of Tunnelblick

    local ntt

    ntt="net.tunnelblick"
    ntt="${ntt}.tunnelblick"
    if [ "${ntt}" != "net.tunnelblick.tunnelblick" ] ; then
        mv "${APP_PATH}/Contents/Resources/${ntt}.tunnelblickd.plist" \
           "${APP_PATH}/Contents/Resources/net.tunnelblick.tunnelblick.tunnelblickd.plist"
    fi
}

CopyTunnelblickAppIconOverSparkleAutoUpdateAppIcon() {

    # Copy the Tunnelblick icon over Sparkle's AutoUpdate.app icon
    # (Our Sparkle patches create AutoUpdate.app as 'TunnelblickUpdater.app')

    local updaterIcons

    updaterIcons="${APP_PATH}/Contents/Frameworks/Sparkle.framework/Resources/TunnelblickUpdater.app/Contents/Resources/AppIcon.icns"
    if [ -e "${updaterIcons}" ] ; then
        cp -f -p -R "${APP_PATH}/Contents/Resources/tunnelblick.icns" "${updaterIcons}"
    else
        echo "warning: No Sparkle AutoUpdater app icons to replace (missing ${updaterIcons})"
    fi
}

RemoveBuildNumberAndVersionStringTxtFiles() {

    rm -f "${APP_PATH}/Contents/Resources/TBBuildNumber.txt"
    rm -f "${APP_PATH}/Contents/Resources/TBVersionString.txt"
}

RemoveExternalBuildCleanScriptShFile() {

    rm -f "${APP_PATH}/Contents/Resources/ExternalBuildCleanScript.sh"
}

RemoveSuperfluousIconSetsFiles() {

    # Remove non-.png files in IconSets (but leave the "templates.png" file)

    local d

    for d in $( ls "${APP_PATH}/Contents/Resources/IconSets" ) ; do
        if [ -d "${APP_PATH}/Contents/Resources/IconSets/${d}" ] ; then
            for f in $( ls "${APP_PATH}/Contents/Resources/IconSets/${d}" ) ; do
                if [ "${f##*.}" != "png" ] ; then
                    if [ "${f%.*}" != "templates" ] ; then
                        if [ -d "${APP_PATH}/Contents/Resources/IconSets/${d}/${f}" ] ; then
                            rm -f -R "${APP_PATH}/Contents/Resources/IconSets/${d}/${f}"
                        else
                            rm -f "${APP_PATH}/Contents/Resources/IconSets/${d}/${f}"
                        fi
                    fi
                fi
            done
        else
            rm -f "${APP_PATH}/Contents/Resources/IconSets/${d}"
        fi
    done
}

RemoveSuperfluousStringsFiles() {

    # Remove NeedsTranslation.strings and Removed.strings from all .lproj folders

    local f

    for f in "${APP_PATH}/Contents/Resources"/*.lproj ; do
      if test -f "${f}/NeedsTranslation.strings" ; then
        rm "${f}/NeedsTranslation.strings"
      fi
      if test -f "${f}/Removed.strings" ; then
        rm "${f}/Removed.strings"
      fi
    done
}

RemoveExtendedAttributes() {

    xattr -c -rs "${f}" 2> /dev/null # Remove extended attributes
}

SetPermissionsOnStringsFiles() {

    # Set permissions on Localizable.strings and InfoPlist.strings files

    local f

    for f in "${APP_PATH}/Contents/Resources"/*.lproj ; do
        if test -f "${f}/Localizable.strings" ; then
            chmod 644 "${f}/Localizable.strings"
        else
            echo "error: There is no 'Localizable.strings' file in ${f}"
            exit 1
        fi
        if test -f "${f}/InfoPlist.strings" ; then
            chmod 644 "${f}/InfoPlist.strings"
        fi
    done
}

SetPermissionsOnExecutables() {

    # Change permissions from 755 to 744 on many executables in Resources (openvpn-down-root.so permissions were changed when setting up the OpenVPN folder structure)
    chmod 744 "${APP_PATH}/Contents/Resources/atsystemstart"
    chmod 744 "${APP_PATH}/Contents/Resources/TunnelblickUpdateHelper"
    chmod 744 "${APP_PATH}/Contents/Resources/installer"
    chmod 744 "${APP_PATH}/Contents/Resources/leasewatch"
    chmod 744 "${APP_PATH}/Contents/Resources/leasewatch3"
    chmod 744 "${APP_PATH}/Contents/Resources/process-network-changes"
    chmod 744 "${APP_PATH}/Contents/Resources/standardize-scutil-output"
    chmod 744 "${APP_PATH}/Contents/Resources/tunnelblickd"
    chmod 744 "${APP_PATH}/Contents/Resources/client.up.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.down.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.route-pre-down.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.1.up.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.1.down.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.2.up.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.2.down.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.3.up.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.3.down.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.4.up.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.4.down.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.5.up.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/client.5.down.tunnelblick.sh"
    chmod 744 "${APP_PATH}/Contents/Resources/re-enable-network-services.sh"
    chmod 744 "${APP_PATH}/Contents/Library/LoginItems/Tunnelblick Launcher.app/Contents/Info.plist"
    chmod 744 "${APP_PATH}/Contents/Library/LoginItems/Tunnelblick Launcher.app/Contents/PkgInfo"
    chmod 744 "${APP_PATH}/Contents/Library/LoginItems/Tunnelblick Launcher.app/Contents/Resources/Base.lproj/MainMenu.nib"
}

CreateSignedCopyOfApp() {

    # Create a signed copy of the Tunnelblick.app after changing " Unsigned" to " Signed (local)" in the version number except if Debug

    if [ "${CONFIGURATION}" == "Debug" ] ; then
        return
    fi

    rm -r -f "$( dirname  "$SIGNED_APP_PATH" )"
    mkdir -p "$( dirname  "$SIGNED_APP_PATH" )"
    cp -a -f "$APP_PATH" "$SIGNED_APP_PATH"
    changeEntry "$SIGNED_APP_PATH/Contents/Info.plist" " Unsigned</string>" " Signed (local)</string>"
    ./SignTunnelblickAppOrDmg.sh "$SIGNED_APP_PATH"
}

CreateDmg() {

    local tmpdmg
    local dmg_files
    local status

    # Create the Tunnelblick .dmg except if Debug

    if [ "${CONFIGURATION}" == "Debug" ] ; then
        return
    fi

    # Staging folder
    tmpdmg="build/${CONFIGURATION}/${PROJECT_NAME}"

    # Folder with files for the .dmg (.DS_Store and background folder which contains background.png background image)
    dmg_files="dmgFiles"

    # Remove the existing "staging" folder and copy the application into it
    rm -r -f "$tmpdmg"
    mkdir -p "$tmpdmg"
    cp -p -R "${APP_PATH}" "$tmpdmg"

    # Copy link to documentation to the staging folder
    cp -p "Online Documentation.webloc" "$tmpdmg"

    # Copy the background folder and its background.png file to the staging folder and make the background folder invisible in the Finder
    cp -p -R "$dmg_files/background" "$tmpdmg"
    SetFile -a V "$tmpdmg/background"

    # Copy dotDS_Store to .DS_Store and make it invisible in the Finder
    cp -p -R "$dmg_files/dotDS_Store" "$tmpdmg/.DS_Store"
    SetFile -a V "$tmpdmg/.DS_Store"

    # Remove any existing .dmg and create a new one. Specify "-noscrub" so that .DS_Store is copied to the image
    rm -r -f "$DMG_PATH"
    hdiutil create -noscrub -srcfolder "$tmpdmg" "$DMG_PATH"
    status=$?
    if [ "${status}" -ne "0" ]; then
        echo "ERROR creating .dmg"
        exit ${status}
    fi

    # Create a signed copy of the .dmg that contains the signed copy of the .app
    rm -r -f "$tmpdmg/${PROJECT_NAME}.app"
    cp -p -R -f "${SIGNED_APP_PATH}" "$tmpdmg"
    rm -r -f "$SIGNED_DMG_PATH"
    hdiutil create -noscrub -srcfolder "$tmpdmg" "$SIGNED_DMG_PATH"
    status=$?
    if [ "${status}" -ne "0" ]; then
        echo "ERROR creating signed .dmg"
        exit ${status}
    fi
    ./SignTunnelblickAppOrDmg.sh "$SIGNED_DMG_PATH"

    # Leave the staging folder so customized .dmgs can be easily created

    touch "$DMG_PATH"
}

################################################################################
#
# START OF MAIN PROGRAM
#
################################################################################

# Set up shell options

shopt nullglob

# Set up global variables

    APP_PATH="build/${CONFIGURATION}/${PROJECT_NAME}.app"   # Path of .app built by Xcode
    DMG_PATH="build/${CONFIGURATION}/${PROJECT_NAME}.dmg"   # Path of unsigned .dmg we create
    readonly APP_PATH
    readonly DMG_PATH

    SIGNED_APP_PATH="build/${CONFIGURATION}/Signed/${PROJECT_NAME}.app" # Paths of signed .app and signed .dmg we create
    SIGNED_DMG_PATH="build/${CONFIGURATION}/Signed/${PROJECT_NAME}.dmg"
    readonly SIGNED_APP_PATH
    readonly SIGNED_DMG_PATH

    BUILT_KEXTS_FOLDER="$( cd ../third_party/products/tuntap ; pwd )" # Path of the folder containing built kexts
    readonly BUILT_KEXTS_FOLDER

    # Names of the kexts to use:
    #       If the notarized versions of kexts exist then use them, otherwise use the normal versions

    if [ -e "$BUILT_KEXTS_FOLDER/tap-notarized.kext" ] ; then
        TAP_NAME="tap-notarized.kext"
    else
        TAP_NAME="tap.kext"
    fi
    if [ -e "$BUILT_KEXTS_FOLDER/tun-notarized.kext" ] ; then
        TUN_NAME="tun-notarized.kext"
    else
        TUN_NAME="tun.kext"
    fi
    readonly TAP_NAME
    readonly TUN_NAME

    # Type of build (Debug or Release)

    if [ "${CONFIGURATION}" = "Debug" ]; then
        CONFIG_TYPE="Debug"
    elif [ "${CONFIGURATION}" = "Release" ]; then
        CONFIG_TYPE="Unsigned"
    else
        echo "Unknown configuration '$CONFIGURATION'. Must be 'Release' or 'Debug'"
        exit 1
    fi
    readonly CONFIG_TYPE

    VERSION_STRING="$(cat TBVersionString.txt)"   # Tunnelblick version (e.g., 4.0.1beta02)
    BUILD_STRING="$(cat TBBuildNumber.txt)"     # Tunnelblick build number (e.g., 4550)
    readonly VERSION_STRING
    readonly BUILD_STRING

# Do all the work:

    VerifyAppWasBuiltWhereExpected

    VerifyLprojFoldersExist

    IndexHelpFiles

    CopyEasyRsaIntoResources

    CopyInstallerScriptsIntoResources

    CopyHelpersIntoResources

    CopyKextsIntoResources

    CopyLauncherAppIntoLoginItems

    SetupShortVersionStringInInfoPlist

    SetVersionAndBuildInInfoPlist

    CopyGitInformationToInfoPlist

    SetBuildDateAndTimeInInfoPlist

    SetVersionNumberInNonNotarizedKexts

    BuildTunAndTapPackages

    CreateOpenvpnDirectoryStructure

    CreateLocalizedInfoPlistStringsFiles

    UpdateAllInfoPlistStringsFilesWithCurrentYear

    RenameTunnelblickdPlistFileIfRebrandedVersion

    CopyTunnelblickAppIconOverSparkleAutoUpdateAppIcon

    RemoveBuildNumberAndVersionStringTxtFiles

    RemoveExternalBuildCleanScriptShFile

    RemoveSuperfluousIconSetsFiles

    RemoveSuperfluousStringsFiles

    RemoveExtendedAttributes

    SetPermissionsOnStringsFiles

    SetPermissionsOnExecutables

    CreateSignedCopyOfApp

    CreateDmg

# Touch the build folder and app to get them to the top of listings sorted by modification date

    touch build
    touch "${APP_PATH}"
