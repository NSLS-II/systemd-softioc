This repository is derived from: https://github.com/epicsdeb/sysv-rc-softioc

This repository contains a systemd style initialization script for a softioc using procServ.


= Usage =

Use "install.sh" (with sudo access) to install this package. By default, the source files are installed in /usr/local/systemd-softioc and a symlink "/usr/bin/manage-iocs -> /usr/local/systemd-softioc/manage-iocs" is created. Since this package is dependant on procServ, install.sh will try its best to get procServ's github repository, then build it and install the executable to /usr/bin/. 

Source files:

    epics-softioc.conf: this is where you can customize a few things; 

    manage-iocs: the main script; 

    library.sh: functions used in the script manage-iocs;

The following are provided as information:

    config.example: a template showing how to create a file named 'config' for an IOC instance/application; 

    softioc-example.service: the unit file generated by "manage-iocs install example" for the IOC named "example";

    softioc-logrotate: installed in /etc/logrotate.d for rotating IOC log files;

    README.md (this file)

In the following sections, a command starting with '#' means sudo is required, '$' means non-sudo required.


== manage-iocs ==

The script 'manage-iocs' has several sub-commands to help in managing softiocs.  See its manpage for details.

$manage-iocs help

    Usage: manage-iocs [-v] [-x] cmd

    Available commands:

      help            - display this message

      report [ioc]    - Show config(s) of an IOC/all IOCs on localhost

      status          - Check if installed IOCs are running or stopped

      nextport        - Find the next unused procServ port

      install <ioc>   - Create /etc/systemd/system/softioc-[ioc].service

      uninstall <ioc> - Remove /etc/systemd/system/softioc-[ioc].service

      start <ioc>     - Start the IOC <ioc>

      stop <ioc>      - Stop the IOC <ioc>

      startall        - Start all IOCs installed for this system

      stopall         - Stop all IOCs installed for this system

      enable <ioc>    - Enable auto-start IOC <ioc> at boot

      disable <ioc>   - Disable auto-start IOC <ioc> at boot

      list            - a list of all IOC instances under /epics/iocs:/opt/epics/iocs;
                        including those IOCs running on other hosts


== Initial Setup ==

1) Choose a location for all softIoc instances / applications

This will be a path which will contain a subdirectory for each softIoc instance. A good choice would be '/epics/iocs' (or '/opt/epics/iocs', or both). You can customize this path in '/usr/local/systemd-softioc/epics-softioc.conf' (not 'epics-softioc.conf' in your cloned repository). This is the default path:

    IOCPATH=/epics/iocs:/opt/epics/iocs

2) Create a Unix user/group 'softioc'

Altough each softIOC can run as a separate user/group, it is recommended using a single username 'softioc'. This provides a nice division and allows Channel Access security to distinguish all instances on a given machine. The script "install.sh" will try to create a username 'softioc'. If the user account 'softioc' does not exist, you can create it:

    #useradd softioc

3) Create a directory (/epics/iocs or /opt/epics/iocs is recommended) for softIOC instances

    #mkdir -p /epics/iocs

    #chown softioc:softioc /epics/iocs 

    #chmod g+ws /epics/iocs

    Now, you can switch to 'softioc': #sudo -s -u softioc, then do whatever you want in /epics/iocs.

Note: softioc:softioc is recommended. You can use other 'username:groupname', but you might get permission issues when 'autosave' is used in an IOC.

4) Optional: Install Conserver

Conserver is a process which connects to the telnet servers provided by all the softIocs on a host.  It then allows (secure) remote access and continuous logging.

    #apt-get install conserver-server

    Edit /etc/conserver/conserver.cf to include the following line.

    default softioc { type host; host localhost;}

    #include /etc/conserver/iocs.cf

See the conserver documentation for information on access control.

Note: Conserver uses the tcpd for authentication.



== Per-Instance Setup ==

0) Firstly, choose a name. Try to pick something more creative than example1. If you have not switched to 'softioc' yet, do this: #sudo -s -u softioc

1) Create an IOC instance directory

    $cd /epics/iocs/

    $mkdir -p example1

Note: If you do not want to use the user account 'softioc' to run your IOC, you can create a user 'example1' specifically for the IOC 'example1': #useradd -c 'example1' -d /epics/iocs/example1 -g softioc -N example1

2) Create and customize the instance's configuration file 'config'

    $cd /epics/iocs/example1

    $touch config    

Each instance must have a unique name and a unique port number (for procServ).  It is also a good idea to include the server's hostname to prevent accidentally running it on the wrong server. Copy & paste the following must-have variables to the file 'config', then make changes accordingly.

    NAME=example1

    PORT=4051

    HOST=myserver

    USER=softioc

NAME: required to match your IOC instance name.

PORT: type 'manage-iocs nextport', which tries to pick an unused port number for procServ. DO NOT use any well-known ports (23, 80, 5064, 5065, 8080, etc.).

HOST: required to match the result of 'hostname -s' or 'hostname -f'.

USER: a user account which must exist on localhost.

CHDIR/EXEC: if you do not have a 'st.cmd' in /epics/iocs/example1, you have to set CHDIR and EXEC accordingly in the 'config'. See config.example for allowed items in a IOC config file.

After you are done with customizing the file 'config', it is a good practice to use 'manage-iocs report' to confirm your IOC's configuration. 

3) install the systemd unit file (/etc/systemd/system/softioc-example.service). 

    #manage-iocs install example1

    (#manage-iocs uninstall example1: this removes the unit file)

4) Start the IOC instance. You will be asked if you want auto-start IOC at boot. If yes, the IOC will automatically startup after the host server boots up.

    #manage-iocs start example1

It is a good practice to use 'manage-iocs status' to confirm your IOC's status. 

5) Telnet to the IOC's EPICS shell to see if it is really working.

    $telnet localhost procServ-port-number


== IOC runtime environment ==

The following environment variables are automatically set before procServ
is started.  They may be overridden in the IOC shell.

    IOCNAME - The IOC name.

    USER - The system user account name which runs the procServ/IOC.

    HOSTNAME - The short name of the host running the IOC.

    TOP - The absolute path of the base IOC directory which contains the 'config' file
