#!/bin/bash -e
#
# 2011-04-18 Changed from client.3.down.tunnelblick.sh to client.3.down.tunnelblick.sh

trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

# NOTE: This script does not use any arguments passed to it by OpenVPN, so it doesn't shift Tunnelblick options out of the argument list

# Do something only if the server pushed something
if [ "$foreign_option_1" == "" ]; then
	exit 0
fi

# Get info saved by the up script
TUNNELBLICK_CONFIG="$(/usr/sbin/scutil <<-EOF
	open
	show State:/Network/OpenVPN
	quit
EOF)"
ARG_MONITOR_NETWORK_CONFIGURATION="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*MonitorNetwork :' | sed -e 's/^.*: //g')"
LEASEWATCHER_PLIST_PATH="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*LeaseWatcherPlistPath :' | sed -e 's/^.*: //g')"
PSID="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*Service :' | sed -e 's/^.*: //g')"
SCRIPT_LOG_FILE="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*ScriptLogFile :' | sed -e 's/^.*: //g')"
# Don't need: ARG_RESTORE_ON_DNS_RESET="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RestoreOnDNSReset :' | sed -e 's/^.*: //g')"
# Don't need: ARG_RESTORE_ON_WINS_RESET="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RestoreOnWINSReset :' | sed -e 's/^.*: //g')"
# Don't need: PROCESS="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*PID :' | sed -e 's/^.*: //g')"

# Issue warning if the primary service ID has changed
PSID_CURRENT="$( (scutil | grep Service | sed -e 's/.*Service : //')<<- EOF
	open
	show State:/Network/OpenVPN
	quit
EOF)"
if [ "${PSID}" != "${PSID_CURRENT}" ] ; then
    echo "$(date '+%a %b %e %T %Y') *Tunnelblick client.3.down.tunnelblick.sh: Ignoring change of Network Primary Service from ${PSID} to ${PSID_CURRENT}" >> "${SCRIPT_LOG_FILE}"
fi

# Remove leasewatcher
if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
    launchctl unload "${LEASEWATCHER_PLIST_PATH}"
    echo "$(date '+%a %b %e %T %Y') *Tunnelblick client.3.down.tunnelblick.sh: Cancelled monitoring of system configuration changes" >> "${SCRIPT_LOG_FILE}"
fi

# Restore configurations
DNS_OLD="$(/usr/sbin/scutil <<-EOF
    open
    show State:/Network/OpenVPN/OldDNS
    quit
EOF)"
WINS_OLD="$(/usr/sbin/scutil <<-EOF
    open
    show State:/Network/OpenVPN/OldSMB
    quit
EOF)"
TB_NO_SUCH_KEY="<dictionary> {
  TunnelblickNoSuchKey : true
}"

if [ "${DNS_OLD}" = "${TB_NO_SUCH_KEY}" ] ; then
    scutil <<- EOF
        open
        remove State:/Network/Service/${PSID}/DNS
        quit
EOF
else
    scutil <<- EOF
        open
        get State:/Network/OpenVPN/OldDNS
        set State:/Network/Service/${PSID}/DNS
        quit
EOF
fi

if [ "${WINS_OLD}" = "${TB_NO_SUCH_KEY}" ] ; then
    scutil <<- EOF
        open
        remove State:/Network/Service/${PSID}/SMB
        quit
EOF
else
    scutil <<- EOF
        open
        get State:/Network/OpenVPN/OldSMB
        set State:/Network/Service/${PSID}/SMB
        quit
EOF
fi

echo "$(date '+%a %b %e %T %Y') *Tunnelblick client.3.down.tunnelblick.sh: Restored the DNS and WINS configurations" >> "${SCRIPT_LOG_FILE}"

# Remove our system configuration data
scutil <<- EOF
	open
	remove State:/Network/OpenVPN/SMB
	remove State:/Network/OpenVPN/DNS
	remove State:/Network/OpenVPN/OldSMB
	remove State:/Network/OpenVPN/OldDNS
	remove State:/Network/OpenVPN
	quit
EOF

exit 0
