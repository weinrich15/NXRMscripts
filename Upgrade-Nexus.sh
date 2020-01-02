#!/bin/sh
#
#
#
# First, shut down _ALL_ nexus nodes
# Start on LAST node to come down
# Modify CONFIGURATION SECTION of this script and update
#     NEXUSARCHIVE
################ CONFIGURATION SECTION ################
# 
# REPOSITORYURL is the url base that holds the installation files
REPOSITORYURL="https://nexus.mycompany.com/repository/linux-binaries/nexus"

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

# TMPDIR is used for temporary files.  By default, the location of this script is TMPDIR.
# Set this to something else to use a specific temp folder.
TMPDIR="/tmp/nexus_install"

# NEXUSCONFIGARCHIVE is the name of the .tar.gz archive created during the VSTS Build pipeline
# and uploaded to the $REPOSITORYURL.  It contains all files needed to configure Nexus after install.
# The Jar file is expected to be named "nexus-repository-r-x.y.z.jar", where x.y.z are the major, minor,
# and revision numbers (The Default Format)
NEXUS-REPOSITORY-R-JARLOCATION=$TMPDIR

# The filename of the Nexus license file to enable PRO features
# is put in LICENSEFILE. This file should reside in the $NEXUSCONFIGARCHIVE archive.
LICENSEFILE="nexus-repository.lic"

# INSTALLBASE, JAVAHOME, and NEXUSHOME are the locations where Java
# and Nexus will be installed. This will probably never change, but
# is included here for completeness.
INSTALLBASE="/opt"
NEXUSHOME="$INSTALLBASE/nexus"

# USERPLUGIN is only required for Nexus versions prior to 3.20.0
# Leave commented out for 3.20.0 or later
# version string for repository-r module
#USERPLUGIN="true"
#
############## END CONFIGURATION SECTION ##############
unalias cp
OLDNEXUSVERSION=`/usr/bin/readlink -en /opt/nexus/latest | cut -d / -f 4`

### STOP NEXUS ###
 systemctl stop nexus

### Set TEMPDIR if necessary
if [ $TMPDIR == "" ]
then 
    TMPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )" # Same directory as this script
fi

### Download installation binaries to $TMPDIR, creating dirs if necessary
 curl --silent --show-error --create-dirs --output $TMPDIR/$NEXUSARCHIVE $REPOSITORYURL/$NEXUSARCHIVE
 curl --silent --show-error --create-dirs --output $TMPDIR/$NEXUSCONFIGARCHIVE $REPOSITORYURL/$NEXUSCONFIGARCHIVE
 
### Discover subdirectory that tarballs will use
 NEXUSDIR=`tar -tvf $TMPDIR/$NEXUSARCHIVE | head -1 | awk '{print $6}' | awk -F/ '{split($0, a); print a[1]}'`   # "nexus-3.15.0-01"
 
### Backup Old Nexus
 rm $NEXUSHOME/latest
 CURRENTDIR=`pwd`
 cd $NEXUSHOME
 tar -cz --exclude '*.backup.tgz' -f $NEXUSHOME/$OLDNEXUSVERSION.backup.tgz sonatype-work $OLDNEXUSVERSION
 rm -rf $NEXUSHOME/$OLDNEXUSVERSION
 #rm -rf $NEXUSHOME/sonatype-work/nexus3
 cd $CURRENTDIR
 mkdir $NEXUSHOME/$NEXUSDIR

### Extract Nexus configuration files to $TMPDIR
 CONFIGHOME=`tar -tvf $TMPDIR/$NEXUSCONFIGARCHIVE | head -1 | awk '{print $6}' | awk -F/ '{split($0, a); print a[1]}'`  # NexusConfig
 tar -xzf $TMPDIR/$NEXUSCONFIGARCHIVE --directory $TMPDIR

### Extract install archives and create symlinks
 tar -xzf $TMPDIR/$NEXUSARCHIVE --directory $NEXUSHOME
 ln -s $NEXUSHOME/$NEXUSDIR $NEXUSHOME/latest

### Inform Nexus to clear cache on startup
 touch /opt/nexus/sonatype-work/nexus3/clean_cache
 
# 
### Re-Configure r support
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

### Copy Keystore
   cp -p $NEXUSHOME/$OLDNEXUSVERSION/etc/ssl/* $NEXUSHOME/latest/etc/ssl/

### Configure Java Memory for host with 16GB Ram
   mv -f $NEXUSHOME/bin/nexus.vmoptions $NEXUSHOME/bin/nexus.vmoptions+
   cp -f $TMPDIR/$CONFIGHOME/NexusConfig/nexus.vmoptions $NEXUSHOME/bin/nexus.vmoptions
   chmod 644 $NEXUSHOME/bin/nexus.vmoptions

### Reset file ownership
 chown -R nexus:nexus $NEXUSHOME
 echo "Done."
