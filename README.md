# autoconv

Watch a directory and automatically convert videos to the desired format.

**CPU resource limit is recommended!**

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
    naming: 'copy' # or 'plex' to attempt to use Plex-compatible movie and TV names, including the necessary paths
    path: '/out' # base directory for output
    containers: # allowable containers (mkv is recommended!)
    - mkv
```

Currently using JSON for native PowerShell support.

## Usage

Put your video files in the watched directory. If you have a subtitle file, put it in the directory **first** and give it the same name as the video. Input files will be deleted if conversion succeeds.

### Naming
For Plex name detection, movies should be `Title Year` (year may be in parentheses), and TV episodes should be `Series Name SxxExx`. Words can be separated by space or period. Any other information after the year or season/episode is ignored.

### Environment Variables
* `DEBUG` for verbose logging
* `DRY_RUN` to log `ffmpeg` command without executing
