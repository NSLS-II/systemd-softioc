# systemd style script for running softIOCs

This repository is derived from: https://github.com/epicsdeb/sysv-rc-softioc.
This repository contains a systemd style initialization script for running a softIOC as a background 
daemon using `procServ` (https://github.com/ralphlange/procServ).

Here the term `softIOC` means an EPICS IOC running on Linux OS.

## Installation 

Type something like `sudo ./install.sh` to install this package. By default, the source files are 
installed in the directory `/usr/local/systemd-softioc` and a symbolic link 
`/usr/bin/manage-iocs -> /usr/local/systemd-softioc/manage-iocs` is created. Since this package is 
dependant on procServ, `install.sh` will try its best to get procServ's github repository, then 
build it and install the executable to `/usr/bin/`. 

Type `which procServ`. If it shows 'procServ' is not installed, you have to install procServ manually.

Type `manage-iocs help` to get a basic idea on how to use this tool.

## Initial Setup

### 1) Choose a top-level directory for all softIOC instances / applications
This will be a path which will contain a subdirectory for each softIOC instance. A good choice would 
be `/epics/iocs` (or `/opt/epics/iocs`, or both). You can customize this path in 
`/usr/local/systemd-softioc/epics-softioc.conf` (not `epics-softioc.conf` in your cloned repository). 
This is the default path: `IOCPATH=/epics/iocs:/opt/epics/iocs`.

### 2) Choose a user account for running softIOC instances
Eventually each softIOC will be running as a process (daemon) wrapped by procServ. It is a good 
practice to use an non-root user account instead of `root` to run an softIOC. Altough each softIOC 
can be run and owned by any user account, e.g. your personal account `tjeffson`, it is a good practice
to use a single username `softioc` for running all softIOCs. This provides a nice division and allows 
Channel Access security to distinguish all softIOC instances on a given machine. The script 
`install.sh` will try to create a username `softioc`. If the user account `softioc` does not exist, 
you can always create it manually by the command `useradd softioc`.

### 3) Create the top-level directory for softIOC instances
Suppose you have chosen the directory `/epics/iocs` for the path and the user account `softioc` for 
running softIOCs. In the following sections, a command starting with '#' means sudo is required, 
'$' means non-sudo required. Here is the commands to complete the initial setup.

    #mkdir -p /epics/iocs

    #chown softioc:softioc /epics/iocs 

    #chmod g+ws /epics/iocs

Now, you can switch to the user account softioc: `#sudo -s -u softioc`, then do whatever you want in 
/epics/iocs.

Note: `softioc:softioc` is recommended. You can use any account, e.g. `tjeffson:tjeffson` as long as 
you use the same username `tjeffson` for the variable `USER` in your softIOC's configuration file 
`config` (see below for more details on `config`). This kind of consistence will avoid file access 
permission issues especially when the EPICS support module `autosave` is used in a softIOC.

## Per-softIOC Setup
Now it is time to setup and run your softIOC. Firstly, of course you need to choose a name for your 
softIOC. `example1` is used here for demonstration. If you want to use the account `softioc` to run 
`example1` and you have not switched to `softioc` yet, do this before you continue: 
`#sudo -s -u softioc`.

### 1) Create a softIOC instance directory

    $cd /epics/iocs/

    $mkdir -p example1

### 2) Create and customize the configuration file `config`

    $cd /epics/iocs/example1

    $nano config

Each softIOC instance must have a unique name and a unique port number (for procServ).  It is also 
a good idea to include the server's hostname to prevent accidentally running it on the wrong server. 
Copy & paste the following must-have variables to the file `config`, then make changes accordingly.

    NAME=example1

    PORT=4051

    HOST=myserver-hostname

    USER=softioc

* NAME: required to match your softIOC instance name.
* PORT: type `manage-iocs nextport`, which tries to pick an unused port number for procServ. DO NOT 
use any well-known ports (23, 80, 5064, 5065, 8080, etc.).
* HOST: required to match the result of 'hostname -s' or 'hostname -f'.
* USER: a user account which must exist on localhost, e.g. `softioc` or `tjeffson`. As mentioned 
above, consistence of using user account is very important for file access permission.
* CHDIR/EXEC: if you do not have `st.cmd` in `/epics/iocs/example1`, you have to set `CHDIR` and 
`EXEC` accordingly. See `config.example` for reference.

After you are done with customizing the file `config`, it is a good practice to use `manage-iocs report` 
to confirm your IOC's configuration. 

### 3) install the softIOC

    #manage-iocs install example1

`/etc/systemd/system/softioc-example.service` will be generated. You may take a quick look at that file.

### 4) Start the softIOC

    #manage-iocs start example1

You will be asked if you want auto-start softIOC at boot. If yes, the softIOC will automatically 
startup after the host server boots up.

It is a good practice to use `manage-iocs status` to confirm your softIOC's status. 

Finally Telnet to the EPICS shell of the softIOC `example1` to see if it is really working.

    $telnet localhost 4051

## References
The following sections are just for your reference.

### IOC runtime environment
The following environment variables are automatically set before procServ is started so that you can
use them in your `st.cmd`.

    IOCNAME - The softIOC name.

    USER - The system user account name which runs the procServ/softIOC.

    HOSTNAME - The short name of the host running the softIOC.

    TOP - The absolute path of the base softIOC directory which contains the file `config`

### files:
* epics-softioc.conf: this is where you can customize a few things; 
* manage-iocs: the main script; 
* library.sh: functions used in the script manage-iocs;
* config.example: a template showing how to create the configutation file `config` for an softIOC instance; 
* softioc-example.service: the unit file generated by `manage-iocs install example` for the softIOC "example";
* softioc-logrotate: installed in /etc/logrotate.d for rotating IOC log files;
* README.md (this file)
