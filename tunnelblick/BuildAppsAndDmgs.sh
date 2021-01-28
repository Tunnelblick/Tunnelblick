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
# This script is the final step in creating Tunnelblick. It creates Tunnelblick.app, Tunnelblick Uninstaller.app, and the disk images for each of them.

# Save the working directory so we can cd to it easily
original_wd="$( pwd )"

# Touch the build folder to get it to the top of listings sorted by modification date
touch build

# Set paths in the build folder
readonly         app_path="build/${CONFIGURATION}/${PROJECT_NAME}.app"
readonly uninstaller_path="build/${CONFIGURATION}/${PROJECT_NAME} Uninstaller.app"

# If Xcode has built Tunnelblick.app in somewhere unexpected, complain and quit
if [ ! -d "${app_path}" ] ; then
  if [ "$ACTION" = "install" ] ; then
    echo "You must 'Build' Tunnelblick before doing an 'Archive'"
  else
    echo "An Xcode preference must be set to put build products in the 'tunnelblick/build' folder. Please set Xcode preference > Locations > Advanced to 'Legacy'"
  fi
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

  mv "${uninstaller_path}/Contents/MacOS/droplet" "${uninstaller_path}/Contents/MacOS/Tunnelblick Uninstaller"

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

# Copy the uninstaller scripts into Resources
  cp -p -f tunnelblick-uninstaller.sh          "${app_path}/Contents/Resources/tunnelblick-uninstaller.sh"
  cp -p -f tunnelblick-uninstaller.applescript "${app_path}/Contents/Resources/tunnelblick-uninstaller.applescript"

# Index the help files
  hiutil -Caf "${app_path}/Contents/Resources/help/help.helpindex" "${app_path}/Contents/Resources/help"

# If the notarized versions exist, use them, otherwise use the normal versions.
kext_products_folder="$( cd ../third_party/products/tuntap ; pwd )"
  if [ -e "$kext_products_folder/tap-notarized.kext" ] ; then
    tap_name="tap-notarized.kext"
  else
	tap_name="tap.kext"
  fi
  if [ -e "$kext_products_folder/tun-notarized.kext" ] ; then
	tun_name="tun-notarized.kext"
  else
	tun_name="tun.kext"
  fi

# Copy helpers into Resources
  cp -a "build/${CONFIGURATION}/atsystemstart"              "${app_path}/Contents/Resources/"
  cp -a "build/${CONFIGURATION}/installer"                  "${app_path}/Contents/Resources/"
  cp -a "build/${CONFIGURATION}/openvpnstart"               "${app_path}/Contents/Resources/"
  cp -a "build/${CONFIGURATION}/process-network-changes"    "${app_path}/Contents/Resources/"
  cp -a "build/${CONFIGURATION}/standardize-scutil-output"  "${app_path}/Contents/Resources/"
  cp -a "build/${CONFIGURATION}/tunnelblickd"               "${app_path}/Contents/Resources/"
  cp -a "build/${CONFIGURATION}/tunnelblick-helper"         "${app_path}/Contents/Resources/"

# Copy tun & tap kexts into the Resources folder
  cp -a "$kext_products_folder/$tap_name" "${app_path}/Contents/Resources/"
  cp -a "$kext_products_folder/$tun_name" "${app_path}/Contents/Resources/"

# Create a tuntap .pkg in the build folder

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
  cp -pR "$kext_products_folder/$tap_name" "$pkg_target_dir/pkgbuild/tap_root/Library/Extensions/tap.kext"
  cp -pR "$kext_products_folder/$tun_name" "$pkg_target_dir/pkgbuild/tun_root/Library/Extensions/tun.kext"

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
  cd "$pkg_target_dir"
  productbuild	--distribution	"$pkg_src_folder/distribution.xml" \
				--package-path	"$pkg_target_dir/pkgbuild" \
				--resources		"$pkg_src_folder/res.dummy" \
				"$pkg_target_dir/tuntap_$tuntap_version.pkg"
  cd "$original_wd"

  # Add the actual resources to the package
  pkgutil --expand "$pkg_target_dir/tuntap_$tuntap_version.pkg" "$pkg_target_dir/pkgbuild/tuntap_pkg.d"
  cp -pR "$pkg_src_folder/res/" "$pkg_target_dir/pkgbuild/tuntap_pkg.d/Resources"
  pkgutil --flatten "$pkg_target_dir/pkgbuild/tuntap_pkg.d" "$pkg_target_dir/tuntap_$tuntap_version.pkg"

  # Create a.tar.gz of the tuntap package
  mkdir "$pkg_target_dir/tunnelblick_tuntap_$tuntap_version"
  cd    "$pkg_target_dir/tunnelblick_tuntap_$tuntap_version"
  cp -a "$pkg_src_folder/../README"                  "README"
  cp -a "$pkg_src_folder/../README.installer"        "README.installer"
  cp -a "$pkg_target_dir/tuntap_$tuntap_version.pkg" "tuntap_$tuntap_version.pkg"
  tar czf "$pkg_target_dir/../tunnelblick_tuntap_$tuntap_version.tar.gz" .
  cd "$original_wd"

changeEntry()
{
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
        printf "warning: cannot change '$2' to '$3' because '$1' does not exist\n"
	fi
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

# Set the build number (CFBundleVersion) from TBBuildNumber.txt (inside CFBundleShortVersionString) in the app and uninstaller
readonly tbbn="$(cat TBBuildNumber.txt)"
changeEntry "${app_path}/Contents/Info.plist"         TBBUILDNUMBER "${tbbn}"
changeEntry "${uninstaller_path}/Contents/Info.plist" TBBUILDNUMBER "${tbbn}"

# Set the CFBundleVersion from TBKextVersionNumber.txt in any kexts that have not been notarized
# Kexts must have small numbers as the second and optional 3rd part of CFBundleVersion.
readonly kextbn="$(cat TBKextVersionNumber.txt)"
for k in "${app_path}/Contents/Resources/"*.kext ; do
  if [ -e "$k" ] ; then
	f="$(basename "$k" )"
	if [ "$f" != "tap-notarized.kext" ] \
	&& [ "$f" != "tun-notarized.kext" ] ; then
		changeEntry "${app_path}/Contents/Resources/$f/Contents/Info.plist" TBBUILDNUMBER     "${tbbn}"
        changeEntry "${app_path}/Contents/Resources/$f/Contents/Info.plist" TBKEXTBUILDNUMBER "${kextbn}"
	fi
  fi
done

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

# Set the build date and time
changeEntry "${app_path}/Contents/Info.plist" TBBUILDTIMESTAMP   "$( date -j +%s )"

# Create the openvpn directory structure:
# ...Contents/Resources/openvpn contains a folder for each version of OpenVPN.
# The folder for each vesion of OpenVPN is named "openvpn-x.x.x".
# Each "openvpn-x.x.x"folder contains the openvpn binary and the openvpn-down-root.so binary
mkdir -p "${app_path}/Contents/Resources/openvpn"
default_openvpn="z"

# DEFAULT OpenVPN will be the lowest version linked to OpenSSL with the following prefix:
default_openvpn_version_prefix="openvpn-2.4"
default_openssl_version_prefix="openssl-1.1.1"

for d in `ls "../third_party/products/openvpn"`
do
  # Include this version of OpenVPN if it is not a beta, rc, or git version, or it's a debug build of Tunnelblick, or it is a Tunnelblick beta
  # In other words, remove beta/rc/git versions of OpenVPN from non-debug builds of stable releases of Tunnelblick.
  t="${d/_beta/}"
  t="${t/_git/}"
  t="${t/_rc/}"
  u="${tbvs/beta/}"
  if [ "$d" == "$t" ] || [ "${CONFIGURATION}" = "Debug" ] || [ "$u" != "$tbvs" ] ; then
    mkdir -p "${app_path}/Contents/Resources/openvpn/${d}"
    cp "../third_party/products/openvpn/${d}/openvpn-executable" "${app_path}/Contents/Resources/openvpn/${d}/openvpn"
    cp "../third_party/products/openvpn/${d}/openvpn-down-root.so" "${app_path}/Contents/Resources/openvpn/${d}/openvpn-down-root.so"
    chmod 744 "${app_path}/Contents/Resources/openvpn/${d}/openvpn-down-root.so"
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
  rm -f "${app_path}/Contents/Resources/openvpn/default"
  ln -s "${default_openvpn}/openvpn" "${app_path}/Contents/Resources/openvpn/default"
else
  echo "error: Could not find a version of OpenVPN to use by default; default_openvpn_version_prefix = '$default_openvpn_version_prefix'"
fi

# Copy en.lproj/Localizable.strings (It isn't copied in Debug builds using recent versions of Xcode, probably because it is the primary language)
if test ! -f "${app_path}/Contents/Resources/en.lproj/Localizable.strings" ; then
  cp -p -f "en.lproj/Localizable.strings" "${app_path}/Contents/Resources/en.lproj/Localizable.strings"
  echo "warning: Copied en.lproj/Localizable.strings from source code into .app"
fi

# Rename the .plist files if this is a rebranded version of Tunnelblick
ntt="net.tunnelblick"
ntt="${ntt}.tunnelblick"
if [ "${ntt}" != "net.tunnelblick.tunnelblick" ] ; then
  mv "${app_path}/Contents/Resources/${ntt}.tunnelblickd.plist"  "${app_path}/Contents/Resources/net.tunnelblick.tunnelblick.tunnelblickd.plist"
  mv "${app_path}/Contents/Resources/${ntt}.LaunchAtLogin.plist" "${app_path}/Contents/Resources/net.tunnelblick.tunnelblick.LaunchAtLogin.plist"
fi

# Copy the Tunnelblick icon over Sparkle's AutoUpdate.app icon (Our Sparkle patches create AutoUpdate.app as 'TunnelblickUpdater.app')
readonly updaterIcons="${app_path}/Contents/Frameworks/Sparkle.framework/Resources/TunnelblickUpdater.app/Contents/Resources/AppIcon.icns"
if [ -e "${updaterIcons}" ] ; then
	cp -f -p -R "${app_path}/Contents/Resources/tunnelblick.icns" "${updaterIcons}"
else
    echo "warning: No Sparkle AutoUpdater app icons to replace (missing ${updaterIcons})"
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
chmod 744 "${app_path}/Contents/Resources/client.4.up.tunnelblick.sh"
chmod 744 "${app_path}/Contents/Resources/client.4.down.tunnelblick.sh"
chmod 744 "${app_path}/Contents/Resources/re-enable-network-services.sh"

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
    status=$?
    if [ "${status}" -ne "0" ]; then
        echo "ERROR creating .dmg"
		exit ${status}
    fi

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
    status=$?
    if [ "${status}" -ne "0" ]; then
        echo "ERROR creating uninstaller .dmg"
		exit ${status}
    fi

	# Leave the staging folder so customized .dmgs can be easily created

    touch "build/${CONFIGURATION}/${PROJECT_NAME} Uninstaller.dmg"
    touch "build/${CONFIGURATION}/${PROJECT_NAME}.dmg"
fi

touch "${uninstaller_path}"
touch "${app_path}"
