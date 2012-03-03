#!/bin/bash
#####################
#
# name: trash (trash.sh)
# vers: 0.2a
# date: 061708
# first: 061708
# auth: "Keith Beckman" <kbeckm@alphahelical.com>
# site: http://alphahelical.com/code/osx/trash
# desc: trash gives command-line access to the OS X Finder Trash
#       facilities. Due to limitations in Finder->delete, trash
#       declines to operate on symlinks rather than allowing the
#       Finder to move the referenced file to the trash. You really
#       shouldn't be dealing with symlinks in the context of the
#       Finder anyway.
#
#       trash requires bash(1).
#
# todo: "-d|--disc disc" confines `trash -l` to the specified disc(s)
# todo: investigate the "put away" functionality which used to be in
#       Finder's Trash handling to see if "original path" is still kept,
#       so trashed files can be restored to their original locations
#
#####################

####configuration####

verstring='trash v0.2a 061708 Keith Beckman'
verbosity=1

##end configuration##

echo_usage () {
	cat >&2 <<EOF
Usage: trash -[ehlv][fqV] [file_1 file_2 ...]
	trash makes use of the Finder's built-in Trash management
	to allow easy access to OS X's Trash from the terminal.

	-e|--empty empties the trash after processing files (if any)
	-f|--force disables confirmation prompting
	-l|--list lists contents of all available trashes
	-q|--quiet disables error reporting
	-V|--verbose enables verbose listings and activity reporting
	-v|--version displays the version string
	-h|--help displays this help text
EOF
	}

fullpath () {
	if [[ -d "${1}" ]]; then
		echo $(cd "${1}"; pwd)
	elif [[ -e "${1}" || -L "${1}" ]]; then
		echo $(cd $(dirname "${1}"); pwd)/$(basename "${1}")
	else
		printf "Error: $s\n" "'${1}' could not be found."
	fi
	}

osa_trash () {
###
# Unfortunately, we can't use the on run handler with argv, since
# there's no way to handle args with spaces without heavy string
# processing in osascript. This means osa_trash must be invoked
# once for each file to be deleted
###
	fp=$(fullpath "${1}")
	if [[ -d "${fp}" ]]; then
		ft='folder'
	elif [[ -f "${fp}" ]]; then
		ft='file'
	else
		report_error "'${fp}' is neither a directory nor a file."
		exit
	fi

	osascript <<EOF
tell application "Finder"
	posix path of ((delete posix file "${fp}") as unicode text)
end tell
EOF
	}

osa_emptytrash () {
	osascript <<EOF
tell application "Finder"
	empty trash
end tell
EOF
	}

osa_list_trash () {
	osascript <<EOF
tell application "Finder"
	set theList to ""
	repeat with theFile in trash
		set theList to theList & posix path of file (theFile as unicode text) & "\n"
	end repeat
end tell
EOF
	}

report () {
# Usage: report message [verbosity_threshold]
	if [[ -n "${1}" && ${verbosity:-1} -gt ${2:-1} ]]; then
		printf "%s\n" "${1}" >&2
	fi
	}

report_error () {
#Usage: report_error message
	report "Error: ${1:-uknown error}" 0
	}

do_trash () {
	if [[ -L "${1}" ]]; then
		report_error "Please use rm(1) to remove symlinks."
	elif [[ -d "${1}" || -f "${1}" ]]; then
		result=$(osa_trash "${1}")
		report "Deleted: ${1} => ${result}"
	else
		report_error "File '${1}' does not exist or is not a regular file or directory"
	fi				
	shift
	}

do_empty_trash () {
	if [[ ! $force ]]; then
		read -p "Really empty trash? [yN] " empty
		if [[ "${empty:0:1}" != 'y' && "${empty:0:1}" != 'Y' ]]; then
			unset empty
		fi
	fi
	if [[ $empty ]]; then
		report "Emptying trash."
		osa_emptytrash
	else
		report "Cancelled emptying trash."
	fi
	}

do_list_trash () {
	osa_list_trash | while read line; do
		if [[ "${line}" != "" ]]; then
			if [[ $verbosity -gt 1 ]]; then
				if [[ -d "${line}" ]]; then 
					echo
					echo "${line}:"
					ls -lR "${line}"
				else
					ls -ld "${line}"
				fi
			else
				echo "${line}"
			fi
		fi
	done
	}

while [[ -n "${1}" ]]; do
	if [[ "${1:0:2}" == '--' ]]; then
		case "${1#--}" in
			empty)
				shopt=e
				;;
			force)
				shopt=f
				;;
			verbose)
				shopt=V
				;;
			list)
				shopt=l
				;;
			quiet|silent)
				shopt=q
				;;
			help|usage)
				shopt=h
				;;
			version)
				shopt=v
				;;
			'')
				shopt=-
				;;
			*)
				report_error "Unknown long option '${1}'"
				echo_usage
				exit -1
				;;
		esac
		args="$args -${shopt}"
	elif [[ "${1:0:1}" == '-' ]]; then
		args="$args ${1}"
	else
		args="$args '${1}'"
	fi
	shift
done

report "Constructed argument list: ${args}" 3
args=$(getopt 'efVqlhv' $args)
report "Parsed argument list: ${args}" 3

if [[ $? != 0 || "${args:1}" == '--' ]]; then
	echo_usage
	exit -1
else
	eval "set -- $args"
fi

while [[ -n "${1}" ]]; do
	case "${1#-}" in
		e)
			empty=1
			;;
		f)
			force=1
			;;
		q)
			verbosity=0
			;;
		V)
			verbosity=2
			;;
		l)
			list=1
			;;
		h)
			echo_usage
			exit
			;;
		v)
			echo $verstring
			exit
			;;
		-)
			shift
			break
			;;
		*)
			report_error "Unknown option '${1}'"
			;;
	esac
	shift
done

while [[ -n "${1}" ]]; do
	do_trash "${1}"
	shift
done

if [[ $list ]]; then
	do_list_trash
fi

if [[ $empty ]]; then
	do_empty_trash
fi
