' ==================== NetworkDownProtocol.brs ====================
' Entered when the device has no network connection. Polls every 10 seconds
' until connectivity returns, then resets ladder state and retries.

sub _enterNetworkWait()
    cancelStreamRetryTimer()
    cancelCountdownTickTimer()
    if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = true
    _showReconnectOverlay(true)   ' sets m.reconnectState = "network"
    _startNetworkPollTimer(10)
end sub

sub _startNetworkPollTimer(seconds as Integer)
    m.reconnectCountdown = seconds
    updateReconnectCountdown(m.reconnectCountdown)
    _startNamedTimer("networkPollTimer", seconds, false, "onNetworkPollFired")
    startCountdownTick()
end sub

sub onNetworkPollFired()
    m.networkPollTimer = invalid
    if m.reconnectState <> "network" then return

    deviceInfo = CreateObject("roDeviceInfo")
    if deviceInfo.GetConnectionType() = "none" then
        print ">>> NETWORK: Still down, polling again"
        _startNetworkPollTimer(10)
    else
        print ">>> NETWORK: Connection restored"
        m.reconnectState         = "idle"
        m.retryCount             = 0
        m.cacheWasAttempted      = false
        m.manifestPatchAttempted = false
        m.isNimbleStream         = false
        m.proxyOriginalUrl       = ""
        ' Stop any stale proxy — connection was lost so its session is dead.
        ' Bug F fix: outage loop does this, network restore must too.
        if m.localProxy <> invalid and m.localProxy.status <> "idle" and m.localProxy.status <> "stopped" then
            print ">>> NETWORK: Stopping stale proxy before reload"
            m.localProxy.stopProxy = true
        end if
        updateReconnectStatus("Network restored — reconnecting...")
        updateReconnectCountdown("")
        cancelCountdownTickTimer()

        channel = _currentChannel()

        ' Use channel.url, not lastWorkingContent — proxy channels have a
        ' session-specific proxy URL in lastWorkingContent that is useless
        ' after a network outage and causes the cache lookup to miss.
        ' Bug F fix: same root cause as PATH E in outage loop.
        if channel <> invalid then
            m.pendingHeaders = _resolveHeaders(channel)
            freshContent = _makeContentNode(channel.url, channel.title, channel)
            _applyContentAndPlay(freshContent)
        else
            hideReconnectingOverlay()
            showChannelError("Network restored but no stream to reload.")
        end if
    end if
end sub
