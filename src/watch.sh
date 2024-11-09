#!/bin/sh

if ! [ -r /config/autoconv.json ]; then
    cp /src/autoconv.json /config/autoconv.json
fi

/usr/bin/inotifywait --monitor --recursive --quiet --format '%w_////%e_////%f' -e close_write -e moved_to /watch |
while read -r notif; do
    nice -n 1 pwsh -File /src/Start-Autoconv.ps1 "$notif" &
done
