#!/bin/bash
#
# Copyright (c) 2015, 2016 by Jonathan K. Bullard. All rights reserved.
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
# This script is the final step in creating Tunnelblick. It creates Tunnelblick.app, Tunnelblick Uninstaller.app, and the disk images for each of them.

# Touch the build folder to get it to the top of listings sorted by modification date
touch build

# Set paths in the build folder
readonly         app_path="build/${CONFIGURATION}/${PROJECT_NAME}.app"
readonly uninstaller_path="build/${CONFIGURATION}/${PROJECT_NAME} Uninstaller.app"

# If Xcode has built Tunnelblick.app in somewhere unexpected, complain and quit
if [ ! -d "${app_path}" ] ; then
  echo "error: An Xcode preference must be set to put build products in the 'tunnelblick/build' folder. Please set Xcode preference > Locations > Advanced to 'Legacy'"
  exit 1
fi

# Make sure that all .lproj folders have been copied to Tunnelblick.app/Contents/Resources
# (They should be put in Xcode's "Resources" so they will be copied automatically)
readonly lprojs_in_source="$(ls -l | grep .lproj | wc -l | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
readonly lprojs_in_app="$(ls -l "${app_path}/Contents/Resources" | grep .lproj | wc -l | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [ "$lprojs_in_source" != "$lprojs_in_app" ] ; then
  echo "error: There are $lprojs_in_source .lproj folders in the source code, but $lprojs_in_app are in the application as built. Add missing .lproj folders to the project's Resources so they will copied into the application"
  exit 1
fi


# Compile Tunnelblick Uninstaller
  rm -r -f      "${uninstaller_path}"
  osacompile -o "${uninstaller_path}" -x "tunnelblick-uninstaller.applescript"

  # The droplet product of the above 'osacompile' command doesn't support PowerPC G3 processors, so we replace it with a droplet compiled on Tiger (which supports PowerPC G3 and 32-bit Intel processors)
  # See tunnelblick-uninstaller-droplet-note.txt for details 
  rm -f "${uninstaller_path}/Contents/MacOS/droplet"
  cp -p "tunnelblick-uninstaller-droplet-compiled-on-tiger" "${uninstaller_path}/Contents/MacOS/Tunnelblick Uninstaller"

  # Add the Uninstaller .app's Info.plist and its icon, script, and localization resources
  cp -p -f "tunnelblick-uninstaller.Info.plist"   "${uninstaller_path}/Contents/Info.plist"
 
  cp -p "tunnelblick-uninstaller.icns"               "${uninstaller_path}/Contents/Resources/droplet.icns"
  cp -p "tunnelblick-uninstaller.sh"                 "${uninstaller_path}/Contents/Resources/tunnelblick-uninstaller.sh"

  for d in `ls "tunnelblick-uninstaller-localization"`
  do
    cp -p -f -R tunnelblick-uninstaller-localization/${d} "${uninstaller_path}/Contents/Resources"
  done

# Copy easy-rsa-tunnelblick, removing .DS_Store files
  rm -r -f                                     "${app_path}/Contents/Resources/easy-rsa-tunnelblick"
  cp -R "../third_party/products/easy-rsa-tunnelblick/" "${app_path}/Contents/Resources/easy-rsa-tunnelblick"
  rm -rf "${app_path}/Contents/Resources/easy-rsa-tunnelblick/keys/.svn"
  rm -rf "${app_path}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3/.svn"
  rm -rf "${app_path}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3/doc/.svn"
  rm -rf "${app_path}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3/easyrsa3/.svn"
  rm -rf "${app_path}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3/easyrsa3/x509-types/.svn"
  rm -rf "${app_path}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3/Licensing/.svn"
  rm -rf "${app_path}/Contents/Resources/easy-rsa-tunnelblick/EasyRSA-3.svn"
  rm -rf "${app_path}/Contents/Resources/easy-rsa-tunnelblick/.svn"
  rm -rf "${app_path}/Contents/Resources/easy-rsa-tunnelblick/.svn"
  find   "${app_path}/Contents/Resources/easy-rsa-tunnelblick"   -name .DS_Store -exec rm -f  '{}' ';'

# Index the help files
  hiutil -Caf "${app_path}/Contents/Resources/help/help.helpindex" "${app_path}/Contents/Resources/help"

# Copy the tun and tap kexts
  rm -r -f                                  "${app_path}/Contents/Resources/tap-20111101.kext"
  cp -R "../third_party/products/tuntap/tap-20111101.kext/" "${app_path}/Contents/Resources/tap-20111101.kext"

  rm -r -f                                  "${app_path}/Contents/Resources/tun-20111101.kext"
  cp -R "../third_party/products/tuntap/tun-20111101.kext/" "${app_path}/Contents/Resources/tun-20111101.kext"

  rm -r -f                                  "${app_path}/Contents/Resources/tap.kext"
  cp -R "../third_party/products/tuntap/tap.kext/"          "${app_path}/Contents/Resources/tap.kext"
 
  rm -r -f                                  "${app_path}/Contents/Resources/tun.kext"
  cp -R "../third_party/products/tuntap/tun.kext/"          "${app_path}/Contents/Resources/tun.kext"

# Create copies of kexts to be signed, too, for Mavericks and higher
  rm -r -f                                  "${app_path}/Contents/Resources/tap-signed.kext"
  cp -R "../third_party/products/tuntap/tap.kext/"          "${app_path}/Contents/Resources/tap-signed.kext"
 
  rm -r -f                                  "${app_path}/Contents/Resources/tun-signed.kext"
  cp -R "../third_party/products/tuntap/tun.kext/"          "${app_path}/Contents/Resources/tun-signed.kext"

changeEntry()
{
    # Changes a string in an Info.plist (or other file)
    # Replaces all occurances of $2 to $3 in file $1
    #
    # @param String, path to Info.plist or other file that should be modified
    # @param String, name of variable to be replaced (TBVERSIONSTRING, TBBUILDNUMBER, or TBCONFIGURATION)
    # @param String, version or build number

    sed -e "s|${2}|${3}|g" "${1}" > "${1}.tmp"
	mv -f "${1}.tmp" "${1}"
}

# Set the type of configuration ("Debug" or "Unsigned") (inside CFBundleShortVersionString) for the app (only the app; the uninstaller has its own versioning)
if [ "${CONFIGURATION}" = "Debug" ]; then
    readonly tbconfig="Debug"
elif [ "${CONFIGURATION}" = "Release" ]; then
    readonly tbconfig="Unsigned"
else
    readonly tbconfig="unknown configuration"
fi
changeEntry "${app_path}/Contents/Info.plist" TBCONFIGURATION "${tbconfig}"

# Set the version number (e.g. '3.6.2beta02') from TBVersionString.txt (inside CFBundleShortVersionString) for the app (only the app; the uninstaller has its own versioning)
readonly tbvs="$(cat TBVersionString.txt)"
changeEntry "${app_path}/Contents/Info.plist" TBVERSIONSTRING "${tbvs}"

# Set the build number (CFBundleVersion0 from TBBuildNumber.txt (inside CFBundleShortVersionString) in the app and uninstaller
readonly tbbn="$(cat TBBuildNumber.txt)"
changeEntry "${app_path}/Contents/Info.plist"         TBBUILDNUMBER "${tbbn}"
changeEntry "${uninstaller_path}/Contents/Info.plist" TBBUILDNUMBER "${tbbn}"

# Set the CFBundleVersion from TBBuildNumber.txt in the kexts
# Kexts must have small numbers as the second and optional 3rd part of CFBundleVersion
# So we change a Tunnelblick build # of (for example) 1234.5678 to just 5678 for use in the kexts.
# Since the kexts have TBBUILDNUMBER.1, TBBUILDNUMBER.2, or TBBUILDNUMBER.3, they will be 5678.1, 5678.2, and 5678.3
readonly kextbn="${tbbn##*.}"
changeEntry "${app_path}/Contents/Resources/tun-20111101.kext/Contents/Info.plist"   TBBUILDNUMBER "${kextbn}"
changeEntry "${app_path}/Contents/Resources/tap-20111101.kext/Contents/Info.plist"   TBBUILDNUMBER "${kextbn}"
changeEntry "${app_path}/Contents/Resources/tun.kext/Contents/Info.plist"            TBBUILDNUMBER "${kextbn}"
changeEntry "${app_path}/Contents/Resources/tap.kext/Contents/Info.plist"            TBBUILDNUMBER "${kextbn}"
changeEntry "${app_path}/Contents/Resources/tun-signed.kext/Contents/Info.plist"     TBBUILDNUMBER "${kextbn}"
changeEntry "${app_path}/Contents/Resources/tap-signed.kext/Contents/Info.plist"     TBBUILDNUMBER "${kextbn}"

# Copy git information into Info.plist: the hash and the git status (uncommitted changes)
# Warn about uncommitted changes except for Debug builds
if [ -e "../.git" -a  "$(which git)" != "" ] ; then
    readonly git_hash="$(git rev-parse HEAD)"
    readonly git_status="$(git status -s | tr '\n' ' ' )"
    if [  "${git_status}" != "" -a "${CONFIGURATION}" != "Debug" ] ; then
		printf "warning: uncommitted changes:\n${git_status}\n"
    fi
    changeEntry "${app_path}/Contents/Info.plist" TBGITHASH   "${git_hash}"
    changeEntry "${app_path}/Contents/Info.plist" TBGITSTATUS "${git_status}"
fi

# Create the openvpn directory structure:
# ...Contents/Resources/openvpn contains a folder for each version of OpenVPN.
# The folder for each vesion of OpenVPN is named "openvpn-x.x.x".
# Each "openvpn-x.x.x"folder contains the openvpn binary and the openvpn-down-root.so binary
mkdir -p "${app_path}/Contents/Resources/openvpn"
default_openvpn="z"
for d in `ls "../third_party/products/openvpn"`
do
  mkdir -p "${app_path}/Contents/Resources/openvpn/${d}"
  cp "../third_party/products/openvpn/${d}/openvpn-executable" "${app_path}/Contents/Resources/openvpn/${d}/openvpn"
  cp "../third_party/products/openvpn/${d}/openvpn-down-root.so" "${app_path}/Contents/Resources/openvpn/${d}/openvpn-down-root.so"
  chmod 744 "${app_path}/Contents/Resources/openvpn/${d}/openvpn-down-root.so"
  if [ "${d}" \< "${default_openvpn}" ] ; then
    default_openvpn="${d}"
  fi
done

if [ "${default_openvpn}" != "z" ] ; then
  rm -f "${app_path}/Contents/Resources/openvpn/default"
  ln -s "${default_openvpn}/openvpn" "${app_path}/Contents/Resources/openvpn/default"
else
  echo "warning: Could not find a version of OpenVPN to use by default"
fi

# Copy English.lproj/Localizable.strings (It isn't copied in Debug builds using recent versions of Xcode, probably because it is the primary language)
if test ! -f "${app_path}/Contents/Resources/English.lproj/Localizable.strings" ; then
  cp -p -f "English.lproj/Localizable.strings" "${app_path}/Contents/Resources/English.lproj/Localizable.strings"
fi

# Rename the .plist files if this is a rebranded version of Tunnelblick
ntt="net.tunnelblick"
ntt="${ntt}.tunnelblick"
if [ "${ntt}" != "net.tunnelblick.tunnelblick" ] ; then
  mv "${app_path}/Contents/Resources/${ntt}.tunnelblickd.plist"  "${app_path}/Contents/Resources/net.tunnelblick.tunnelblick.tunnelblickd.plist"
  mv "${app_path}/Contents/Resources/${ntt}.LaunchAtLogin.plist" "${app_path}/Contents/Resources/net.tunnelblick.tunnelblick.LaunchAtLogin.plist"
fi

# Remove extra files that are not needed

rm -f "${app_path}/Contents/Resources/TBBuildNumber.txt"
rm -f "${app_path}/Contents/Resources/TBVersionString.txt"

rm -f "${app_path}/Contents/Resources/ExternalBuildCleanScript.sh"

# Remove non-.png files in IconSets (but leave the "templates.png" file)
for d in `ls "${app_path}/Contents/Resources/IconSets"` ; do
  if [ -d "${app_path}/Contents/Resources/IconSets/${d}" ] ; then
    for f in `ls "${app_path}/Contents/Resources/IconSets/${d}"` ; do
      if [ "${f##*.}" != "png" ] ; then
        if [ "${f%.*}" != "templates" ] ; then
          if [ -d "${app_path}/Contents/Resources/IconSets/${d}/${f}" ] ; then
            rm -f -R "${app_path}/Contents/Resources/IconSets/${d}/${f}"
          else
            rm -f "${app_path}/Contents/Resources/IconSets/${d}/${f}"
          fi
        fi
      fi
    done
  else
    rm -f "${app_path}/Contents/Resources/IconSets/${d}"
  fi
done

# Remove extended attributes
for f in ${app_path}/Contents/Resources/*
do
  xattr -d "com.apple.FinderInfo" ${f} 2> /dev/null
done

# Remove NeedsTranslation.strings and Removed.strings from all .lproj folders and set permissions on Localizable.strings and InfoPlist.strings files
shopt -s nullglob
for f in ${app_path}/Contents/Resources/*.lproj ; do
  if test -f "${f}/NeedsTranslation.strings" ; then
    rm "${f}/NeedsTranslation.strings"
  fi
  if test -f "${f}/Removed.strings" ; then
    rm "${f}/Removed.strings"
  fi
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

# Change permissions from 755 to 744 on many executables in Resources (openvpn-down-root.so permissions were changed when setting up the OpenVPN folder structure)
chmod 744 "${app_path}/Contents/Resources/atsystemstart"
chmod 744 "${app_path}/Contents/Resources/installer"
chmod 744 "${app_path}/Contents/Resources/leasewatch"
chmod 744 "${app_path}/Contents/Resources/leasewatch3"
chmod 744 "${app_path}/Contents/Resources/process-network-changes"
chmod 744 "${app_path}/Contents/Resources/standardize-scutil-output"
chmod 744 "${app_path}/Contents/Resources/tunnelblickd"
chmod 744 "${app_path}/Contents/Resources/client.up.tunnelblick.sh"
chmod 744 "${app_path}/Contents/Resources/client.down.tunnelblick.sh"
chmod 744 "${app_path}/Contents/Resources/client.route-pre-down.tunnelblick.sh"
chmod 744 "${app_path}/Contents/Resources/client.1.up.tunnelblick.sh"
chmod 744 "${app_path}/Contents/Resources/client.1.down.tunnelblick.sh"
chmod 744 "${app_path}/Contents/Resources/client.2.up.tunnelblick.sh"
chmod 744 "${app_path}/Contents/Resources/client.2.down.tunnelblick.sh"
chmod 744 "${app_path}/Contents/Resources/client.3.up.tunnelblick.sh"
chmod 744 "${app_path}/Contents/Resources/client.3.down.tunnelblick.sh"

# Create the Tunnelblick .dmg and the Uninstaller .dmg except if Debug
if [ "${CONFIGURATION}" != "Debug" ]; then

	# Staging folder
	TMPDMG="build/${CONFIGURATION}/${PROJECT_NAME}"

	# Folder with files for the .dmg (.DS_Store and background folder which contains background.png background image)
	DMG_FILES="dmgFiles"

	# Remove the existing "staging" folder and copy the application into it
	rm -r -f "$TMPDMG"
	mkdir -p "$TMPDMG"
	cp -p -R "${app_path}" "$TMPDMG"

	# Copy link to documentation to the staging folder
	cp -p "Online Documentation.webloc" "$TMPDMG"

	# Copy the background folder and its background.png file to the staging folder and make the background folder invisible in the Finder
	cp -p -R "$DMG_FILES/background" "$TMPDMG"
	SetFile -a V "$TMPDMG/background"

	# Copy dotDS_Store to .DS_Store and make it invisible in the Finder
	cp -p -R "$DMG_FILES/dotDS_Store" "$TMPDMG/.DS_Store"
	SetFile -a V "$TMPDMG/.DS_Store"

	# Remove any existing .dmg and create a new one. Specify "-noscrub" so that .DS_Store is copied to the image
	rm -r -f "build/${CONFIGURATION}/${PROJECT_NAME}.dmg"
	hdiutil create -noscrub -srcfolder "$TMPDMG" "build/${CONFIGURATION}/${PROJECT_NAME}.dmg"

	# Leave the staging folder so customized .dmgs can be easily created

	# Uninstaller Staging folder
	TMPDMG="build/${CONFIGURATION}/${PROJECT_NAME} Uninstaller"

	# Folder with files for the uninstaller .dmg (.DS_Store and background folder which contains background.png background image)
	DMG_FILES="uninstaller-dmgFiles"

	# Remove the existing "staging" folder and copy the uninstaller into it
	rm -r -f "$TMPDMG"
	mkdir -p "$TMPDMG"
	cp -p -R "${uninstaller_path}" "$TMPDMG"

	# Copy link to documentation to the staging folder
	cp -p "Online Documentation.webloc" "$TMPDMG"

	# Remove any existing .dmg and create a new one. Specify "-noscrub" so that .DS_Store is copied to the image
	rm -r -f "build/${CONFIGURATION}/${PROJECT_NAME} Uninstaller.dmg"
	hdiutil create -noscrub -srcfolder "$TMPDMG" "build/${CONFIGURATION}/${PROJECT_NAME} Uninstaller.dmg"

	# Leave the staging folder so customized .dmgs can be easily created

    touch "build/${CONFIGURATION}/${PROJECT_NAME} Uninstaller.dmg"
    touch "build/${CONFIGURATION}/${PROJECT_NAME}.dmg"
fi

touch "${uninstaller_path}"
touch "${app_path}"
