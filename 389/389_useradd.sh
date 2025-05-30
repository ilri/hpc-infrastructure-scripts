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
readonly DEF_SHELL=/usr/bin/bash

function usage {
    cat <<- EOF
Usage: $PROGNAME -f FirstName -l LastName -G location [ -u username -i userid -g groupid -p password -e email]

Optional arguments:
    -e: user email address (NOT a CGIAR address!)
    -g: numeric groupid (default: latest available)
    -i: numeric userid (default: latest available)
    -p: password (default: generate random string)
    -u: username

Import to 389 with the LDAP Directory Admin:

    ldapmodify -a -D "cn=Directory Manager" -W -p 389 -h localhost -f /tmp/blah.ldif

or, safer, a dedicated admin user:

    ldapmodify -a -D "cn=admin,ou=Special Users,dc=ilri,dc=cgiar,dc=org" -W -p 389 -h localhost -f /tmp/blah.ldif
EOF

    exit 0
}

function genpass() {
    dd if=/dev/random bs=1 count=1 2>/dev/null \
      | sha256sum -b \
      | sed 's/ .*//' \
      | head -c 20; echo
}

while getopts e:f:g:G:i:l:p:u:h OPTION
do
    case $OPTION in
        e) EMAIL=$OPTARG;;
        f) FIRSTNAME=$OPTARG;;
        g) GROUPID=$OPTARG;;
        G) LOCATION=$OPTARG;;
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
    LATESTUID=$(ldapsearch -x 'objectclass=posixAccount' uidNumber | grep -v \^dn | grep -v \^\$ | sed -e 's/uidNumber: //g' | grep -E '^[0-9]{3,4}$' | sort -n | tail -n 1)
    USERID=$((LATESTUID + 1))
fi
if [[ -z "$GROUPID" ]]; then
    LATESTGID=$(ldapsearch -x 'objectclass=posixGroup' gidNumber | grep -v \^dn | grep -v \^\$ | sed -e 's/gidNumber: //g' | grep -E '^[0-9]{3,4}$' | sort -n | tail -n 1)
    GROUPID=$((LATESTGID + 1))
fi
if [[ ! -z "$LOCATION" ]]; then
    if [[ ! "$LOCATION" =~ (addis|nairobi) ]]; then
        echo "Location must be addis or nairobi."

        exit 1
    fi
else
    usage
fi
if [[ -z "$USERNAME" ]]; then
    FIRSTINITIAL=$(echo $FIRSTNAME | cut -c1)
    USERNAME=$(echo "${FIRSTINITIAL}${LASTNAME}" | tr '[:upper:]' '[:lower:]')
fi

# Make sure the email address is NOT a CGIAR one so that we can contact
# the user after they leave the institute!
if [[ ! -z "$EMAIL" ]]; then
    if [[ "$EMAIL" =~ cgiar\.org ]]; then
        echo "Email should be a non-CG address so we can contact the user after they leave."

        exit 1
    fi
fi

# Print LDIF for user account
printf 'dn: uid=%s,ou=People,dc=ilri,dc=cgiar,dc=org\n' "$USERNAME"
printf 'changetype: add\n'
printf 'loginShell: %s\n' "$DEF_SHELL"
printf 'gidNumber: %d\n' "$GROUPID"
printf 'uidNumber: %d\n' "$USERID"
printf 'objectClass: top\n'
printf 'objectClass: nsPerson\n'
printf 'objectClass: nsAccount\n'
printf 'objectClass: nsOrgPerson\n'
printf 'objectClass: posixAccount\n'
printf 'uid: %s\n' "$USERNAME"
printf 'displayName: %s %s\n' "$FIRSTNAME" "$LASTNAME"
printf 'cn: %s %s\n' "$FIRSTNAME" "$LASTNAME"
# send password in clear text, so 389 can hash using the best scheme
# see: https://lists.fedoraproject.org/pipermail/389-users/2012-August/014908.html
printf 'userPassword: %s\n' "${PASSWORD:-$(genpass)}"
printf 'homeDirectory: /home/%s\n' "$USERNAME"
[[ ! -z "$EMAIL" ]] && printf 'mail: %s\n' "$EMAIL"

# Print LDIF for primary group
printf '\n'
printf 'dn: cn=%s,ou=Groups,dc=ilri,dc=cgiar,dc=org\n' "$USERNAME"
printf 'changetype: add\n'
printf 'gidNumber: %d\n' "$GROUPID"
printf 'member: uid=%s,ou=People,dc=ilri,dc=cgiar,dc=org\n' "$USERNAME"
printf 'objectClass: top\n'
printf 'objectClass: groupOfNames\n'
printf 'objectClass: posixGroup\n'
printf 'objectClass: nsMemberOf\n'
printf 'cn: %s\n\n' "$USERNAME"

# add user to appropriate group
printf 'dn: cn=%s,ou=Groups,dc=ilri,dc=cgiar,dc=org\n' "$LOCATION"
printf 'changetype: modify\n'
printf 'add: member\n'
printf 'member: uid=%s,ou=People,dc=ilri,dc=cgiar,dc=org\n' "$USERNAME"
