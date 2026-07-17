' ==================== PlaybackHealthTimers.brs ====================
' Timers that track and react to playback health: buffer stalls, slow-buffer
' recovery, the error-delay pause before retrying, network-down polling,
' the stream-outage retry interval, the reconnect countdown display tick,
' and the brief OK-keypress suppression right after a channel launch.
'
' Timers managed in this file:
'   stallTimer              - fires after 15s of no buffer progress → retryStream()
'   slowBufferRecoveryTimer - restores full ABR after 30s of clean playback
'   errorDelayTimer         - 4s pause before retrying on clean error
'   networkPollTimer        - 10s poll interval when network is down
'   streamRetryTimer        - 30s retry interval when stream is down
'   countdownTickTimer      - 1s tick to update countdown display
'   overlayOkSuppressTimer  - 0.5s window absorbing a stray OK right after channel launch

' ---------- Channel-load buffer-bar timer ----------
' Guarantees the buffer bar appears at a predictable time after a channel
' is requested (3s), rather than depending on the video node's own first
' bufferingStatus event via bufferDelayTimer in BufferBar.brs — if the
' stream is slow to even start connecting, that event itself is delayed,
' so the "1 second after buffering starts" never actually starts ticking.
' Shows with 0% if no real percentage has been reported yet by the time
' this fires.
sub startChannelLoadBufferTimer()
    _startNamedTimer("channelLoadBufferTimer", 3.0, false, "onChannelLoadBufferTimeout")
end sub

sub cancelChannelLoadBufferTimer()
    _cancelNamedTimer("channelLoadBufferTimer")
end sub

sub onChannelLoadBufferTimeout()
    m.channelLoadBufferTimer = invalid
    if m.bufferVisible then return               ' organic path already showing it
    if m.previewVideo.state = "playing" then return   ' already loaded, nothing to show
    showBufferBar()
end sub

' ---------- Reconnect dialog shade timer ----------
' Shades the reconnect dialog itself (not just the background behind it,
' which screensaverOverlay already handles) 30s after either: the gave-up
' state is reached (button switches to RETRY) and nobody's touched it, or
' the outage loop begins its second (or later) cycle — a sign the stream
' may be down indefinitely rather than just having a brief hiccup.
sub startDialogShadeTimer()
    _startNamedTimer("dialogShadeTimer", 30.0, false, "onDialogShadeTimeout")
end sub

sub cancelDialogShadeTimer()
    _cancelNamedTimer("dialogShadeTimer")
    if m.reconnectDialogShade <> invalid then m.reconnectDialogShade.visible = false
end sub

sub onDialogShadeTimeout()
    m.dialogShadeTimer = invalid
    if m.reconnectDialogShade <> invalid then m.reconnectDialogShade.visible = true
end sub

' ---------- Buffer stall detection ----------

sub cancelStallTimer()
    _cancelNamedTimer("stallTimer")
end sub

sub onBufferStall()
    m.stallTimer = invalid
    if m.previewVideo.state <> "buffering" then return
    ' Don't restart the ladder if the user already cancelled
    if m.reconnectState = "gaveup" then return
    if m.loadingChannelIndex < 0 then return
    pct    = 0
    status = m.previewVideo.bufferingStatus
    if status <> invalid and status.percentage <> invalid then pct = status.percentage
    if pct >= 100 then return
    print ">>> STALL: Buffer stalled at "; pct; "% — calling retryStream()"
    retryStream("Buffer stall at " + pct.ToStr() + "%")
end sub

' ---------- Slow-buffer recovery ----------

sub startSlowBufferRecoveryTimer()
    _startNamedTimer("slowBufferRecoveryTimer", 30.0, false, "onSlowBufferRecovery")
end sub

sub cancelSlowBufferRecoveryTimer()
    _cancelNamedTimer("slowBufferRecoveryTimer")
end sub

sub onSlowBufferRecovery()
    m.slowBufferRecoveryTimer = invalid
    if m.previewVideo.state <> "playing" then return
    print ">>> RECOVERY: Stream stable — restoring full ABR"
    m.softStepCount       = 0
    m.softStepBandwidth   = 0
    m.slowBufferStartTime = invalid
    ' Cap cleared — next content node will use MaxBandwidth=0 (full ABR)
end sub

' ---------- Error delay timer ----------

sub cancelErrorDelayTimer()
    _cancelNamedTimer("errorDelayTimer")
end sub

' ---------- Network poll timer ----------

sub cancelNetworkPollTimer()
    _cancelNamedTimer("networkPollTimer")
end sub

' ---------- Stream retry timer ----------

sub cancelStreamRetryTimer()
    _cancelNamedTimer("streamRetryTimer")
end sub

' ---------- Countdown tick timer ----------
' Fires every second to update the countdown display in the reconnect overlay.

sub startCountdownTick()
    _startNamedTimer("countdownTickTimer", 1.0, true, "onCountdownTick")
end sub

sub cancelCountdownTickTimer()
    _cancelNamedTimer("countdownTickTimer")
end sub

sub onCountdownTick()
    ' Stop ticking if neither retry loop is active
    if m.reconnectState <> "outage" and m.reconnectState <> "network" then
        cancelCountdownTickTimer()
        return
    end if
    if m.reconnectCountdown > 0 then
        m.reconnectCountdown = m.reconnectCountdown - 1
        updateReconnectCountdown(m.reconnectCountdown)
    end if
end sub

' ---------- OK-suppression timer ----------

sub startOverlayOkSuppressionTimer()
    _startNamedTimer("overlayOkSuppressTimer", 0.5, false, "clearOverlayOkSuppression")
end sub

sub clearOverlayOkSuppression()
    _cancelNamedTimer("overlayOkSuppressTimer")
    m.suppressNextVideoOptionsMenu = false
end sub
