#!/usr/bin/env bash
############################################################################
# increasetimeouts.sh
#	Copyright 2023-2025 OneCD
#
# Contact:
#	one.cd.only@gmail.com
#
# Description:
#	This script is part of the 'IncreaseTimeouts' package
#
# Available via the sherpa package manager:
#	https://git.io/sherpa
#
# Project source:
#	https://github.com/OneCDOnly/IncreaseTimeouts
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

set -o nounset -o pipefail
shopt -s extglob
[[ -L /dev/fd ]] || ln -fns /proc/self/fd /dev/fd		# KLUDGE: `/dev/fd` isn't always created by QTS.
readonly r_user_args_raw=$*

Init()
    {

    readonly r_qpkg_name=IncreaseTimeouts

    # KLUDGE: mark QPKG installation as complete.

    /sbin/setcfg $r_qpkg_name Status complete -f /etc/config/qpkg.conf

    # KLUDGE: 'clean' the QTS 4.5.1+ App Center notifier status.

    [[ -e /sbin/qpkg_cli ]] && /sbin/qpkg_cli --clean $r_qpkg_name &> /dev/null

	readonly r_backup_utility_pathfile=/usr/local/sbin/qpkg_service.orig
	readonly r_chars_regular_prompt='$ '
		readonly r_chars_sudo_prompt="${r_chars_regular_prompt}sudo "
	readonly r_chars_super_prompt='# '
	readonly r_nas_firmware_ver=$(GetFirmwareVer)
	readonly r_qpkg_extended_timeout_seconds=1800		# 30 minutes
    readonly r_qpkg_version=$(/sbin/getcfg $r_qpkg_name Version -f /etc/config/qpkg.conf)
	readonly r_service_action_pathfile=/var/log/$r_qpkg_name.action
	readonly r_service_result_pathfile=/var/log/$r_qpkg_name.result
	readonly r_target_utility_pathfile=/usr/local/sbin/qpkg_service

    }

StartQPKG()
	{

	IsSU ||	exit 1
	IncreaseTimeouts
	SendToStart $r_qpkg_name

	}

StopQPKG()
	{

	IsSU ||	exit 1
	DecreaseTimeouts

	}

StatusQPKG()
	{

	if IsTimeoutsIncreased; then
		ShowAsInfo 'QPKG timeouts have been increased'
		exit 0
	else
		ShowAsInfo 'default QPKG timeouts are in-effect'
		exit 1
	fi

	}

IncreaseTimeouts()
	{

	# Notes:

	# utility is not boot-persistent (but timeout specifier is unsupported anyway):
	#	QTS 4.2.6.0468 20221028 (TS-559 Pro+)

	# utility is boot-persistent as /usr is symlink to /mnt/ext/usr:
	#	QTS 4.3.3.1624 20221124 (TS-220)

	# utility is not boot-persistent:
	#	QTS 5.1.0.2444 20230629 (TS-230)
	#	QTS 5.1.0.2444 20230629 (TS-231P2)
	#	QTS 5.2.5.3145 20250526 (TS-251+)

	# utility timeout is larger than 11 minutes (actual is unknown):
	#	QTS 5.2.5.3145 20250526 (TS-251+)

	if ! IsOsSupportQpkgTimeout; then
		ShowAsAbort "QPKG timeouts are unsupported in this $(GetQnapOS) version"
		return 1
	fi

	if [[ ! -e $r_target_utility_pathfile ]]; then
		ShowAsError 'original utility not found'
		return 1
	fi

	if [[ -e $r_backup_utility_pathfile ]]; then
		ShowAsInfo 'QPKG timeouts have already been increased'
	else
		mv "$r_target_utility_pathfile" "$r_backup_utility_pathfile"

		/bin/cat > "$r_target_utility_pathfile" << EOF
#!/usr/bin/env bash
# This script was added by IncreaseTimeouts: https://github.com/OneCDOnly/IncreaseTimeouts
# Increase the default timeout for 'qpkg_service' to $((r_qpkg_extended_timeout_seconds/60)) minutes.
# Subsequent specification of -t values will override this value.
$r_backup_utility_pathfile -t $r_qpkg_extended_timeout_seconds "\$@"
EOF

		/bin/chmod +x "$r_target_utility_pathfile"
		ShowAsDone "QPKG timeouts have been increased to $((r_qpkg_extended_timeout_seconds/60)) minutes"
	fi

	return 0

	}

DecreaseTimeouts()
	{

	if [[ ! -e $r_backup_utility_pathfile ]]; then
		ShowAsInfo 'default QPKG timeouts are in-effect'
	else
		mv -f "$r_backup_utility_pathfile" "$r_target_utility_pathfile"
		ShowAsDone 'default QPKG timeouts have been restored'
	fi

	return 0

	}

ShowTitle()
    {

    echo "$(ShowAsTitleName) $(ShowAsVersion)"

	echo -e "\nIncrease the timeouts for the $(GetQnapOS) 'qpkg_service' utility from 3 minutes (default) to $((r_qpkg_extended_timeout_seconds/60)) minutes."

    }

ShowAsTitleName()
	{

	TextBrightWhite $r_qpkg_name

	}

ShowAsVersion()
	{

	printf '%s' "v$r_qpkg_version"

	}

ShowAsUsage()
    {

    echo -e "\nUsage: $0 {start|stop|restart|status}"

	}

SendToStart()
    {

    # sends $1 to the start of qpkg.conf

    local temp_pathfile=/tmp/qpkg.conf.tmp
    local buffer=$(ShowDataBlock "${1:-}")

    if [[ $? -gt 0 ]]; then
        echo "error - ${buffer}!"
        return 2
    fi

    /sbin/rmcfg "${1:-}" -f /etc/config/qpkg.conf
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

    if [[ -z ${1:-} ]]; then
        echo 'QPKG not specified'
        return 1
    fi

    if ! /bin/grep "${1:-}" /etc/config/qpkg.conf &> /dev/null; then
        echo 'QPKG not found'; return 2
    fi

    sl=$(/bin/grep -n "^\[${1:-}\]" /etc/config/qpkg.conf | /usr/bin/cut -f1 -d':')
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

	tr 'a-z' 'A-Z' <<< "${1:-}"

	}

Lowercase()
	{

	tr 'A-Z' 'a-z' <<< "${1:-}"

	}

ShowAsInfo()
	{

	# note to user

	echo "$(TextBrightYellow note):" "${1:-}"

	} >&2

ShowAsDone()
	{

	# process completed OK

	echo "$(TextBrightGreen 'done'):" "${1:-}"

	} >&2

ShowAsAbort()
	{

	# fatal abort

	echo "$(TextBrightRed bort):" "${1:-}"

	} >&2

ShowAsError()
	{

	# fatal error

	echo "$(TextBrightRed derp):" "$(Capitalise "${1:-}")"

	} >&2

SetServiceAction()
	{

	service_action=${1:-none}
	CommitServiceAction
	SetServiceResultAsInProgress

	}

SetServiceResultAsOK()
	{

	service_result=ok
	CommitServiceResult

	}

SetServiceResultAsFailed()
	{

	service_result=failed
	CommitServiceResult

	}

SetServiceResultAsInProgress()
	{

	# Selected action is in-progress and hasn't generated a result yet.

	service_result=in-progress
	CommitServiceResult

	}

CommitServiceAction()
	{

    echo "$service_action" > "$r_service_action_pathfile"

	}

CommitServiceResult()
	{

    echo "$service_result" > "$r_service_result_pathfile"

	}

IsSU()
	{

	# running as superuser?

	if [[ $EUID -ne 0 ]]; then
		if [[ -e /usr/bin/sudo ]]; then
			ShowAsError 'this utility must be run with superuser privileges. Try again as:'

			echo "${r_chars_sudo_prompt}$0 $r_user_args_raw" >&2
		else
			ShowAsError "this utility must be run as the 'admin' user. Please login via SSH as 'admin' and try again"
		fi

		return 1
	fi

	return 0

	}

IsOsSupportQpkgTimeout()
	{

	[[ ${r_nas_firmware_ver//.} -ge 430 ]]

	}

IsTimeoutsIncreased()
	{

	[[ -e $r_backup_utility_pathfile ]]

	}

GetQnapOS()
    {

    if IsQuTS; then
        printf 'QuTS hero'
    else
        printf QTS
    fi

    }

IsQuTS()
    {

    /bin/grep zfs /proc/filesystems

    } &> /dev/null

GetFirmwareVer()
	{

	/sbin/getcfg System Version -f /etc/config/uLinux.conf

	}

TextBrightGreen()
	{

    printf '\033[1;32m%s\033[0m' "${1:-}"

	}

TextBrightYellow()
	{

    printf '\033[1;33m%s\033[0m' "${1:-}"

	}

TextBrightRed()
	{

    printf '\033[1;31m%s\033[0m' "${1:-}"

	}

TextBrightWhite()
	{

    printf '\033[1;97m%s\033[0m' "${1:-}"

	}

Init

user_arg=${r_user_args_raw%% *}		# Only process first argument.

case $user_arg in
    ?(-)r|?(--)restart)
        SetServiceAction restart

        if StopQPKG && StartQPKG; then
            SetServiceResultAsOK
        else
            SetServiceResultAsFailed
        fi
        ;;
    ?(--)start)
        SetServiceAction start

        if StartQPKG; then
            SetServiceResultAsOK
        else
            SetServiceResultAsFailed
        fi
        ;;
    ?(-)s|?(--)status)
        StatusQPKG
        ;;
    ?(--)stop)
        SetServiceAction stop

        if StopQPKG; then
            SetServiceResultAsOK
        else
            SetServiceResultAsFailed
        fi
        ;;
    *)
        ShowTitle
        ShowAsUsage
esac

exit 0
