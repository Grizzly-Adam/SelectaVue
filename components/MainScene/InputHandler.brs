' ==================== InputHandler.brs ====================
' Single onKeyEvent entry point: handles the reconnect-dialog intercept,
' gave-up state, stream-retry/screensaver dismissal, and inactivity-timer
' resets, then dispatches to FullscreenInput.brs or GridInput.brs.
' (Fullscreen and grid key handling live in their own files — see those
' for the full key map; only the cross-cutting dialog/overlay logic stays here.)
'
' Key map summary:
'
' FULLSCREEN (channel bar hidden):
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
' FULLSCREEN (channel bar visible — bar owns left/right/OK):
'   back        → dismiss the bar only
'   left/right  → move focus between bar buttons (CC / Details / Live), wraps around
'   OK          → activate the focused button
'   up/down     → still change channel — bar refreshes for the new channel
'   options (*) → toggle favorite on current channel
'   play        → pause / resume (unaffected by the bar)
'   replay      → jump to previously watched channel (unaffected by the bar)
'   (auto-hides after 4s of no input; bar and quick channel menu are mutually exclusive)
'
' GRID (channel list focused):
'   back        → return to playing preview channel (if not already there); else open playlist panel
'   left        → open playlist panel
'   right       → go fullscreen with current preview (if playing)
'   OK          → load preview / go fullscreen
'   replay      → jump focus to previously watched channel
'
' GRID (playlist panel focused):
'   back        → go fullscreen if preview is playing; else consume
'   right       → move focus to channel list
'   options     → show playlist options
'   replay      → reload current playlist
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

    ' Loading overlay (grid only): OK/back dismiss and stop there — don't
    ' let them act on whatever's focused in the grid underneath. Up/down/
    ' left dismiss too but still fall through to their normal handling, so
    ' the grid can be browsed while the fetch keeps running in the
    ' background. OK/up/down are also handled in onChannelSelected/
    ' onChannelFocused/onPlaylistSelected/onPlaylistFocused since a focused
    ' LabelList consumes those natively before they'd ever reach here.
    if m.loadingDialogVisible and not m.isPlayingVideo then
        if m.suppressLoadingDialogDismissOnce then
            m.suppressLoadingDialogDismissOnce = false
            print ">>> LOADDLG: onKeyEvent -- suppressing dismiss for key="; key; " (trailing echo of the press that just started the load)"
            return true
        end if
        if key = "OK" or key = "back" then
            _dismissLoadingDialogForInput()
            return true
        else if key = "up" or key = "down" or key = "left" then
            _dismissLoadingDialogForInput()
            ' fall through to normal grid handling below
        end if
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
