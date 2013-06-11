#!/bin/bash

FUNCTIONS=/home/backup/scripts/functions.sh
SETTINGS=/home/backup/scripts/settings.ini

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

# loop through all databases listed in settings.ini
for DB_NAME in "${databases[@]}"; do
    /usr/bin/vacuumdb --analyze -h localhost -U "$username" "$DB_NAME"
done
