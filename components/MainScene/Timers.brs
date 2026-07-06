' ==================== Timers.brs ====================
' UI inactivity timers: auto-fullscreen/screensaver on the grid, the
' fullscreen screensaver shade, quick-menu auto-dismiss, and the video
' options dialog auto-close.
'
' Timers managed in this file:
'   gridInactivityTimer       - auto-fullscreen or screensaver after 45s on grid
'   fullscreenInactivityTimer - screensaver shade after 45s fullscreen with error
'   overlayInactivityTimer    - auto-dismiss quick-menu after 30s
'   optionsDialogTimer        - auto-close video options dialog after 30s
'
' See also: PlaybackHealthTimers.brs (stall/error-delay/network/stream-retry/
' countdown/OK-suppression), SessionRefreshTimer.brs (session-token refresh),
' and SettingsCache.brs (settingsCacheTimer, a 2min promotion delay — managed
' entirely in that file, not here).

' ---------- Loading dialog: active-input dismissal (grid only) ----------
' Called from onKeyEvent (OK/back/up/down/left) and from the itemSelected/
' itemFocused observers (OK/up/down are natively consumed by a focused
' LabelList before they'd ever reach onKeyEvent). Just hides the overlay —
' m.loadingDialogVisible stays true since the fetch task is still running;
' SetContent() clears it properly once the load actually finishes.
sub _dismissLoadingDialogForInput()
    if m.loadingOverlay       <> invalid then m.loadingOverlay.visible       = false
    if m.loadingOverlayBorder <> invalid then m.loadingOverlayBorder.visible = false
    if m.screensaverOverlay <> invalid and (m.reconnectOverlay = invalid or not m.reconnectOverlay.visible) then
        m.screensaverOverlay.visible = false
    end if
end sub

' ---------- Screensaver / dim-shader dismissal ----------
' Shared by onKeyEvent AND by the itemFocused/itemSelected observers below.
' Necessary because focused LabelLists (channelList, playlistList,
' channelOverlayList) consume up/down/OK internally via their own native
' key handling and never let those reach Scene.onKeyEvent — so dismissing
' the shader can't live in onKeyEvent alone, or an OK press meant to "just
' clear the dim" would instead fall straight through to onChannelSelected /
' onPlaylistSelected and act on whatever happened to be focused underneath.
' Returns true if the shader was up and this call handled it (caller should
' stop and not process the key/event any further).
function _dismissScreensaverIfVisible() as Boolean
    if m.screensaverOverlay = invalid or not m.screensaverOverlay.visible then return false
    ' The reconnect dialog owns the shade for as long as it's up, in any
    ' state — cancelling/dismissing it goes through hideReconnectingOverlay
    ' (which explicitly turns the shade off itself), not this generic path.
    if m.reconnectOverlay <> invalid and m.reconnectOverlay.visible then return false
    m.screensaverOverlay.visible = false
    if m.loadingDialogVisible then
        _showLoadingDialog()   ' restore the modal loading dialog — the fetch task never stopped
    end if
    if m.isPlayingVideo then
        resetFullscreenInactivityTimer()
    else
        resetGridInactivityTimer()
    end if
    return true
end function

' ---------- Grid inactivity ----------

sub resetGridInactivityTimer()
    if m.isPlayingVideo then return
    if m.screensaverOverlay <> invalid and (m.reconnectOverlay = invalid or not m.reconnectOverlay.visible) then
        m.screensaverOverlay.visible = false
    end if
    _startNamedTimer("gridInactivityTimer", 45.0, false, "onGridInactivity")
end sub

sub onGridInactivity()
    m.gridInactivityTimer = invalid
    if m.isPlayingVideo then return
    ' Loading overlay still up (not manually dismissed) — it already dims
    ' via screensaverOverlay the whole time it's shown, so there's nothing
    ' to do here except not auto-transition to fullscreen underneath it. If
    ' the user already dismissed it, fall through to normal inactivity
    ' handling below like any other idle grid moment.
    if m.loadingDialogVisible and m.loadingOverlay <> invalid and m.loadingOverlay.visible then return
    if m.previewVideo.state = "playing" then
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
        m.loadingChannelIndex = m.currentChannelIndex   ' explicit — same channel, no ambiguity
        m.suppressNextVideoOptionsMenu = true
        startOverlayOkSuppressionTimer()
        ' Explicitly defocus grid/list nodes before taking scene focus —
        ' same as playChannel() / _goFullscreenFromGrid() — or m.channelList
        ' (which almost certainly has focus right now) could keep consuming
        ' Up/Down instead of letting them reach changeChannel() in fullscreen.
        m.channelList.setFocus(false)
        m.playlistList.setFocus(false)
        m.channelOverlayList.setFocus(false)
        m.top.setFocus(true)
        if m.currentChannelIndex >= 0 and m.flatChannelList <> invalid and m.currentChannelIndex < m.flatChannelList.Count() then
            channel = m.flatChannelList[m.currentChannelIndex]
            if channel <> invalid then showChannelBar(channel)
        end if
        saveLastState()
    else
        if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = true
    end if
end sub

' ---------- Fullscreen inactivity ----------

sub resetFullscreenInactivityTimer()
    if m.screensaverOverlay <> invalid and (m.reconnectOverlay = invalid or not m.reconnectOverlay.visible) then
        m.screensaverOverlay.visible = false
    end if
    _startNamedTimer("fullscreenInactivityTimer", 45.0, false, "onFullscreenInactivity")
end sub

sub onFullscreenInactivity()
    m.fullscreenInactivityTimer = invalid
    if m.screensaverOverlay = invalid then return
    if m.reconnectOverlay <> invalid and m.reconnectOverlay.visible then
        m.screensaverOverlay.visible = true
    end if
end sub

' ---------- Overlay (quick-menu) inactivity — 30s ----------

sub resetOverlayInactivityTimer()
    _startNamedTimer("overlayInactivityTimer", 30.0, false, "onOverlayInactivity")
end sub

sub onOverlayInactivity()
    m.overlayInactivityTimer = invalid
    if m.overlayVisible then
        hideOverlay()
        if m.isPlayingVideo then
            m.top.setFocus(true)
            resetFullscreenInactivityTimer()
        end if
    end if
end sub

' ---------- Options dialog auto-close ----------

sub resetOptionsDialogTimer()
    _startNamedTimer("optionsDialogTimer", 30.0, false, "onOptionsDialogTimeout")
end sub

sub onOptionsDialogTimeout()
    m.optionsDialogTimer = invalid
    if m.top.dialog <> invalid then m.top.dialog.close = true
end sub
