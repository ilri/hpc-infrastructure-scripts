#!/bin/bash
function Usage {
echo "Usage: $0 -f FirstName -i UserID -l LastName -u UserName [ -s Shell -g GroupID -p password]"
exit 1
}
Shell=/bin/bash
GroupID=100
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
if [ "$UserID" == "" ]; then Usage; fi
if [ "$UserName" == "" ]; then
FirstInitial=`echo $FirstName | cut -c1`
UserName=`echo "${FirstInitial}${LastName}" | tr "[:upper:]" "[:lower:]"`
fi
echo
echo
echo
echo
echo
echo
"dn: uid=$UserName, ou=People, dc=theyjas,dc=com"
"changetype: add"
"uid: $UserName"
"objectClass: top"
"objectClass: person"
"objectClass: organizationalPerson"echo
echo
echo
echo
echo
echo
echo
echo
echo
echo
echo
"objectClass: inetorgperson"
"objectClass: posixAccount"
"cn: $FirstName $LastName"
"sn: $LastName"
"givenName: $FirstName $LastName"
"gidNumber: $GroupID"
"uidNumber: $UserID"
"userPassword: {clear}$Password"
"loginShell: $Shell"
"h
