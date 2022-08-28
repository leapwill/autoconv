#!/bin/bash

cp -n /src/autoconv.json /config/

/usr/bin/inotifywait --monitor --recursive --quiet --csv -e close_write -e moved_to /watch |
while read -r notif; do
    nice -n 1 pwsh -File /src/Start-Autoconv.ps1 "$notif" -ErrorAction Stop &
done
