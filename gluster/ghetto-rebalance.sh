#!/usr/bin/env bash
#
# ghetto-rebalance.sh v1.3.1
#
# Checks a list of files on a Gluster volume's brick mount point and removes
# files that don't belong (according to their file name and the layout, see
# gf_dm_hash.py). This should be run after ghetto-heal.sh once you are sure
# that you have copied all files to one or more bricks in each replica set.
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
# see: https://joejulian.name/post/dht-misses-are-expensive/
readonly GF_DM_HASH_PATH=/root/gf_dm_hash.py
readonly PROGNAME=$(basename $0)
DRY_RUN='no'
DEBUG='no'

function usage() {
    cat <<-EOF
Usage: $PROGNAME -b /path/to/brick -i /path/to/file [-d] [-n]

Mandatory options:
    -b: absolute brick path on local storage node
    -i: input file containing list of files to consider for analysis (with path
	relative to brick mount, ie no leading "/")

Optional options:
    -d: print debug messages
    -n: dry run (don't actually remove or re-create any files)

Written by: Alan Orth <a.orth@cgiar.org>
EOF

    exit 0
}

function parse_options() {
    # make sure at least 4 options are passed from CLI
    if [[ $# -lt 4 ]]; then
        usage
    fi

    while getopts 'b:di:n' opt; do
        case $opt in
            b)
                # strip trailing slash from brick path
                readonly BRICK_PATH="${OPTARG%%/}"
                ;;
            d)
                DEBUG='yes'
                ;;
            i)
                readonly INPUT_FILE="$OPTARG"
                ;;
            n)
                DRY_RUN='yes'
                ;;
            \?|:)
                usage
                ;;
        esac
    done
}

function check_sanity() {
    if [[ ! -x "$GF_DM_HASH_PATH" ]]; then
        echo "ERROR: Make sure $GF_DM_HASH_PATH exists and is executable. See: https://joejulian.name/post/dht-misses-are-expensive/"

        exit 1
    fi

    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "ERROR: Make sure $INPUT_FILE exists and is readable. Contents should be one file per line."

        exit 1
    fi

    if [[ ! -d "$BRICK_PATH" ]]; then
        echo "ERROR: Brick path does not exist: $BRICK_PATH"
    
        exit 1
    fi
}

function main() {
    # check how many lines in the input file to compare against how many we actually process
    FILES_TO_CONSIDER_COUNT=$(wc -l "$INPUT_FILE" | awk '{print $1}')
    FILES_CONSIDERED_COUNT=0

    while read -r line; do
        FILE_NAME=$(basename "${BRICK_PATH}/${line}")

        # check if the file is actually present on this brick and only try to
        # get its GFID if it exists. Unset FILE_GFID just in case, as its a
        # global variable and we don't want to be reading it if it was set in
        # a previous iteration (though bash's `set -o nounset` should catch it).
        unset FILE_GFID
        if [[ -f "${BRICK_PATH}/${line}" || -L "${BRICK_PATH}/${line}" ]]; then
            FILE_GFID=$(getfattr -n trusted.gfid -h -e hex "${BRICK_PATH}/${line}" 2> /dev/null | grep 0x | grep -o -E '([a-f]|[0-9]){32}$')
        fi

        FILE_PARENT_DIR=$(dirname "${BRICK_PATH}/${line}")

        # check if the file's parent directory is present so we can get its DHT
        # layout. This shouldn't be necessary, but it also serves to verify the
        # formatting of the input file.
        if [[ ! -d "$FILE_PARENT_DIR" ]]; then
            [[ $DEBUG = 'yes' ]] && echo "WARN: parent dir does not exist: ${BRICK_PATH}/${line}"

            (( FILES_CONSIDERED_COUNT+=1 ))

            continue
        fi

        # get the parent directory's DHT in hex
        FILE_PARENT_DIR_DHT=$(getfattr -n trusted.glusterfs.dht -h -e hex "$FILE_PARENT_DIR" 2> /dev/null | grep 0x | grep -o -E '([a-f]|[0-9]){32}$')
        # construct DHT layout start / end for current directory on this brick
        FILE_PARENT_DIR_DHT_MIN="0x${FILE_PARENT_DIR_DHT:16:8}"
        FILE_PARENT_DIR_DHT_MAX="0x${FILE_PARENT_DIR_DHT:24:8}"

        # get the file name's hash according to gf_dm_hash.py and strip the trailing "L"
        FILE_NAME_DM_HASH=$("$GF_DM_HASH_PATH" "$FILE_NAME" | sed 's/L$//')
        
        # check the DHT to see if the file belongs on this brick
        if [[ $FILE_NAME_DM_HASH -gt $FILE_PARENT_DIR_DHT_MIN && $FILE_NAME_DM_HASH -lt $FILE_PARENT_DIR_DHT_MAX ]]; then
            # not sure if this is necessary, but make sure the path is not a directory just in case
            if [[ -d "${BRICK_PATH}/${line}" ]]; then
                [[ $DEBUG = 'yes' ]] && echo "WARN: ${BRICK_PATH}/${line} is a directory, skipping."

                (( FILES_CONSIDERED_COUNT+=1 ))
            # file is not a directory, now check to see if it is a normal file or symlink
            elif [[ -f "${BRICK_PATH}/${line}" || -L "${BRICK_PATH}/${line}" ]]; then
                # will be > 0 if this xattr is present. Sadly getfattr throws an
                # error and returns with non-zero if the attribute is not present,
                # and grep also returns with non-zero if there is no match, so we
                # do an elaborate pipeline to get the number of matches with wc -l.
                DHT_LINKTO=$(getfattr -d -m. -h -e hex "${BRICK_PATH}/${line}" 2> /dev/null | grep trusted.glusterfs.dht.linkto | wc -l)


                # I have seen some zero-size files that are owned by root and
                # have the sticky bit set, but do not have a linkto xattr. I
                # don't know where they come from, but we need to skip those!
                ZERO_STICKY_ROOT=$(stat -c '%a %u %g' "${BRICK_PATH}/${line}")
    
                # file exists, so we need to check if it's zero size and has a
                # trusted.glusterfs.dht.linkto xattr, in which case we should
                # delete it. Gluster will recreate linktos if it needs them.
                if [[ ! -s "${BRICK_PATH}/${line}" && $DHT_LINKTO -gt 0 ]]; then
                    [[ $DEBUG = 'yes' ]] && echo "WARN: exists, belongs, zero-size linkto: ${BRICK_PATH}/${line}"

                    if [[ $DRY_RUN = 'no' ]]; then
                        echo "INFO: deleting: ${BRICK_PATH}/${line}"

                        rm -f "${BRICK_PATH}/${line}" "${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}/${FILE_GFID:2:2}/${FILE_GFID:0:8}-${FILE_GFID:8:4}-${FILE_GFID:12:4}-${FILE_GFID:16:4}-${FILE_GFID:20:12}"
                    fi # if delete

                    (( FILES_CONSIDERED_COUNT+=1 ))
                # else, check if file is zero size, owned by root, and has the
                # sticky bit set, but is not a linkto file.
                elif [[ ! -s "${BRICK_PATH}/${line}" && $ZERO_STICKY_ROOT == '1000 0 0' ]]; then
                    # If we are here then the file exists and belongs on this
                    # brick, but is a zero-size file like:
                    # ---------T.  1 root      root
                    # I think it's best to check for these and run them through
                    # ghetto-heal.sh again to see if another node has the corr-
                    # ect copy.
                    [[ $DEBUG = 'yes' ]] && echo "WARN: exists, belongs, but zero size, root, sticky: ${BRICK_PATH}/${line}"

                    # 2019-11-17 we should probably delete these... but for now
                    # I will just print a warning so I can investigate.
                    
                    (( FILES_CONSIDERED_COUNT+=1 ))
                # else, file belongs on this brick, is present, and is not a
                # zero-size linkto or a root-owned, zero-size sticky file.
                # Note that it could still be zero size and root owned! Need
                # to check the inodes and compare file hashes to see if they
                # are the same file.
                else
                    # get the inode of the "real" file on the brick
                    FILE_INODE=$(stat -c%i "${BRICK_PATH}/${line}")

                    # construct the path to the .glusterfs link based on the GIFD
                    FILE_GLUSTERFS_PATH="${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}/${FILE_GFID:2:2}/${FILE_GFID:0:8}-${FILE_GFID:8:4}-${FILE_GFID:12:4}-${FILE_GFID:16:4}-${FILE_GFID:20:12}"

                    # set the inode to something temporary
                    GLUSTERFS_FILE_INODE='unset'

                    # try to get the inode of the .glusterfs link if it exists
                    if [[ -f $FILE_GLUSTERFS_PATH || -L $FILE_GLUSTERFS_PATH ]]; then
                        GLUSTERFS_FILE_INODE=$(stat -c%i "$FILE_GLUSTERFS_PATH")
                    fi

                    # check if the "real" file's inode matches the inode of its
                    # link in .glusterfs (if it even exists at all).
                    if [[ $GLUSTERFS_FILE_INODE = 'unset' ]]; then
                        # if the .glusterfs link is missing it's not a critical
                        # error because Gluster will re-create it upon heal.
                        [[ $DEBUG = 'yes' ]] && echo "WARN: exists, belongs, but missing .glusterfs link for: ${BRICK_PATH}/${line}"

                        echo "INFO: creating .glusterfs link: ${BRICK_PATH}/${line} → $FILE_GLUSTERFS_PATH"

                        # make sure the target directory exists in .glusterfs!
                        # we need to create these two independently so that we
                        # can enforce the permissions. A single `mkdir -p` only
                        # ensures the permissions on the final directory, but
                        # not on the intermediate directories. Also, I think
                        # this is easier than messing with umask or chown.
                        mkdir -m 700 -p "${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}"
                        mkdir -m 700 -p "${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}/${FILE_GFID:2:2}"

                        ln "${BRICK_PATH}/${line}" "$FILE_GLUSTERFS_PATH"
                    # check if the "real" file's inode matches the .glusterfs
                    # link file's inode. If Gluster is working properly these
                    # will be same. If not, I *think* we can just delete them
                    # safely, but let's just do a few more checks and print a
                    # message to the user about the state of those files.
                    elif [[ $FILE_INODE != $GLUSTERFS_FILE_INODE ]]; then
                        DHT_LINKTO=$(getfattr -d -m. -h -e hex "$FILE_GLUSTERFS_PATH" 2> /dev/null | grep trusted.glusterfs.dht.linkto | wc -l)

                        # check if .glusterfs hard link is *not* more than zero
                        # bytes and has a trusted.glusterfs.dht.linkto xattr.
                        if [[ ! -s "$FILE_GLUSTERFS_PATH" && $DHT_LINKTO -gt 0 ]]; then
                            [[ $DEBUG = 'yes' ]] && echo "WARN: exists, belongs, but zero-size .glusterfs linkto for: ${BRICK_PATH}/${line}"

                            if [[ $DRY_RUN = 'no' ]]; then
                                echo "INFO: deleting zero-size .glusterfs linkto: $FILE_GLUSTERFS_PATH"

                                rm -f "$FILE_GLUSTERFS_PATH"

			        echo "INFO: creating .glusterfs link: ${BRICK_PATH}/${line} → $FILE_GLUSTERFS_PATH"

                                mkdir -m 700 -p "${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}"
                                mkdir -m 700 -p "${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}/${FILE_GFID:2:2}"

                                ln "${BRICK_PATH}/${line}" "$FILE_GLUSTERFS_PATH"
                            fi

                        elif [[ ! -s "$FILE_GLUSTERFS_PATH" ]]; then
                            # if we get here then the "real" file's inode differs
                            # from the .glusterfs link's inode, but it does not
                            # have a trusted.glusterfs.dht.linkto xattr. I think
                            # that deleting these is safe, primarily because the
                            # good copy of the file is assumed to be the "real"
                            # file on the brick.
                            [[ $DEBUG = 'yes' ]] && echo "WARN: exists, belongs, but inode differs and .glusterfs link file is zero bytes: ${BRICK_PATH}/${line}"

                            if [[ $DRY_RUN = 'no' ]]; then
                                echo "INFO: deleting zero-size .glusterfs link file: $FILE_GLUSTERFS_PATH"

                                rm -f "$FILE_GLUSTERFS_PATH"

                                echo "INFO: creating .glusterfs link: ${BRICK_PATH}/${line} → $FILE_GLUSTERFS_PATH"

                                mkdir -m 700 -p "${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}"
                                mkdir -m 700 -p "${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}/${FILE_GFID:2:2}"

                                ln "${BRICK_PATH}/${line}" "$FILE_GLUSTERFS_PATH"
                            fi
                        else
                            # if we get here then:
                            #   - the "real" file's inode differs from the
                            #     .glusterfs link's inode
                            #   - the "real" file might be larger than zero
                            #     bytes, but the checks above do not explicitly
                            #     check for that alone, so we can't be sure
                            #   - the .glusterfs link file *is* larger than zero
                            #     bytes, however...
                            #
                            # In this case we should manually examine the "real"
                            # file on the brick as well as the .glusterfs link
                            # file to see which is correct, or perhaps we can do
                            # this automatically if their hashes match!
                            FILE_SHA256SUM=$(sha256sum "${BRICK_PATH}/${line}" | awk '{print $1}')
                            GLUSTERFS_FILE_SHA256SUM=$(sha256sum "$FILE_GLUSTERFS_PATH" | awk '{print $1}')

                            if [[ $FILE_SHA256SUM = $GLUSTERFS_FILE_SHA256SUM ]]; then
                                [[ $DEBUG = 'yes' ]] && echo "WARN: exists, belongs, but inode differs and hashes match: ${BRICK_PATH}/${line}"
                                if [[ $DRY_RUN = 'no' ]]; then
                                    echo "INFO: deleting .glusterfs link file: $FILE_GLUSTERFS_PATH"
    
                                    rm -f "$FILE_GLUSTERFS_PATH"
    
                                    echo "INFO: creating new .glusterfs link: ${BRICK_PATH}/${line} → $FILE_GLUSTERFS_PATH"
    
                                    mkdir -m 700 -p "${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}"
                                    mkdir -m 700 -p "${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}/${FILE_GFID:2:2}"
    
                                    ln "${BRICK_PATH}/${line}" "$FILE_GLUSTERFS_PATH"
                                fi # end if delete yes
                            else
                                # if we get here then the following is true:
                                #   - the "real" file's inode differs from the
                                #     .glusterfs link's inode
                                #   - at least one of the "real" file or the
                                #     .glusterfs link file are larger than zero
                                #     bytes
                                #   - the hashes of each do not match
                                #
                                # This is a split brain and we should manually
                                # inspect both files, though we can inform the
                                # user if one of the files seems to be correct.
                                [[ $DEBUG = 'yes' ]] && echo "WARN: exists, belongs, but inode differs: ${BRICK_PATH}/${line}"

                                # check if "real" file is non zero and .glusterfs link is zero
                                if [[ -s "${BRICK_PATH}/${line}" && ! -s $FILE_GLUSTERFS_PATH ]]; then
                                    [[ $DEBUG = 'yes' ]] && echo "→ ${BRICK_PATH}/${line} is non zero and probably the correct file"
                                    # we probably want to delete the .glusterfs link and re-create it from the "real" file, but I haven't seen an example of this scenario yet so I won't do it automatically
                                    [[ $DEBUG = 'yes' ]] && echo "→ ... should probably do something here."
                                # check if "real" file is zero and .glusterfs link is non zero
                                elif [[ ! -s "${BRICK_PATH}/${line}" && -s $FILE_GLUSTERFS_PATH ]]; then
                                    [[ $DEBUG = 'yes' ]] && echo "→ $FILE_GLUSTERFS_PATH is non zero and probably the correct file"

                                    if [[ $DRY_RUN = 'no' ]]; then
                                        echo "INFO: re-creating file from .glusterfs link: $FILE_GLUSTERFS_PATH → ${BRICK_PATH}/${line}"

                                        rm -f "${BRICK_PATH}/${line}"
                                        ln "$FILE_GLUSTERFS_PATH" "${BRICK_PATH}/${line}" 
                                    fi
                                else
                                    [[ $DEBUG = 'yes' ]] && echo "→ both files are non-zero... uh oh"
                                fi
                            fi # end if sha256sum match
                        fi # end if non-zero .glusterfs linkto
                    else
                        echo "INFO: exists, belongs: ${BRICK_PATH}/${line}"
                    fi # end if glusterfs_file_inode unset

                    (( FILES_CONSIDERED_COUNT+=1 ))
                fi # end if "real" file is non-zero linkto
            else
                # If we get here then the file doesn't exist, perhaps because it
                # was not copied from another brick with ghetto-heal.sh, or per-
                # haps it really just does not exist (uh oh). 
                [[ $DEBUG = 'yes' ]] && echo "WARN: does not exist, belongs: ${BRICK_PATH}/${line}"

                (( FILES_CONSIDERED_COUNT+=1 ))
            fi
        # else, file does not belong on this brick
        else
            # we shouldn't be trying to heal directories, so check just in case
            if [[ -d "${BRICK_PATH}/${line}" ]]; then
                [[ $DEBUG = 'yes' ]] && echo "WARN: ${BRICK_PATH}/${line} is a directory, skipping."

                (( FILES_CONSIDERED_COUNT+=1 ))
            elif [[ -f "${BRICK_PATH}/${line}" || -L "${BRICK_PATH}/${line}" ]]; then
                # file exists, so let's see if it's a zero-size linkto or not
                # so we can inform the user properly.
                DHT_LINKTO=$(getfattr -d -m. -h -e hex "${BRICK_PATH}/${line}" 2> /dev/null | grep trusted.glusterfs.dht.linkto | wc -l)

                if [[ ! -s "${BRICK_PATH}/${line}" && $DHT_LINKTO -gt 0 ]]; then
                    [[ $DEBUG = 'yes' ]] && echo "WARN: exists, does not belong, zero-size linkto: ${BRICK_PATH}/${line}"
                else
                    [[ $DEBUG = 'yes' ]] && echo "WARN: exists, does not belong: ${BRICK_PATH}/${line}"
                fi

                # assuming we've copied the real file to the correct brick already, let's delete the copy on this brick since it doesn't belong here
                if [[ $DRY_RUN = 'no' ]]; then
                    echo "INFO: deleting: ${BRICK_PATH}/${line}"

                    rm -f "${BRICK_PATH}/${line}" "${BRICK_PATH}/.glusterfs/${FILE_GFID:0:2}/${FILE_GFID:2:2}/${FILE_GFID:0:8}-${FILE_GFID:8:4}-${FILE_GFID:12:4}-${FILE_GFID:16:4}-${FILE_GFID:20:12}"
                fi

                (( FILES_CONSIDERED_COUNT+=1 ))
            else
                [[ $DEBUG = 'yes' ]] && echo "INFO: does not exist, does not belong: ${BRICK_PATH}/${line}"

                (( FILES_CONSIDERED_COUNT+=1 ))
            fi
        fi # end if file_name_dm_hash
    done < "$INPUT_FILE" # end while read input file

    if [[ $FILES_CONSIDERED_COUNT -lt $FILES_TO_CONSIDER_COUNT ]]; then
        echo "INFO: input file had $FILES_TO_CONSIDER_COUNT files, but we only considered $FILES_CONSIDERED_COUNT. Check the script output above, as well as your input file."
    fi
}

# pass the shell's argument array to the parsing function
parse_options $ARGS

# make sure requirements and paths exist
check_sanity

main
