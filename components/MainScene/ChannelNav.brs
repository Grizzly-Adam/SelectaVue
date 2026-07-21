' ==================== ChannelNav.brs ====================
' Channel navigation (up/down, replay/previous), reload, launch-fullscreen,
'  and the video state observer (checkState).

' ---------- Channel navigation in fullscreen ----------

sub changeChannel(direction as Integer)
    print ">>> NAV: changeChannel called, direction="; direction; " from index="; m.currentChannelIndex
    hideChannelBar()
    if m.flatChannelList = invalid or m.flatChannelList.Count() = 0 then return

    ' Dwell timer for previousChannelIndex:
    ' Capture the departure point only on the FIRST press of a surf session
    ' (i.e. when no timer is already running). Subsequent rapid presses just
    ' restart the timer without changing the capture — so no matter how many
    ' channels the user skips through, "previous" always means the channel
    ' they left when they STARTED surfing, not something in the middle.
    if m.surfDwellTimer = invalid then
        ' Use playingPreviewIndex (last confirmed-playing channel) as the
        ' departure point — not loadingChannelIndex which may be mid-load.
        m.surfStartChannelIndex = m.playingPreviewIndex
    end if
    _startNamedTimer("surfDwellTimer", 2.0, false, "onSurfDwellTimerFired")

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

' Called 2 seconds after the last channel-change press.
' Commits the captured departure channel as previousChannelIndex.
sub onSurfDwellTimerFired()
    m.surfDwellTimer = invalid
    if m.surfStartChannelIndex >= 0 then
        m.previousChannelIndex = m.surfStartChannelIndex
        print ">>> NAV: Dwell committed previousChannelIndex="; m.surfStartChannelIndex
        m.surfStartChannelIndex = -1
    end if
end sub

' Jump to the previously watched channel. Swaps current/previous so that
' a second press toggles back — without this, previousChannelIndex was
' left pointing at the channel we just jumped TO, so it equaled
' currentChannelIndex and every subsequent press silently no-opped on
' the "already on previous channel" guard below until the user surfed
' (changeChannel's dwell-commit is what actually re-populates it).
'
' If there's no surf-based previousChannelIndex yet (e.g. you just switched
' playlists and haven't surfed within this one), falls back to the last
' channel watched on THIS SPECIFIC playlist (see StateManager.brs) and
' actually plays it — unlike the grid's version of this same fallback
' (GridInput.brs), which only moves focus/selection without tuning, fullscreen
' has no "browse without committing" mode, so replay here always tunes.
' A second press (m.replayFallbackActive), still without a real channel
' change, toggles back to whatever's actually playing (m.playingPreviewIndex).
sub jumpToPreviousChannel()
    print ">>> NAV: jumpToPreviousChannel called, previousChannelIndex="; m.previousChannelIndex; " currentChannelIndex="; m.currentChannelIndex
    if m.flatChannelList = invalid then return

    if m.previousChannelIndex >= 0 and m.previousChannelIndex < m.flatChannelList.Count() and m.previousChannelIndex <> m.currentChannelIndex then
        channel = m.flatChannelList[m.previousChannelIndex]
        if channel = invalid then return
        departingIndex          = m.currentChannelIndex
        m.currentChannelIndex   = m.previousChannelIndex
        m.previousChannelIndex  = departingIndex
        m.replayFallbackActive  = false
        _jumpToChannelIndex(m.currentChannelIndex, channel)
    else if m.replayFallbackActive then
        ' Second press since switching playlists, still without an actual
        ' channel change -- toggle back to whatever's really playing.
        if m.playingPreviewIndex >= 0 and m.playingPreviewIndex < m.flatChannelList.Count() then
            channel = m.flatChannelList[m.playingPreviewIndex]
            if channel <> invalid then
                m.currentChannelIndex = m.playingPreviewIndex
                _jumpToChannelIndex(m.currentChannelIndex, channel)
            end if
        end if
        m.replayFallbackActive = false
    else
        ' No surf-based previous channel yet -- fall back to the last
        ' channel watched on THIS SPECIFIC playlist. If that turns out to BE
        ' what's already playing, there's nothing to jump to/toggle.
        lastUrl = lastWatchedUrlForCurrentPlaylist()
        if lastUrl <> "" then
            idx = findChannelIndexByUrl(lastUrl)
            if idx >= 0 and idx <> m.playingPreviewIndex then
                channel = m.flatChannelList[idx]
                if channel <> invalid then
                    m.currentChannelIndex  = idx
                    m.replayFallbackActive = true
                    _jumpToChannelIndex(idx, channel)
                end if
            end if
        end if
    end if
end sub

' Shared by jumpToPreviousChannel()'s branches above: plays the channel in
' fullscreen, or updates grid focus/preview if called while not fullscreen.
sub _jumpToChannelIndex(index as Integer, channel as Object)
    if m.isPlayingVideo then
        playChannel(channel)
    else
        if m.channelList <> invalid then m.channelList.jumpToItem = index
        playPreviewChannel(index)
    end if
end sub

' ---------- Reload ----------

' ---------- Launch fullscreen on startup ----------
' Called once at first playlist load to skip the grid and go straight to fullscreen.
sub _launchFullscreen(channelIndex as Integer)
    print ">>> NAV: _launchFullscreen called, channelIndex="; channelIndex; " initialLaunch="; m.initialLaunch; " isPlayingVideo="; m.isPlayingVideo
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
    _resetRetryCounters()   ' reset ladder state but keep overlay visible for RETRY flow
    m.loadingChannelIndex = m.currentChannelIndex
    m.channelLoadTimer = CreateObject("roTimespan")

    ' Check cache — proxy channels can restart immediately without a doomed URL attempt
    cached = lookupCachedSettings(channel.url)
    if cached <> invalid and cached.useProxy = true then
        print ">>> RELOAD: Cache says useProxy=true — starting proxy immediately"
        m.cacheWasAttempted    = true
        m.manifestPatchAttempted = true
        m.pendingHeaders       = _resolveHeaders(channel)
        _startLocalProxy(channel.url, _makeContentNode(channel.url, channel.title, channel))
    else
        content = _makeContentNode(channel.url, channel.title, channel)
        m.pendingHeaders = _resolveHeaders(channel)
        _applyContentAndPlay(content)
    end if
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
        ' Matches onPlaylistSelected() in PlaylistManager.brs -- pendingChannelUrl
        ' should only ever be non-empty once, right after launch, and gets
        ' consumed by the very first SetContent() before any reload could
        ' happen. Clearing it here too is defensive: if that consumption
        ' timing ever changes, this stays consistent with its sibling
        ' instead of silently reintroducing a stale-restore path here only.
        m.pendingChannelUrl = invalid
        _captureCurrentlyPlayingChannel()
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
        ' Only reset fullscreen inactivity timer when actually in fullscreen.
        ' If preview is playing on the grid, we should NOT dismiss the screensaver shade.
        if m.isPlayingVideo then resetFullscreenInactivityTimer()

        ' Dwell commit: if the user stopped surfing and this channel reached
        ' playing state, that's definitive — commit the departure channel as
        ' previousChannelIndex now rather than waiting for the 2s timer.
        if m.surfStartChannelIndex >= 0 then
            m.previousChannelIndex  = m.surfStartChannelIndex
            m.surfStartChannelIndex = -1
            _cancelNamedTimer("surfDwellTimer")
            print ">>> NAV: Playing — committed previousChannelIndex="; m.previousChannelIndex
        end if

        ' Notify settings cache
        if m.previewVideo.content <> invalid then
            onChannelPlayingSuccessfully(m.previewVideo.content.url, m.previewVideo.content)
            ' Remember this as the last channel watched on the currently
            ' loaded playlist -- see StateManager.brs, used by GridInput.brs's
            ' replay fallback. _currentLoadingChannelUrl() resolves proxy
            ' channels back to the real channel URL (previewVideo.content.url
            ' would be the local proxy address instead).
            realUrl = _currentLoadingChannelUrl()
            if realUrl <> "" then saveLastWatchedChannelForCurrentPlaylist(realUrl)
        end if

        ' Clear retry state
        m.retryCount             = 0
        m.manifestPatchAttempted = false
        m.isNimbleStream         = false
        m.cacheWasAttempted      = false
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

        ' Guard 1: user already cancelled — do not restart the ladder.
        ' After CANCEL, reconnectState="gaveup". Any error arriving here is from
        ' the video node draining its last attempt after control="stop" was sent.
        if m.reconnectState = "gaveup" then
            print ">>> STATE ERROR: Ignored — user already cancelled (gaveup state)"
            return
        end if

        ' Guard 2: no channel is being loaded (loadingChannelIndex=-1 means state
        ' was reset). Stale error from a previous load cycle — ignore it.
        if m.loadingChannelIndex < 0 then
            print ">>> STATE ERROR: Ignored — no active loading channel"
            return
        end if

        ' Guard 3: error URL doesn't match what we're currently loading.
        ' Fired from an abandoned channel after the user surfed away.
        ' RetryLadder's compat step (retryCount=1) appends &_HLS_skip=NO to
        ' the URL, and an active proxy session's content.url is a
        ' session-specific http://IP:7171/master rather than the channel's
        ' real URL — neither of which _currentLoadingChannelUrl() ever has.
        ' Normalize both the same way before comparing, or every error from
        ' that retry step's own attempt (or a live proxy session) looks like
        ' it belongs to a different channel and gets discarded here,
        ' silently stalling the ladder forever.
        if m.previewVideo.content <> invalid then
            currentLoadingChannel = _currentLoadingChannelUrl()
            errorUrl = _normalizeChannelUrl(m.previewVideo.content.url)
            if currentLoadingChannel <> "" and errorUrl <> currentLoadingChannel then
                print ">>> STATE ERROR: Stale error for abandoned channel — ignoring"
                return
            end if
        end if

        hdrs = m.previewVideo.httpHeaders
        if hdrs <> invalid then
            print ">>> STATE ERROR video.HttpHeaders="; hdrs
        end if
        bs = m.previewVideo.bufferingStatus
        if bs <> invalid then
            print ">>> STATE ERROR bufferPct="; bs.percentage; " bufferRate="; bs.isUnderrun
        end if
        startErrorDelayTimer()
    end if
end sub
