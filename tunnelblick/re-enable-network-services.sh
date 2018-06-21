#!/bin/bash -e
# Note: must be bash; uses bash-specific tricks
#
# ******************************************************************************************************************
# This Tunnelblick script re-enables network services that were disabled by client-route-pre-down.sh
# ******************************************************************************************************************

trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

list_path="/Library/Application Support/Tunnelblick/disabled-network-services.txt"

if [  ! -e "$list_path" ] ; then
	echo "No list of network services to re-enable"
	exit 0
fi

list="$(  cat "$list_path" )"
if [  "$list" = "" ] ; then
	echo "No network services to re-enable"
	rm -f "$list_path"
	exit 0
fi

# Get list of services (remove the first line which contains a heading)
dia_services="$( networksetup  -listallnetworkservices | sed -e '1,1d')"

# Go through the list re-enabling the services
printf %s "$dia_services
" | \
while IFS= read -r dia_service ; do

	# If first character of a line is not an asterisk, the service is enabled, so we skip it (but we don't skip Wi-Fi no matter what)
	if [  "${dia_service:0:1}" == "*" -o "$dia_service" = "Wi-Fi"  ] ; then

		if [  "${dia_service:0:1}" == "*"  ] ; then
			dia_service="${dia_service:1}"
		fi

		if [[  "$list" =~ "\"$dia_service\""  ]] ; then

			if [ "$dia_service" = "Wi-Fi" ] ; then
				dia_interface="$(networksetup -listallhardwareports | awk '$3=="Wi-Fi" {getline; print $2}')"
				dia_airport_power="$( networksetup -getairportpower "$dia_interface" | sed -e 's/^.*: //g' )"
				if [  "$dia_airport_power" = "Off"  ] ; then
					networksetup -setairportpower "$dia_interface" on
					echo "Turned on $dia_service ($dia_interface)"
				else
					echo "$dia_service ($dia_interface) was already on"
				fi
			else
				# (We already know it is disabled from the above)
				networksetup -setnetworkserviceenabled "$dia_service" on
				echo "Re-enabled $dia_service"
			fi
		fi
	fi

done

rm -f "$list_path"

exit 0
