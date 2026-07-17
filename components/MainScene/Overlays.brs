' ==================== Overlays.brs ====================
' Manages every visual overlay on top of the main UI:
'   - Error overlays (preview & fullscreen)
'   - Reconnect overlay (stream-down / network-down)
'   - Buffer progress bar + slow-buffer detector
'   - Grid decoration overlays
'   - Screensaver shade
' Channel bar (logo/name/CC/Details/Live) lives in ChannelBar.brs.

' ---------- Comprehensive retry-timer cleanup ----------
' Cancels every timer that could resurrect the retry/reconnect flow after
' it's been dismissed. cancelRetryOverlay(), _silentCancelRetry(), and
' cancelAnyInFlightRetry() all call this now. Previously each had its own
' smaller subset — notably cancelRetryOverlay() never cancelled
' errorDelayTimer, so a pending 4s retry-delay (see ErrorDelayTimer.brs)
' could still fire afterward and call retryStream(), resurrecting the
' overlay even though the user had already dismissed it via up/down.
sub _cancelAllRetryTimers()
    cancelErrorDelayTimer()
    cancelStreamRetryTimer()
    cancelCountdownTickTimer()
    cancelStallTimer()
    cancelSlowBufferRecoveryTimer()
    cancelNetworkPollTimer()
    cancelChannelLoadBufferTimer()
    cancelDialogShadeTimer()
    _cancelNamedTimer("surfDwellTimer")
end sub

' ---------- Error overlays ----------
' Note: channel name lookups use m.loadingChannelIndex (the channel that was
' actually being loaded) rather than m.currentChannelIndex (what has focus now),
' so error messages show the correct channel when focus moves during loading.

sub showChannelError(errorMsg as String)
    friendlyMsg = getFriendlyError(errorMsg)
    m.lastError.msg = friendlyMsg

    ' Use loading channel index for correct name
    m.lastError.channelIndex = m.loadingChannelIndex
    if m.lastError.channelIndex < 0 then m.lastError.channelIndex = m.currentChannelIndex

    hideBufferBar()
    cancelStallTimer()
    if m.isPlayingVideo then resetFullscreenInactivityTimer() else resetGridInactivityTimer()
    if m.isPlayingVideo then
        showFullscreenError(friendlyMsg)
    else
        showPreviewError()
    end if
end sub

sub showFullscreenError(friendlyMsg as String)
    ' Fullscreen errors now go through the reconnect overlay gave-up state
    ' so the user sees the retry button rather than the old static container
    showGaveUpState(friendlyMsg)
end sub

sub showPreviewError()
    if m.previewErrorContainer <> invalid then m.previewErrorContainer.visible = true
end sub

sub hidePreviewError()
    if m.previewErrorContainer <> invalid then m.previewErrorContainer.visible = false
end sub

' ---------- Reconnect overlay ----------
' Three modes:
'   Retry active   - spinner on, status = what we are trying, no error label, no dismiss hint
'   Outage/network - spinner on, status = down message, countdown, dismiss hint hidden/shown
'   Gave up        - spinner off, status = "Could not load", error label shown, OK to retry hint

' Called at the start of each retry step to show progress to the user.
' Shows the overlay with spinner running and updates the status line.
sub showRetryStatus(message as String)
    if m.reconnectOverlay = invalid then return
    hideChannelBar()
    m.reconnectState = "ladder"

    ' Set channel name
    idx = m.loadingChannelIndex
    if idx < 0 then idx = m.currentChannelIndex
    channelName = "Unknown Channel"
    channel = iif(m.flatChannelList <> invalid and idx >= 0 and idx < m.flatChannelList.Count(), m.flatChannelList[idx], invalid)
    if channel <> invalid and cleanChannelTitle(channel) <> "" then channelName = cleanChannelTitle(channel)
    if m.reconnectChannelLabel  <> invalid then m.reconnectChannelLabel.text     = channelName
    if m.reconnectStatusLabel   <> invalid then m.reconnectStatusLabel.text      = message
    if m.reconnectErrorLabel    <> invalid then m.reconnectErrorLabel.visible    = false
    if m.reconnectCountdownLabel <> invalid then m.reconnectCountdownLabel.text  = ""
    if m.reconnectActionLabel   <> invalid then m.reconnectActionLabel.text      = "CANCEL"
    if m.reconnectSpinner       <> invalid then m.reconnectSpinner.visible       = true
    m.reconnectOverlay.visible = true
    if m.reconnectOverlayBorder <> invalid then m.reconnectOverlayBorder.visible = true
    ' Dim the rest of the screen for the whole time this overlay is up, not
    ' just once it reaches the terminal gave-up state.
    if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = true
    ' Clear any dialog-shade left over from a prior outage-loop cycle —
    ' a fresh active retry step means we're not stalled anymore.
    cancelDialogShadeTimer()
end sub

sub _showReconnectOverlay(isNetworkDown as Boolean)
    if m.reconnectOverlay = invalid then return
    hideChannelBar()
    m.reconnectState = iif(isNetworkDown, "network", "outage")

    ' Set channel name
    idx = m.loadingChannelIndex
    if idx < 0 then idx = m.currentChannelIndex
    channelName = "Unknown Channel"
    channel = iif(m.flatChannelList <> invalid and idx >= 0 and idx < m.flatChannelList.Count(), m.flatChannelList[idx], invalid)
    if channel <> invalid and cleanChannelTitle(channel) <> "" then channelName = cleanChannelTitle(channel)
    if m.reconnectChannelLabel <> invalid then m.reconnectChannelLabel.text = channelName

    ' Set status based on mode
    if isNetworkDown then
        if m.reconnectStatusLabel  <> invalid then m.reconnectStatusLabel.text     = "No network connection"
    else
        if m.reconnectStatusLabel  <> invalid then m.reconnectStatusLabel.text     = "Stream source appears to be down"
    end if

    if m.reconnectErrorLabel    <> invalid then m.reconnectErrorLabel.visible    = false
    if m.reconnectCountdownLabel <> invalid then m.reconnectCountdownLabel.text  = ""
    if m.reconnectActionLabel   <> invalid then m.reconnectActionLabel.text      = "CANCEL"
    if m.reconnectSpinner       <> invalid then m.reconnectSpinner.visible       = true
    m.reconnectOverlay.visible = true
    if m.reconnectOverlayBorder <> invalid then m.reconnectOverlayBorder.visible = true
    if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = true
end sub

' Show the terminal gave-up state — spinner off, error reason shown, OK to retry.
sub showGaveUpState(friendlyMsg as String)
    if m.reconnectOverlay = invalid then return
    m.reconnectState = "gaveup"
    hideChannelBar()

    ' Set channel name
    idx = m.loadingChannelIndex
    if idx < 0 then idx = m.currentChannelIndex
    channelName = "Unknown Channel"
    channel = iif(m.flatChannelList <> invalid and idx >= 0 and idx < m.flatChannelList.Count(), m.flatChannelList[idx], invalid)
    if channel <> invalid and cleanChannelTitle(channel) <> "" then channelName = cleanChannelTitle(channel)
    if m.reconnectChannelLabel  <> invalid then m.reconnectChannelLabel.text     = channelName
    if m.reconnectSpinner       <> invalid then m.reconnectSpinner.visible       = false
    if m.reconnectStatusLabel   <> invalid then m.reconnectStatusLabel.text      = "Could not load this channel"
    if m.reconnectErrorLabel    <> invalid then
        m.reconnectErrorLabel.text    = friendlyMsg
        m.reconnectErrorLabel.visible = true
    end if
    if m.reconnectCountdownLabel <> invalid then m.reconnectCountdownLabel.text  = ""
    if m.reconnectActionLabel   <> invalid then m.reconnectActionLabel.text      = "RETRY"
    m.reconnectOverlay.visible = true
    if m.reconnectOverlayBorder <> invalid then m.reconnectOverlayBorder.visible = true
    ' Dim the rest of the screen immediately — this is a terminal state the
    ' user needs to actually read, not something that should wait on the
    ' normal 45s inactivity timer to get shaded.
    if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = true
    ' If nobody touches this for another 30s, shade the dialog itself too.
    startDialogShadeTimer()
end sub

sub hideReconnectingOverlay()
    if m.reconnectOverlay       <> invalid then m.reconnectOverlay.visible       = false
    if m.reconnectOverlayBorder <> invalid then m.reconnectOverlayBorder.visible = false
    if m.reconnectSpinner  <> invalid then m.reconnectSpinner.visible  = true   ' reset spinner for next use
    if m.reconnectErrorLabel <> invalid then m.reconnectErrorLabel.visible = false
    ' Always ensure shader is off when overlay hides
    if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = false
    cancelDialogShadeTimer()
end sub

sub updateReconnectStatus(message as String)
    if m.reconnectStatusLabel <> invalid then m.reconnectStatusLabel.text = message
end sub

sub updateReconnectCountdown(seconds as Dynamic)
    if m.reconnectCountdownLabel = invalid then return
    if type(seconds) = "Integer" or type(seconds) = "roInt" then
        if seconds > 0 then
            m.reconnectCountdownLabel.text = "Retrying in " + seconds.ToStr() + " seconds..."
        else
            m.reconnectCountdownLabel.text = "Retrying now..."
        end if
    else
        m.reconnectCountdownLabel.text = iif(seconds = invalid, "", seconds)
    end if
end sub

' ---------- Grid decoration overlays ----------

sub showGridOverlays()
    if m.videoClipLeft               <> invalid then m.videoClipLeft.visible               = true
    if m.tvOverlay                   <> invalid then m.tvOverlay.visible                   = true
    if m.previewChannelNameContainer <> invalid then m.previewChannelNameContainer.visible     = true
    if m.flatChannelList <> invalid and m.currentChannelIndex >= 0 and m.currentChannelIndex < m.flatChannelList.Count() then
        _updatePreviewLogo(m.flatChannelList[m.currentChannelIndex])
    end if
    if m.lastError.msg <> "" and m.lastError.channelIndex = m.currentChannelIndex then
        showPreviewError()
    end if
    m.playlistPanelActive = false
    m.channelList.SetFocus(true)
end sub

sub hideGridOverlays()
    if m.videoClipLeft               <> invalid then m.videoClipLeft.visible               = false
    if m.tvOverlay                   <> invalid then m.tvOverlay.visible                   = false
    if m.previewChannelNameContainer <> invalid then m.previewChannelNameContainer.visible     = false
    if m.previewChannelLogo          <> invalid then m.previewChannelLogo.visible           = false
    hidePreviewError()
end sub

sub hideOverlay()
    m.channelOverlay.visible = false
    m.overlayVisible         = false
    m.channelOverlayList.setFocus(false)
    m.top.setFocus(true)
    if m.overlayInactivityTimer <> invalid then
        m.overlayInactivityTimer.control = "stop"
        m.overlayInactivityTimer.unobserveField("fire")
        m.overlayInactivityTimer = invalid
    end if
end sub

' ---------- Cancel / dismiss loading overlay ----------
' Called when user presses Back while the reconnect overlay is showing.
' Stops all retry activity and shows the appropriate error UI.

sub cancelRetryOverlay()
    print ">>> CANCEL: User cancelled loading"
    ' Kill all retry timers
    _resetRetryState()
    _cancelAllRetryTimers()
    stopPreviewVideo()
    hideReconnectingOverlay()
    ' The channel-load buffer/progress bar isn't part of the reconnect overlay
    ' and isn't touched by any of the calls above, so without this it keeps
    ' sitting on top of the Channel Unavailable overlay we're about to show —
    ' it only went away before because a focus change (up/down) happened to
    ' call hideBufferBar() separately in onChannelFocused.
    hideBufferBar()

    if m.isPlayingVideo then
        ' Fullscreen: show gave-up state
        showGaveUpState(getFriendlyError(""))
    else
        ' Grid: preview error indicator only
        showPreviewError()
    end if
end sub

' Stops all retry timers without showing any error UI — used when the user
' is navigating straight to a different channel (e.g. replay/jump-to-previous)
' rather than dismissing into an error state.
sub _silentCancelRetry()
    print ">>> CANCEL: Silent (navigating away while loading)"
    ' Stop async operations that may be in flight
    ' ManifestPatcher: clear pendingRetryContent so onManifestPatched ignores the result
    m.pendingRetryContent = invalid
    m.pendingProxyContent = invalid
    ' Stop the proxy if it was starting for the old channel
    if m.localProxy <> invalid and m.localProxy.status <> "idle" and m.localProxy.status <> "stopped" then
        print ">>> CANCEL: Stopping LocalProxy (was starting for cancelled channel)"
        m.localProxy.stopProxy = true
    end if
    m.proxyOriginalUrl = ""
    _resetRetryState()
    _cancelAllRetryTimers()
    stopPreviewVideo()
    hideReconnectingOverlay()
    hideBufferBar()
end sub

' Clears any in-flight reconnect state (m.reconnectState: ladder/outage/
' gaveup — network is excluded, see below) and its timers in one call. Used
' by selection observers (itemSelected on the grid list and the quick-menu
' overlay list) which can fire independently of onKeyEvent's dialog
' intercept, so they need to do this cleanup themselves before acting on
' the selection. Doesn't check for "network": onKeyEvent has a hard input
' lockout while m.reconnectState = "network", so this is never reachable
' in that state anyway.
sub cancelAnyInFlightRetry()
    ' Always cancel if the retry ladder is actively running (retryCount > 0)
    ' even if the reconnect overlay isn't visible yet — the async patcher/proxy
    ' must be stopped or they'll fire against the wrong channel.
    if m.retryCount > 0 then
        _silentCancelRetry()
        return
    end if
    ' Also cancel if the reconnect overlay is showing or in gave-up/outage state
    if (m.reconnectOverlay = invalid or not m.reconnectOverlay.visible) and m.reconnectState <> "gaveup" and m.reconnectState <> "outage" then return
    _silentCancelRetry()
end sub
