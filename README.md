# autoconv

Watch a directory and automatically convert videos to the desired format.

**CPU resource limit is recommended!**

## Installation

```yaml
---
services:
  autoconv:
    image: ghcr.io/leapwill/autoconv:1.latest
    container_name: autoconv
    environment:
      - DEBUG=1 # optional
    volumes:
      - /path/to/config/dir:/config
      - /path/to/watch:/watch
      - /path/to/output:/out
    restart: unless-stopped
    network_mode: none
    devices:
      - /dev/dri:/dev/dri # optional hardware acceleration
    deploy:
      resources:
        limits:
          cpus: "10"
```

Path of config is required. Other paths (`/watch` and `/out` in example) are configurable.

Tags:
* `1.latest`: latest "stable" version as long as there are no breaking changes
* `dev`: latest version regardless of stability
* Version numbers are also available for rollback convenience

Based on the [LinuxServer.io image](https://docs.linuxserver.io/images/docker-ffmpeg/). See their README for more information on hardware acceleration.

## Configuration

Modify `/config/autoconv.json` according to your needs. The first codec in the allowed list will be used if conversion is necessary.

```yaml
matchers: # list of file path prefix matchers, the first matching one is used
- dir: '/watch' # path to match
  recurse: true # watch subdirectories
  result: # desired output format
    vcodecs: # allowable video codecs
    - h264
    maxheight: '2160' # scale down if necessary
    acodecs: # allowable audio codecs for stereo audio
    - aac
    - ac3
    acodecs6: # allowable audio codecs for surround sound
    - ac3
    scodecs: # allowable subtitle formats
    - srt
    - ass
    allowcopy: true # don't re-encode a stream if it's already compliant
    keepextra: "asdt" # which types of streams to keep non-selected of (after the selected streams)
    naming: 'copy' # or 'plex' to attempt to use Plex-compatible movie and TV names, including the necessary paths
    path: '/out' # base directory for output
    containers: # allowable containers (mkv is recommended!)
    - mkv
  ffargs: [] # extra arguments to ffmpeg (e.g. preset, profile, crf)
logerr: true # optional, failures will be logged in <FileName>.err.log in the matcher dir
maxConcurrent: 1 # number of concurrent conversions to allow
```

Currently using JSON for native PowerShell support, but documented in YAML for readability.

## Usage

Put your video files in the watched directory. If you have a subtitle file, put it in the directory **first** and give it the same name as the video. Input files will be deleted if conversion succeeds.

### Naming
For Plex name detection, movies should be `Title Year` (year may be in parentheses), and TV episodes should be `Series Name SxxExx`. Words can be separated by space or period. Any other information after the year or season/episode is ignored.

Extras are supported. The extra file name must start with the movie name and year, and then contain an extra name, hyphen, and type of extra in square brackets. Supported extras types are `behindthescenes`, `deleted`, `featurette`, `interview`, `scene`, `short`, `trailer`, and `other`, per [the Plex documentation](https://support.plex.tv/articles/local-files-for-trailers-and-extras/).

Tags `tvdb`, `tmdb`, `imdb`, and `edition` are supported.

Example:
- Movie: `Avatar 2009.mp4`
- Subtitles: `Avatar 2009.srt`
- Extras: `Avatar 2009 [Sigourney Weaver-interview].mp4`

### Environment Variables
* `DEBUG` for verbose logging
* `DRY_RUN` to log `ffmpeg` command without executing
