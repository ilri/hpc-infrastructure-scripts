#!/bin/bash

FUNCTIONS=/home/backup/scripts/functions.sh
SETTINGS=/home/backup/scripts/settings.ini

[ -e "$FUNCTIONS" ] || exit 1
source "$FUNCTIONS"

# parse settings
[ -e "$SETTINGS" ] || exit 1
cfg_parser "$SETTINGS"

# read which sections to clean
cfg.section.cleanup

for SECTION in "${sections[@]}"; do

    # read variables in section
    cfg.section.$SECTION

    find "${backup_dir}" -type f ! -newermt "${keep[@]}" ! -name "*.sh"

done
