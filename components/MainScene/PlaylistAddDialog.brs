' ==================== PlaylistAddDialog.brs ====================
' Two-step "add new playlist" dialog flow (name, then URL), plus the
' private dialog helpers shared between this file and PlaylistEditDialogs.brs.

' ---------- Add new playlist (two-step dialog) ----------

sub showPlaylistManager()
    if m.top.dialog <> invalid then
        m.top.dialog.close = true
        m.top.dialog = invalid
    end if
    m.tempPlaylistName = invalid
    _showKeyboardDialog("NEW PLAYLIST - STEP 1/2: Enter name", "Enter name (ex: My list)", "", ["Next", "Cancel"], "onPlaylistNameEntered")
end sub

sub onPlaylistNameEntered()
    buttonSelected = m.top.dialog.buttonSelected
    if buttonSelected = 0 then
        name = m.top.dialog.text
        if name = "" or name = invalid then name = "New Playlist"
        m.tempPlaylistName = name
        _closeDialog()
        _delayedCall("showUrlDialog", 0.3)
    else
        _closeDialog()
        m.tempPlaylistName = invalid
        _returnToPlaylistPanel()
    end if
end sub

sub showUrlDialog()
    if m.tempPlaylistName = invalid then
        _returnToPlaylistPanel()
        return
    end if
    _showKeyboardDialog("NEW PLAYLIST - STEP 2/2: Enter URL", "", "", ["Add", "Cancel"], "onPlaylistUrlEntered")
end sub

sub onPlaylistUrlEntered()
    buttonSelected = m.top.dialog.buttonSelected
    if buttonSelected = 0 then
        url = m.top.dialog.text
        _closeDialog()
        if url = "" or url = invalid then
            _showPlaylistError("URL cannot be empty")
            return
        end if
        if not isValidUrl(url) then
            _showPlaylistError("URL invalid. Must start with http:// or https://")
            return
        end if
        if m.tempPlaylistName <> invalid then
            savePlaylist(m.tempPlaylistName, url)
            m.currentPlaylist = m.playlists.Count() - 1   ' the playlist we just pushed
            loadPlaylist(url)
        end if
        m.tempPlaylistName = invalid
        _returnToPlaylistPanel()
    else
        _closeDialog()
        m.tempPlaylistName = invalid
        _returnToPlaylistPanel()
    end if
end sub

' ---------- Private helpers ----------

' Fires AppDialogComplete exactly once, only if this dialog sequence was
' the very-first-run one (see m.isFirstRunSetupDialog in MainScene.brs's
' init()) — not when showPlaylistManager() is reached later from the
' in-app "add playlist" menu. Called at every exit point of the flow below
' (success, cancel, or error) since the beacon measures time spent in the
' dialog, not whether it succeeded.
sub _completeFirstRunSetupDialogIfNeeded()
    if m.isFirstRunSetupDialog then
        m.top.signalBeacon("AppDialogComplete")
        m.isFirstRunSetupDialog = false
    end if
end sub

' Unobserve and close the current dialog in one call.
sub _closeDialog()
    if m.top.dialog <> invalid then
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
    end if
end sub

' Return focus to the playlist side panel — always done together.
sub _returnToPlaylistPanel()
    _completeFirstRunSetupDialogIfNeeded()
    m.playlistList.setFocus(true)
    m.playlistPanelActive = true
end sub

' Show a simple error dialog, then return to the playlist panel on dismiss.
sub _showPlaylistError(message as String)
    m.pendingErrorMessage = message
    _delayedCall("onShowPlaylistError", 0.3)
end sub

sub onShowPlaylistError()
    _cancelNamedTimer("optionTimer")
    message = "An error occurred."
    if m.pendingErrorMessage <> invalid then
        message = m.pendingErrorMessage
        m.pendingErrorMessage = invalid
    end if
    _showSimpleDialog("Error", message, ["OK"], "onPlaylistErrorClosed")
end sub

sub onPlaylistErrorClosed()
    _closeDialog()
    _returnToPlaylistPanel()
end sub

' Creates a one-shot timer that fires callbackName after delaySec seconds.
sub _delayedCall(callbackName as String, delaySec as Float)
    _startNamedTimer("optionTimer", delaySec, false, callbackName)
end sub

sub _clearOptionTimer()
    _cancelNamedTimer("optionTimer")
end sub
