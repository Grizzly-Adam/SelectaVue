' ==================== FullscreenInput.brs ====================
' Fullscreen key handling: the channel bar (left/right/OK while visible),
' channel surfing, the quick channel menu, captions, play/pause, replay,
' and the exit-to-grid / enter-fullscreen transition helpers.
'
' Key map — FULLSCREEN (channel bar hidden):
'   back        → exit to grid
'   left        → toggle quick channel menu
'   right       → reload current stream
'   up          → previous channel (also shows the channel bar)
'   down        → next channel (also shows the channel bar)
'   OK          → show channel bar
'   options (*) → toggle favorite on current channel
'   play        → pause / resume
'   replay      → jump to previously watched channel (also shows the channel bar)
'
' Key map — FULLSCREEN (channel bar visible — bar owns left/right/OK):
'   back        → dismiss the bar only
'   left        → move focus toward Favorite; if already on Favorite
'                 (leftmost), dismiss the bar and open the quick channel
'                 menu instead of wrapping to Live
'   right       → move focus between bar buttons (Favorite / CC / Details / Live), wraps around
'   OK          → activate the focused button
'   up/down     → still change channel — bar refreshes for the new channel
'   options (*) → toggle favorite on current channel
'   play        → pause / resume (unaffected by the bar)
'   replay      → jump to previously watched channel (unaffected by the bar)
'   (auto-hides after 4s of no input; bar and quick channel menu are mutually exclusive)

' ---------- Fullscreen key handling ----------

function _handleFullscreenKey(key as String) as Boolean
    ' A just-consumed OK that triggered fullscreen entry (grid double-OK,
    ' quick-menu selection) can echo through to this handler on the same
    ' physical press. This has to be checked BEFORE the channel-bar-owns-OK
    ' branch below -- _goFullscreenFromGrid()/selectChannelFromList() both
    ' show the bar (m.barVisible=true) as part of the same transition that
    ' sets this flag, so by the time the echo arrives the bar-visible branch
    ' would otherwise catch it first and activate whatever's focused there
    ' (Favorite, index 0) instead of this having a chance to swallow it.
    if key = "OK" and m.suppressNextVideoOptionsMenu then
        clearOverlayOkSuppression()
        return true
    end if

    ' Channel bar owns left/right/OK while visible — checked first since it
    ' takes priority over the quick channel menu (the two are mutually exclusive)
    if m.barVisible then
        if key = "back" then
            hideChannelBar()
            return true
        else if key = "left" then
            if m.barFocusIndex = 0 then
                ' Leftmost button already focused — dismiss the bar and open
                ' the quick channel menu instead of wrapping back to the last
                ' button.
                hideChannelBar()
                _showQuickMenu()
            else
                channelBarFocusLeft()
            end if
            return true
        else if key = "right" then
            channelBarFocusRight()
            return true
        else if key = "OK" then
            channelBarActivate()
            return true
        else if key = "options" then
            toggleFavoriteForCurrentChannel()
            return true
        end if
        ' up/down/play/replay fall through to normal handling below —
        ' channel changes re-show/refresh the bar, play/replay are unaffected
    end if

    if key = "back" then
        _exitFullscreen()
        return true

    else if key = "left" then
        if m.overlayVisible then
            hideOverlay()
            m.top.setFocus(true)
        else
            hideChannelBar()   ' bar and quick menu are mutually exclusive
            _showQuickMenu()
        end if
        return true

    else if key = "right" then
        if m.overlayVisible then
            hideOverlay()
            m.top.setFocus(true)
        else
            reloadCurrentChannel()
        end if
        return true

    else if key = "up" then
        if not m.overlayVisible then
            changeChannel(-1)
            return true
        end if

    else if key = "down" then
        if not m.overlayVisible then
            changeChannel(1)
            return true
        end if

    else if key = "OK" then
        if m.overlayVisible then
            channel = m.flatChannelList[m.currentChannelIndex]
            if channel <> invalid then
                print ">>> NAV: OK-in-overlay playChannel, currentChannelIndex="; m.currentChannelIndex
                m.suppressNextVideoOptionsMenu = true
                startOverlayOkSuppressionTimer()
                hideOverlay()
                playChannel(channel)
            end if
            return true
        else if m.previewVideo.state = "playing" or m.previewVideo.state = "paused" or m.previewVideo.state = "buffering" then
            toggleChannelBar()
            return true
        end if

    else if key = "options" then
        toggleFavoriteForCurrentChannel()
        return true

    else if key = "play" then
        if m.previewVideo.state = "playing" then
            m.previewVideo.control = "pause"
        else
            m.previewVideo.control = "resume"
        end if
        return true

    else if key = "replay" then
        ' Jump to previously watched channel
        jumpToPreviousChannel()
        return true
    end if

    return false
end function

' ---------- Fullscreen enter/exit transition helpers ----------

sub _exitFullscreen()
    m.suppressFocusChange = true
    _setPreviewGeometry()
    hideBufferBar()
    cancelStallTimer()
    m.lastBufferPct = -1
    ' Preserve network-wait state when exiting fullscreen — don't silently dismiss
    ' a "waiting for network" overlay the user may not have noticed.
    if m.reconnectState <> "network" then
        hideReconnectingOverlay()
    end if
    hideChannelBar()

    ' Restore preview error if this channel previously failed
    if m.lastError.msg <> "" and m.lastError.channelIndex = m.currentChannelIndex then
        showPreviewError()
    end if

    ' Restore buffer bar in preview position if still buffering
    if m.previewVideo.state = "buffering" and m.lastError.channelIndex <> m.currentChannelIndex then
        m.bufferContainer.translation = [1467, 252]
        m.bufferContainer.width       = 283
        m.bufferTrack.width           = 277
        m.bufferLabel.width           = 283
        m.bufferContainer.visible     = true
        m.bufferVisible               = true
        status = m.previewVideo.bufferingStatus
        if status <> invalid and status.percentage <> invalid then
            updateBufferBar(status.percentage)
        end if
    end if

    hideOverlay()
    m.channelList.visible = true
    if m.channelListHeaderLabel <> invalid then m.channelListHeaderLabel.visible = true
    if m.gridBackgroundTexture <> invalid then m.gridBackgroundTexture.visible = true
    m.sidePanel.visible   = true
    showGridOverlays()
    m.isPlayingVideo      = false
    m.top.backgroundURI   = ""
    m.top.backgroundColor = APP_BACKGROUND_TEAL()

    if m.currentChannelIndex >= 0 then m.channelList.jumpToItem = m.currentChannelIndex
    m.channelList.SetFocus(true)
    m.suppressFocusChange = false
    resetGridInactivityTimer()
end sub

sub _goFullscreenFromGrid()
    m.top.backgroundURI   = ""
    m.top.backgroundColor = APP_BACKGROUND_TEAL()
    m.previewVideo.visible = true
    _setFullscreenGeometry()
    m.channelList.visible = false
    if m.channelListHeaderLabel <> invalid then m.channelListHeaderLabel.visible = false
    if m.gridBackgroundTexture <> invalid then m.gridBackgroundTexture.visible = false
    m.sidePanel.visible   = false
    hideGridOverlays()
    m.isPlayingVideo = true
    m.suppressNextVideoOptionsMenu = true
    startOverlayOkSuppressionTimer()
    ' Explicitly defocus all nodes before taking scene focus,
    ' same as playChannel() does — prevents video node retaining focus
    m.previewVideo.setFocus(false)
    m.channelList.setFocus(false)
    m.playlistList.setFocus(false)
    m.channelOverlayList.setFocus(false)
    m.top.setFocus(true)
    if m.currentChannelIndex >= 0 and m.flatChannelList <> invalid and m.currentChannelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[m.currentChannelIndex]
        if channel <> invalid then
            m.playingChannel = channel
            showChannelBar()
        end if
    end if
    saveLastState()
end sub

' Shows the quick channel menu. Shared by the bare-fullscreen left-key
' toggle and the channel bar's leftmost-button left-key dismiss-to-quick-
' menu behavior. Caller is responsible for hiding the channel bar first if
' it's up (the two are mutually exclusive) — not done here since one of
' the two call sites already knows the bar isn't visible.
sub _showQuickMenu()
    if m.allChannels = invalid then return
    m.channelOverlay.visible         = true
    m.overlayVisible                 = true
    ' Refreshed from m.allChannels fresh on every open specifically because
    ' this reference can otherwise go stale relative to m.flatChannelList if
    ' the tree gets rebuilt (playlist switch, view toggle, hide/unhide) while
    ' the menu isn't the thing driving that rebuild -- selectChannelFromList()
    ' reads the overlay's own content rather than m.flatChannelList for
    ' exactly this reason, since this reassignment is what keeps the two
    ' reliably in agreement at selection time.
    m.channelOverlayList.content     = m.allChannels
    m.channelOverlayList.jumpToItem  = m.currentChannelIndex
    m.channelOverlayList.itemFocused = m.currentChannelIndex
    m.channelOverlayList.SetFocus(true)
    resetOverlayInactivityTimer()
end sub
