# functions used in manage-iocs

usage() {
    printf "Usage: %s [-v] [-x] cmd\n" `basename $0`
    echo "Available commands:"
    echo "  help            - Display this message"
    echo "  report [ioc]    - Show config(s) of an IOC/all IOCs on localhost"
    echo "  status          - Check if installed IOCs are running or stopped"
    echo "  nextport        - Find the next unused procServ port"
    echo "  install <ioc>   - Create /etc/systemd/system/softioc-[ioc].service"
    echo "  uninstall <ioc> - Remove /etc/systemd/system/softioc-[ioc].service"
    echo "  start <ioc>     - Start the IOC <ioc>"
    echo "  stop <ioc>      - Stop the IOC <ioc>"
    echo "  restart <ioc>   - Restart the IOC <ioc>"
    echo "  startall        - Start all IOCs installed for this system"
    echo "  stopall         - Stop all IOCs installed for this system"
    echo "  enable <ioc>    - Enable auto-start IOC <ioc> at boot"
    echo "  disable <ioc>   - Disable auto-start IOC <ioc> at boot"
    echo "  list            - A list of all IOC instances under $IOCPATH;"
    echo "                    including those IOCs running on other hosts"
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
    for ent in $IOCPATH
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
    for ent in $IOCPATH
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
    CHDIR="$1"
    . "$1/config"
    USER="${USER:-${IOC}}"
    EXEC="${EXEC:-${CHDIR}/st.cmd}"

    #only report an IOC instance on localhost
    #[ -z "$HOST" ] && echo "Warning: HOST is not set on $INSTBASE" && return 0
    #[ "$HOST" != "$(hostname -s)" -a "$HOST" != "$(hostname -f)" -a -n "$HOST" ] && return 0
    [ "$HOST" != "$(hostname -s)" -a "$HOST" != "$(hostname -f)" ] && return 0
    printf "%-15s | %-15s | %-15s | %5s | %s\n" $BASE $IOC $USER $PORT $EXEC
}


installioc() {
    IOC="$1"
    IOCBASE="`findbase "$IOC"`"
    [ $? -ne 0 -o -z "$IOCBASE" ] && 
        die "Aborted: no '$IOC' or '$IOC/config' in '$IOCPATH'"

    # Thsese variables must have valid/proper values: NAME, PORT, USER, HOST
    # Modify environment before including global config
    # NAME is the ioc instance name to be used for consistance checking
    NAME=invalid
    # PORT (telnet port) to be used by procServ; must be a unique number
    PORT=invalid
    # USER to run procServ; the account USER must exist
    unset USER
    # HOST: computer that this softioc runs on. Used to prevent copy+paste
    # errors and duplicate PV names
    unset HOST
    unset CHDIR
    unset EXEC

    GLOBALBASE="$IOCBASE/config"
    INSTBASE="$IOCBASE/$IOC"
    INSTCONF="$INSTBASE/config"
    CHDIR="$INSTBASE"

    if [ -f "$GLOBALBASE/config" ]; then
        cd "$GLOBALBASE"
        . "$GLOBALBASE/config"
    fi

    # thsese variables must be explicitly set in $INSTCONF: NAME, PORT, HOST
    cd "$INSTBASE" || die "Failed to cd to $INSTBASE"
    . "$INSTCONF"

    # consistency checking
    [ "$NAME" = "invalid" ] && die "Aborted: NAME is not set in '$INSTCONF'"
    [ "$NAME" = "$IOC" ] || die "Aborted: Wrong NAME('$NAME') set in '$INSTCONF';\
 it should be $IOC"
    
    # check if telnet PORT is a number and a unique number
    [ "$PORT" = "invalid" ] && die "Aborted: PORT is not set in '$INSTCONF'"
    case $PORT in
    ''|*[!0-9]*) die "Aborted: PORT($PORT) is not a number in $INSTCONF'" ;;
    esac
    # ports: a string, not an array
    ports="`visit reportone "" | grep -vw "$NAME" | awk '{print $7}' ORS=' '| sort -n`"
    case "$ports" in 
    *$PORT*) die "Aborted: PORT $PORT is already being used; type 'manage-iocs nextport'\
 to find out next available port";;
    esac
    
    [ -z "$HOST" ] && die "Aborted: HOST is not set in '$INSTCONF'"
    [ "$HOST" != "$(hostname -s)" -a "$HOST" != "$(hostname -f)" ] && 
die "Aborted: Wrong HOST('$HOST') set in '$INSTCONF'; it should be "$(hostname -s)""

    # provide defaults for things not set by any config: USER, EXEC
    # default user name is softioc instance name
    USER="${USER:-${IOC}}"
    id $USER &> /dev/null || die "Aborted: the user account '$USER' does not exist;\
 please set USER to an existing account (e.g. 'softioc') in "$INSTCONF""

    EXEC="${EXEC:-${CHDIR}/st.cmd}"
    [ -r $EXEC ] || die "Aborted: the startup script $EXEC does not exist"

    # The official runtime environment
    export HOSTNAME="$(hostname -s)"
    export IOCNAME="$NAME"
    export TOP="$INSTBASE"
    #export EPICS_HOST_ARCH=`/usr/lib/epics/startup/EpicsHostArch`
    export PROCPORT="$PORT"

    # Needed so that the pid file can be written by $USER/procServ
    PID=$PIDDIR/softioc-$IOC.pid
    touch $PID || die "Failed to create pid file $PID"
    chown "$USER" $PID || die "Failed to chown pid file $PID"
    # Ensure PID is readable so 'manage-iocs status' works for anyone
    # regardless of the active umask when an ioc is restarted.
    chmod a+r $PID || die "Failed to chmod pid file $PID"

    # create log directory if necessary
    IOCLOGDIR=$LOGDIR/softioc/${IOC}
    [ -d "$IOCLOGDIR" ] || install -d -m755 -o "$USER" "$IOCLOGDIR" \
    || echo "Warning: Failed to create directory $IOCLOGDIR"

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
