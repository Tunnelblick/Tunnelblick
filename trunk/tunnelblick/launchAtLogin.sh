#!/bin/bash
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"
launch="$( defaults read net.tunnelblick.tunnelblick launchAtNextLogin 2> /dev/null )"
if [ "${launch}" = "1" ] ; then
  open /Applications/Tunnelblick.app
fi
