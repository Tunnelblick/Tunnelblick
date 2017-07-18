#!/bin/bash
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

# Launch Tunnelblick if the 'launchAtNextLogin' preference is "1" or OpenVPN is running or is about to be run.
#
# The preference is set to "1" when you launch Tunnelblick if the 'doNotLaunchOnLogin' preference is not "1".
# The preference is set to "0" when you quit Tunnelblick and you are not logging out.

launch_at_login_preference="$( defaults read net.tunnelblick.tunnelblick launchAtNextLogin 2> /dev/null )"
if [ "${launch_at_login_preference}" = "1" ] ; then
  open /Applications/Tunnelblick.app
  exit
fi

processes="$(ps -ef)"

openvpn_is_running="$( echo "${processes}" | grep -w openvpn | grep -v grep )"
if [ "${openvpn_is_running}" != "" ] ; then
  open /Applications/Tunnelblick.app
  exit
fi

helper_is_running="$( echo "${processes}" | grep -w tunnelblick-helper | grep -v grep )"
if [ "${helper_is_running}" != "" ] ; then
  open /Applications/Tunnelblick.app
  exit
fi
