#!/bin/sh
################ CONFIGURATION SECTION ################
#
# REPOSITORYURL is the url base that holds the installation files
REPOSITORYURL="https://nexus.mycompany.com/repository/linux-binaries/nexus"

# Set JAVAARCHIVE to the filename of the Java installation tarball.
# It will be downloaded from the repository
JAVAARCHIVE="server-jre-8u192-linux-x64.tar.gz"

# NEXUSARCHIVE is the filename of the Nexus installation tarball.
# The latest version can be retrieved from www.sonatype.com and placed into the $REPOSITORYURL.
# This script will downloaded the file from $REPOSITORYURL.
NEXUSARCHIVE="nexus-latest.tar.gz"

# NEXUSCONFIGARCHIVE is the name of the .tar.gz archive created during the VSTS Build pipeline
# and uploaded to the $REPOSITORYURL.  It contains all files needed to configure Nexus after install.
#   .bash_profile
#   .bashrc
#   nexus-repository-r-1.0.3.jar
#   nexus.properties
#   nexus.rc
#   nexus.service
#   nexus.vmoptions
#   nexus-repository.lic
#   nexus-keystore.jks
NEXUSCONFIGARCHIVE="nexusconfig.tar.gz"

# The filename of the Nexus license file to enable PRO features
# is put in LICENSEFILE. This file should reside in the $NEXUSCONFIGARCHIVE archive.
LICENSEFILE="nexus-repository.lic"

# TMPDIR is used for temporary files.  By default, the location of this script is also in TMPDIR.
# Set this to something else to use a specific temp folder.
TMPDIR="/tmp/nexus_install"

# INSTALLBASE, JAVAHOME, and NEXUSHOME are the locations where Java
# and Nexus will be installed. This will probably never change, but
# is included here for completeness.
INSTALLBASE="/opt"
JAVAHOME="$INSTALLBASE/java"
NEXUSHOME="$INSTALLBASE/nexus"
#

# USERPLUGIN is only required for Nexus versions prior to 3.20.0
# Leave commented out for 3.20.0 or later
# version string for repository-r module
#USERPLUGIN="true"
#
############## END CONFIGURATION SECTION ##############

### Set TEMPDIR if necessary
if [ ${#TMPDIR} == 0 ]
then
    TMPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )" # Same directory as this script
fi

### Download installation binaries to $TMPDIR, creating dirs if necessary
 curl --silent --show-error --create-dirs --output $TMPDIR/$JAVAARCHIVE $REPOSITORYURL/$JAVAARCHIVE
 curl --silent --show-error --create-dirs --output $TMPDIR/$NEXUSARCHIVE $REPOSITORYURL/$NEXUSARCHIVE
 curl --silent --show-error --create-dirs --output $TMPDIR/$NEXUSCONFIGARCHIVE $REPOSITORYURL/$NEXUSCONFIGARCHIVE

### Discover subdirectory that tarballs will use
 JAVADIR=`tar -tvf $TMPDIR/$JAVAARCHIVE | head -1 | awk '{print $6}' | awk -F/ '{split($0, a); print a[1]}'`     # "jdk1.8.0_192"
 NEXUSDIR=`tar -tvf $TMPDIR/$NEXUSARCHIVE | head -1 | awk '{print $6}' | awk -F/ '{split($0, a); print a[1]}'`   # "nexus-3.14.0-04"

### Extract Nexus configuration files to $TMPDIR
CONFIGHOME=`tar -tvf $TMPDIR/$NEXUSCONFIGARCHIVE | head -1 | awk '{print $6}' | awk -F/ '{split($0, a); print a[1]}'`  # NexusConfig
tar -xzf $TMPDIR/$NEXUSCONFIGARCHIVE --directory $TMPDIR

### Create nexus user and group, if necessary
ENTRYEXISTS=`grep nexus /etc/passwd`
if [ ${#ENTRYEXISTS} == 0 ]
then
 useradd --uid 200 --user-group --create-home nexus
 cp -f $TMPDIR/$CONFIGHOME/NexusConfig/.bashrc /home/nexus
 cp -f $TMPDIR/$CONFIGHOME/NexusConfig/.bash_profile /home/nexus
 chown -R nexus:nexus /home/nexus
fi

### Exit if Nexus is already installed
 ISINSTALLED=`ls -d $NEXUSHOME/$NEXUSDIR | wc -l`
 if [ ${#ISINSTALLED} -gt 1 ]
 then
    printf "Nexus $NEXUSDIR is already installed.  Aborting...\n"
    exit
 fi

### Create Installation Directories
 mkdir $JAVAHOME
 mkdir $NEXUSHOME
 chown nexus:nexus $NEXUSHOME

### Extract install archives and create symlinks
 tar -xzf $TMPDIR/$JAVAARCHIVE --directory $JAVAHOME
 ln -s $JAVAHOME/$JAVADIR $JAVAHOME/latest
 chmod o+rx $JAVAHOME
 tar -xzf $TMPDIR/$NEXUSARCHIVE --directory $NEXUSHOME
 ln -s $NEXUSHOME/$NEXUSDIR $NEXUSHOME/latest

### Configure run-as-service
 cp -f $TMPDIR/$CONFIGHOME/NexusConfig/nexus.service /etc/systemd/system/
 cp -f $TMPDIR/$CONFIGHOME/NexusConfig/nexus.rc $NEXUSHOME/latest/bin/
 chown -R nexus:nexus $NEXUSHOME
 systemctl daemon-reload
 systemctl enable nexus.service

### Launch and allow Nexus to run for first time
### Creates files and directories on first run
### Only necessary if Nexus was never installed on this machine
if [ -d /opt/nexus/sonatype-work ]; then
   echo "Skipping first time startup because /opt/nexus/sonatype-work already exists..."
else
   systemctl start nexus.service
   sleep 30
   systemctl stop nexus.service
fi

### Configure SSL on Server
 cp -f $TMPDIR/$CONFIGHOME/NexusConfig/nexus.properties $NEXUSHOME/sonatype-work/nexus3/etc/
 chmod 640 $NEXUSHOME/sonatype-work/nexus3/etc/nexus.properties
 mkdir $NEXUSHOME/sonatype-work/nexus3/etc/ssl
 cp -f $TMPDIR/$CONFIGHOME/NexusConfig/nexus-keystore.jks $NEXUSHOME/sonatype-work/nexus3/etc/ssl/keystore.jks
 chmod 640 $NEXUSHOME/sonatype-work/nexus3/etc/ssl/keystore.jks
 cp -pf $NEXUSHOME/sonatype-work/nexus3/etc/ssl/keystore.jks $NEXUSHOME/latest/etc/ssl/

### Copy License
 cp -f $TMPDIR/$CONFIGHOME/NexusConfig/$LICENSEFILE $NEXUSHOME/
 chmod 640 $NEXUSHOME/$LICENSEFILE

### Configure Java Memory for host with 16GB Ram
 mv -f $NEXUSHOME/latest/bin/nexus.vmoptions $NEXUSHOME/latest/bin/nexus.vmoptions+
 cp -f $TMPDIR/$CONFIGHOME/NexusConfig/nexus.vmoptions $NEXUSHOME/latest/bin/nexus.vmoptions
 chmod 644 $NEXUSHOME/latest/bin/nexus.vmoptions

### Configure r support
 if [ ${#USERPLUGIN} -gt 1 ]
 then
   # Get nexus-repository-r filename
   cd $TMPDIR
   NEXUSRFILE=`ls nexus-repository-r*.jar | grep -v "sources.jar"`
   NEXUSRVERSION=`echo $NEXUSRFILE | awk -F- '{split($4,a,"."); print a[1]"."a[2]"."a[3]}'`
   VERSIONDIR=`echo $NEXUSDIR | awk -F- '{split($0, a); print a[2]"-"a[3]}'`

   mkdir $NEXUSHOME/latest/system/org/sonatype/nexus/plugins/nexus-repository-r
   mkdir $NEXUSHOME/latest/system/org/sonatype/nexus/plugins/nexus-repository-r/$NEXUSRVERSION
   cp -f $TMPDIR/$NEXUSRFILE $NEXUSHOME/latest/system/org/sonatype/nexus/plugins/nexus-repository-r/$NEXUSRVERSION
   chmod -R 750 /opt/nexus/latest/system/org/sonatype/nexus/plugins/nexus-repository-r

   cp $NEXUSHOME/latest/system/com/sonatype/nexus/assemblies/nexus-pro-feature/$VERSIONDIR/nexus-pro-feature-$VERSIONDIR-features.xml $NEXUSHOME/latest/system/com/sonatype/nexus/assemblies/nexus-pro-feature/$VERSIONDIR/nexus-pro-feature-$VERSIONDIR-features.xml+
   SEARCHFOR='prerequisite="false" dependency="false">nexus-repository-rubygems</feature>'
   aLINE='<feature version="'$NEXUSRVERSION'" prerequisite="false" dependency="false">nexus-repository-r</feature>'
   INSERTLINE=`grep -m1 -n "$SEARCHFOR" $NEXUSHOME/latest/system/com/sonatype/nexus/assemblies/nexus-pro-feature/$VERSIONDIR/nexus-pro-feature-$VERSIONDIR-features.xml | awk -F: '{ print $1 }'`
   let INSERTLINE++
   sed -i "$INSERTLINE i $aLINE" /opt/nexus/latest/system/com/sonatype/nexus/assemblies/nexus-pro-feature/$VERSIONDIR/nexus-pro-feature-$VERSIONDIR-features.xml

   anotherLINE2=$'<feature name="nexus-repository-r" description="org.sonatype.nexus.plugins:nexus-repository-r" version="'$NEXUSRVERSION'">\
      <details>org.sonatype.nexus.plugins:nexus-repository-r</details>\
      <bundle>mvn:org.sonatype.nexus.plugins/nexus-repository-r/'$NEXUSRVERSION'</bundle>\
   </feature>'
   INSERTLINE=`sudo grep -m1 -n "</features>" $NEXUSHOME/latest/system/com/sonatype/nexus/assemblies/nexus-pro-feature/$VERSIONDIR/nexus-pro-feature-$VERSIONDIR-features.xml | awk -F: '{ print $1 }'`
   sudo sed -i "$INSERTLINE i $anotherLINE2" $NEXUSHOME/latest/system/com/sonatype/nexus/assemblies/nexus-pro-feature/$VERSIONDIR/nexus-pro-feature-$VERSIONDIR-features.xml
   sudo chmod 644 $NEXUSHOME/latest/system/com/sonatype/nexus/assemblies/nexus-pro-feature/$VERSIONDIR/nexus-pro-feature-$VERSIONDIR-features.xml
 fi
chown -R nexus:nexus $NEXUSHOME
