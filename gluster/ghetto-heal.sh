#!/usr/bin/env bash
#
# ghetto-heal.sh v1.2.1
#
# Copies files from one local brick to remote bricks in an attempt to fix issues
# where files may be on the wrong brick, causing them to be shown with a sticky
# bit, (incorrect) root ownership, or in duplicate on the client's FUSE mount.
# This script should be run on every brick, or at least one in every replica
# set, followed by running ghetto-rebalance.sh on each brick.
#
# You need to have passwordless SSH login for the root user on all your nodes
# because this script will rsync many files automatically!
#
# Copyright (C) 2019–2020 Alan Orth
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

# be super careful
set -o nounset
set -o errexit

readonly ARGS="$@"
readonly HOSTNAME=$(hostname -s)
readonly PROGNAME=$(basename "$0")
readonly RSYNC_OPTS='-aAXv --quiet --protect-args'
export RSYNC_RSH='ssh -T -c aes256-gcm@openssh.com -x -o Compression=no -o ControlMaster=auto -o ControlPath=/root/.ssh/control-%L-%r@%h:%p -o ControlPersist=60'
LOCAL_BRICK='unset'
INPUT_FILE='unset'
VOLUME_NAME='unset'
DRY_RUN='no'
DEBUG='no'

function usage() {
    cat <<-EOF
Usage: $PROGNAME -b /path/to/brick -v volume -i /path/to/file [-d] [-n]

Mandatory options:
    -b: absolute brick path on local storage node
    -i: input file containing list of files to consider for healing (with path
	relative to brick mount, ie no leading "/")
    -v: name of Gluster volume to heal (check gluster volume info)

Optional options:
    -d: print debug messages
    -n: dry run (don't copy anything)

Written by: Alan Orth <a.orth@cgiar.org>
EOF

    exit 0
}

function parse_options() {
    # make sure at least 5 options are passed from CLI
    if [[ $# -lt 5 ]]; then
        usage
    fi

    while getopts 'b:di:nv:' opt; do
        case $opt in
            b)
                # strip trailing slash from brick path
                LOCAL_BRICK="${OPTARG%%/}"
                ;;
            d)
                DEBUG='yes'
                ;;
            i)
                INPUT_FILE="$OPTARG"
                ;;
            n)
                DRY_RUN='yes'
                ;;
            v)
                VOLUME_NAME="$OPTARG"
                ;;
            \?|:)
                usage
                ;;
        esac
    done
}

function check_sanity() {
    if [[ $LOCAL_BRICK == 'unset' || $INPUT_FILE == 'unset' || $VOLUME_NAME == 'unset' ]]; then
        echo "ERROR: Please make sure the local brick path, input file, and volume name are set."
        echo

        usage
    fi

    local GLUSTER_ARBITER_MATCH=$(gluster volume info $VOLUME_NAME | grep -c arbiter)
    if [[ $GLUSTER_ARBITER_MATCH -gt 0 ]]; then
        echo "ERROR: It seems $VOLUME_NAME is using an arbiter. This configuration is not supported."

        exit 1
    fi

    local GLUSTER_VOLUME_OPTIONS="cluster.data-self-heal cluster.data-self-heal cluster.entry-self-heal self-heal-daemon"
    for option in $GLUSTER_VOLUME_OPTIONS; do
        local gluster_volume_option_state=$(gluster volume get $VOLUME_NAME $option | grep $option | awk '{print $2}')
        if [[ $gluster_volume_option_state == 'on' && $DRY_RUN == 'no' ]]; then
            echo "ERROR: Volume heal option(s) enabled. Please make sure these options are off before using $PROGNAME:"
            echo
            echo "# gluster volume set $VOLUME_NAME cluster.data-self-heal off"
            echo "# gluster volume set $VOLUME_NAME cluster.metadata-self-heal off"
            echo "# gluster volume set $VOLUME_NAME cluster.entry-self-heal off"
            echo "# gluster volume set $VOLUME_NAME self-heal-daemon off"
            echo
            echo "You can re-enable them once you are done."

            exit 1
        fi
    done

    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "ERROR: Make sure $INPUT_FILE exists and is readable. Contents should be one file per line."

        exit 1
    fi

    local GLUSTER_VOLUME_MATCH=$(gluster volume list | grep -c $VOLUME_NAME)
    if [[ $GLUSTER_VOLUME_MATCH -eq 1 ]]; then
        # get a list of bricks from gluster volume info (local bricks will be skipped
        # later when we are actually copying).
        readonly REMOTE_BRICKS=$(gluster volume info homes | grep -E '^Brick[[:digit:]]' | cut -d ' ' -f2)
    else
        echo "ERROR: Gluster volume does not exist: $VOLUME_NAME"
    
        exit 1
    fi

    if [[ ! -d "$LOCAL_BRICK" ]]; then
        echo "ERROR: Brick path does not exist: $LOCAL_BRICK"
    
        exit 1
    fi
}

function main() {
    # check how many lines in the input file to compare against how many we actually process
    FILES_TO_CONSIDER_COUNT=$(wc -l "$INPUT_FILE" | awk '{print $1}')
    FILES_PROCESSED_COUNT=0
    # check how many files we don't find on this brick so we can warn the user
    # to check on other bricks
    MISSING_FILES_COUNT=0

    # read input file line by line
    while read -r line; do
        # make sure files exist on the local brick before trying to copy them
        if [[ -f "${LOCAL_BRICK}/${line}" || -L "${LOCAL_BRICK}/${line}" ]]; then
            # if the file is zero size it might be a "linkto" file, in which case
            # we should not copy it to the other storage bricks. If the dht.linkto
            # xattr is not present then it is a "real" zero-size file and we should
            # maybe copy it... or maybe just print a warning?
            if [[ ! -s "${LOCAL_BRICK}/${line}" ]]; then
                # will be > 0 if this xattr is present. Sadly getfattr throws an
                # error and returns with non-zero if the attribute is not present,
                # and grep also returns with non-zero if there is no match, so we
                # do an elaborate pipeline to get the number of matches with wc -l.
                DHT_LINKTO=$(getfattr -d -m. -h -e hex "${LOCAL_BRICK}/${line}" 2> /dev/null | grep trusted.glusterfs.dht.linkto | wc -l)
    
                # skip zero-size files with linkto xattrs
                if [[ $DHT_LINKTO -gt 0 ]]; then
                    [[ $DEBUG = 'yes' ]] && echo "WARN: zero size, linkto, skipping: ${LOCAL_BRICK}/${line}"
    
                    # increment files processed count because we are skipping for
                    # a valid reason.
                    (( FILES_PROCESSED_COUNT+=1 ))
    
                    continue
                fi # if linkto
  
                # I have seen some zero-size files that are owned by root and
                # have the sticky bit set, but do not have a linkto xattr. I
                # don't know where they come from, but we need to skip those!
                ZERO_STICKY_ROOT=$(stat -c '%a %u %g' "${LOCAL_BRICK}/${line}")

                if [[ $ZERO_STICKY_ROOT == "1000 0 0" ]]; then
                    [[ $DEBUG = 'yes' ]] && echo "WARN: zero size, root, sticky, skipping: ${LOCAL_BRICK}/${line}"
    
                    # increment files processed count because we are skipping for
                    # a valid reason.
                    (( FILES_PROCESSED_COUNT+=1 ))
    
                    continue
                fi # if zero sticky root

                # Lastly, I have seen some zero-size files that are owned by
                # root and do *not* have the linkto xattr. Technically they
                # *could* be legitimate files, though I have seen cases where
                # a better (aka non-zero, user-owned) copy actually exists on
                # another brick so I'd rather not copy these automatically for
                # now. We might just overwrite some good copies on other bricks!
                # Another theory is that these are split brain from a rename or
                # delete? In any case, let's skip them.
                ZERO_ROOT=$(stat -c '%u %g' "${LOCAL_BRICK}/${line}")

                if [[ $ZERO_ROOT == "0 0" ]]; then
                    [[ $DEBUG = 'yes' ]] && echo "WARN: zero size, root, suspicious, skipping: ${LOCAL_BRICK}/${line}"
    
                    # increment files processed count because we are skipping for
                    # a valid reason.
                    (( FILES_PROCESSED_COUNT+=1 ))
    
                    continue
                fi # if zero root

            fi # if ! -s

            # copy file to remote bricks
            for remote_brick in $REMOTE_BRICKS; do
                # don't copy files to the brick we're currently analyzing
                [[ $remote_brick = "${HOSTNAME}:${LOCAL_BRICK}" ]] && continue

                if [[ $DRY_RUN = 'yes' ]]; then
                    echo "INFO (dry run): ${LOCAL_BRICK}/${line} → ${remote_brick}/${line}"
                else
                    echo "INFO: ${LOCAL_BRICK}/${line} → ${remote_brick}/${line}"

                    rsync $RSYNC_OPTS "${LOCAL_BRICK}/${line}" "${remote_brick}/${line}"
                fi
            done

        else # file doesn't exist
            [[ $DEBUG = 'yes' ]] && echo "WARN: file ${LOCAL_BRICK}/${line} does not exist on this brick, make sure to run ${PROGNAME} on bricks in another replica set."

            (( MISSING_FILES_COUNT+=1 ))
        fi # if file exists
    
   (( FILES_PROCESSED_COUNT+=1 ))
    
    done < "$INPUT_FILE"
    
    if [[ $FILES_PROCESSED_COUNT -lt $FILES_TO_CONSIDER_COUNT ]]; then
        echo "WARN: input file had $FILES_TO_CONSIDER_COUNT lines, but we only considered $FILES_PROCESSED_COUNT. Check the script output above, as well as your input file."
    fi

    if [[ $MISSING_FILES_COUNT -gt 0 ]]; then
        echo "WARN: $MISSING_FILES_COUNT file(s) from your input file were not found on this brick. Make sure to run $PROGNAME on bricks in other replica sets too."
    fi

    [[ $DEBUG = 'yes' ]] && echo "INFO: considered $FILES_PROCESSED_COUNT lines from $INPUT_FILE."
}

# pass the shell's argument array to the parsing function
parse_options $ARGS

check_sanity

main
