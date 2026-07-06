' ==================== StreamOutageLoop.brs ====================
' Entered when the retry ladder is exhausted but the stream previously
' played successfully. Retries a clean reload every 30 seconds until the
' stream comes back or the user changes channel. Each retry checks
' network status first and hands off to NetworkDownProtocol.brs if it's down.

' ---------- Stream outage loop ----------
' Entered when the retry ladder is exhausted but the stream previously played.
' Retries a clean reload every 30 seconds until the stream comes back
' or the user changes channel. Each retry checks network first.

sub _enterOutageLoop()
    m.outageLoopCycleCount = m.outageLoopCycleCount + 1
    _showReconnectOverlay(false)   ' sets m.reconnectState = "outage"
    if m.outageLoopCycleCount >= 2 then
        ' Perpetual retry with no end in sight — shade the dialog itself
        ' 30s into this cycle, same treatment as the gave-up state.
        startDialogShadeTimer()
    end if
    _startStreamRetryTimer(30)
end sub

sub _startStreamRetryTimer(seconds as Integer)
    m.reconnectCountdown = seconds
    updateReconnectCountdown(m.reconnectCountdown)
    _startNamedTimer("streamRetryTimer", seconds, false, "onStreamRetryFired")
    startCountdownTick()
end sub

sub onStreamRetryFired()
    m.streamRetryTimer = invalid
    if m.reconnectState <> "outage" then return

    ' Check network first
    deviceInfo = CreateObject("roDeviceInfo")
    if deviceInfo.GetConnectionType() = "none" then
        print ">>> OUTAGE: Network down during stream retry — switching to network poll"
        _enterNetworkWait()
        return
    end if

    ' Network up — reset retry state so ladder starts fresh, then attempt reload
    print ">>> OUTAGE: Retrying stream"
    m.retryCount        = 0
    m.cacheWasAttempted = false
    m.bandwidthProbeIndex = 0
    m.manifestPatchAttempted = false
    m.isNimbleStream         = false
    m.proxyOriginalUrl       = ""
    ' Stop any running proxy — it may have stale session tokens.
    ' The retry will restart it fresh via the cache fast-path (useProxy=true).
    if m.localProxy <> invalid and m.localProxy.status <> "idle" and m.localProxy.status <> "stopped" then
        print ">>> OUTAGE: Stopping stale proxy before retry"
        m.localProxy.stopProxy = true
    end if
    updateReconnectStatus("Reconnecting...")
    updateReconnectCountdown("")

    channel = _currentChannel()

    if m.lastWorkingContent <> invalid then
        m.pendingHeaders = _resolveHeaders(channel)
        _applyContentAndPlay(m.lastWorkingContent)
    else if channel <> invalid then
        freshContent = _makeContentNode(channel.url, channel.title, channel)
        _applyContentAndPlay(freshContent)
    else
        ' Nothing to retry with — give up
        m.reconnectState = "idle"
        hideReconnectingOverlay()
        showChannelError("Stream could not be restored.")
    end if
end sub
