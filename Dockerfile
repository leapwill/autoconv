FROM jrottenberg/ffmpeg:5.1-alpine313 AS ffbuild
FROM mcr.microsoft.com/powershell:lts-alpine-3.13
COPY --from=ffbuild /usr/local /usr/local
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
# ffmpeg dynamic linking
RUN apk add --no-cache --update libgcc libstdc++ ca-certificates libcrypto1.1 libssl1.1 libgomp expat git

LABEL "org.opencontainers.image.source"="https://github.com/leapwill/autoconv"

RUN apk add --no-cache --update inotify-tools

COPY src/ /src/

CMD ["/bin/sh", "/src/watch.sh"]
