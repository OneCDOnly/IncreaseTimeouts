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

Init()
    {

    readonly QPKG_NAME=IncreaseTimeouts
	readonly TARGET_UTILITY_PATHFILE=/usr/local/sbin/qpkg_service
	readonly BACKUP_UTILITY_PATHFILE=/usr/local/sbin/qpkg_service.orig

    /sbin/setcfg "$QPKG_NAME" Status complete -f /etc/config/qpkg.conf

    # KLUDGE: 'clean' the QTS 4.5.1 App Center notifier status
    [[ -e /sbin/qpkg_cli ]] && /sbin/qpkg_cli --clean "$QPKG_NAME" > /dev/null 2>&1

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
		ShowAsInfo 'default QPKG timeouts have already been increased'
	else
		mv "$TARGET_UTILITY_PATHFILE" "$BACKUP_UTILITY_PATHFILE"

		/bin/cat > "$TARGET_UTILITY_PATHFILE" << EOF
#!/usr/bin/env bash
#* this script was added by sherpa: https://git.io/sherpa
#* increase the default timeout for qpkg_service to $((QPKG_EXTENDED_TIMEOUT_SECONDS/60)) minutes
#* subsequent specification of -t values will override this value
$BACKUP_UTILITY_PATHFILE -t $QPKG_EXTENDED_TIMEOUT_SECONDS "\$@"
EOF

		/bin/chmod +x "$TARGET_UTILITY_PATHFILE"
		ShowAsDone "default QPKG timeouts have been increased to $((QPKG_EXTENDED_TIMEOUT_SECONDS/60)) minutes"
	fi

	qpkg_timeouts_increased=true
	return 0

	}

QPKGs.Timeouts:Decrease()
	{

	if [[ ! -e $BACKUP_UTILITY_PATHFILE ]]; then
		ShowAsInfo 'default QPKG timeouts are in-effect'
	else
		mv -f "$BACKUP_UTILITY_PATHFILE" "$TARGET_UTILITY_PATHFILE"
		ShowAsDone 'default QPKG timeouts have been reverted to 3 minutes'
	fi

	qpkg_timeouts_increased=false
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

Init

case $1 in
    start)
		QPKGs.Timeouts:Increase
		SendToStart "$QPKG_NAME"
        ;;
    stop)
		QPKGs.Timeouts:Decrease
        ;;
	restart)
		QPKGs.Timeouts:Decrease
		QPKGs.Timeouts:Increase
		;;
	status)
		if [[ -e $BACKUP_UTILITY_PATHFILE ]]; then
			echo 'default QPKG timeouts have been increased'
			exit 0
		else
			echo 'default QPKG timeouts are in-effect'
			exit 1
		fi
		;;
    *)
        echo -e "\n Usage: $0 {start|stop|restart|status}\n"
esac

SetServiceOperationResultOK

exit 0
