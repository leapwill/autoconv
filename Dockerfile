FROM lscr.io/linuxserver/ffmpeg:latest

LABEL "org.opencontainers.image.source"="https://github.com/leapwill/autoconv"

RUN <<EOR
set -eu
ver=$(curl -Ls -o /dev/null -w '%{url_effective}' 'https://aka.ms/powershell-release?tag=lts')
ver=$(grep -Po '[0-9.]+$' <<EOF
$ver
EOF
)
echo "Fetching PowerShell version $ver"
curl -s -L -o /tmp/pwsh.deb "https://github.com/PowerShell/PowerShell/releases/download/v${ver}/powershell-lts_${ver}-1.deb_amd64.deb"
dpkg -i /tmp/pwsh.deb
apt-get update
apt-get install -f
rm /tmp/pwsh.deb
EOR

RUN apt-get install -y inotify-tools && \
    rm -rf /var/lib/apt/lists/*

COPY src/ /src/

ENTRYPOINT ["/bin/sh", "/src/watch.sh"]
