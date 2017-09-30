#!/usr/bin/env bash

# Copyright (C) 2014–present Alan Orth
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

# some defaults
readonly DEF_SHELL=/bin/bash
readonly DEF_PASSWORD=redhat

function usage {
    cat <<- EOF
Usage: $PROGNAME -f FirstName -l LastName [ -u username -i userid -g groupid -p password -e email]

Optional arguments:
    -e: user email address
    -g: numeric groupid (default: latest available)
    -i: numeric userid (default: latest available)
    -p: password (default: $DEF_PASSWORD)
    -u: username

Import to 389 with the LDAP Directory Admin:

    ldapmodify -a -D "cn=Directory Manager" -W -p 389 -h localhost -f /tmp/blah.ldif

or, safer, a dedicated admin user:

    ldapmodify -a -D "uid=user,ou=administrators,ou=topologymanagement,o=netscaperoot" -W -p 389 -h localhost -f /tmp/blah.ldif
EOF

    exit 0
}

while getopts e:f:g:i:l:p:u:h OPTION
do
    case $OPTION in
        e) EMAIL=$OPTARG;;
        f) FIRSTNAME=$OPTARG;;
        g) GROUPID=$OPTARG;;
        i) USERID=$OPTARG;;
        l) LASTNAME="$OPTARG";;
        p) PASSWORD=$OPTARG;;
        u) USERNAME=$OPTARG;;
        h) usage;;
    esac
done

# check existence and validity of parameters
[[ -z "$FIRSTNAME" ]] && usage
[[ -z "$LASTNAME" ]] && usage
if [[ -z "$USERID" ]]; then
    local latestuid=$(ldapsearch -x 'objectclass=posixAccount' uidNumber | grep -v \^dn | grep -v \^\$ | sed -e 's/uidNumber: //g' | grep -E '^[0-9]{3,4}$' | sort -n | tail -n 1)
    USERID=$((latestuid + 1))
fi
if [[ -z "$GROUPID" ]]; then
    local latestgid=$(ldapsearch -x 'objectclass=posixGroup' gidNumber | grep -v \^dn | grep -v \^\$ | sed -e 's/gidNumber: //g' | grep -E '^[0-9]{3,4}$' | sort -n | tail -n 1)
    GROUPID=$((latestgid + 1))
fi
if [[ -z "$USERNAME" ]]; then
    local firstinitial=$(echo $FIRSTNAME | cut -c1)
    USERNAME=$(echo "${firstinitial}${LASTNAME}" | tr '[:upper:]' '[:lower:]')
fi

# Print LDIF for user account
printf 'dn: uid=%s, ou=People, dc=ilri,dc=cgiar,dc=org\n' "$USERNAME"
printf 'changetype: add\n'
printf 'givenName: %s\n' "$FIRSTNAME"
printf 'sn: %s\n' "$LASTNAME"
printf 'loginShell: %s\n' "$DEF_SHELL"
printf 'gidNumber: %d\n' "$GROUPID"
printf 'uidNumber: %d\n' "$USERID"
printf 'objectClass: top\n'
printf 'objectClass: person\n'
printf 'objectClass: organizationalPerson\n'
printf 'objectClass: inetorgperson\n'
printf 'objectClass: posixAccount\n'
printf 'uid: %s\n' "$USERNAME"
printf 'gecos: %s %s\n' "$FIRSTNAME" "$LASTNAME"
printf 'cn: %s %s\n' "$FIRSTNAME" "$LASTNAME"
# send password in clear text, so 389 can hash using the best scheme
# see: https://lists.fedoraproject.org/pipermail/389-users/2012-August/014908.html
printf 'userPassword: %s\n' "${PASSWORD:-$DEF_PASSWORD}"
printf 'homeDirectory: /home/%s\n' "$USERNAME"
[[ ! -z "$EMAIL" ]] && printf 'mail: %s\n\n' "$EMAIL"

# Print LDIF for primary group
printf 'dn: cn=%s, ou=Groups, dc=ilri,dc=cgiar,dc=org\n' "$USERNAME"
printf 'changetype: add\n'
printf 'gidNumber: %d\n' "$GROUPID"
printf 'memberUid: %s\n' "$USERNAME"
printf 'objectClass: top\n'
printf 'objectClass: groupofuniquenames\n'
printf 'objectClass: posixgroup\n'
printf 'cn: %s\n\n' "$USERNAME"

# add user to SSH group
printf 'dn: cn=ssh, ou=Groups, dc=ilri,dc=cgiar,dc=org\n'
printf 'changetype: modify\n'
printf 'add: memberuid\n'
printf 'memberuid: %s\n' "$USERNAME"
