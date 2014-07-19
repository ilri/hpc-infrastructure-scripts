#!/bin/bash

# Copyright (C) 2013 Alan Orth
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
#
# ---
#
# Portions Copyright (C) 2008 Red Hat Inc., Durham, North Carolina.
# https://www.redhat.com/resourcelibrary/whitepapers/netgroupwhitepaper

function Usage {
    echo "Usage: $0 -f FirstName -l LastName [ -u username -i userid -g groupid -p password]"
    exit 1
}

SHELL=/bin/bash
Password=redhat

while getopts f:g:i:l:i:p:u:h OPTION
do
    case $OPTION in
        f) FirstName=$OPTARG;;
        g) GroupID=$OPTARG;;
        i) UserID=$OPTARG;;
        l) LastName=$OPTARG;;
        p) Password=$OPTARG;;
        u) UserName=$OPTARG;;
        h) Usage;;
    esac
done

[[ -z "$FirstName" ]] && Usage
[[ -z "$LastName" ]] && Usage
if [[ -z "$UserID" ]]; then
    LatestUID=`ldapsearch -x "objectclass=posixAccount" uidNumber | grep -v \^dn | grep -v \^\$ | sed -e 's/uidNumber: //g' | grep -E "^[0-9]{3,4}$" | sort -n | tail -n 1`
    UserID=$((LatestUID + 1))
fi
if [[ -z "$GroupID" ]]; then
    LatestGID=`ldapsearch -x "objectclass=posixGroup" gidNumber | grep -v \^dn | grep -v \^\$ | sed -e 's/gidNumber: //g' | grep -E "^[0-9]{3,4}$" | sort -n | tail -n 1`
    GroupID=$((LatestGID + 1))
fi
if [[ -z "$UserName" ]]; then
    FirstInitial=`echo $FirstName | cut -c1`
    UserName=`echo "${FirstInitial}${LastName}" | tr "[:upper:]" "[:lower:]"`
fi

# Print LDIF for user account
printf "dn: uid=%s, ou=People, dc=ilri,dc=cgiar,dc=org\n" "$UserName"
printf "changetype: add\n"
printf "givenName: %s\n" "$FirstName"
printf "sn: %s\n" "$LastName"
printf "loginShell: %s\n" "$SHELL"
printf "gidNumber: %d\n" "$GroupID"
printf "uidNumber: %d\n" "$UserID"
printf "objectClass: top\n"
printf "objectClass: person\n"
printf "objectClass: organizationalPerson\n"
printf "objectClass: inetorgperson\n"
printf "objectClass: posixAccount\n"
printf "uid: %s\n" "$UserName"
printf "gecos: %s %s\n" "$FirstName" "$LastName"
printf "cn: %s %s\n" "$FirstName" "$LastName"
# send password in clear text, so 389 can hash using the best scheme
# see: https://lists.fedoraproject.org/pipermail/389-users/2012-August/014908.html
printf "userPassword: %s\n" "$Password"
printf "homeDirectory: /home/%s\n\n" "$UserName"

# Print LDIF for primary group
printf "dn: cn=%s, ou=Groups, dc=ilri,dc=cgiar,dc=org\n" "$UserName"
printf "changetype: add\n"
printf "gidNumber: %d\n" "$GroupID"
printf "memberUid: %s\n" "$UserName"
printf "objectClass: top\n"
printf "objectClass: groupofuniquenames\n"
printf "objectClass: posixgroup\n"
printf "cn: %s\n\n" "$UserName"

# add user to SSH group
printf "dn: cn=ssh, ou=Groups, dc=ilri,dc=cgiar,dc=org\n"
printf "changetype: modify\n"
printf "add: memberuid\n"
printf "memberuid: %s\n" "$UserName"
