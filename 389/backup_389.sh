#!/bin/bash

# Copyright (C) 2014 Alan Orth
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# ---
#
# Portions Copyright (C) 2013 Orion Poplawski
# https://www.redhat.com/archives/freeipa-users/2013-January/msg00075.html

#
# backup-389.sh: Make backups of 389 LDAP using db2bak and db2ldif
#

ARGC="$#"
ARGV="$@"

function help() {
    echo "`basename $0`: Make backups of 389 LDAP"
    echo -e "Uses db2bak for database backups and db2ldif for exporting contents to LDIF.\n"
    echo -e "Usage: `basename $0` ldap_password\n"
    echo "Notes:"
    echo -e "\t- 'ldap_password' is the 389 Directory Manager password"
    echo -e "\t- make sure to quote the password with '' if it contains special characters"

    echo -e "\nWritten by: Alan Orth <a.orth@cgiar.org>"

    exit 0
}

if [[ $ARGC -eq 1 ]]; then
    LDAP_PASSWORD=$1
else
    help
fi

# Backup each instance
for dirsrv in /etc/dirsrv/slapd-*
do
   name=${dirsrv/*slapd-/}
   vardir=/var/lib/dirsrv/slapd-${name}
   [ -d /var/lib/dirsrv/scripts-${name} ] && scriptdir=/var/lib/dirsrv/scripts-${name}
   [ -d /usr/lib64/dirsrv/slapd-${name} ] && scriptdir=/usr/lib64/dirsrv/slapd-${name}
   [ -d /usr/lib/dirsrv/slapd-${name} ] && scriptdir=/usr/lib/dirsrv/slapd-${name}

   ${scriptdir}/db2bak.pl -D 'cn=Directory Manager' -w "$LDAP_PASSWORD" -a ${vardir}/bak/${name}-`date +%Y_%m_%d_%H_%M_%S` > /dev/null
   /usr/sbin/tmpwatch -mM 240 ${vardir}/bak

   dbdir=${vardir}/db
   for dbentry in ${dbdir}/*
   do
      if [ -d ${dbentry} ]
      then
         dbname=$(basename ${dbentry})
         ${scriptdir}/db2ldif -n ${dbname} > /dev/null
      fi
   done
   /usr/sbin/tmpwatch -mM 240 ${vardir}/ldif
done

# vim: set sw=4 ts=4:
