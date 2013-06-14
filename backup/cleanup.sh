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

    find "${backup_dir}" -type f ! -newermt "${keep[@]}" ! -name "*.sh" -delete

done
