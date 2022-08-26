#Requires -Version 7

<#
.PARAMETER Notif
CSV notification from inotifywait, in format directory,event[,event...],filename
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

}
#endregion

#region parse config, find output format
$ConfigFile = '/config/autoconv.json'
$Config = Get-Content $ConfigFile | ConvertFrom-Json
$Matcher = $null
foreach ($m in $Config.matchers) {
    if ($WatchedDir.StartsWith($m.dir)) {
        $Matcher = $m
        break
    }
}
# TODO fill in default values for optional matcher params
if ((-not ($Matcher.recurse)) -and ($File.Directory.ToString() + [IO.Path]::DirectorySeparatorChar) -ne $WatchedDir) {
    # file is in child dir, and recursion is disabled
    $Matcher = $null
}
if ($Matcher -eq $null) {
    Write-Warning "[$LOG_TAG]Could not find a directory matcher for $($FileName)"
    exit
}
Write-Output "[$LOG_TAG]Using matcher dir=$($Matcher.dir)"
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
    $words = $OrigName.Split([char[]]@('.', ' '))
    [string]$year = $null
    [string]$season = $null
    [string]$episode = $null
    [int]$seasEpIdx = $null
    $isTv = $false
    foreach ($word in $words) {
        if ($word -iMatch 's([0-9]{2,3})e([0-9]{2,3})') {
            $isTv = $true
            $season = $Matches[1]
            $episode = $Matches[2]
            $seasEpIdx = $words.IndexOf($word)
        }
        elseif ($word -Match '(?:19|20)[0-9]{2}') {
            $year = $word
        }
    }
    Write-Debug "[$LOG_TAG]isTv:$isTv year:$year season:$season episode:$episode seasEpIdx:$seasEpIdx"

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
        return (Join-Path $name "Season $season" "$name - s${season}e$episode")
    }
    elseif ($year -ne $null -and -not $isTv) {
        return (Join-Path "$name (${year})" "$name (${year})")
    }
    else {
        throw "[$LOG_TAG]Indecipherable movie or TV name=$OrigName"
    }
}
function Get-AudioCodecRank {
    param([Parameter(Mandatory,Position=0)]$Stream)
    switch ($Stream.channels) {
        6 {
            switch ($Stream.codec_name) {
                'aac' {
                    switch ($Stream.profile) {
                        'LC' { return 699 }
                        'HE-AAC' { return 698 }
                        default {
                            throw "[$LOG_TAG]Unkown 6ch AAC profile='$($Stream.profile)' on stream index=$($Stream.index)"
                        }
                    }
                }
                'dts' {
                    switch ($Stream.profile) {
                        'DTS-HD MA' { return 690 } # great but TV won't play
                        default {
                            throw "[$LOG_TAG]Uninvestigated 6ch DTS profile='$($Stream.profile)' on stream index=$($Stream.index)"
                        }
                    }
                }
                'eac3' { return 660 }
                'ac3' { return 650 }
                default {
                    throw "[$LOG_TAG]Unknown 6ch codec='$($Stream.codec_name)' on stream index=$($Stream.index)"
                }
            }
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
            throw "[$LOG_TAG]Not yet implemented number of channels=$($Stream.channels) on stream index=$($Stream.index)"
        }
    }
}
#endregion

$vSrc = @{} # stream obj, int idx
$aSrc = @{}
$sSrc = @{}
#region probe input, decide what to convert
$Probe = ffprobe -print_format json -show_streams $FileName 2>$null | ConvertFrom-Json
$SubFile = Join-Path $File.Directory ($File.BaseName+'.srt') # TODO could be better, .srt is not the only format
if (-not (Test-Path -PathType Leaf -LiteralPath $SubFile)) {
    $SubFile = $null
}
if ($SubFile) {
    $subProbe = ffprobe -print_format json -show_streams $SubFile 2>$null | ConvertFrom-Json
    $sSrc.stream = $subProbe.streams[0]
    $sSrc.idx = -1
}
foreach ($s in $Probe.streams) {
    Write-Debug "[$LOG_TAG]Processing stream=$s"
    switch ($s.codec_type) {
        'video' {
            if ($vSrc.stream -ne $null) {
                throw "[$LOG_TAG]Second video stream found at index=$($s.index)"
            }
            # TODO ranking and preference
            $vSrc.stream = $s
            $vSrc.idx = $s.index
            Break
        }
        'audio' {
            if ($aSrc.stream -ne $null -and $s.tags.PSobject.Properties['language'] -and -not ($s.tags.language -iLike '*eng*')) {
                Write-Debug "[$LOG_TAG]Skipping audio track: already have one and new is not English"
                Break
            }
            if ($aSrc.stream -ne $null -and (Get-AudioCodecRank $aSrc.stream) -gt (Get-AudioCodecRank $s)) {
                Write-Debug "[$LOG_TAG]Skipping audio track: already have one and new one is worse"
                # TODO check language='eng'
                Break
            }
            Write-Debug "[$LOG_TAG]Taking audio track"
            $aSrc.stream = $s
            $aSrc.idx = $s.index
            Break
        }
        'subtitle' {
            if ($SubFile) {
                # explicitly given, ignore any in input file
                Break
            }
            if ($sSrc.stream -ne $null -and $s.tags.PSobject.Properties['language'] -and -not ($s.tags.language -iLike '*eng*')) {
                Write-Debug "[$LOG_TAG]Skipping sub track: already have one and new is not English"
                Break
            }
            if ($sSrc.stream -ne $null -and $sSrc.stream.tags.language -iLike '*eng*' -and $s.tags.PSobject.Properties['title'] -and $s.tags.title -iLike '*SDH*') {
                Write-Debug "[$LOG_TAG]Skipping sub track: already have an English and new is SDH"
                Break
            }
            Write-Debug "[$LOG_TAG]Taking sub track"
            $sSrc.stream = $s
            $sSrc.idx = $s.index
            Break
        }
        default {
            Write-Warning "[$LOG_TAG]Unknown codec type='$($s.codec_type)' name='$($s.codec_name)'"
            Break
        }
    }
}

Write-Verbose "[$LOG_TAG]Chose vcodec='$($vSrc.stream.codec_name)'@$($vSrc.idx) acodec='$($aSrc.stream.codec_name)'$($aSrc.stream.channels)ch@$($aSrc.idx) scodec='$(${sSrc.stream}.codec_name)'@$($sSrc.idx)"

# figure out what needs to be done (consider codecs; video: resolution, dynamic range, color, and field_order)
$vDestCodec = $Matcher.result.vcodecs[0]
if ($Matcher.result.vcodecs -Contains $vSrc.stream.codec_name -and $Matcher.result.allowcopy) {
    $vDestCodec = 'copy'
}
if ($Matcher.result.vcodecs -Contains 'hevc' -and $vDestCodec -ne 'hevc' -and (($vSrc.stream.width -gt 1920 -or $vSrc.stream.height -gt 1080) -or ($vSrc.stream.profile -iLike '*10' -or $vSrc.stream.pix_fmt -iMatch '.*10[bl]e') -or ($vSrc.stream.color_space -eq 'bt2020nc' -or $vSrc.stream.color_transfer -eq 'smpte2084' -or $vSrc.stream.color_primaries -eq 'bt2020'))) {
    # compatibility with some TVs
    $vDestCodec = 'libx265'
    Write-Debug "[$LOG_TAG]Video stream will be $vDestCodec : >FHD or 10-bit color or HDR"
}
$aDestCodec = $null
if ($aSrc.stream.channels -le 2) {
    $aDestCodec = $Matcher.result.acodecs[0]
    if ($Matcher.result.acodecs -Contains $aSrc.stream.codec_name -and $Matcher.result.allowcopy) {
        $aDestCodec = 'copy'
    }
}
else {
    $aDestCodec = $Matcher.result.acodecs6[0]
    if ($Matcher.result.acodecs6 -Contains $aSrc.stream.codec_name -and $Matcher.result.allowcopy) {
        $aDestCodec = 'copy'
    }
}
$sDestCodec = $Matcher.result.scodecs[0]
if ($Matcher.result.scodecs -Contains $sSrc.stream.codec_name -and $Matcher.result.allowcopy) {
    $sDestCodec = 'copy'
}

Write-Verbose "[$LOG_TAG]Producing vcodec='$($vDestCodec)' acodec='$($aDestCodec)' scodec='$($sDestCodec)'"
#endregion

#region convert
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
$ffArgs += @('-c:v', $vDestCodec, '-crf', '22', '-c:a', $aDestCodec)
if ($vSrc.stream.height -gt $Matcher.result.maxheight) {
    # could do this with force_original_aspect_ratio=decrease:force_divisible_by=2 but that's quirky
    $ffArgs += @('-vf', "scale=-2:$($Matcher.result.maxheight)")
}
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
    Invoke-Expression $cmd
    if ($?) {
        Remove-Item $File
    }
}
Write-Output "[$LOG_TAG]Complete."
#endregion
