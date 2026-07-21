' ==================== RetryLadder.brs ====================
' The unified retry ladder. All entry points call retryStream(reason).
' When exhausted, hands off to the outage loop or gave-up state.
'
' Step 0 (retryCount=1, cache hit):   cached settings (useProxy fast-path if flagged)
' Step 1 (retryCount=1, no cache):    no-adaptation + _HLS_skip=NO (merged compat step)
' Step 2 (retryCount=2):              ManifestPatcher (async — rewrites manifest/proxy)
' Step 3 (retryCount=3):              8Mbps bandwidth cap (single probe)
' Step 4+ (retryCount=4):             outage loop or gave-up

sub retryStream(reason as String)
    content = m.previewVideo.content
    if content = invalid then
        showGaveUpState(getFriendlyError(""))
        return
    end if

    m.retryCount = m.retryCount + 1
    print ">>> RETRY "; m.retryCount; ": "; reason; " (t="; _loadElapsedMs(); "ms)"

    channel = _currentChannel()

    ' Normalize the URL — resolves an active proxy session back to the
    ' original channel URL and strips any _HLS_skip suffix — all retry steps
    ' work from this clean base. See _normalizeChannelUrl() in Utils.brs.
    if m.proxyOriginalUrl <> "" and Left(LCase(content.url), 7) = "http://" and content.url.InStr(":7171/") >= 0 then
        print ">>> RETRY: Resolving proxy URL to original: "; m.proxyOriginalUrl
    end if
    cleanUrl = _normalizeChannelUrl(content.url)

    if m.retryCount = 1 then
        ' --- Step 0: try cached settings ---
        ' Skip if the initial play already used the cache (cacheWasAttempted=true)
        ' to avoid replaying settings we just tried and know failed.
        if not m.cacheWasAttempted then
            cached = lookupCachedSettings(cleanUrl)
            if cached <> invalid then
                if cached.useProxy = true then
                    print ">>> RETRY 0: Cache says useProxy=true -- starting proxy immediately"
                    showRetryStatus("Starting stream proxy...")
                    m.manifestPatchAttempted = true
                    _startLocalProxy(cleanUrl, _makeContentNode(cleanUrl, content.title, channel))
                    return
                end if
                print ">>> RETRY 0: Using cached settings"
                showRetryStatus("Trying last known settings...")
                cachedContent = buildContentFromCache(cached, channel)
                m.cacheWasAttempted = true
                _applyContentAndPlay(cachedContent)
                return
            end if
        end if

        ' No cache — check for known fast-path signals
        m.cacheWasAttempted = false
        skipToPatcher = (m.isNimbleStream and not m.manifestPatchAttempted) or (LCase(m.savedErrorStr).InStr("unsupported version") >= 0 and not m.manifestPatchAttempted)
        if skipToPatcher then
            print ">>> RETRY 1: Fast-path to ManifestPatcher"
            showRetryStatus("Analyzing stream...")
            m.retryCount = 1   ' will be incremented to 2 = patcher step
            retryStream(reason)
            return
        end if

        ' --- Step 1: merged compat attempt ---
        ' Combines old steps 1+2: no-adaptation + _HLS_skip=NO in a single attempt.
        ' Saves one full error-delay cycle vs the old two-step approach.
        print ">>> RETRY 1: no-adaptation + _HLS_skip=NO"
        showRetryStatus("Trying compatibility mode...")
        freshContent = _makeContentNode(cleanUrl, content.title, channel)
        freshContent.SwitchingStrategy = "no-adaptation"
        freshContent.url = cleanUrl + iif(cleanUrl.InStr("?") >= 0, "&", "?") + "_HLS_skip=NO"
        _applyContentAndPlay(freshContent)

    else if m.retryCount = 2 then
        ' Handle post-cache fallthrough (cache failed → run compat step first)
        if m.cacheWasAttempted then
            print ">>> RETRY 1 (post-cache): no-adaptation + _HLS_skip=NO"
            m.cacheWasAttempted = false
            showRetryStatus("Trying compatibility mode...")
            freshContent = _makeContentNode(cleanUrl, content.title, channel)
            freshContent.SwitchingStrategy = "no-adaptation"
            freshContent.url = cleanUrl + iif(cleanUrl.InStr("?") >= 0, "&", "?") + "_HLS_skip=NO"
            m.retryCount = 1
            _applyContentAndPlay(freshContent)
            return
        end if

        ' --- Step 2: ManifestPatcher ---
        if m.manifestPatchAttempted then
            ' Patcher already ran (e.g. proxy error escalation) — skip to 8Mbps
            retryStream(reason)
            return
        end if

        ' ManifestPatcher fetches and parses HLS text manifests -- it has no
        ' business being pointed at a raw continuous MPEG-TS feed (streamFormat
        ' "ts"). _fetch() would block trying to read that stream to completion,
        ' which for a live feed never happens, so this step would just sit on
        ' a connection timeout instead of failing fast. Mark it attempted and
        ' skip straight to the next step for these.
        if content.streamFormat = "ts" then
            print ">>> RETRY 2: Skipping ManifestPatcher — streamFormat=ts (raw MPEG-TS, not an HLS manifest)"
            m.manifestPatchAttempted = true
            retryStream(reason)
            return
        end if

        print ">>> RETRY 2: Running ManifestPatcher"
        showRetryStatus("Analyzing stream manifest...")
        m.manifestPatchAttempted = true
        patchContent = _makeContentNode(cleanUrl, content.title, channel)
        m.pendingRetryContent = patchContent
        if m.manifestPatcher <> invalid then
            headers = _resolveHeaders(channel)
            m.manifestPatcher.url       = cleanUrl
            m.manifestPatcher.userAgent = headers.ua
            m.manifestPatcher.referrer  = headers.ref
            m.manifestPatcher.control   = "RUN"
        else
            ' manifestPatcher node missing — escalate directly to 8Mbps probe
            retryStream(reason)
        end if

    else if m.retryCount = 3 then
        ' --- Step 3: single 8Mbps bandwidth cap ---
        ' Lower caps (4/2/1Mbps) have never proven useful — streams that fail
        ' at 8Mbps fail due to auth or manifest issues, not bandwidth.
        print ">>> RETRY 3: 8Mbps bandwidth cap"
        showRetryStatus("Trying with bandwidth limit...")
        freshContent = _makeContentNode(cleanUrl, content.title, channel)
        freshContent.SwitchingStrategy = "no-adaptation"
        freshContent.MaxBandwidth      = 8000000
        _applyContentAndPlay(freshContent)

    else
        ' Ladder exhausted
        print ">>> RETRY: Ladder exhausted"
        hideBufferBar()
        cancelStallTimer()
        if m.streamWasPlaying then
            print ">>> RETRY: Entering outage loop (stream was playing)"
            _enterOutageLoop()
        else
            print ">>> RETRY: Giving up (never played)"
            _cancelNamedTimer("sessionRefreshTimer")
            showGaveUpState(getFriendlyError(m.savedErrorMsg))
            if m.isPlayingVideo then resetFullscreenInactivityTimer() else resetGridInactivityTimer()
        end if
    end if
end sub
