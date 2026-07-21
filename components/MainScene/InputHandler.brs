' ==================== InputHandler.brs ====================
' Single onKeyEvent entry point: handles the reconnect-dialog intercept,
' gave-up state, stream-retry/screensaver dismissal, and inactivity-timer
' resets, then dispatches to FullscreenInput.brs or GridInput.brs.
' (Full key maps for fullscreen/grid live in those files. Reconnect-dialog
' key map below since that logic lives here.)
'
' RECONNECT DIALOG (actively retrying — steps 0-5 of the retry ladder):
'   GRID:
'     OK              → cancel + eat
'     back             → cancel + eat
'     up/down          → cancel + fall through
'     left              → cancel + fall through
'     right             → fall through only, dialog stays up (no cancel)
'     replay            → cancel + fall through
'     everything else   → cancel + eat
'   FULLSCREEN:
'     OK              → cancel + eat
'     back             → cancel + eat
'     up/down          → cancel + fall through
'     left              → fall through only, dialog stays up (no cancel)
'     right             → fall through only, dialog stays up (no cancel)
'     replay            → cancel + fall through
'     everything else   → cancel + eat

function onKeyEvent(key as String, press as Boolean) as Boolean
    result = false
    if not press then return result
    print ">>> KEY: "; key; " isPlayingVideo="; m.isPlayingVideo; " currentChannelIndex="; m.currentChannelIndex

    ' Network lockout — all input blocked while waiting for network
    if m.reconnectState = "network" then return true

    ' Loading overlay (grid only): NOT dismissable -- blocks every key until
    ' the fetch actually finishes and _hideLoadingDialog() is called (from
    ' SetContent()'s completion handler). Home still exits the app since
    ' that's handled by the OS, not here. OK/up/down are also blocked in
    ' onChannelSelected/onChannelFocused/onPlaylistSelected/onPlaylistFocused
    ' since a focused LabelList consumes those natively before they'd ever
    ' reach here.
    if m.loadingDialogVisible and not m.isPlayingVideo then
        return true
    end if

    ' Reconnect overlay visible and actively retrying (not gave-up, not outage loop, not network wait)
    if m.reconnectOverlay <> invalid and m.reconnectOverlay.visible and m.reconnectState = "ladder" then
        if key = "right" then
            ' No cancel, dialog stays up — same in grid and fullscreen
        else if key = "left" and m.isPlayingVideo then
            ' Fullscreen left: no cancel, dialog stays up
        else if key = "left" then
            ' Grid left: cancel + fall through
            cancelRetryOverlay()
            ' fall through
        else if key = "up" or key = "down" then
            ' Cancel + fall through — same in grid and fullscreen
            cancelRetryOverlay()
            ' fall through
        else if key = "replay" then
            ' Cancel (silent, no error flash) + fall through to jump-to-previous
            _silentCancelRetry()
            ' fall through
        else if key = "OK" or key = "back" then
            ' Cancel + eat — same in grid and fullscreen
            cancelRetryOverlay()
            return true
        else
            ' Everything else: cancel + eat
            cancelRetryOverlay()
            return true
        end if
    end if

    ' Gave-up state — OK retries, up/down/right/back work normally, everything else consumed
    if m.reconnectState = "gaveup" then
        if key = "OK" then
            ' Show active-retry style immediately (spinner, CANCEL, status message)
            ' then reload. reloadCurrentChannel now uses _resetRetryCounters (not
            ' _resetRetryState) so the overlay is NOT hidden during the retry.
            showRetryStatus("Retrying...")
            reloadCurrentChannel()
            return true
        end if
        ' up, down, right, left, back fall through to normal handling below
        ' but first clear the gave-up overlay since the user is taking action
        if key = "up" or key = "down" or key = "right" or key = "left" or key = "back" or key = "replay" then
            m.reconnectState = "idle"
            _cancelAllRetryTimers()
            hideReconnectingOverlay()
            ' fall through
        else
            return true   ' consume all other keys silently
        end if
    end if

    ' Stream retry dismiss — any key cancels the outage retry overlay
    if m.reconnectState = "outage" then
        m.reconnectState = "idle"
        _cancelAllRetryTimers()
        hideReconnectingOverlay()
        ' Don't consume the key — let it fall through to normal handling below
    end if

    ' Screensaver: any key dismisses it
    if _dismissScreensaverIfVisible() then return true

    ' Reset inactivity timers on every keypress
    if not m.isPlayingVideo then resetGridInactivityTimer()
    if m.isPlayingVideo then resetFullscreenInactivityTimer()
    if m.overlayVisible then resetOverlayInactivityTimer()

    if m.isPlayingVideo then
        result = _handleFullscreenKey(key)
    else
        result = _handleGridKey(key)
    end if
    return result
end function
