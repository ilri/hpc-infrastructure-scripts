#!/bin/bash

FUNCTIONS=/home/backup/scripts/functions.sh
SETTINGS=/home/backup/scripts/settings.ini
DATE="$(date +%Y%m%d)"

[ -e "$FUNCTIONS" ] || exit 1
source "$FUNCTIONS"

# parse settings
[ -e "$SETTINGS" ] || exit 1
cfg_parser "$SETTINGS"

# read variables in [postgres] section
cfg.section.postgres

# set the user's Postgres password in the variable because we are
# not using pg_dump interactively, so we can't type it in!
export PGPASSWORD="$password"

# Check for the existence of the backup directory and create
# it if it doesn't exist.
if [ ! -d "$backup_dir" ]
then
    mkdir -p "$backup_dir"
fi

# loop through all databases listed in settings.ini
for DB_NAME in "${databases[@]}"; do
    /usr/bin/pg_dump -b -v -o --format=custom -h localhost -U "$username" -f "${backup_dir}/${DB_NAME}_${DATE}.backup" "$DB_NAME"
done
