#!/bin/bash

function Usage {
    echo "Usage: $0 -f FirstName -l LastName -u username [ -i userid -g groupid -p password]"
    exit 1
}

SHELL=/bin/bash
Password=redhat

while getopts f:g:i:l:i:p:u: OPTION
do
    case $OPTION in
        f) FirstName=$OPTARG;;
        g) GroupID=$OPTARG;;
        i) UserID=$OPTARG;;
        l) LastName=$OPTARG;;
        p) Password=$OPTARG;;
        u) UserName=$OPTARG;;
    esac
done

[[ -z "$FirstName" ]] && Usage
[[ -z "$LastName" ]] && Usage
if [[ -z "$UserID" ]]; then
    LatestUID=`ldapsearch -x "objectclass=posixAccount" uidNumber | grep -v \^dn | grep -v \^\$ | sed -e 's/uidNumber: //g' | grep -E "^[0-9]{3,4}$" | sort -n | tail -n 1`
    UserID=$((LatestUID + 1))
fi
if [[ -z "$GroupID" ]]; then
    LatestGID=`ldapsearch -x "objectclass=posixAccount" gidNumber | grep -v \^dn | grep -v \^\$ | sed -e 's/gidNumber: //g' | grep -E "^[0-9]{3,4}$" | sort -n | tail -n 1`
    GroupID=$((LatestGID + 1))
fi
if [[ -z "$UserName" ]]; then
    FirstInitial=`echo $FirstName | cut -c1`
    UserName=`echo "${FirstInitial}${LastName}" | tr "[:upper:]" "[:lower:]"`
fi

# Print LDIF for user account
printf "dn: uid=%s, ou=People, dc=ilri,dc=cgiar,dc=org\n" "$UserName"
printf "changetype: add\n"
printf "givenName: %s %s\n" "$FirstName" "$LastName"
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

# Print LDIF for primary group account
printf "dn: cn=%s, ou=Groups, dc=ilri,dc=cgiar,dc=org\n" "$UserName"
printf "changetype: add\n"
printf "gidNumber: %d\n" "$GroupID"
printf "memberUid: %s\n" "$UserName"
printf "objectClass: top\n"
printf "objectClass: groupofuniquenames\n"
printf "objectClass: posixgroup\n"
printf "cn: %s\n" "$UserName"
