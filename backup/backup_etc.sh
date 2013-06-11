#!/bin/bash

FUNCTIONS=/home/backup/scripts/functions.sh
SETTINGS=/home/backup/scripts/settings.ini
DATE="$(date +%Y%m%d)"

[ -e "$FUNCTIONS" ] || exit 1
source "$FUNCTIONS"

# parse settings
[ -e "$SETTINGS" ] || exit 1
cfg_parser "$SETTINGS"

# read variables in [etc] section
cfg.section.etc

# Check for the existence of the backup directory and create
# it if it doesn't exist.
if [ ! -d "$backup_dir" ]
then
    mkdir -p "$backup_dir"
fi

tar acf "${backup_dir}/etc_${DATE}.tar.xz" /etc
