FROM mcr.microsoft.com/powershell:debian-bullseye-slim

LABEL "org.opencontainers.image.source"="https://github.com/leapwill/autoconv"

# get deps
RUN \
    apt-get update && \
    apt-get install -y inotify-tools wget xz-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# get a nightly git build of ffmpeg
RUN \
    mkdir -p /tmp/dl-ffmpeg && \
    cd /tmp/dl-ffmpeg && \
    wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz && \
    wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz.md5 && \
    md5sum -c ffmpeg-git-amd64-static.tar.xz.md5 && \
    tar xvf ffmpeg-git-amd64-static.tar.xz && \
    mv $(find . -maxdepth 1 -type d -name 'ffmpeg*') ffmpeg-git-amd64-static && \
    mv ffmpeg-git-amd64-static/ffmpeg ffmpeg-git-amd64-static/ffprobe /usr/local/bin/ && \
    cd / && \
    rm -rf /tmp/dl-ffmpeg

COPY src/ /src/

CMD ["/bin/bash", "/src/watch.sh"]
