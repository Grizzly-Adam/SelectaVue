' ==================== NetworkDownProtocol.brs ====================
' Entered when the device has no network connection at all (detected
' either up front or mid-retry). Polls every 10 seconds until connectivity
' returns, then resets the retry ladder state and attempts a clean reload.

' ---------- Network down protocol ----------

sub _enterNetworkWait()
    cancelStreamRetryTimer()
    cancelCountdownTickTimer()
    ' Shader on for network-down
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
        m.reconnectState = "idle"
        ' Reset retry state so ladder starts fresh
        m.retryCount             = 0
        m.cacheWasAttempted      = false
        m.bandwidthProbeIndex    = 0
        m.manifestPatchAttempted = false
        m.isNimbleStream         = false
        ' Attempt reload
        updateReconnectStatus("Network restored — reconnecting...")
        updateReconnectCountdown("")
        cancelCountdownTickTimer()

        channel = _currentChannel()

        if m.lastWorkingContent <> invalid then
            m.pendingHeaders = _resolveHeaders(channel)
            _applyContentAndPlay(m.lastWorkingContent)
        else if channel <> invalid then
            freshContent = _makeContentNode(channel.url, channel.title, channel)
            _applyContentAndPlay(freshContent)
        else
            hideReconnectingOverlay()
            showChannelError("Network restored but no stream to reload.")
        end if
    end if
end sub
