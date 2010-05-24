#!/bin/bash -e
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

# NOTE: We don't use the script arguments, so we don't need to shift any Tunnelblick options out of the argument list

# Get info saved by the up script
TUNNELBLICK_CONFIG="$(/usr/sbin/scutil <<-EOF
	open
	show State:/Network/OpenVPN
	quit
EOF)"

ARG_MONITOR_NETWORK_CONFIGURATION="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*MonitorNetwork :' | sed -e 's/^.*: //g')"
LEASEWATCHER_PLIST_PATH="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*LeaseWatcherPlistPath :' | sed -e 's/^.*: //g')"
LOG_FILE="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*LogFile :' | sed -e 's/^.*: //g')"
PSID="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*Service :' | sed -e 's/^.*: //g')"
# Don't need: ARG_RESTORE_ON_DNS_RESET="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RestoreOnDNSReset :' | sed -e 's/^.*: //g')"
# Don't need: ARG_RESTORE_ON_WINS_RESET="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RestoreOnWINSReset :' | sed -e 's/^.*: //g')"
# Don't need: PROCESS="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*PID :' | sed -e 's/^.*: //g')"

# Issue warning if the primary service ID has changed
PSID_CURRENT="$( (scutil | grep Service | sed -e 's/.*Service : //')<<- EOF
	open
	show State:/Network/OpenVPN
	quit
EOF)"

if [ "{PSID}" != "{PSID_CURRENT}" ] ; then
        echo -e "\003\n$(date '+%Y-%m-%d %T') *Tunnelblick: Warning: Ignoring change of Network Primary Service from ${PSID} to ${PSID_CURRENT}\003" >> "${LOG_FILE}"
fi

# Remove leasewatcher
if {ARG_MONITOR_NETWORK_CONFIGURATION} ; then
    launchctl unload "${LEASEWATCHER_PLIST_PATH}"
fi

# Restore configurations
scutil <<- EOF
	open
	get State:/Network/OpenVPN/OldDNS
	set State:/Network/Service/${PSID}/DNS
	remove State:/Network/Service/${PSID}/SMB
	remove State:/Network/OpenVPN/SMB
	remove State:/Network/OpenVPN/DNS
	remove State:/Network/OpenVPN/OldSMB
	remove State:/Network/OpenVPN/OldDNS
	remove State:/Network/OpenVPN
	quit
EOF
