#!/usr/bin/env bash
############################################################################
# increasetimeouts.sh - (C)opyright 2023 OneCD - one.cd.only@gmail.com
#
# This script is part of the 'IncreaseTimeouts' package
#
# For more info: https://forum.qnap.com/viewtopic.php?
#
# Project source: https://github.com/OneCDOnly/IncreaseTimeouts
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.
############################################################################

readonly USER_ARGS_RAW=$*

Init()
    {

    readonly QPKG_NAME=IncreaseTimeouts
	readonly SCRIPT_VERSION=230718
	readonly TARGET_UTILITY_PATHFILE=/usr/local/sbin/qpkg_service
	readonly BACKUP_UTILITY_PATHFILE=/usr/local/sbin/qpkg_service.orig
	readonly NAS_FIRMWARE_VER=$(GetFirmwareVer)
	readonly QPKG_EXTENDED_TIMEOUT_SECONDS=1800		# 30 minutes
	readonly CHARS_REGULAR_PROMPT='$ '
	readonly CHARS_SUPER_PROMPT='# '
	readonly CHARS_SUDO_PROMPT="${CHARS_REGULAR_PROMPT}sudo "

    /sbin/setcfg "$QPKG_NAME" Status complete -f /etc/config/qpkg.conf

    # KLUDGE: 'clean' the QTS 4.5.1 App Center notifier status
    [[ -e /sbin/qpkg_cli ]] && /sbin/qpkg_cli --clean "$QPKG_NAME" &>/dev/null

    readonly QPKG_PATH=$(/sbin/getcfg $QPKG_NAME Install_Path -f /etc/config/qpkg.conf)
    readonly SERVICE_STATUS_PATHFILE=/var/run/$QPKG_NAME.last.operation

    }

QPKGs.Timeouts:Increase()
	{

	# boot-persistent:
	#	QTS 4.3.3.1624 20221124 (TS-220) as /usr is symlink to /mnt/ext/usr

	# not boot-persistent:
	#	QTS 5.1.0.2444 20230629 (TS-230)
	#	QTS 5.1.0.2444 20230629 (TS-231P2)

	# not boot-persistent (but timeout specifier is unsupported anyway):
	#	QTS 4.2.6.0468 20221028 (TS-559 Pro+)

	if ! OS.IsSupportQpkgTimeout; then
		ShowAsAbort "QPKG timeouts are unsupported in this $(GetQnapOS) version"
		return 1
	fi

	if [[ ! -e $TARGET_UTILITY_PATHFILE ]]; then
		ShowAsError 'original utility not found'
		return 1
	fi

	if [[ -e $BACKUP_UTILITY_PATHFILE ]]; then
		ShowAsInfo 'QPKG timeouts have already been increased'
	else
		mv "$TARGET_UTILITY_PATHFILE" "$BACKUP_UTILITY_PATHFILE"

		/bin/cat > "$TARGET_UTILITY_PATHFILE" << EOF
#!/usr/bin/env bash
# This script was added by IncreaseTimeouts: https://github.com/OneCDOnly/IncreaseTimeouts
# Increase the default timeout for 'qpkg_service' to $((QPKG_EXTENDED_TIMEOUT_SECONDS/60)) minutes.
# Subsequent specification of -t values will override this value.
$BACKUP_UTILITY_PATHFILE -t $QPKG_EXTENDED_TIMEOUT_SECONDS "\$@"
EOF

		/bin/chmod +x "$TARGET_UTILITY_PATHFILE"
		ShowAsDone "QPKG timeouts have been increased to $((QPKG_EXTENDED_TIMEOUT_SECONDS/60)) minutes"
	fi

	return 0

	}

QPKGs.Timeouts:Decrease()
	{

	if [[ ! -e $BACKUP_UTILITY_PATHFILE ]]; then
		ShowAsInfo 'default QPKG timeouts are in-effect'
	else
		mv -f "$BACKUP_UTILITY_PATHFILE" "$TARGET_UTILITY_PATHFILE"
		ShowAsDone 'default QPKG timeouts have been restored'
	fi

	return 0

	}

SendToStart()
    {

    # sends $1 to the start of qpkg.conf

    local temp_pathfile=/tmp/qpkg.conf.tmp
    local buffer=$(ShowDataBlock "$1")

    if [[ $? -gt 0 ]]; then
        echo "error - ${buffer}!"
        return 2
    fi

    /sbin/rmcfg "$1" -f /etc/config/qpkg.conf
    echo -e "$buffer" > "$temp_pathfile"
    /bin/cat /etc/config/qpkg.conf >> "$temp_pathfile"
    mv "$temp_pathfile" /etc/config/qpkg.conf

    }

ShowDataBlock()
    {

    # returns the data block for the QPKG name specified as $1

    local -i sl=0       # line number: start of specified config block
    local -i ll=0       # line number: last line in file
    local -i bl=0       # total lines in specified config block
    local -i el=0       # line number: end of specified config block

    if [[ -z $1 ]]; then
        echo 'QPKG not specified'
        return 1
    fi

    if ! /bin/grep -q "$1" /etc/config/qpkg.conf; then
        echo 'QPKG not found'; return 2
    fi

    sl=$(/bin/grep -n "^\[$1\]" /etc/config/qpkg.conf | /usr/bin/cut -f1 -d':')
    ll=$(/usr/bin/wc -l < /etc/config/qpkg.conf | /bin/tr -d ' ')
    bl=$(/usr/bin/tail -n$((ll-sl)) < /etc/config/qpkg.conf | /bin/grep -n '^\[' | /usr/bin/head -n1 | /usr/bin/cut -f1 -d':')
    [[ $bl -ne 0 ]] && el=$((sl+bl-1)) || el=$ll

    /bin/sed -n "$sl,${el}p" /etc/config/qpkg.conf

    }

Capitalise()
	{

	# capitalise first character of $1

	echo "$(Uppercase ${1:0:1})${1:1}"

	}

Uppercase()
	{

	tr 'a-z' 'A-Z' <<< "$1"

	}

Lowercase()
	{

	tr 'A-Z' 'a-z' <<< "$1"

	}

ShowAsInfo()
	{

	# note to user

	echo "$(ColourTextBrightYellow note):" "${1:-}"

	} >&2

ShowAsDone()
	{

	# process completed OK

	echo "$(ColourTextBrightGreen 'done'):" "${1:-}"

	} >&2

ShowAsAbort()
	{

	# fatal abort

	echo "$(ColourTextBrightRed bort):" "${1:-}"

	} >&2

ShowAsError()
	{

	# fatal error

	echo "$(ColourTextBrightRed derp):" "$(Capitalise "${1:-}")"

	} >&2

SetServiceOperationResultOK()
    {

    SetServiceOperationResult ok

    }

SetServiceOperationResultFailed()
    {

    SetServiceOperationResult failed

    }

SetServiceOperationResult()
    {

    # $1 = result of operation to recorded

    [[ -n $1 && -n $SERVICE_STATUS_PATHFILE ]] && echo "$1" > "$SERVICE_STATUS_PATHFILE"

    }

IsSU()
	{

	# running as superuser?

	if [[ $EUID -ne 0 ]]; then
		if [[ -e /usr/bin/sudo ]]; then
			ShowAsError 'this utility must be run with superuser privileges. Try again as:'

			echo "${CHARS_SUDO_PROMPT}$0 $USER_ARGS_RAW" >&2
		else
			ShowAsError "this utility must be run as the 'admin' user. Please login via SSH as 'admin' and try again"
		fi

		return 1
	fi

	return 0

	}

OS.IsSupportQpkgTimeout()
	{

	[[ ${NAS_FIRMWARE_VER//.} -ge 430 ]]

	}

QPKGs.IsTimeoutsIncreased()
	{

	[[ -e $BACKUP_UTILITY_PATHFILE ]]

	}

GetQnapOS()
	{

	if /bin/grep -q zfs /proc/filesystems; then
		echo 'QuTS hero'
	else
		echo QTS
	fi

	}

GetFirmwareVer()
	{

	/sbin/getcfg System Version -f /etc/config/uLinux.conf

	}

FormatAsPackageName()
	{

	echo "'${1:-}'"

	}

ColourTextBrightGreen()
	{

    printf '\033[1;32m%s\033[0m' "${1:-}"

	} 2>/dev/null

ColourTextBrightYellow()
	{

    printf '\033[1;33m%s\033[0m' "${1:-}"

	} 2>/dev/null

ColourTextBrightRed()
	{

    printf '\033[1;31m%s\033[0m' "${1:-}"

	} 2>/dev/null

ColourTextBrightWhite()
	{

    printf '\033[1;97m%s\033[0m' "${1:-}"

	} 2>/dev/null

Init

case $1 in
    start)
        IsSU ||	exit 1
		QPKGs.Timeouts:Increase
		SendToStart "$QPKG_NAME"
        SetServiceOperationResultOK
        ;;
    stop)
        IsSU ||	exit 1
		QPKGs.Timeouts:Decrease
        SetServiceOperationResultOK
        ;;
	restart)
        IsSU ||	exit 1
		QPKGs.Timeouts:Decrease &>/dev/null
		QPKGs.Timeouts:Increase
        SetServiceOperationResultOK
		;;
	s|status)
		if QPKGs.IsTimeoutsIncreased; then
			ShowAsInfo 'QPKG timeouts have been increased'
			exit 0
		else
			ShowAsInfo 'default QPKG timeouts are in-effect'
			exit 1
		fi
		;;
    *)
        echo "$(ColourTextBrightWhite "$(/usr/bin/basename "$0")") $SCRIPT_VERSION • a service control script for the $(FormatAsPackageName $QPKG_NAME) QPKG"

        echo -e "\nIncrease the timeouts for the $(GetQnapOS) 'qpkg_service' utility from 3 minutes (default) to $((QPKG_EXTENDED_TIMEOUT_SECONDS/60)) minutes."

        echo -e "\nUsage: $0 {start|stop|restart|status}\n"
esac

exit 0
