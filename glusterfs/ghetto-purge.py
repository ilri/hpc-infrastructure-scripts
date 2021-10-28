#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-3.0-only
#
# ghetto-purge.py v0.0.1
#
# Read files and directories from an input file, one per line, and attempt to
# remove them from the GlusterFS brick along with their .glusterfs links. This
# is to work around split brain issues when trying to remove directories from
# the FUSE mount, for example:
#
# - Directory not empty
# - No such file or directory
#
# These are caused by various types of GlusterFS split brain.
#
# Requires Python 3.6+.

import argparse
import os
from pathlib import Path


def main():
    # Strip trailing slash from brick path
    brick_path = args.brick_path.rstrip("/")

    # Read paths from input file (could be files or directories)
    lines_to_analyze = args.input_file.readlines()

    for line in lines_to_analyze:
        # Note that we have to remove \n from the line
        path_to_analyze = f"{brick_path}/{line.strip()}"

        # To be safe I check if this is a symlink first, because we only
        # want to process entries named in our input file and not follow them
        # all over the file system. I am not sure how to deal with these yet...
        # pathlib's exists() will follow symlinks and return False if they are
        # broken, for example (note that pathlib's is_dir() is different than
        # os.is_dir(), and the latter has follow_symlinks(false)).
        if Path(f"{path_to_analyze}").is_symlink():
            print(f"Skipping symlink: {path_to_analyze}")

            continue

        if Path(f"{path_to_analyze}").exists():
            if Path(f"{path_to_analyze}").is_dir():
                if args.debug:
                    print(f"Descend into: {path_to_analyze}")

                # This will recursively handle all child directories and files,
                # so by the time we get back here we can simply remove the ori-
                # directory safely.
                descend_into_directory(brick_path, path_to_analyze)

                if args.debug:
                    print(f"Process directory: {path_to_analyze}")

                process_directory(brick_path, path_to_analyze)

            elif Path(f"{path_to_analyze}").is_file():
                process_file(brick_path, path_to_analyze)
        else:
            if args.debug:
                print(f"Does not exist on this brick: {path_to_analyze}")

            continue

    args.input_file.close()


def descend_into_directory(brick_path, path):
    if args.debug:
        print(f"Descended into: {path}")

    with os.scandir(path) as list_of_entries:
        for entry in list_of_entries:
            if entry.is_dir():
                if args.debug:
                    print(f"Descend into: {path}")

                descend_into_directory(brick_path, entry.path)

                # After we return from descending into and removing child dirs
                # we should be able to remove the original dir as we go back up.
                # This is the same logic as in main(), but here it is for dirs
                # we encounter as we walk, whereas in main() we are iterating
                # over entries named in the input file.
                process_directory(brick_path, entry.path)

            elif entry.is_file():
                process_file(brick_path, entry.path)


def process_directory(brick_path, path):
    if args.debug:
        print(f"Processing directory: {path}")

    # Get a string representation of the xattr from hex bytes
    directory_gfid = os.getxattr(path, "trusted.gfid").hex()
    directory_glusterfs_path = dot_glusterfs_path(brick_path, directory_gfid)

    if Path(path).exists():
        if not args.dry_run:
            os.rmdir(path)

        print(f'{"(DRY RUN) " if args.dry_run else ""}Removed directory: {path}')

    # Directories inside the .glusterfs directory should always be symlinks. We
    # should remove them unconditionally. We don't use exists() here because it
    # follows symlinks by default and errors if the link is broken.
    if Path(directory_glusterfs_path).is_symlink():
        if not args.dry_run:
            os.remove(directory_glusterfs_path)

        print(
            f'{"(DRY RUN) " if args.dry_run else ""}Removed directory symlink: {directory_glusterfs_path}'
        )


def process_file(brick_path, path):
    if args.debug:
        print(f"Processing file: {path}")

    # Get a string representation of the xattr from hex bytes
    file_gfid = os.getxattr(path, "trusted.gfid").hex()
    file_glusterfs_path = dot_glusterfs_path(brick_path, file_gfid)

    if Path(path).exists():
        if not args.dry_run:
            os.remove(path)

        print(f'{"(DRY RUN) " if args.dry_run else ""}Removed file: {path}')

    if Path(file_glusterfs_path).exists():
        if not args.dry_run:
            os.remove(file_glusterfs_path)

        print(
            f'{"(DRY RUN) " if args.dry_run else ""}Removed file hardlink: {file_glusterfs_path}'
        )


def dot_glusterfs_path(brick_path, gfid):
    # Construct path to .glusterfs file based on the GFID
    return f"{brick_path}/.glusterfs/{gfid[0:2]}/{gfid[2:4]}/{gfid[0:8]}-{gfid[8:12]}-{gfid[12:16]}-{gfid[16:20]}-{gfid[20:]}"


parser = argparse.ArgumentParser(
    description="Purge files and directories from GlusterFS backend brick (along with their .glusterfs links)."
)
parser.add_argument(
    "-b",
    "--brick-path",
    help="Path to brick.",
    required=True,
)
parser.add_argument(
    "-d",
    "--debug",
    help="Print debug messages.",
    action="store_true",
)
parser.add_argument(
    "-i",
    "--input-file",
    help="Path to input file.",
    required=True,
    type=argparse.FileType("r"),
)
parser.add_argument(
    "-n",
    "--dry-run",
    help="Don't actually delete anything.",
    action="store_true",
)
args = parser.parse_args()


if __name__ == "__main__":
    main()

# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
