' ==================== ManifestCallbacks.brs ====================
' onManifestPatched — handles patcher results.
' onProxyStatusChanged — fires when the local HTTP proxy is ready.

sub onManifestPatched()
    result = m.manifestPatcher.result
    if result = invalid then return

    print ">>> PATCHER: patched="; result.patched; " error="; result.error; " url="; result.url
    print ">>> PATCHER: useProxy="; iif(result.useProxy = true, "true", "false")

    ' Guard: if pendingRetryContent was cleared (user navigated away during async patch),
    ' discard this result — it belongs to the old channel.
    ' For useProxy=true: the proxy callback has its own pendingProxyContent=invalid guard
    ' which stops a stale proxy, but we still check loadingChannelIndex for consistency.
    if m.pendingRetryContent = invalid and result.useProxy <> true then
        print ">>> PATCHER: Stale result (pendingRetryContent cleared) -- discarding"
        return
    end if
    if m.loadingChannelIndex < 0 then
        print ">>> PATCHER: Stale result (no active channel) -- discarding"
        m.pendingRetryContent = invalid
        return
    end if

    ' Handle useProxy: start LocalProxy HTTP server instead of playing directly.
    ' Proxy serves http://localIP:7171/master so Roku HLS engine fetches segments
    ' natively with no tmp: sandbox restriction. Audio groups work natively too.
    if result.useProxy = true then
        channel = _currentChannel()
        content = m.pendingRetryContent
        m.pendingRetryContent = invalid
        if content = invalid then
            print ">>> PROXY: No pendingRetryContent -- creating fresh content node"
            content = _makeContentNode(result.url, "", channel)
        end if
        _startLocalProxy(result.url, content)
        return
    end if

    content = m.pendingRetryContent
    m.pendingRetryContent = invalid
    if content = invalid then return

    if result.error <> "" then
        if result.error = "Empty response from server" then
            ' Direct proof the origin didn't respond at all to a plain HTTP
            ' fetch -- not a bandwidth or adaptation problem the remaining
            ' ladder steps could plausibly fix, so skip the 8Mbps probe
            ' (and the ~20s stall wait it'd otherwise burn) and short-circuit
            ' straight to the same outcome the ladder would reach anyway once
            ' exhausted -- see the "Ladder exhausted" branch in
            ' RetryLadder.brs, mirrored here.
            print ">>> PATCHER: Empty response from server -- source is dead, skipping remaining retries"
            hideBufferBar()
            cancelStallTimer()
            if m.streamWasPlaying then
                print ">>> PATCHER: Entering outage loop (stream was playing)"
                _enterOutageLoop()
            else
                print ">>> PATCHER: Giving up (never played)"
                _cancelNamedTimer("sessionRefreshTimer")
                showGaveUpState(getFriendlyError(result.error))
                if m.isPlayingVideo then resetFullscreenInactivityTimer() else resetGridInactivityTimer()
            end if
            return
        end if
        print ">>> PATCHER: Fetch failed -- escalating to 8Mbps probe"
        m.retryCount = 2   ' retryStream() increments to 3 = 8Mbps step
        m.manifestPatchAttempted = true
        retryStream("Manifest fetch failed: " + result.error)
        return
    end if

    if result.isNimble = true then
        print ">>> PATCHER: Nimble stream -- fast-path on future retries"
        m.isNimbleStream = true
    end if

    content.url          = result.url
    content.streamFormat = iif(result.url.EndsWith("mpegts"), "ts", "hls")

    channel = invalid
    if m.flatChannelList <> invalid and m.loadingChannelIndex >= 0 and m.loadingChannelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[m.loadingChannelIndex]
    end if
    m.pendingHeaders = _resolveHeaders(channel)
    _applyContentAndPlay(content)
end sub

' ---------- Local proxy ready ----------
' Called when LocalProxy binds its socket and reports its URL.
' Point the pending content node at the proxy URL and start playback.

sub onProxyStatusChanged()
    status = m.localProxy.status
    print ">>> PROXY [callback]: Status changed: "; status

    if Left(status, 6) = "error:" then
        print ">>> PROXY [callback]: Proxy error -- "; status
        m.pendingProxyContent = invalid
        m.proxyOriginalUrl    = ""
        ' Escalate to the 8Mbps bandwidth probe (Step 3 in the new ladder).
        ' We set retryCount=2 with manifestPatchAttempted=true so retryStream()
        ' increments to 3 and lands on the bandwidth probe — skipping the patcher
        ' which would just return useProxy=true again and loop.
        print ">>> PROXY [callback]: Escalating to 8Mbps bandwidth probe"
        m.retryCount = 2
        m.manifestPatchAttempted = true
        retryStream("Proxy failed: " + status)
        return
    end if

    if Left(status, 6) <> "ready:" then return  ' "stopped", "idle" -- ignore

    proxyUrl = Mid(status, 7)
    if proxyUrl = "" then return
    print ">>> PROXY [callback]: Ready at "; proxyUrl

    ' Guard: if pendingProxyContent was cleared (user navigated away),
    ' stop the proxy immediately -- it started for the wrong channel.
    if m.pendingProxyContent = invalid then
        print ">>> PROXY [callback]: Stale proxy (pendingProxyContent cleared) -- stopping"
        m.localProxy.stopProxy = true
        m.proxyOriginalUrl = ""
        return
    end if

    content = m.pendingProxyContent
    m.pendingProxyContent = invalid
    if content = invalid then
        ' Race: callback fired before pendingProxyContent was set -- reconstruct from channel
        print ">>> PROXY [callback]: No pending content -- reconstructing from current channel"
        channel = _currentChannel()
        if channel = invalid then return
        content = _makeContentNode(channel.url, iif(channel.title <> invalid, channel.title, ""), channel)
    end if

    content.url          = proxyUrl
    content.streamFormat = "hls"
    content.live         = true

    channel = invalid
    if m.flatChannelList <> invalid and m.loadingChannelIndex >= 0 and m.loadingChannelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[m.loadingChannelIndex]
    end if

    ' Track the original channel URL so _isChannelActivelyLoaded can match
    ' channel.url (original) against the proxy URL (http://IP:7171/master).
    ' Without this, OK on a playing proxy channel reloads instead of going fullscreen.
    m.proxyOriginalUrl = iif(channel <> invalid and channel.url <> invalid, channel.url, "")

    ' Write useProxy=true directly to settings cache so second load skips retry ladder
    if channel <> invalid and channel.url <> invalid and channel.url <> "" then
        entry = {
            url              : channel.url,
            title            : iif(content.title <> invalid, content.title, ""),
            streamFormat     : "hls",
            switchingStrategy: "full-adaptation",
            maxBandwidth     : 0,
            useProxy         : true
        }
        if m.persistentSettingsCache.DoesExist(channel.url) then
            m.persistentSettingsCache[channel.url] = entry
            _savePersistentCache()
        else
            _addToSessionCache(channel.url, entry)
            m.pendingCacheUrl = channel.url
            _startNamedTimer("settingsCacheTimer", 120.0, false, "onSettingsCacheTimerFired")
        end if
        print ">>> PROXY [callback]: Cached useProxy=true for: "; channel.url
    end if

    headers = _resolveHeaders(channel)
    print ">>> PROXY [callback]: Playing via proxy -- UA: "; headers.ua
    m.pendingHeaders = headers
    _applyContentAndPlay(content)
end sub
