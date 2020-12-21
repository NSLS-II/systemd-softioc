#!/bin/bash

function die {
    echo "$1" >&2
    exit 1
}

[ "`id -u`" -eq 0 ] || die "Aborted: this action requires root (sudo) access"

#create a username 'softioc' (used in an IOC's config) if it doesn't exist
id softioc &> /dev/null || useradd softioc


#copy source files to $INSTALLDIR
INSTALLDIR=/usr/local/systemd-softioc
[ -d $INSTALLDIR ] || install -d -m755 "$INSTALLDIR" || die "Failed to create $INSTALLDIR"

cp ./epics-softioc.conf $INSTALLDIR
cp ./library.sh $INSTALLDIR
cp ./manage-iocs $INSTALLDIR

[ $? -ne 0 ] && die "Failed to copy files to $INSTALLDIR" 
echo "Source files are successfully copied to $INSTALLDIR. See below:"
ls -lht $INSTALLDIR

#install epics-softioc.logrotate
if [ -d /etc/logrotate.d ]; then
    cp epics-softioc.logrotate /etc/logrotate.d || echo "Failed to setup logrotate"
fi

#'manage-iocs' is a symbolic link
SYMLINK=/usr/bin/manage-iocs
if [ -f $SYMLINK -a "$(readlink -f $SYMLINK)" != $INSTALLDIR/manage-iocs ]; then
    ls -lh $SYMLINK
    die "There is already a symlink: $SYMLINK->$(readlink -f $SYMLINK). \
Please manually remove it. Then type 'sudo ./install.sh' to reinstall this package"
fi

printf "\nCreating the symlink $SYMLINK ...\n"
rm -f $SYMLINK || die "Failed to remove $SYMLINK"
ln -s $INSTALLDIR/manage-iocs $SYMLINK || die "Failed to create $SYMLINK"
printf "Successfully created the symlink: $SYMLINK -> $(readlink -f $SYMLINK)\n\n"


#get, build and install procServ
[ -f /usr/bin/procServ ] && read -p "procServ is already installed in /usr/bin. \
Do you want to remove it and install a new one? Type 'yes' if you do. " answer
[ ! "$answer" = "yes" ] && die "Done."

distID="$(cat /etc/os-release | grep "^ID=" | cut -d '=' -f2)"
if [ "$distID" == "\"centos\"" ] || [ "$distID" == "debian" ]; then
    read -p "There is a package for 'procServ'. You may manually install it. \
Do you still want to build procServ from github? Type 'yes' if you do" answer
    [ ! "$answer" = "yes" ] && die "Done."
fi 

PROCSERVGIT="https://github.com/ralphlange/procServ.git"
PROCSERVDIR=/tmp/procServ
cd /tmp
[ -d $PROCSERVDIR ] && { rm -fR $PROCSERVDIR || die "Failed to remove $PROCSERVDIR"; }

echo "Building procServ from github..."
git clone $PROCSERVGIT
cd procServ

make 
./configure --disable-doc
make

if [ -f procServ ]; then
    cp procServ /usr/bin || die "Failed to copy procServ to /usr/bin"
else
    die "Failed to build procServ in $PROCSERVDIR"
fi
printf "\n\nSuccessfully installed procServ to /usr/bin\n\n"


