# functions used in manage-iocs

usage() {
    printf "Usage: %s [-v] [-x] cmd\n" `basename $0`
    echo "Available commands:"
    echo "  help            - display this message"
    echo "  report [ioc]    - Show config(s) of all/an IOC on localhost"
    echo "  status          - Check if IOCs are running"
    echo "  nextport        - Find the next unused procServ port"
    echo "  install <ioc>   - Create /etc/systemd/system/softioc-[ioc].service"
    echo "  uninstall <ioc> - Remove /etc/systemd/system/softioc-[ioc].service"
    echo "  start <ioc>     - Start the IOC <ioc>"
    echo "  stop <ioc>      - Stop the IOC <ioc>"
    echo "  startall        - Start all IOCs installed for this system"
    echo "  stopall         - Stop all IOCs installed for this system"
    echo "  list            - a list of IOC instances under $IOCBASE;\
 may be different from 'manage-iocs report'"
    exit 2
}


requireroot() {
    [ "`id -u`" -eq 0 ] || die "Aborted: this action requires root access"
}


# Run command $1 on IOC all instances
# $1 - A shell command
# $2 - one and only one IOC name (empty for all IOCs)
visit() {
    [ -z "$1" ] && die "visitall: missing argument"
    vcmd="$1"
    vname="$2"
    shift
    shift

    save_IFS="$IFS"
    IFS=':'
    for ent in $IOCBASE
    do
        IFS="$save_IFS"
        [ -z "$ent" -o ! -d "$ent" ] && continue

        for iocconf in "$ent"/*/config
        do
            ioc="`dirname "$iocconf"`"
            name="`basename "$ioc"`"
            [ "$name" = '*' ] && continue

            if [ -z "$vname" ] || [ "$name" = "$vname" ]; then
                $vcmd $ioc "$@"
            fi
        done
    done
}


# Find the location of an IOC
# prints a single line which is a directory, which contains '$IOC/config'
# $1 - IOC name
findbase() {
    [ -z "$1" ] && die "findbase: missing argument"
    IOC="$1"

    save_IFS="$IFS"
    IFS=':'
    for ent in $IOCBASE
    do
        IFS="$save_IFS"
        [ -z "$ent" -o ! -d "$ent" ] && continue

        if [ -f "$ent/$IOC/config" ]; then
            printf "$ent"
            return 0
        fi
    done
    return 1
}


# Print an IOC instance config on localhost: BASEDIR  IOCNAME  USER  PORT  CMD
# $1 - iocdir (i.e. /epics/iocs/example)
reportone() {
    [ $# -ge 2 ] && echo "only one IOC instance ($1) is reported: "

    # print header once
    if [ -z "$HEADER" ]; then
        printf "%-15s | %-15s | %-15s | %5s | %s\n" BASE IOC USER PORT EXEC
        export HEADER=1
    fi

    # may not need the following check
    if [ ! -r "$1/config" ]; then
        echo "Missing config $1/config" >&2
        return 1
    fi

    unset EXEC USER HOST
    PORT=0
    local IOC="`basename $1`"
    local BASE="`dirname $1`"
    local INSTBASE="$1"
    #CHDIR="$1"
    . "$1/config"
    USER="${USER:-${IOC}}"
    EXEC="${EXEC:-${INSTBASE}/st.cmd}"

    printf "%-15s | %-15s | %-15s | %5s | %s\n" $BASE $IOC $USER $PORT $EXEC
}


installioc() {
    IOC="$1"
    IOCBASE="`findbase "$IOC"`"
    [ $? -ne 0 -o -z "$IOCBASE" ] && 
        die "Failed to find ioc $IOC in $IOCBASE: missing 'config' in $IOC?"

    GLOBALBASE="$IOCBASE/config"
    INSTBASE="$IOCBASE/$IOC"
    # Modify environment before including global config
    # NAME is the ioc instance name to be used for consistance checking
    NAME=invalid
    # PORT to be used by procServ
    PORT=invalid
    # USER to run procServ (if not set defaults to $IOC)
    unset USER
    # Computer that this softioc runs on.  Used to prevent copy+paste
    # errors and duplicate PV names.  (optional)
    unset HOST
    unset CHDIR
    unset EXEC
    INSTCONF="$INSTBASE/config"
    CHDIR="$INSTBASE"

    if [ -f "$GLOBALBASE/config" ]; then
	    cd "$GLOBALBASE"
	    . "$GLOBALBASE/config"
    fi

    # thsese variables must be defined in $INSTCONF: NAME, PORT, HOST
    cd "$INSTBASE" || die "Failed to cd to $INSTBASE"
    . "$INSTCONF"

    # provide defaults for things not set by any config
    # default user name is softioc instance name
    USER="${USER:-${IOC}}"
    id $USER &> /dev/null || \
        die "Aborted: the user '$USER' does not exist; please set USER in "$INSTCONF""

    EXEC="${EXEC:-${CHDIR}/st.cmd}"
    [ -r $EXEC ] || die "Aborted: the startup script $EXEC does not exist"

    # consistency checking
    [ "$NAME" = "invalid" ] && die "Aborted: configuration does not set IOC name"
    [ "$NAME" = "$IOC" ] || die "Aborted: Wrong NAME('$NAME') set in "$INSTCONF""
    
    # check if telnet PORT is already being used
    [ "$PORT" = "invalid" ] && die "Aborted: configuration does not set port"
    # ports: a string, not an array
    ports="`visit reportone "" | grep -vw "$NAME" | awk '{print $7}' ORS=' '| sort -n`"
    #echo "$ports"
    [[ $ports == *$PORT* ]] && die "Aborted: PORT $PORT is already being used"
    
    if [ -n "$HOST" ]; then
      if [ "$HOST" != "$(hostname -s)" -a "$HOST" != "$(hostname -f)" ]; then
        die "Aborted: Wrong HOST('$HOST') set in "$INSTCONF""
      fi
    fi

    # The official runtime environment
    export HOSTNAME="$(hostname -s)"
    export IOCNAME="$NAME"
    export TOP="$INSTBASE"
    #export EPICS_HOST_ARCH=`/usr/lib/epics/startup/EpicsHostArch`
    export PROCPORT="$PORT"

	# Needed so that the pid file can be written by $USER
	# procServ will put in the correct pid
    PID=$PIDDIR/softioc-$IOC.pid
	touch $PID || die "Failed to create pid file"
	chown "$USER" $PID || die "Failed to chown pid file"
	# Ensure PID is readable so 'manage-iocs status' works for anyone
	# regardless of the active umask when an ioc is restarted.
	chmod a+r $PID || die "Failed to chmod pid file"

	# create log directory if necessary
    IOCLOGDIR=$LOGDIR/softioc/${IOC}
	[ -d "$IOCLOGDIR" ] || install -d -m755 -o "$USER" "$IOCLOGDIR" \
	|| echo "Warning: Failed to create directory: $IOCLOGDIR"

    # procServ arguments: --foreground, --quiet, --chdir, --ignore ...    
    PROCARGS="-f -q -c $CHDIR -i ^D^C^] -p $PID -n $IOC --restrict"
    # By default write logfile.  Set to 0 or '' to disable.
    LOG=1
    if [ -n "$LOG" -a "$LOG" != 0 ]; then
	    PROCARGS="$PROCARGS -L $IOCLOGDIR/$IOC.log"
    fi

    #if [ -n $CORESIZE ]; then
	#    PROCARGS="$PROCARGS --coresize=$CORESIZE"
    #fi

    echo "Installing IOC $IOCBASE/$IOC ..."
    SCRIPT="$SYSTEMDDIR/softioc-$IOC.service"
    if [ -f "$SCRIPT" ] && ! grep 'AUTOMATICALLYGENERATED' "$SCRIPT" &>/dev/null
    then
        # script is a file and isn't automatically managed
        mv --backup=numbered "$SCRIPT" "$SCRIPT".old || die "failed to backup"
        echo "Backing up existing script"
    fi

    cat << EOF > "$SCRIPT"
## Notice
# This file was generated by `basename $0`
# on `date -R`
# If you edit this file, remove the following line to prevent automatic updates
## AUTOMATICALLYGENERATED
[Unit]
Description=IOC $IOC via procServ 
After=network.target remote_fs.target local_fs.target syslog.target time.target
ConditionFileIsExecutable=$PROCSERV

[Service]
User=$USER
ExecStart=$PROCSERV $PROCARGS $PORT $EXEC
#Restart=on-failure

[Install]
WantedBy=multi-user.target

EOF

    [ -f "$SCRIPT" -a -s "$SCRIPT" ] || die "Failed to create $SCRIPT"
    #chmod +x "$SCRIPT"
    echo "  the unit file $SCRIPT has been created"
    echo "To start the IOC:"
    echo "  `basename $0` start $IOC"
}
