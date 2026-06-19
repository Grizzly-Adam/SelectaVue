' ==================== VideoPlayback.brs ====================
' Everything related to playing, previewing, and switching channels:
'   - playChannel()         - load + go fullscreen
'   - playPreviewChannel()  - load in the grid preview window
'   - changeChannel()       - up/down navigation in fullscreen
'   - reloadCurrentChannel()
'   - reloadCurrentPlaylist()
'   - Video state observer (checkState)
'   - Audio track menu
'   - Subtitle menu
'   - Channel info details dialog

' ---------- Channel list helpers ----------

sub buildFlatChannelList()
    m.flatChannelList = []
    if m.allChannels = invalid then return

    for i = 0 to m.allChannels.getChildCount() - 1
        section = m.allChannels.getChild(i)
        if section = invalid then continue for

        if section.getChildCount() = 0 then
            m.flatChannelList.Push(section)
        else
            for j = 0 to section.getChildCount() - 1
                channel = section.getChild(j)
                if channel <> invalid then m.flatChannelList.Push(channel)
            end for
        end if
    end for

    print ">>> PLAYLIST: Total channels in flat list: "; m.flatChannelList.Count()
end sub

function getChannelByFocusIndex(focusIndex as Integer) as Object
    return getChannelFromListItem(m.channelList, focusIndex)
end function

function getChannelFromListItem(list as Object, itemIndex as Integer) as Object
    if list = invalid or list.content = invalid then return invalid
    content = list.content
    if content.getChildCount() = 0 then return invalid
    if content.getChild(0) = invalid then return invalid
    return getChannelFromFlatListItem(content, itemIndex)
end function

function getChannelFromFlatListItem(content as Object, itemIndex as Integer) as Object
    if content = invalid or itemIndex < 0 then return invalid

    channelIndex = 0
    for i = 0 to content.getChildCount() - 1
        section = content.getChild(i)
        if section = invalid then continue for

        if section.getChildCount() = 0 then
            if channelIndex = itemIndex then return section
            channelIndex = channelIndex + 1
        else
            sectionCount = section.getChildCount()
            if itemIndex < channelIndex + sectionCount then
                return section.getChild(itemIndex - channelIndex)
            end if
            channelIndex = channelIndex + sectionCount
        end if
    end for

    return invalid
end function

sub findChannelIndexByUrl(url as String)
    if m.flatChannelList = invalid or m.flatChannelList.Count() = 0 then
        m.currentChannelIndex = 0
        return
    end if
    for i = 0 to m.flatChannelList.Count() - 1
        channel = m.flatChannelList[i]
        if channel <> invalid and channel.url = url then
            m.currentChannelIndex = i
            return
        end if
    end for
    m.currentChannelIndex = 0
end sub

' ---------- Channel focus / selection (grid) ----------

sub onChannelFocused()
    if m.isPlayingVideo then return
    if m.channelList = invalid then return
    if m.suppressFocusChange then return

    if m.screensaverOverlay <> invalid and m.screensaverOverlay.visible then
        m.screensaverOverlay.visible = false
        resetGridInactivityTimer()
        return
    end if

    focusedIndex = m.channelList.itemFocused
    print ">>> GRID: Channel focused = "; focusedIndex

    channel = getChannelByFocusIndex(focusedIndex)
    if channel <> invalid then
        m.lastFocusedChannel = focusedIndex
        if focusedIndex <> m.currentChannelIndex then
            hideBufferBar()
            cancelStallTimer()
        end if
        m.currentChannelIndex = focusedIndex
    end if
    resetGridInactivityTimer()
end sub

sub onChannelSelected()
    if m.channelList = invalid then return
    if m.suppressFocusChange then return

    focusedIndex = m.channelList.itemFocused
    channel      = getChannelByFocusIndex(focusedIndex)
    if channel = invalid then return

    if m.previewVideo.content <> invalid and m.previewVideo.content.url = channel.url then
        print ">>> GRID: Double OK - going fullscreen"
        m.suppressNextVideoOptionsMenu = true
        startOverlayOkSuppressionTimer()
        playChannel(channel)
    else
        print ">>> GRID: Single OK - loading preview"
        m.currentChannelIndex = focusedIndex
        playPreviewChannel(focusedIndex)
    end if
end sub

sub onOverlayChannelSelected()
    m.suppressNextVideoOptionsMenu = true
    startOverlayOkSuppressionTimer()
    hideOverlay()
    selectChannelFromList(m.channelOverlayList)
end sub

sub onOverlayItemFocused()
    if m.screensaverOverlay <> invalid and m.screensaverOverlay.visible then
        m.screensaverOverlay.visible = false
        return
    end if
    if m.overlayVisible then
        m.currentChannelIndex = m.channelOverlayList.itemFocused
        resetOverlayInactivityTimer()
    end if
end sub

sub selectChannelFromList(list as Object)
    if list.content = invalid or list.content.getChildCount() = 0 then return
    if list.content.getChild(0) = invalid then return

    content = getChannelFromListItem(list, list.itemSelected)
    if content = invalid then return

    print ">>> SELECTCHANNEL: Selecting channel: "; content.title
    findChannelIndexByUrl(content.url)
    playChannel(content)
end sub

' ---------- Preview ----------

sub playPreviewChannel(channelIndex as Integer)
    if m.previewVideo = invalid then return
    if m.flatChannelList = invalid or m.flatChannelList.Count() = 0 then return

    channel = getChannelByFocusIndex(channelIndex)
    if channel = invalid and channelIndex >= 0 and channelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[channelIndex]
    end if
    if channel = invalid or channel.url = invalid then return

    ' Skip reload if this channel is already loaded
    if m.previewVideo.content <> invalid and m.previewVideo.content.url = channel.url then return

    ' Reset per-channel state
    m.bitrateRetryDone      = false
    m.stallRetryCount       = 0
    m.lastBufferPct         = -1
    m.lastErrorMsg          = ""
    m.lastErrorChannelIndex = -1
    cancelStallTimer()
    hidePreviewError()

    print ">>> PREVIEW: Starting preview playback: "; channel.title

    if m.previewChannelNameLabel     <> invalid then m.previewChannelNameLabel.text     = channel.title
    if m.previewChannelNameContainer <> invalid then m.previewChannelNameContainer.visible = true

    previewContent = CreateObject("roSGNode", "ContentNode")
    previewContent.url                     = channel.url
    previewContent.title                   = channel.title
    previewContent.streamFormat            = "hls"
    previewContent.HttpSendClientCertificates = true
    previewContent.HttpCertificatesFile    = "common:/certs/ca-bundle.crt"

    m.previewVideo.translation = [1380, 145]
    m.previewVideo.width       = 444
    m.previewVideo.height      = 250
    m.previewVideo.trickplaybarvisibilityauto = true

    m.previewVideo.content = previewContent
    m.previewVideo.control = "play"
    m.previewVideo.mute    = m.previewMuted
end sub

sub stopPreviewVideo()
    if m.previewVideo <> invalid then m.previewVideo.control = "stop"
end sub

' ---------- Fullscreen playback ----------

sub playChannel(content as Object)
    hideChannelInfo()
    if m.fullscreenFailContainer <> invalid then m.fullscreenFailContainer.visible = false

    content.streamFormat = "hls, mp4, mkv, mp3, avi, m4v, ts, mpeg-4, flv, vob, ogg, ogv, webm, mov, wmv, asf, amv, mpg, mp2, mpeg, mpe, mpv, mpeg2"

    if m.previewVideo.content = invalid or m.previewVideo.content.url <> content.url then
        hideBufferBar()
        cancelStallTimer()
        m.lastBufferPct = -1
        print ">>> PLAY: Loading channel: "; content.title
        content.HttpSendClientCertificates = true
        content.HttpCertificatesFile       = "common:/certs/ca-bundle.crt"
        content.SwitchingStrategy          = "full-adaptation"
        m.previewVideo.EnableCookies()
        m.previewVideo.SetCertificatesFile("common:/certs/ca-bundle.crt")
        m.previewVideo.InitClientCertificates()
        m.previewVideo.maxBandwidth = 0
        m.previewVideo.content      = content
        m.previewVideo.control      = "play"
        m.bitrateRetryDone          = false
        m.stallRetryCount           = 0
        m.lastBufferPct             = -1
        cancelStallTimer()
    else
        print ">>> PLAY: Already playing, expanding to fullscreen"
    end if

    m.previewVideo.mute = m.previewMuted

    m.top.backgroundURI   = ""
    m.top.backgroundColor = "0x024c48FF"
    m.previewVideo.trickplaybarvisibilityauto = false
    m.previewVideo.visible   = true
    m.previewVideo.translation = [0, 0]
    m.previewVideo.width     = 1920
    m.previewVideo.height    = 1080

    m.channelList.visible = false
    m.sidePanel.visible   = false
    hideGridOverlays()

    if m.gridInactivityTimer <> invalid then
        m.gridInactivityTimer.control = "stop"
        m.gridInactivityTimer.unobserveField("fire")
        m.gridInactivityTimer = invalid
    end if
    resetFullscreenInactivityTimer()

    ' Reposition buffer bar for fullscreen if it was visible
    if m.bufferVisible then
        m.bufferContainer.translation = [560, 980]
        m.bufferContainer.width       = 800
        m.bufferTrack.width           = 794
        m.bufferLabel.width           = 800
    end if

    hideOverlay()
    m.isPlayingVideo = true

    channel = m.flatChannelList[m.currentChannelIndex]
    if channel <> invalid then showChannelInfo(channel)

    if m.lastErrorMsg <> "" and m.lastErrorChannelIndex = m.currentChannelIndex then
        showFullscreenError(m.lastErrorMsg)
    end if

    ' Hand focus to the Scene so onKeyEvent fires
    m.previewVideo.setFocus(false)
    m.channelList.setFocus(false)
    m.playlistList.setFocus(false)
    m.channelOverlayList.setFocus(false)
    m.top.setFocus(true)

    saveLastState()
    print ">>> PLAY: Video fullscreen, scene focused"
end sub

' ---------- Channel navigation in fullscreen ----------

sub changeChannel(direction as Integer)
    hideChannelInfo()
    if m.flatChannelList.Count() = 0 then return

    m.currentChannelIndex = m.currentChannelIndex + direction

    if m.currentChannelIndex < 0 then
        m.currentChannelIndex = m.flatChannelList.Count() - 1
    else if m.currentChannelIndex >= m.flatChannelList.Count() then
        m.currentChannelIndex = 0
    end if

    channel = m.flatChannelList[m.currentChannelIndex]
    if channel <> invalid then
        showChannelInfo(channel)
        playChannel(channel)
    end if
end sub

' ---------- Reload ----------

sub reloadCurrentChannel()
    print ">>> RELOAD: Reloading current channel"
    if m.flatChannelList = invalid or m.currentChannelIndex < 0 then return

    channel = m.flatChannelList[m.currentChannelIndex]
    if channel = invalid then return

    m.previewVideo.control = "stop"

    content = CreateObject("roSGNode", "ContentNode")
    content.title                     = channel.title
    content.url                       = channel.url
    content.streamFormat              = "hls"
    content.HttpSendClientCertificates = true
    content.HttpCertificatesFile      = "common:/certs/ca-bundle.crt"
    content.SwitchingStrategy         = "full-adaptation"

    m.previewVideo.content = invalid
    m.previewVideo.EnableCookies()
    m.previewVideo.SetCertificatesFile("common:/certs/ca-bundle.crt")
    m.previewVideo.InitClientCertificates()
    m.previewVideo.maxBandwidth = 0
    m.previewVideo.content      = content
    m.previewVideo.control      = "play"
    m.top.setFocus(true)
    m.bitrateRetryDone  = false
    m.stallRetryCount   = 0
    m.lastBufferPct     = -1
    cancelStallTimer()
    print ">>> RELOAD: Channel reloaded successfully"
end sub

sub reloadCurrentPlaylist()
    if m.playlists = invalid or m.playlists.Count() = 0 then return
    idx = m.playlistList.itemFocused
    if idx >= 0 and idx < m.playlists.Count() then loadPlaylist(m.playlists[idx].url)
end sub

' ---------- Video state observer ----------

sub checkState()
    state = m.previewVideo.state
    if state = "playing" then
        hideBufferBar()
        cancelStallTimer()
        m.bitrateRetryDone = false
        m.stallRetryCount  = 0
        if m.fullscreenFailContainer <> invalid then m.fullscreenFailContainer.visible = false
    else if state = "error" then
        hideBufferBar()
        cancelStallTimer()
        errorMsg = m.previewVideo.errorMsg
        ' Auto-retry once for bitrate errors
        if not m.bitrateRetryDone and LCase(errorMsg).InStr("bitrate") >= 0 then
            print ">>> BITRATE RETRY: No valid bitrates, retrying with relaxed constraints"
            m.bitrateRetryDone = true
            retryContent = m.previewVideo.content
            if retryContent <> invalid then
                retryContent.SwitchingStrategy = "no-adaptation"
                m.previewVideo.maxBandwidth    = 0
                m.previewVideo.content         = invalid
                m.previewVideo.content         = retryContent
                m.previewVideo.control         = "play"
                return
            end if
        end if
        showChannelError(errorMsg)
    end if
end sub

' ---------- Video options menu ----------

sub showVideoOptionsMenu()
    dialog         = CreateObject("roSGNode", "Dialog")
    dialog.title   = "Playback options"
    dialog.buttons = ["Audio Settings", "Subtitles", "Channel Details", "Close"]
    m.top.dialog   = dialog
    m.top.dialog.observeField("buttonSelected", "onVideoOptionSelected")
    resetOptionsDialogTimer()
end sub

sub onVideoOptionSelected()
    buttonIdx = m.top.dialog.buttonSelected
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true

    if buttonIdx = 0 then
        showAudioTracksMenu()
    else if buttonIdx = 1 then
        showSubtitlesMenu()
    else if buttonIdx = 2 then
        showCurrentChannelInfo()
    end if

    m.top.setFocus(true)
end sub

' ---------- Audio tracks ----------

sub showAudioTracksMenu()
    if m.previewVideo = invalid then return

    audioTracks = m.previewVideo.audioTracks
    if audioTracks = invalid or audioTracks.Count() = 0 then
        audioTracks = m.previewVideo.availableAudioTracks
    end if

    if audioTracks = invalid or audioTracks.Count() = 0 then
        message  = "No alternate audio tracks detected." + chr(10) + chr(10)
        message  = message + "Audio format: " + toStr(m.previewVideo.audioFormat) + chr(10)
        message  = message + "Video status: " + m.previewVideo.state
        dialog         = CreateObject("roSGNode", "Dialog")
        dialog.title   = "Audio tracks"
        dialog.message = message
        dialog.buttons = ["OK"]
        m.top.dialog   = dialog
        m.top.dialog.observeField("buttonSelected", "onSimpleDialogClosed")
        resetOptionsDialogTimer()
        return
    end if

    m.audioTracksList   = []
    buttons             = []
    currentTrackIndex   = -1
    if m.previewVideo.currentAudioTrack <> invalid then
        currentTrackIndex = m.previewVideo.currentAudioTrack
    end if

    for i = 0 to audioTracks.Count() - 1
        track     = audioTracks[i]
        trackName = ""
        language  = ""

        if type(track) = "roAssociativeArray" then
            if track.Language <> invalid and track.Language <> "" then
                language = track.Language
            else if track.language <> invalid and track.language <> "" then
                language = track.language
            end if
            trackName = iif(language <> "", getLanguageName(language), "Track " + (i + 1).ToStr())
            if track.Name <> invalid and track.Name <> "" then
                trackName = trackName + " (" + track.Name + ")"
            else if track.name <> invalid and track.name <> "" then
                trackName = trackName + " (" + track.name + ")"
            end if
        else if type(track) = "String" or type(track) = "roString" then
            trackName = getLanguageName(track)
        else
            trackName = "Track " + (i + 1).ToStr()
        end if

        if i = currentTrackIndex then trackName = "* " + trackName

        buttons.Push(trackName)
        m.audioTracksList.Push(i)
    end for

    buttons.Push("Cancel")

    dialog         = CreateObject("roSGNode", "Dialog")
    dialog.title   = "Select audio track (" + audioTracks.Count().ToStr() + " available)"
    dialog.buttons = buttons
    m.top.dialog   = dialog
    m.top.dialog.observeField("buttonSelected", "onAudioTrackSelected")
    resetOptionsDialogTimer()
end sub

sub onAudioTrackSelected()
    buttonIdx = m.top.dialog.buttonSelected
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true

    if m.audioTracksList <> invalid and buttonIdx < m.audioTracksList.Count() then
        trackIndex = m.audioTracksList[buttonIdx]
        m.previewVideo.audioTrack       = trackIndex
        m.previewVideo.selectAudioTrack = trackIndex
        showChannelInfoMessage("Audio: Track " + (trackIndex + 1).ToStr() + " selected")
    end if

    m.top.setFocus(true)
end sub

' ---------- Subtitles ----------

sub showSubtitlesMenu()
    if m.previewVideo = invalid then return

    subtitleTracks     = m.previewVideo.availableCaptionTracks
    buttons            = ["Subtitles off"]
    m.subtitleTracksList = [-1]

    if subtitleTracks <> invalid and subtitleTracks.Count() > 0 then
        for i = 0 to subtitleTracks.Count() - 1
            track     = subtitleTracks[i]
            trackName = ""
            if track.Language <> invalid and track.Language <> "" then
                trackName = getLanguageName(track.Language)
            else
                trackName = "Subtitle " + (i + 1).ToStr()
            end if
            if track.Description <> invalid and track.Description <> "" then
                trackName = trackName + " (" + track.Description + ")"
            end if
            buttons.Push(trackName)
            m.subtitleTracksList.Push(i)
        end for
    end if

    buttons.Push("Cancel")

    dialog         = CreateObject("roSGNode", "Dialog")
    dialog.title   = "Subtitles"
    if subtitleTracks = invalid or subtitleTracks.Count() = 0 then
        dialog.message = "No subtitles available for this channel."
    end if
    dialog.buttons = buttons
    m.top.dialog   = dialog
    m.top.dialog.observeField("buttonSelected", "onSubtitleTrackSelected")
    resetOptionsDialogTimer()
end sub

sub onSubtitleTrackSelected()
    buttonIdx = m.top.dialog.buttonSelected
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true

    if m.subtitleTracksList <> invalid and buttonIdx < m.subtitleTracksList.Count() then
        trackIndex = m.subtitleTracksList[buttonIdx]
        if trackIndex = -1 then
            m.previewVideo.suppressCaptions = true
            showChannelInfoMessage("Subtitles off")
        else
            m.previewVideo.suppressCaptions  = false
            m.previewVideo.selectCaptionTrack = trackIndex
            showChannelInfoMessage("Subtitles on")
        end if
    end if

    m.top.setFocus(true)
end sub

' ---------- Channel detail dialog ----------

sub showCurrentChannelInfo()
    if m.flatChannelList = invalid or m.flatChannelList.Count() = 0 then return
    if m.currentChannelIndex < 0 or m.currentChannelIndex >= m.flatChannelList.Count() then return

    channel = m.flatChannelList[m.currentChannelIndex]
    if channel = invalid then return

    message  = "Channel: "  + channel.title + chr(10)
    message  = message + "Position: " + (m.currentChannelIndex + 1).ToStr() + " of " + m.flatChannelList.Count().ToStr() + chr(10)

    if m.previewVideo <> invalid then
        message = message + "State: " + m.previewVideo.state + chr(10)
        audioTracks = m.previewVideo.availableAudioTracks
        if audioTracks <> invalid then message = message + "Audio tracks: " + audioTracks.Count().ToStr() + chr(10)
        captionTracks = m.previewVideo.availableCaptionTracks
        if captionTracks <> invalid then message = message + "Subtitles: " + captionTracks.Count().ToStr()
    end if

    dialog         = CreateObject("roSGNode", "Dialog")
    dialog.title   = "Channel information"
    dialog.message = message
    dialog.buttons = ["OK"]
    m.top.dialog   = dialog
    m.top.dialog.observeField("buttonSelected", "onSimpleDialogClosed")
    resetOptionsDialogTimer()
end sub

sub onSimpleDialogClosed()
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true
    m.top.setFocus(true)
end sub
