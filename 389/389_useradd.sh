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
#
# ---
#
# Portions Copyright (C) 2008 Red Hat Inc., Durham, North Carolina.
# https://www.redhat.com/resourcelibrary/whitepapers/netgroupwhitepaper

readonly PROGNAME=$(basename $0)
readonly PROGDIR=$(readlink -m $(dirname $0))
readonly ARGS="$@"

# some defaults
readonly DEF_SHELL=/bin/bash
readonly DEF_PASSWORD=redhat

function usage {
    cat <<- EOF
Usage: $PROGNAME -f FirstName -l LastName [ -u username -i userid -g groupid -p password]

Optional arguments:
    -u: username
    -i: numeric userid (default: latest available)
    -g: numeric groupid (default: latest available)
    -p: password (default: $DEF_PASSWORD)
EOF

    exit 0
}

function parse_arguments {
    while getopts f:g:i:l:i:p:u:h OPTION
    do
        case $OPTION in
            f) FirstName=$OPTARG;;
            g) GroupID=$OPTARG;;
            i) UserID=$OPTARG;;
            l) LastName=$OPTARG;;
            p) Password=$OPTARG;;
            u) UserName=$OPTARG;;
            h) usage;;
        esac
    done
}

function generate_ldif {

    # check existence and validity of parameters
    [[ -z "$FirstName" ]] && usage
    [[ -z "$LastName" ]] && usage
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

    local username=$UserName
    local firstname=$FirstName
    local lastname=$LastName
    local shell=$SHELL
    local groupid=$GroupID
    local userid=$UserID
    local password=${Password:-$DEF_PASSWORD}

    # Print LDIF for user account
    printf "dn: uid=%s, ou=People, dc=ilri,dc=cgiar,dc=org\n" "$username"
    printf "changetype: add\n"
    printf "givenName: %s\n" "$firstname"
    printf "sn: %s\n" "$lastname"
    printf "loginShell: %s\n" "$shell"
    printf "gidNumber: %d\n" "$groupid"
    printf "uidNumber: %d\n" "$userid"
    printf "objectClass: top\n"
    printf "objectClass: person\n"
    printf "objectClass: organizationalPerson\n"
    printf "objectClass: inetorgperson\n"
    printf "objectClass: posixAccount\n"
    printf "uid: %s\n" "$username"
    printf "gecos: %s %s\n" "$firstname" "$lastname"
    printf "cn: %s %s\n" "$firstname" "$lastname"
    # send password in clear text, so 389 can hash using the best scheme
    # see: https://lists.fedoraproject.org/pipermail/389-users/2012-August/014908.html
    printf "userPassword: %s\n" "$password"
    printf "homeDirectory: /home/%s\n\n" "$username"

    # Print LDIF for primary group
    printf "dn: cn=%s, ou=Groups, dc=ilri,dc=cgiar,dc=org\n" "$username"
    printf "changetype: add\n"
    printf "gidNumber: %d\n" "$groupid"
    printf "memberUid: %s\n" "$username"
    printf "objectClass: top\n"
    printf "objectClass: groupofuniquenames\n"
    printf "objectClass: posixgroup\n"
    printf "cn: %s\n\n" "$username"

    # add user to SSH group
    printf "dn: cn=ssh, ou=Groups, dc=ilri,dc=cgiar,dc=org\n"
    printf "changetype: modify\n"
    printf "add: memberuid\n"
    printf "memberuid: %s\n" "$username"
}

function main {
    parse_arguments $ARGS
    generate_ldif
}

main
