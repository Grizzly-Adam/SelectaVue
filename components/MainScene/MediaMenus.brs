' ==================== MediaMenus.brs ====================
' Channel-details dialog only. Audio track and subtitle selection are now
' handled by Roku's own system overlay (the * button) instead of a custom
' dialog — see ChannelBar.brs for the CC on/off toggle and the bar that
' replaced the old OK options menu.

' ---------- Channel details dialog ----------

sub showCurrentChannelInfo()
    channel = m.playingChannel
    if channel = invalid then return

    ' Order: Channel name, Playlist, State, Format, Player size, Audio tracks
    ' (+ codecs/bitrate/subtitles alongside), Channel Number, Video URL (last
    ' -- gets extra wrap room since some sources hand out very long URLs).
    message = "Channel name: " + cleanChannelTitle(channel) + chr(10)

    serverName = currentServerName()
    if serverName <> "" then message = message + "Playlist: " + serverName + chr(10)

    if m.previewVideo <> invalid then
        message = message + "State: " + m.previewVideo.state + chr(10)
    end if

    if channel.url <> invalid then
        message = message + "Format: " + UCase(detectStreamFormat(channel.url)) + chr(10)
    end if

    if m.previewVideo <> invalid then
        ' Player pane size — the actual video-window dimensions currently in
        ' use (fullscreen 1920x1080 vs. the smaller grid preview), not the
        ' source encode's resolution: Roku's Video node doesn't expose the
        ' decoded stream's native resolution through a public field.
        message = message + "Player size: " + m.previewVideo.width.ToStr() + " x " + m.previewVideo.height.ToStr() + chr(10)

        ' videocodec/audiocodec are read-only Video node fields reporting
        ' what's actually being decoded right now — "", "none", or "unknown"
        ' whenever nothing has started decoding yet.
        videoCodec = _describeCodec(m.previewVideo.videocodec)
        if videoCodec <> "" then message = message + "Video codec: " + videoCodec + chr(10)
        audioCodec = _describeCodec(m.previewVideo.audiocodec)
        if audioCodec <> "" then message = message + "Audio codec: " + audioCodec + chr(10)

        ' streamingsegment carries live bitrate info for the segment currently
        ' playing — only present once the stream has actually started.
        segment = m.previewVideo.streamingsegment
        if segment <> invalid and segment.bitrate <> invalid and segment.bitrate > 0 then
            message = message + "Bitrate: " + (segment.bitrate \ 1000).ToStr() + " kbps" + chr(10)
        end if

        ' availableAudioTracks only lists SELECTABLE alternate audio tracks
        ' (e.g. multiple dubs/languages called out in the manifest) — it's
        ' empty for the very common case of a single muxed audio track with
        ' no alternates, even while that track is playing perfectly fine.
        ' Report what's actually true instead of a bare, misleading "0".
        audioTracks = m.previewVideo.availableAudioTracks
        trackCount  = 0
        if audioTracks <> invalid then trackCount = audioTracks.Count()
        if trackCount > 0 then
            message = message + "Audio tracks: " + trackCount.ToStr() + chr(10)
        else if m.previewVideo.state = "playing" or m.previewVideo.state = "buffering" or m.previewVideo.state = "paused" then
            message = message + "Audio tracks: 1 (default, no alternates listed)" + chr(10)
        else
            message = message + "Audio tracks: 0" + chr(10)
        end if
        captionTracks = m.previewVideo.availableCaptionTracks
        if captionTracks <> invalid then message = message + "Subtitles: " + captionTracks.Count().ToStr() + chr(10)
    end if

    channelNum = -1
    if channel.url <> invalid then channelNum = findChannelIndexByUrl(channel.url)
    if channelNum >= 0 and m.flatChannelList <> invalid then
        message = message + "Channel Number: " + (channelNum + 1).ToStr() + " of " + m.flatChannelList.Count().ToStr() + chr(10)
    end if

    ' Video URL goes last and gets extra wrap room (see dialogHeight below) --
    ' some sources hand out very long URLs.
    if channel.url <> invalid then message = message + "Video URL: " + channel.url

    _showThemedMessageDialog("Channel information", message, ["OK"], "onSimpleDialogClosed", 1200, 750, "left")
    resetOptionsDialogTimer()
end sub

' Maps the Video node's raw videocodec/audiocodec enum values to a friendlier
' label. Returns "" for the empty/none/unknown states so callers can just
' skip the line rather than show a confusing "Video codec: unknown".
function _describeCodec(rawCodec as Dynamic) as String
    if rawCodec = invalid then return ""
    codec = LCase(rawCodec)
    if codec = "" or codec = "none" or codec = "unknown" then return ""
    labels = {
        hevc: "HEVC (H.265)"
        hevc_b: "HEVC (H.265, Annex B)"
        mpeg1: "MPEG-1"
        mpeg2: "MPEG-2"
        mpeg4_2: "MPEG-4 Part 2 (H.263)"
        mpeg4_10b: "AVC (H.264)"
        mpeg4_15: "AVC (H.264)"
        vc1: "VC-1"
        wmv: "WMV"
        vp8: "VP8"
        vp9: "VP9"
        aac: "AAC"
        aac_adif: "AAC (ADIF)"
        aac_adts: "AAC (ADTS)"
        aac_latm: "AAC (LATM)"
        ac3: "Dolby Digital (AC3)"
        alac: "Apple Lossless"
        dts: "DTS"
        eac3: "Dolby Digital Plus (E-AC3)"
        flac: "FLAC"
        mp2: "MPEG Audio Layer II"
        mp3: "MPEG Audio Layer III"
        pcm: "PCM"
        vorbis: "Vorbis"
        wma: "WMA"
        wmapro: "WMA Pro"
    }
    if labels[codec] <> invalid then return labels[codec]
    return UCase(rawCodec)   ' unrecognized value — show as-is rather than hide it
end function

sub onSimpleDialogClosed()
    if m.themedMessageDialog.buttonSelected = -1 then return   ' -1 is the reset default, never a real press
    _closeThemedMessageDialog()
    ' Explicitly defocus before reclaiming scene focus, same as
    ' playChannel()/_goFullscreenFromGrid() -- prevents the video node
    ' retaining focus and silently swallowing every key. Log evidence
    ' (build 302) showed themedMessageDialog itself also still held focus
    ' after m.top.setFocus(true) alone, despite Roku's docs saying setFocus
    ' should release the prior holder automatically -- so it needs the same
    ' explicit defocus as previewVideo.
    if m.previewVideo <> invalid then m.previewVideo.setFocus(false)
    m.themedMessageDialog.setFocus(false)
    m.top.setFocus(true)
    print ">>> CHANNELINFO CLOSE: top.hasFocus="; m.top.hasFocus(); " top.isInFocusChain="; m.top.isInFocusChain(); " dialog.hasFocus="; m.themedMessageDialog.hasFocus(); " previewVideo.hasFocus="; m.previewVideo.hasFocus(); " isPlayingVideo="; m.isPlayingVideo; " barVisible="; m.barVisible
end sub
