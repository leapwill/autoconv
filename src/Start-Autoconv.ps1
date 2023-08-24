#Requires -Version 7

<#
.PARAMETER Notif
CSV notification from inotifywait, in format directory/,event[,event...],filename
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory,Position=0)]
    [string]
    $Notif
)

$LOG_TAG = Get-Random

#region parse parmeter
if ("$Env:DEBUG" -eq '1') {
  $VerbosePreference = 'Continue'
  $DebugPreference = 'Continue'
}
$NotifArr = $Notif.Split(',')
[string]$WatchedDir = $NotifArr[0]
[string]$FileName = $NotifArr[-1]
[string[]]$Events = $NotifArr[1..($NotifArr.Length-2)]
Write-Output "[$LOG_TAG]Recieved event dir=$($WatchedDir) file=$($FileName) events=$($Events)"
$FileName = $WatchedDir + $FileName
$File = Get-Item -LiteralPath $FileName
[string[]]$VIDEO_EXTENSIONS = @('.3g2','.3gp','.3gp2','.3gpp','.amr','.amv','.asf','.avi','.bdmv','.bik','.d2v','.divx','.drc','.dsa','.dsm','.dss','.dsv','.evo','.f4v','.flc','.fli','.flic','.flv','.hdmov','.ifo','.ivf','.m1v','.m2p','.m2t','.m2ts','.m2v','.m4b','.m4p','.m4v','.mkv','.mk3d','.mp2v','.mp4','.mp4v','.mpe','.mpeg','.mpg','.mpls','.mpv2','.mpv4','.mov','.mts','.mxf','.ogm','.ogv','.pss','.pva','.qt','.ram','.ratdvd','.rm','.rmm','.rmvb','.roq','.rpm','.smil','.smk','.swf','.tp','.tpr','.ts','.vob','.vp6','.webm','.wm','.wmp','.wmv')
if (-not ($VIDEO_EXTENSIONS -Contains $File.Extension)) {
    Write-Warning "[$LOG_TAG]Skipping as it does not appear to be a video file"
    exit 0
}
[string[]]$BITMAP_SUBS = @('dvb_subtitle', 'dvd_subtitle', 'hdmv_pgs_subtitle')
#endregion

#region parse config, find output format
[PSCustomObject]$Config = $null
[PSCustomObject]$Matcher = $null
function Parse-Config {
    $ConfigFile = '/config/autoconv.json'
    $script:Config = Get-Content $ConfigFile | ConvertFrom-Json
    foreach ($m in $Config.matchers) {
        if ($WatchedDir.StartsWith($m.dir)) {
            $script:Matcher = $m
            break
        }
    }
    # TODO fill in default values for optional matcher params
    if ((-not ($Matcher.recurse)) -and ($File.Directory.ToString() + [IO.Path]::DirectorySeparatorChar) -ne $WatchedDir) {
        # file is in child dir, and recursion is disabled
        $script:Matcher = $null
    }
    if ($Matcher -eq $null) {
        throw "[$LOG_TAG]Could not find a directory matcher for $($FileName)"
    }
    Write-Output "[$LOG_TAG]Using matcher dir=$($Matcher.dir)"
} 
#endregion

#region support functions
function Guess-PlexName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]
        $OrigName
    )
    Set-StrictMode -Version Latest
    # https://support.plex.tv/articles/naming-and-organizing-your-tv-show-files/
    # https://support.plex.tv/articles/naming-and-organizing-your-movie-media-files/
    # https://support.plex.tv/articles/local-files-for-trailers-and-extras/
    [System.Collections.Generic.Dictionary[string,string]]$EXTRAS_TYPES = @{}
    $EXTRAS_TYPES.Add('behindthescenes', 'Behind The Scenes')
    $EXTRAS_TYPES.Add('deleted', 'Deleted Scenes')
    $EXTRAS_TYPES.Add('featurette', 'Featurettes')
    $EXTRAS_TYPES.Add('interview', 'Interviews')
    $EXTRAS_TYPES.Add('scene', 'Scenes')
    $EXTRAS_TYPES.Add('short', 'Shorts')
    $EXTRAS_TYPES.Add('trailer', 'Trailers')
    $EXTRAS_TYPES.Add('other', 'Other')
    $words = (($OrigName -Replace ' - ',' ') -Replace '  ',' ').Split([char[]]@('.', ' '))
    [string]$year = ''
    [string]$season = ''
    [string]$episode = ''
    [int]$seasEpIdx = $null
    $isTv = $false
    for ($i = 0; $i -lt $words.Length; $i++) {
        $word = $words[$i]
        if ($word -iMatch 's([0-9]{2,3})e([0-9]{2,3})') {
            $isTv = $true
            $season = $Matches[1]
            $episode = $Matches[2]
            $seasEpIdx = $words.IndexOf($word)
        }
        elseif ($word -Match '(?:1[89]|20)[0-9]{2}') {
            $year = $words[$i] = $word -Replace '[\(\)]',''
        }
    }
    [string]$extraName = ''
    [string]$extraType = ''
    if ($OrigName -iMatch "\[([^\[\]]+)-($([string]::Join('|',$EXTRAS_TYPES.Keys)))\]") {
        $extraName = $Matches[1]
        $extraType = $Matches[2]
    }
    [string]$TAGS_PATTERN = '{(tvdb|tmdb|imdb)-[^}]+}'
    [string]$tags = ''
    if ($OrigName -Match $TAGS_PATTERN) {
        $tags = ' ' + (($words | Select-String $TAGS_PATTERN -AllMatches).Matches | Join-String -Property Value -Separator ' ')
    }
    [string]$editionTag = ''
    if ($OrigName -Match '{edition-[^}]+}') {
        $editionTag = ' ' + $Matches[0]
    }
    Write-Debug "[$LOG_TAG]isTv:$isTv year:$year season:$season episode:$episode seasEpIdx:$seasEpIdx isExtra:$($extraType -ne '') tags:$tags"

    [int]$nameStopIdx = -1
    if ($year -and $seasEpIdx) {
        $nameStopIdx = [Math]::Min($words.IndexOf($year), $seasEpIdx)
    }
    elseif ($year) {
        $nameStopIdx = $words.IndexOf($year)
    }
    else {
        $nameStopIdx = $seasEpIdx
    }
    $name = [System.ArraySegment[string]]::new($words, 0, $nameStopIdx)
    if ($isTv) {
        return (Join-Path "${name}${tags}" "Season $season" "$name - s${season}e$episode")
    }
    elseif ($year -ne $null -and -not $isTv) {
        if ($extraType -ne '') {
            return (Join-Path "$name (${year})${tags}" $EXTRAS_TYPES[$extraType] $extraName)
        }
        return (Join-Path "$name (${year})${tags}" "$name (${year})${tags}${editionTag}")
    }
    else {
        throw "[$LOG_TAG]Indecipherable movie or TV name=$OrigName"
    }
}
function Get-AudioCodecRank {
    param([Parameter(Mandatory,Position=0)]$Stream)
    function Get-SurroundRank {
        param([Parameter(Mandatory,Position=0)]$Stream)
        switch ($Stream.codec_name) {
            'aac' {
                function Get-AacProfileName {
                    # --enable-small makes libavcodec give numbers, defined at https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/avcodec.h#L1554 and names at https://github.com/FFmpeg/FFmpeg/blob/870bfe16a12bf09dca3a4ae27ef6f81a2de80c40/libavcodec/profiles.c#L26
                    param([Parameter(Mandatory,Position=0)]$NameOrNum)
                    [int]$i = -1
                    if ([int]::TryParse($NameOrNum, [ref]$i)) {
                        return @('Main', 'LC', 'SSR', 'LTP', 'HE-AAC')[$i]
                    }
                    return $NameOrNum
                }
                switch (Get-AacProfileName $Stream.profile) {
                    'LC' { return 99 }
                    'HE-AAC' { return 98 }
                    default {
                        throw "[$LOG_TAG]Unkown multi-channel AAC profile='$($Stream.profile)' on stream index=$($Stream.index)"
                    }
                }
            }
            'dts' {
                switch ($Stream.profile) {
                    'DTS-HD MA' { return 90 } # great but TV won't play
                    default {
                        throw "[$LOG_TAG]Uninvestigated multi-channel DTS profile='$($Stream.profile)' on stream index=$($Stream.index)"
                    }
                }
            }
            'eac3' { return 60 }
            'ac3' { return 50 }
            default {
                throw "[$LOG_TAG]Unknown multi-channel codec='$($Stream.codec_name)' on stream index=$($Stream.index)"
            }
        }
    }
    switch -Regex ($Stream.channels) {
        '6|8' {
            return (Get-SurroundRank $Stream) + ($Stream.channels * 100)
        }
        2 {
            switch ($Stream.codec_name) {
                'aac' { return 270 }
                default {
                    throw "[$LOG_TAG]Unknown 2ch codec='$($Stream.codec_name)' on stream index=$($Stream.index)"
                }
            }
        }
        default {
            throw "[$LOG_TAG]Not yet implemented number of audio channels=$($Stream.channels) on stream index=$($Stream.index)"
        }
    }
}
#endregion

$vSrc = @{} # stream obj, int idx
$aSrc = @{}
$sSrc = @{}
#region probe input, decide what to convert
[PSCustomObject]$Probe = $null
[string]$SubFile = $null
function Examine-InputFile {
    $script:Probe = ffprobe -v error -print_format json -show_streams -show_entries format=duration $FileName 2>$null | ConvertFrom-Json
    $script:SubFile = Join-Path $File.Directory ($File.BaseName+'.srt') # TODO could be better, .srt is not the only format
    if (-not (Test-Path -PathType Leaf -LiteralPath $SubFile)) {
        $script:SubFile = $null
    }
    if ($SubFile) {
        $subProbe = ffprobe -print_format json -show_streams $SubFile 2>$null | ConvertFrom-Json
        $script:sSrc.stream = $subProbe.streams[0]
        $script:sSrc.idx = -1
    }
    foreach ($s in $Probe.streams) {
        Write-Debug "[$LOG_TAG]Processing stream=$s"
        switch ($s.codec_type) {
            'video' {
                if ($vSrc.ContainsKey('stream') -and $vSrc.stream -ne $null) {
                    if ($s.codec_name -eq 'mjpeg') {
                        # cover art, ignore
                        continue
                    }
                    else {
                        throw "[$LOG_TAG]Second video stream found at index=$($s.index)"
                    }
                }
                # TODO ranking and preference
                $script:vSrc.stream = $s
                $script:vSrc.idx = $s.index
                Break
            }
            'audio' {
                if ($aSrc.ContainsKey('stream') -and $aSrc.stream -ne $null -and $s.tags.PSobject.Properties['language'] -and -not ($s.tags.language -iLike '*eng*')) {
                    Write-Debug "[$LOG_TAG]Skipping audio track: already have one and new is not English"
                    Break
                }
                if ($aSrc.ContainsKey('stream') -and $aSrc.stream -ne $null -and (Get-AudioCodecRank $aSrc.stream) -gt (Get-AudioCodecRank $s)) {
                    Write-Debug "[$LOG_TAG]Skipping audio track: already have one and new one is worse"
                    # TODO check language='eng'
                    Break
                }
                if ($aSrc.ContainsKey('stream') -and $aSrc.stream -ne $null -and $aSrc.stream.tags.PSobject.Properties['language'] -and $aSrc.stream.tags.language -iLike '*eng*') {
                    Write-Debug "[$LOG_TAG]Skipping audio track: already have one that is English"
                    Break
                }
                Write-Debug "[$LOG_TAG]Taking audio track"
                $script:aSrc.stream = $s
                $script:aSrc.idx = $s.index
                Break
            }
            'subtitle' {
                if ($SubFile) {
                    # explicitly given, ignore any in input file
                    Break
                }
                if ($sSrc.ContainsKey('stream') -and $sSrc.stream -ne $null -and $s.tags.PSobject.Properties['language'] -and -not ($s.tags.language -iLike '*eng*')) {
                    Write-Debug "[$LOG_TAG]Skipping sub track: already have one and new is not English"
                    Break
                }
                if ($sSrc.ContainsKey('stream') -and $sSrc.stream -ne $null -and $sSrc.stream.tags.language -iLike '*eng*' -and $s.tags.PSobject.Properties['title'] -and $s.tags.title -iLike '*SDH*') {
                    Write-Debug "[$LOG_TAG]Skipping sub track: already have an English and new is SDH"
                    Break
                }
                if ($sSrc.ContainsKey('stream') -and $sSrc.stream -ne $null -and $sSrc.stream.tags.PSobject.Properties['language'] -and $sSrc.stream.tags.language -iLike '*eng*') {
                    Write-Debug "[$LOG_TAG]Skipping sub track: already have one that is English"
                    Break
                }
                Write-Debug "[$LOG_TAG]Taking sub track"
                $script:sSrc.stream = $s
                $script:sSrc.idx = $s.index
                Break
            }
            default {
                Write-Warning "[$LOG_TAG]Unknown codec type='$($s.codec_type)' name='$($s.codec_name)'"
                Break
            }
        }
    }
 
    Write-Verbose "[$LOG_TAG]Chose vcodec='$($vSrc.stream.codec_name)'@$($vSrc.idx) acodec='$($aSrc.stream.codec_name)'$($aSrc.stream.channels)ch@$($aSrc.idx) scodec='$(($sSrc.ContainsKey('stream') -and $sSrc.stream -ne $null) ? $($sSrc.stream.codec_name) : '')'@$($sSrc.ContainsKey('idx') ? $sSrc.idx : '')"
}

# figure out what needs to be done (consider codecs; video: resolution, dynamic range, color, and field_order)
[string]$vDestCodec = $null
[string]$aDestCodec = $null
[string]$sDestCodec = $null
function Select-Codecs {
    $script:vDestCodec = $Matcher.result.vcodecs[0]
    if ($Matcher.result.vcodecs -Contains $vSrc.stream.codec_name -and $Matcher.result.allowcopy) {
        $script:vDestCodec = 'copy'
    }
    if ($Matcher.result.vcodecs -Contains 'hevc' -and -not ($vDestCodec -eq 'hevc' -or ($vDestCodec -eq 'copy' -and $vSrc.stream.codec_name -eq 'hevc')) -and (($vSrc.stream.width -gt 1920 -or $vSrc.stream.height -gt 1080) -or ($vSrc.stream.profile -iLike '*10' -or $vSrc.stream.pix_fmt -iMatch '.*10[bl]e') -or ($vSrc.stream.color_space -eq 'bt2020nc' -or $vSrc.stream.color_transfer -eq 'smpte2084' -or $vSrc.stream.color_primaries -eq 'bt2020'))) {
        # compatibility with some TVs
        $script:vDestCodec = 'libx265'
        Write-Debug "[$LOG_TAG]Video stream will be $vDestCodec : >FHD or 10-bit color or HDR"
    }
    $script:aDestCodec = $null
    if ($aSrc.stream.channels -le 2) {
        $script:aDestCodec = $Matcher.result.acodecs[0]
        if ($Matcher.result.acodecs -Contains $aSrc.stream.codec_name -and $Matcher.result.allowcopy) {
            $script:aDestCodec = 'copy'
        }
    }
    else {
        $script:aDestCodec = $Matcher.result.acodecs6[0]
        if ($Matcher.result.acodecs6 -Contains $aSrc.stream.codec_name -and $Matcher.result.allowcopy) {
            $script:aDestCodec = 'copy'
        }
    }
    $script:sDestCodec = $Matcher.result.scodecs[0]
    if (($Matcher.result.scodecs -Contains $sSrc.stream.codec_name -and $Matcher.result.allowcopy)) {
        $script:sDestCodec = 'copy'
    }
    elseif ($BITMAP_SUBS -Contains $sSrc.stream.codec_name) {
        $bitmapAllowedIntersection = $Matcher.result.scodecs | Where-Object {$BITMAP_SUBS -Contains $_}
        if ($bitmapAllowedIntersection.Length -eq 0) {
            $script:sDestCodec = 'copy'
            Write-Debug "[$LOG_TAG]Subtitle stream will be copied as $($sSrc.stream.codec_name) : is bitmap type and no bitmap types in allow list"
        }
        else {
            $script:sDestCodec = $bitmapAllowedIntersection[0]
            Write-Debug "[$LOG_TAG]Subtitle stream will be $sDestCodec : is first allowed bitmap type"
        }
    }
    # convert codec to encoder where names are different
    $vDestCodec = switch ($vDestCodec) {
        'x264' { 'libx264' }
        'hevc' { 'libx265' }
        default { $vDestCodec }
    }
    $aDestCodec = switch ($aDestCodec) {
        'opus' { 'libopus' }
        default { $aDestCodec }
    }
    Write-Verbose "[$LOG_TAG]Producing vcodec='$($vDestCodec)' acodec='$($aDestCodec)' scodec='$($sDestCodec)'"
}
#endregion

#region convert
function Invoke-Ffmpeg {
    $OutFullName = $null
    if ($Matcher.result.naming -eq 'plex') {
        $OutFullName = Join-Path $Matcher.result.path (Guess-PlexName $File.Name)
        $path = Split-Path $OutFullName -Parent
        New-Item -ItemType Directory -Force -Path $path > $null
    }
    else {
        $OutFullName = Join-Path $Matcher.result.path $File.BaseName
    }

    [string[]]$ffArgs = @('ffmpeg','-i', "`"$FileName`"")
    if ($SubFile) {
        $ffArgs += @('-i', "`"$SubFile`"")
    }
    # TODO Move-Item if possible instead of copying streams to new container
    $ffArgs += @('-map', "0:$($vSrc.idx)", '-map', "0:$($aSrc.idx)")
    if ($SubFile) {
        $ffArgs += @('-map', '1:s')
    }
    elseif ($sSrc.stream) {
        $ffArgs += @('-map', "0:$($sSrc.idx)")
    }
    if ($SubFile -or $sSrc.stream) {
        $ffArgs += @('-c:s', $sDestCodec)
    }
    $ffArgs += @('-c:v', $vDestCodec, '-crf', '22', '-c:a', $aDestCodec)
    if ($vSrc.stream.height -gt $Matcher.result.maxheight) {
        # could do this with force_original_aspect_ratio=decrease:force_divisible_by=2 but that's quirky
        $ffArgs += @('-vf', "scale=-2:$($Matcher.result.maxheight)")
    }
    if (@('hevc','libx265') -Contains $vDestCodec) {
        $ffArgs += @('-x265-params', 'log-level=warning')
    }
    if ($aDestCodec -eq 'ac3' -and $aSrc.stream.channels -gt 6 -and $aSrc.stream.channel_layout -Match '\.1') {
        # for some reason ffmpeg defaults to not including LFE when downmixing to ac3
        $ffArgs += @('-ac', '6')
    }
    $ffArgs += $Matcher.ffargs
    $destExtension = $null
    if (($sSrc.stream -or $SubFile) -and $Matcher.result.containers -Contains 'mkv') {
        $destExtension = 'mkv'
    }
    elseif ($Matcher.result.containers -Contains $File.Extension.Substring(1)) {
        $destExtension = $File.Extension.Substring(1)
    }
    else {
        $destExtension = $Matcher.result.containers[0]
    }
    $OutFullName += '.' + $destExtension
    $ffArgs += "`"$OutFullName`""
    if ($VerbosePreference -eq 'SilentlyContinue') {
        $ffArgs += @('-hide_banner', '-loglevel', 'warning')
    }
    if (Test-Path -LiteralPath $OutFullName) {
        Write-Warning "[$LOG_TAG]Skipping, output file already exists"
    }
    else {
        [string]$cmd = [string]::Join(' ', $ffArgs)
        Write-Output "[$LOG_TAG]$cmd"
        # TODO environment variable for dry run
        if ($Env:DRY_RUN) {
            Write-Output "[$LOG_TAG]Dry run, but would have run: $cmd"
        }
        else {
            Invoke-Expression $cmd -ErrorVariable fferr
            $retCode = $LASTEXITCODE
            if ($retCode -eq 0) {
                Write-Verbose "[$LOG_TAG]Succeeded ($retCode), deleting input files"
                Remove-Item -LiteralPath $File
                if ($SubFile) {
                    Remove-Item -LiteralPath $SubFile
                }
            }
            else {
                if (Test-Path -LiteralPath $OutFullName) {
                    if ((Get-Item -LiteralPath $OutFullName).Length -eq 0) {
                        # if ffmpeg fails during initialization, it still creates an empty output file
                        Remove-Item -LiteralPath $OutFullName
                        throw "[$LOG_TAG]Conversion failed ($retCode). Bad parameters to ffmpeg? $fferr"
                    }
                    elseif ([Math]::Abs((ffprobe -v error -print_format json -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $OutFullName) - $Probe.format.duration) -gt 1) {
                        # duration of output is significantly different from input
                        throw "[$LOG_TAG]Output file is wrong length ($retCode). You should probably delete the output and retry. $fferr"
                    }
                    else {
                        throw "[$LOG_TAG]Unknown error occurred ($retCode). Please report this. $fferr"
                    }
                }
                else {
                    throw "[$LOG_TAG]No output file produced ($retCode). Odd. $fferr"
                }
            }
        }
    }
}
#endregion

#region main entry point
[System.Threading.Mutex]$mutex = $null
[boolean]$gotMutex = $false
try {
    # wait for available resources (named semaphores are not supported on Linux. this does not preserve queue order)
    [int]$maxConcurrent = [Math]::Max([int]($Config.maxConcurrent), 1)
    [int]$ppid=(Get-Process -Id $PID).Parent.Id
    do {
        [int[]]$cpids = (Get-Process -Name 'pwsh' | Where-Object {$_.Parent.Id -eq $ppid}).Id
        [int]$currentRunning = (Get-Process -Name 'ffmpeg' | Where-Object {$cpids -Contains $_.Id} | Measure-Object).Count
        if ($currentRunning -lt $maxConcurrent) {
            break
        }
        Write-Verbose "[$LOG_TAG]Found $currentRunning/$maxConcurrent already running, trying again later"
        Start-Sleep -Seconds 30
    } while (true)
    Parse-Config
    Examine-InputFile
    Select-Codecs
    $mutex = New-Object System.Threading.Mutex($false, "Global\$($File.Name)")
    $gotMutex = $mutex.WaitOne(60 * 1000) # 1 minute to let other process get started
    if (-not $gotMutex) {
        Write-Debug "[$LOG_TAG]Failed to get mutex. Maybe inotify double-fired?"
    }
    Invoke-Ffmpeg
}
catch {
    if ($Config.PSobject.Properties['logerr'] -and $Config.logerr -eq $true) {
        $errFileName = Join-Path $Matcher.dir "$($File.Name).err.log"
        Write-Error -Message $_ 2>&1 | Tee-Object -LiteralPath $errFileName
    }
    else {
        Write-Error -Message $_
    }
}
finally {
    if ($mutex -ne $null -and $gotMutex) {
        $mutex.ReleaseMutex()
    }
}
Write-Output "[$LOG_TAG]Complete."
#endregion
