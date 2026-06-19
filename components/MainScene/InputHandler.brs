' ==================== InputHandler.brs ====================
' Contains the single onKeyEvent entry point.
' Delegates all real work to functions in the other modules
' so this file stays easy to read and audit.

function onKeyEvent(key as String, press as Boolean) as Boolean
    print ">>> KEYEVENT: key = '"; key; "', press = "; press; ", isPlayingVideo = "; m.isPlayingVideo
    result = false

    if not press then return result

    ' Screensaver intercept — dismiss on any key
    if m.screensaverOverlay <> invalid and m.screensaverOverlay.visible then
        m.screensaverOverlay.visible = false
        resetGridInactivityTimer()
        return true
    end if

    ' Reset inactivity timers on any keypress
    if not m.isPlayingVideo then resetGridInactivityTimer()
    if m.isPlayingVideo and (m.fullscreenFailContainer = invalid or not m.fullscreenFailContainer.visible) then
        resetFullscreenInactivityTimer()
    end if
    if m.overlayVisible then resetOverlayInactivityTimer()

    ' Error overlay intercept (grid/preview only)
    if m.errorVisible and not m.isPlayingVideo then
        hideErrorOverlay()
        m.channelList.SetFocus(true)
        resetGridInactivityTimer()
        return true
    end if

    if m.isPlayingVideo then
        result = _handleFullscreenKey(key)
    else
        result = _handleGridKey(key)
    end if

    return result
end function

' ---------- Fullscreen key handling ----------

function _handleFullscreenKey(key as String) as Boolean
    if key = "back" then
        _exitFullscreen()
        return true

    else if key = "left" then
        if m.overlayVisible then
            print ">>> QUICKMENU: Hiding quick menu"
            hideOverlay()
            m.top.setFocus(true)
        else
            print ">>> QUICKMENU: Showing quick menu"
            if m.allChannels <> invalid then
                m.channelOverlay.visible         = true
                m.overlayVisible                 = true
                m.channelOverlayList.content     = m.allChannels
                m.channelOverlayList.jumpToItem  = m.currentChannelIndex
                m.channelOverlayList.itemFocused = m.currentChannelIndex
                m.channelOverlayList.SetFocus(true)
                resetOverlayInactivityTimer()
            end if
        end if
        return true

    else if key = "right" then
        if m.overlayVisible then
            hideOverlay()
            m.top.setFocus(true)
        else
            ' Toggle mute
            m.previewMuted         = not m.previewMuted
            m.previewVideo.mute    = m.previewMuted
            showMuteIndicator()
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
        if m.suppressNextVideoOptionsMenu then
            clearOverlayOkSuppression()
            return true
        else if m.overlayVisible then
            channel = m.flatChannelList[m.currentChannelIndex]
            if channel <> invalid then
                m.suppressNextVideoOptionsMenu = true
                startOverlayOkSuppressionTimer()
                hideOverlay()
                playChannel(channel)
            end if
            return true
        else if m.previewVideo.state = "playing" or m.previewVideo.state = "paused" or m.previewVideo.state = "buffering" then
            showVideoOptionsMenu()
            return true
        end if

    else if key = "play" then
        if m.previewVideo.state = "playing" then
            m.previewVideo.control = "pause"
        else
            m.previewVideo.control = "resume"
        end if
        return true

    else if key = "replay" then
        reloadCurrentChannel()
        return true
    end if

    return false
end function

' ---------- Grid key handling ----------

function _handleGridKey(key as String) as Boolean
    if key = "back" then
        if m.playlistPanelActive then
            if m.previewVideo.state = "playing" then
                _goFullscreenFromGrid()
            end if
            ' Consume the key either way
        else
            ' Move focus to the playlist panel
            m.sidePanel.visible      = true
            m.playlistPanelActive    = true
            m.playlistList.SetFocus(true)
        end if
        return true

    else if key = "right" then
        if m.playlistPanelActive then
            m.playlistPanelActive = false
            m.channelList.SetFocus(true)
        else
            m.previewMuted = not m.previewMuted
            if m.previewVideo <> invalid then m.previewVideo.mute = m.previewMuted
            updatePreviewHint()
            showMuteIndicator()
        end if
        return true

    else if key = "left" then
        m.sidePanel.visible   = true
        m.playlistPanelActive = true
        m.playlistList.SetFocus(true)
        return true

    else if key = "options" then
        if m.playlistPanelActive then
            m.playlistFocusIndex = m.playlistList.itemFocused
            showPlaylistOptions()
            return true
        end if

    else if key = "replay" then
        if m.playlistPanelActive then
            reloadCurrentPlaylist()
        else
            reloadCurrentChannel()
        end if
        return true
    end if

    return false
end function

' ---------- Private helper ----------

sub _exitFullscreen()
    m.suppressFocusChange = true
    m.previewVideo.translation            = [1380, 145]
    m.previewVideo.width                  = 444
    m.previewVideo.height                 = 250
    m.previewVideo.mute                   = m.previewMuted
    m.previewVideo.trickplaybarvisibilityauto = true
    hideBufferBar()
    cancelStallTimer()
    m.lastBufferPct = -1
    if m.fullscreenFailContainer <> invalid then m.fullscreenFailContainer.visible = false

    ' Restore preview error if this channel previously failed
    if m.lastErrorMsg <> "" and m.lastErrorChannelIndex = m.currentChannelIndex then
        showPreviewError(m.lastErrorMsg)
    end if

    ' Restore buffer bar in preview position if still buffering
    if m.previewVideo.state = "buffering" and m.lastErrorChannelIndex <> m.currentChannelIndex then
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
    m.sidePanel.visible   = true
    showGridOverlays()
    m.isPlayingVideo      = false
    m.top.backgroundURI   = ""
    m.top.backgroundColor = "0x024c48FF"

    if m.currentChannelIndex >= 0 then m.channelList.jumpToItem = m.currentChannelIndex
    m.channelList.SetFocus(true)
    m.suppressFocusChange = false
    resetGridInactivityTimer()
end sub

sub _goFullscreenFromGrid()
    m.top.backgroundURI   = ""
    m.top.backgroundColor = "0x024c48FF"
    m.previewVideo.trickplaybarvisibilityauto = false
    m.previewVideo.translation = [0, 0]
    m.previewVideo.width       = 1920
    m.previewVideo.height      = 1080
    m.channelList.visible      = false
    m.sidePanel.visible        = false
    hideGridOverlays()
    m.isPlayingVideo           = true
    m.suppressNextVideoOptionsMenu = true
    startOverlayOkSuppressionTimer()
    m.top.setFocus(true)
    saveLastState()
end sub
