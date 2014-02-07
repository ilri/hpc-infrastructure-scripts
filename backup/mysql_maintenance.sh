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

[[ -e "$FUNCTIONS" ]] || exit 1
source "$FUNCTIONS"

# parse settings
[[ -e "$SETTINGS" ]] || exit 1
cfg_parser "$SETTINGS"

# read variables in [mysql] section
cfg.section.mysql

/usr/bin/mysqlcheck --check --auto-repair --all-databases --verbose -u "$username" -p"$password"
/usr/bin/mysqlcheck --optimize --all-databases --verbose -u "$username" -p"$password"
