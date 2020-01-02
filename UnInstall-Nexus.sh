#!/bin/sh

# TMPDIR is used for temporary files.  By default, the location of this script is TMPDIR.
# Set this to something else to use a specific temp folder.
TMPDIR="/tmp/nexus_install"

# INSTALLBASE, JAVAHOME, and NEXUSHOME are the locations where Java
# and Nexus will be installed. This will probably never change, but
# is included here for completeness.
INSTALLBASE="/opt"
JAVAHOME="$INSTALLBASE/java"
NEXUSHOME="$INSTALLBASE/nexus"
#
############## END CONFIGURATION SECTION ##############

### Set TEMPDIR if necessary
if [ $TMPDIR == "" ]
then 
    TMPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )" # Same directory as this script
fi

### Disable Service
 systemctl stop nexus.service
 systemctl disable nexus.service
 rm -f /etc/systemd/system/nexus.service
 systemctl daemon-reload

### Delete nexus user and group
 userdel --force --remove  nexus

### Remove App  Directories
 rm -rf $JAVAHOME
 rm -rf $NEXUSHOME

### Remove Temp Files
 rm -rf $TMPDIR
