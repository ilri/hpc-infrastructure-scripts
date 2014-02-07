#!/bin/bash

# Copyright (C) 2013 Alan Orth
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

FUNCTIONS=/home/backup/scripts/backup/functions.sh
SETTINGS=/home/backup/scripts/backup/settings.ini
DATE="$(date +%Y%m%d)"

[[ -e "$FUNCTIONS" ]] || exit 1
source "$FUNCTIONS"

# parse settings
[[ -e "$SETTINGS" ]] || exit 1
cfg_parser "$SETTINGS"

# read variables in [mysql] section
cfg.section.mysql

# Check for the existence of the backup directory and create
# it if it doesn't exist.
if [[ ! -d "$backup_dir" ]]
then
    mkdir -p "$backup_dir"
fi

# loop through all databases listed in settings.ini
for DB_NAME in "${databases[@]}"; do
    /usr/bin/mysqldump -u "$username" -p"$password" -h localhost -e --opt -c "$DB_NAME" | /usr/bin/xz > "${backup_dir}/${DB_NAME}_${DATE}.xz"
done
