#!/bin/bash

function Usage {
    echo "Usage: $0 -f FirstName -l LastName -u UserName [ -i UserID -s shell -g GroupID -p password]"
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

if [ "$FirstName" == "" ]; then Usage; fi
if [ "$LastName" == "" ]; then Usage; fi
if [ "$UserID" == "" ]; then
    LatestUID=`ldapsearch -x "objectclass=posixAccount" uidNumber | grep -v \^dn | grep -v \^\$ | sed -e 's/uidNumber: //g' | grep -E "^[0-9]{3,4}$" | sort -n | tail -n 1`
    UserID=$((LatestUID + 1))
fi
if [ "$GroupID" == "" ]; then
    LatestGID=`ldapsearch -x "objectclass=posixAccount" gidNumber | grep -v \^dn | grep -v \^\$ | sed -e 's/gidNumber: //g' | grep -E "^[0-9]{3,4}$" | sort -n | tail -n 1`
    GroupID=$((LatestGID + 1))
fi
if [ "$UserName" == "" ]; then
    FirstInitial=`echo $FirstName | cut -c1`
    UserName=`echo "${FirstInitial}${LastName}" | tr "[:upper:]" "[:lower:]"`
fi

echo "dn: uid=$UserName, ou=People, dc=ilri,dc=cgiar,dc=org"
echo "changetype: add"
echo "givenName: $FirstName $LastName"
echo "sn: $LastName"
echo "loginShell: $SHELL"
echo "gidNumber: $GroupID"
echo "uidNumber: $UserID"
echo "objectClass: top"
echo "objectClass: person"
echo "objectClass: organizationalPerson"
echo "objectClass: inetorgperson"
echo "objectClass: posixAccount"
echo "uid: $UserName"
echo "gecos: $FirstName $LastName"
echo "cn: $FirstName $LastName"
echo "userPassword: {clear}$Password"
echo "homeDirectory: /home/$UserName"
echo
