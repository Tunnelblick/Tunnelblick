#!/bin/bash
launch=`defaults read net.tunnelblick.tunnelblick launchAtNextLogin 2> /dev/null`
if [ "${launch}" = "1" ] ; then
  open /Applications/Tunnelblick.app
fi
