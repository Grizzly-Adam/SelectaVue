' ==================== Timers.brs ====================
' UI inactivity timers: auto-fullscreen/screensaver on the grid, the
' fullscreen screensaver shade, quick-menu auto-dismiss, and the video
' options dialog auto-close.
'
' Timers managed in this file:
'   gridInactivityTimer       - auto-fullscreen or screensaver after 45s on grid
'   fullscreenInactivityTimer - screensaver shade after 45s idle in fullscreen
'   overlayInactivityTimer    - auto-dismiss quick-menu after 30s
'   optionsDialogTimer        - auto-close video options dialog after 90s
'
' onDialogChanged()/onPhoneKeyboardDialogShowChanged() below pause
' gridInactivityTimer/fullscreenInactivityTimer entirely for as long as a
' text-entry dialog (playlist name/URL entry) is up — otherwise a slow
' typist could get yanked into fullscreen or dimmed by the screensaver
' mid-dialog. See also PlaybackHealthTimers.brs
' (stall/error-delay/network/stream-retry/countdown/OK-suppression),
' SessionRefreshTimer.brs (session-token refresh), and SettingsCache.brs
' (settingsCacheTimer, a 2min promotion delay — managed entirely in that
' file, not here).

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
    print ">>> LOADDLG: _dismissScreensaverIfVisible -- shade was visible, dismissing"
    ' The reconnect dialog owns the shade for as long as it's up, in any
    ' state — cancelling/dismissing it goes through hideReconnectingOverlay
    ' (which explicitly turns the shade off itself), not this generic path.
    if m.reconnectOverlay <> invalid and m.reconnectOverlay.visible then return false
    m.screensaverOverlay.visible = false
    if m.isPlayingVideo then
        resetFullscreenInactivityTimer()
    else
        resetGridInactivityTimer()
    end if
    return true
end function

' ---------- Text-entry dialog pause ----------
' Fires on every change to m.top.dialog — both when one is assigned (opened)
' and when it reverts to invalid (closed, whether via its own buttons or the
' Back key — the framework clears the field automatically either way, so
' this catches every dismiss path without needing a hook at each call site).
sub onDialogChanged()
    dlg = m.top.dialog
    if dlg <> invalid and dlg.subtype() = "StandardKeyboardDialog" then
        m.textEntryDialogVisible = true
        _cancelNamedTimer("gridInactivityTimer")
        _cancelNamedTimer("fullscreenInactivityTimer")
    else if m.textEntryDialogVisible then
        m.textEntryDialogVisible = false
        if m.isPlayingVideo then
            resetFullscreenInactivityTimer()
        else
            resetGridInactivityTimer()
        end if
    end if
end sub

' Companion to onDialogChanged() above -- same inactivity-timer pause/resume
' protection, but for PhoneKeyboardDialog. That dialog is a permanent child
' node (see MainScene.xml) rather than something assigned to m.top.dialog,
' so onDialogChanged's subtype check above never sees it open or close.
' Without this, a slow typist using the on-screen keyboard or the phone/QR
' entry could get yanked into fullscreen or dimmed by the screensaver
' mid-entry -- exactly the bug onDialogChanged was originally written to
' prevent for the keyboard dialog this one replaced.
sub onPhoneKeyboardDialogShowChanged()
    if m.phoneKeyboardDialog = invalid then return
    if m.phoneKeyboardDialog.show then
        m.textEntryDialogVisible = true
        _cancelNamedTimer("gridInactivityTimer")
        _cancelNamedTimer("fullscreenInactivityTimer")
    else if m.textEntryDialogVisible then
        m.textEntryDialogVisible = false
        if m.isPlayingVideo then
            resetFullscreenInactivityTimer()
        else
            resetGridInactivityTimer()
        end if
    end if
end sub

' Companion to onDialogChanged() above -- same inactivity-timer pause/resume,
' but for ThemedMenuDialog (the playlist options menu). Reuses
' m.textEntryDialogVisible even though this isn't text entry -- the flag's
' actual contract (pause grid/fullscreen inactivity while a modal custom
' dialog is up) already covers PhoneKeyboardDialog below for the same
' reason. Without this, 45s of no input while the menu is up would yank the
' grid into fullscreen underneath it.
sub onThemedMenuDialogShowChanged()
    if m.themedMenuDialog = invalid then return
    if m.themedMenuDialog.show then
        m.textEntryDialogVisible = true
        _cancelNamedTimer("gridInactivityTimer")
        _cancelNamedTimer("fullscreenInactivityTimer")
    else if m.textEntryDialogVisible then
        m.textEntryDialogVisible = false
        if m.isPlayingVideo then
            resetFullscreenInactivityTimer()
        else
            resetGridInactivityTimer()
        end if
    end if
end sub

' ---------- Grid inactivity ----------

sub resetGridInactivityTimer()
    if m.isPlayingVideo then return
    if m.textEntryDialogVisible then return   ' paused — see onDialogChanged above
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
            if channel <> invalid then
                m.playingChannel = channel
                showChannelBar()
            end if
        end if
        saveLastState()
        resetFullscreenInactivityTimer()
    else
        if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = true
    end if
end sub

' ---------- Fullscreen inactivity ----------

sub resetFullscreenInactivityTimer()
    if m.textEntryDialogVisible then return   ' paused — see onDialogChanged above
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
    _startNamedTimer("optionsDialogTimer", 90.0, false, "onOptionsDialogTimeout")
end sub

sub onOptionsDialogTimeout()
    m.optionsDialogTimer = invalid
    if m.themedMenuDialog <> invalid and m.themedMenuDialog.show then
        _closeThemedMenuDialog()
        _returnToPlaylistPanel()
    else
        _closeThemedMessageDialog()
        if m.previewVideo <> invalid then m.previewVideo.setFocus(false)
        m.themedMessageDialog.setFocus(false)
        m.top.setFocus(true)
    end if
end sub
