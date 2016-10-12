#!/bin/bash
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

# Launch Tunnelblick if the 'launchAtNextLogin' preference is "1" or OpenVPN is running.
#
# The preference is set to "1" when you launch Tunnelblick and is set to "0" when you
# quit Tunnelblick and you are not logging out.
# So Tunnelblick is launched only if it was running when you logged out or shut down
# or restarted the computer or a process whose name contains 'openvpn' or 'tunnelblick-helper'
# is running. (This includes 'openvpnstart' and 'tunnelblick-helper' to handle the case where
# OpenVPN is about to be started but has not yet been started.)

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
