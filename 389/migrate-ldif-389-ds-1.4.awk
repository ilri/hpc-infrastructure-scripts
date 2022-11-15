##
#
# SPDX-License-Identifier: GPL-3.0-only
#
# migrate-ldif-389-ds-1.4.awk v1.0.0
#
# Awk script to migrate an LDIF from RFC 2307 schema to RFC 2307bis in addition
# to some other changes to attributes that I found with our particular data when
# upgrading from 389-ds 1.3.x (CentOS 7) to 1.4.x (CentOS Stream 8).
#
# To use this script, stop your 389-ds 1.3.x instance and export an LDIF:
#
#   # systemctl stop dirsrv@instance-name.service
#   # db2ldif -Z instance-name -n userRoot -a /tmp/userRoot.ldif
#   # systemctl start dirsrv@instance-name.service
#
# Then you can migrate the LDIF (note, you need to edit this script to replace
# the hard-coded base DN):
#
#   # awk -f migrate-ldif-389-ds-1.4.awk userRoot.ldif > userRoot-migrated.ldif
#
# And import it into your new directory server according to the Red Hat DS docs.
#
# ― Alan Orth, 2022
# 
## 

BEGIN {}

/dn: uid=.*,ou=People,dc=ilri,dc=cgiar,dc=org/ {
    print "# User migrated to RFC 2307bis";

    # Keep getting the next line until we have a blank one (which means this
    # user's LDIF entry is finished).
    while ($0 !~ /^$/) {
        # Lines to update or remove. I comment them out by printing a hash and
        # "&", which is a special awk syntax to print the pattern that matched.
        switch($0) {
            case /^objectClass: person/:
                sub(/^objectClass: person/, "objectClass: nsPerson");
                # Print the line as it is after substitution
                print;
                # Break out so we don't process any more cases
                break;
            case /^objectClass: organizationalPerson/:
                sub(/^objectClass: organizationalPerson/, "objectClass: nsAccount");
                print;
                break;
            case /^objectClass: (inetorgperson|inetOrgPerson)/:
                sub(/^objectClass: (inetorgperson|inetOrgPerson)/, "objectClass: nsOrgPerson");
                print;
                break;
            # givenName is not allowed. Note we also check for base64 encoded
            # attributes with a double colon here.
            case /^givenName:+ .*/:
                sub(/^givenName:+ .*/, "#&");
                print;
                break;
            # sn is not allowed. Note we also check for base64 encoded attribu-
            # tes with a double colon here.
            case /^sn:+ .*/:
                sub(/^sn:+ .*/, "#&");
                print;
                break;
            # When we see a cn, copy the value to displayName and then print
            # them both. Note we pay special attention to cn attributes that
            # are base64 encoded and therefore have a double colon.
            case /^cn:+ .*/:
                displayName = gensub(/^cn(:+) (.*)/, "displayName\\1 \\2", "g", $0);
                print;
                print displayName;
                break;
            # facsimileTelephoneNumber is not allowed
            case /^facsimileTelephoneNumber: /:
                break;
            default:
                print;
        }

        # Read the next record (aka line) immediately, which effectively runs the line
        # through the switch cases again. Exit if we have reached the end of the file.
        if (getline <= 0) {
            exit;
        }
    }
}

/dn: cn=.*,ou=Groups,dc=ilri,dc=cgiar,dc=org/ {
    print "# Group migrated to RFC 2307bis";

    # Assume if this is a primary user group unless it matches a handful of
    # known secondary groups. If it is a primary group then we can remove
    # the "memberUid" attribute because it is not necessary. If it is a
    # secondary group then we need to convert the attribute to member with
    # a full DN to the user.
    primaryUserGroup = "true";
    if ($0 ~ /^dn: cn=(beca|beca_web|rmglinuxadm|gisusers|miseqadmin|bcop2018|becabix|sarscov2|bcop2021|nanoseqadmin|nextseqadmin|segoli|segoliadmin|ssh)/) {
        primaryUserGroup = "false";
    }

    while ($0 !~ /^$/) {

        switch($0) {
            case /^objectClass: groupofuniquenames/:
                sub(/^objectClass: groupofuniquenames/, "objectClass: groupOfNames");
                print;
                break;
            case /^memberUid: .*/:
                if (primaryUserGroup == "true") {
                    # Comment out memberUid for primary user groups because it is
                    # not necessary.
                    sub(/^memberUid: .*/, "#&");
                    print;
                }
                else {
                    # For secondary groups we capture the user's name and resolve
                    # it to a DN for the member attribute.
                    member = gensub(/^memberUid: (.*)/, "member: uid=\\1,ou=People,dc=ilri,dc=cgiar,dc=org", "g", $0);
                    print member;
                }

                break;
            case /^objectClass: posixgroup/:
                sub(/^objectClass: posixgroup/, "objectClass: posixGroup");
                print;
                # Not sure why, but it seems 389-ds 1.4.x wants this. I think it
                # enables more complex group membership, like nested groups.
                print "objectClass: nsMemberOf";
                break;
            default:
                print;
        }

        if (getline <= 0) {
            exit;
        }
    }
}

# Match and print all other lines in the LDIF
{ print }

END {}
