' ==================== ChannelNav.brs ====================
' Channel navigation (up/down, replay/previous), reload, launch-fullscreen,
'  and the video state observer (checkState).

' ---------- Channel navigation in fullscreen ----------

sub changeChannel(direction as Integer)
    hideChannelBar()
    if m.flatChannelList = invalid or m.flatChannelList.Count() = 0 then return
    m.currentChannelIndex = m.currentChannelIndex + direction
    if m.currentChannelIndex < 0 then
        m.currentChannelIndex = m.flatChannelList.Count() - 1
    else if m.currentChannelIndex >= m.flatChannelList.Count() then
        m.currentChannelIndex = 0
    end if
    channel = m.flatChannelList[m.currentChannelIndex]
    if channel <> invalid then
        playChannel(channel)
    end if
end sub

' Jump to the previously watched channel
sub jumpToPreviousChannel()
    if m.previousChannelIndex < 0 then return
    if m.flatChannelList = invalid or m.previousChannelIndex >= m.flatChannelList.Count() then return
    if m.previousChannelIndex = m.currentChannelIndex then return   ' already on previous channel
    channel = m.flatChannelList[m.previousChannelIndex]
    if channel = invalid then return
    m.currentChannelIndex = m.previousChannelIndex
    if m.isPlayingVideo then
        playChannel(channel)
    else
        m.channelList.jumpToItem = m.previousChannelIndex
        playPreviewChannel(m.previousChannelIndex)
    end if
end sub

' ---------- Reload ----------

' ---------- Launch fullscreen on startup ----------
' Called once at first playlist load to skip the grid and go straight to fullscreen.
sub _launchFullscreen(channelIndex as Integer)
    if m.flatChannelList = invalid or channelIndex < 0 or channelIndex >= m.flatChannelList.Count() then return
    m.currentChannelIndex = channelIndex
    if m.channelList <> invalid then m.channelList.jumpToItem = channelIndex
    channel = m.flatChannelList[channelIndex]
    if channel <> invalid then playChannel(channel)
end sub

sub reloadCurrentChannel()
    print ">>> RELOAD: Reloading current channel"
    if m.flatChannelList = invalid or m.currentChannelIndex < 0 then return
    channel = m.flatChannelList[m.currentChannelIndex]
    if channel = invalid then return

    stopPreviewVideo()
    _resetRetryState()
    m.loadingChannelIndex = m.currentChannelIndex

    content = _makeContentNode(channel.url, channel.title, channel)
    m.pendingHeaders = _resolveHeaders(channel)
    _applyContentAndPlay(content)
    m.top.setFocus(true)
    print ">>> RELOAD: Done"
end sub

sub reloadCurrentPlaylist()
    if m.playlists = invalid or m.playlists.Count() = 0 then return
    rawIdx = m.playlistList.itemFocused
    if rawIdx = 0 then return   ' Favorites entry — nothing to reload
    idx = rawIdx - 1
    if idx >= 0 and idx < m.playlists.Count() then
        m.currentPlaylist = idx
        loadPlaylist(m.playlists[idx].url)
    end if
end sub

' ---------- Video state observer ----------

sub checkState()
    state = m.previewVideo.state
    if state = "playing" then
        hideBufferBar()
        cancelStallTimer()
        cancelErrorDelayTimer()

        ' Update channel tracking
        m.playingPreviewIndex    = m.loadingChannelIndex
        m.streamWasPlaying       = true
        m.lastWorkingContent     = m.previewVideo.content

        ' Notify settings cache
        if m.previewVideo.content <> invalid then
            onChannelPlayingSuccessfully(m.previewVideo.content.url, m.previewVideo.content)
        end if

        ' Clear retry state
        m.retryCount             = 0
        m.manifestPatchAttempted = false
        m.isNimbleStream         = false
        m.cacheWasAttempted      = false
        m.bandwidthProbeIndex    = 0
        m.softStepCount          = 0
        m.slowBufferStartTime    = invalid

        ' If we were in outage/network loop, clear it
        if m.reconnectState = "outage" or m.reconnectState = "network" then
            m.reconnectState = "idle"
            cancelStreamRetryTimer()
            cancelNetworkPollTimer()
            cancelCountdownTickTimer()
            if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = false
            hideReconnectingOverlay()
        end if

        ' Always hide the retry status overlay on successful playback
        hideReconnectingOverlay()
        startSlowBufferRecoveryTimer()

        ' Captions are local to each piece of content — the CC button only
        ' toggles the video node's live state, so a channel change (new
        ' content assigned in _applyContentAndPlay) silently drops it even
        ' though the button/icon still shows "on". Re-apply here so the two
        ' stay in sync.
        if m.isPlayingVideo and m.ccEnabled then _reapplyCaptionsIfEnabled()

    else if state = "error" then
        hideBufferBar()
        cancelStallTimer()
        m.savedErrorMsg = m.previewVideo.errorMsg
        m.savedErrorStr = m.previewVideo.errorStr
        print ">>> STATE ERROR: "; m.savedErrorMsg
        print ">>> STATE ERROR errorCode="; m.previewVideo.errorCode; " errorStr="; m.previewVideo.errorStr
        print ">>> STATE ERROR FULL errorStr=["; m.previewVideo.errorStr; "]"
        if m.previewVideo.content <> invalid then
            print ">>> STATE ERROR url="; m.previewVideo.content.url
            print ">>> STATE ERROR streamFormat="; m.previewVideo.content.streamFormat
            print ">>> STATE ERROR live="; m.previewVideo.content.live
        end if
        ' Dump all current video node headers for debugging
        hdrs = m.previewVideo.httpHeaders
        if hdrs <> invalid then
            print ">>> STATE ERROR video.HttpHeaders="; hdrs
        end if
        ' Log buffer status at time of error
        bs = m.previewVideo.bufferingStatus
        if bs <> invalid then
            print ">>> STATE ERROR bufferPct="; bs.percentage; " bufferRate="; bs.isUnderrun
        end if
        startErrorDelayTimer()
    end if
end sub
