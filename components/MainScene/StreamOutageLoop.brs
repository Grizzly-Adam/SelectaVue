' ==================== StreamOutageLoop.brs ====================
' Entered when the retry ladder is exhausted but the stream previously
' played successfully. Retries a clean reload every 30 seconds until the
' stream comes back or the user changes channel.

sub _enterOutageLoop()
    m.outageLoopCycleCount = m.outageLoopCycleCount + 1
    _showReconnectOverlay(false)   ' sets m.reconnectState = "outage"
    if m.outageLoopCycleCount >= 2 then
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

    deviceInfo = CreateObject("roDeviceInfo")
    if deviceInfo.GetConnectionType() = "none" then
        print ">>> OUTAGE: Network down during stream retry — switching to network poll"
        _enterNetworkWait()
        return
    end if

    print ">>> OUTAGE: Retrying stream"
    m.retryCount             = 0
    m.cacheWasAttempted      = false
    m.manifestPatchAttempted = false
    m.isNimbleStream         = false
    m.proxyOriginalUrl       = ""
    ' Stop any stale proxy — it may have session tokens that expired.
    ' The fresh load will restart it via the cache fast-path (useProxy=true).
    if m.localProxy <> invalid and m.localProxy.status <> "idle" and m.localProxy.status <> "stopped" then
        print ">>> OUTAGE: Stopping stale proxy before retry"
        m.localProxy.stopProxy = true
    end if
    updateReconnectStatus("Reconnecting...")
    updateReconnectCountdown("")

    channel = _currentChannel()

    ' Use channel.url, not lastWorkingContent — for proxy channels,
    ' lastWorkingContent.url is http://IP:7171/master which is session-specific,
    ' causes a cache miss, and bypasses the useProxy fast-path in playChannel().
    if channel <> invalid then
        m.pendingHeaders = _resolveHeaders(channel)
        freshContent = _makeContentNode(channel.url, channel.title, channel)
        _applyContentAndPlay(freshContent)
    else
        m.reconnectState = "idle"
        hideReconnectingOverlay()
        showChannelError("Stream could not be restored.")
    end if
end sub
