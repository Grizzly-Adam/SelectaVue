' ==================== RetryLadder.brs ====================
' The unified retry ladder itself (steps 0-5+). All entry points call
' retryStream(reason). When the ladder is exhausted it hands off to
' either the outage loop (StreamOutageLoop.brs) or the gave-up state,
' depending on whether the stream had previously played successfully.

' ---------- UNIFIED RETRY LADDER ----------
'
' Step 0 (retryCount=1, cache hit):  cached settings
' Step 1 (retryCount=1, no cache):   no-adaptation + clear maxBandwidth, fresh node
' Step 2 (retryCount=2):             2.5 Mbps + _HLS_skip=NO, fresh node
' Step 3 (retryCount=3, NEW):        bare-minimum headers — no UA, no Referer, no strategy
' Step 4 (retryCount=4):             ManifestPatcher (async)
' Step 5 (retryCount=5):             bandwidth probing 8→4→2→1 Mbps
' Step 6+ (retryCount=6):            if streamWasPlaying → outage loop; else → gave-up state

sub retryStream(reason as String)
    content = m.previewVideo.content
    if content = invalid then
        showGaveUpState(getFriendlyError(""))
        return
    end if

    m.retryCount = m.retryCount + 1
    print ">>> RETRY "; m.retryCount; ": "; reason

    channel = _currentChannel()

    ' Strip _HLS_skip from URL — all steps work on the clean URL
    cleanUrl = content.url
    sepPos = cleanUrl.InStr("&_HLS_skip")
    if sepPos > 0 then cleanUrl = Left(cleanUrl, sepPos)
    sepPos = cleanUrl.InStr("?_HLS_skip")
    if sepPos > 0 then cleanUrl = Left(cleanUrl, sepPos)

    if m.retryCount = 1 then
        ' --- Step 0: try cached settings ---
        cached = lookupCachedSettings(cleanUrl)
        if cached <> invalid then
            ' Fast-path: if this channel previously needed the proxy, start it immediately
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
        ' No cache — check if we should skip straight to ManifestPatcher
        m.cacheWasAttempted = false
        skipToPatcher = (m.isNimbleStream and not m.manifestPatchAttempted) or (LCase(m.savedErrorStr).InStr("unsupported version") >= 0 and not m.manifestPatchAttempted)
        if skipToPatcher then
            print ">>> RETRY 1: Fast-path to ManifestPatcher (Nimble="; m.isNimbleStream; " VersionErr="; (LCase(m.savedErrorStr).InStr("unsupported version") >= 0); ")"
            showRetryStatus("Analyzing stream...")
            m.retryCount = 3   ' will be incremented to 4 = patcher step
            retryStream(reason)
            return
        end if
        print ">>> RETRY 1: no-adaptation, clear maxBandwidth, fresh node"
        showRetryStatus("Trying compatibility mode...")
        freshContent = _makeContentNode(cleanUrl, content.title, channel)
        freshContent.SwitchingStrategy = "no-adaptation"
        _applyContentAndPlay(freshContent)

    else if m.retryCount = 2 then
        if m.cacheWasAttempted then
            ' Cache failed — run step 1 before step 2
            print ">>> RETRY 1 (post-cache): no-adaptation, fresh node"
            m.cacheWasAttempted = false
            showRetryStatus("Trying compatibility mode...")
            freshContent = _makeContentNode(cleanUrl, content.title, channel)
            freshContent.SwitchingStrategy = "no-adaptation"
            m.retryCount = 1
            _applyContentAndPlay(freshContent)
        else
            print ">>> RETRY 2: 2.5 Mbps + _HLS_skip=NO, fresh node"
            showRetryStatus("Trying with reduced bandwidth...")
            freshContent = _makeContentNode(cleanUrl, content.title, channel)
            freshContent.SwitchingStrategy   = "no-adaptation"
            freshContent.MaxBandwidth = 2500000
            freshContent.url = cleanUrl + iif(cleanUrl.InStr("?") >= 0, "&", "?") + "_HLS_skip=NO"
            _applyContentAndPlay(freshContent)
        end if

    else if m.retryCount = 3 then
        ' --- Step 3 (NEW): bare-minimum headers — strip UA, Referer, strategy ---
        print ">>> RETRY 3: bare-minimum settings, no custom headers"
        showRetryStatus("Trying with minimal settings...")
        bareContent = CreateObject("roSGNode", "ContentNode")
        bareContent.url         = cleanUrl
        bareContent.title       = content.title
        bareContent.streamFormat = detectStreamFormat(cleanUrl)  ' not hardcoded — respects DASH and TS streams
        bareContent.live        = true
        ' Deliberately no HttpHeaders, no SwitchingStrategy, no MaxBandwidth —
        ' clear pending header state too, or _applyContentAndPlay would still
        ' AddHeader() whatever UA/Referer/Cookie was left over from a prior step.
        m.pendingHeaders = { ua: "", ref: "", cookie: "" }
        _applyContentAndPlay(bareContent)

    else if m.retryCount = 4 then
        if m.manifestPatchAttempted then
            m.retryCount = 5
            retryStream(reason)
            return
        end if
        print ">>> RETRY 4: Running ManifestPatcher"
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
            m.retryCount = 5
            retryStream(reason)
        end if

    else if m.retryCount = 5 then
        bandwidths = [8000000, 4000000, 2000000, 1000000]
        if m.bandwidthProbeIndex < bandwidths.Count() then
            bw = bandwidths[m.bandwidthProbeIndex]
            print ">>> RETRY 5." + m.bandwidthProbeIndex.ToStr() + ": probing at "; bw; " bps"
            showRetryStatus("Trying at " + (bw / 1000000).ToStr() + " Mbps...")
            freshContent = _makeContentNode(cleanUrl, content.title, channel)
            freshContent.SwitchingStrategy   = "no-adaptation"
            freshContent.MaxBandwidth = bw
            m.bandwidthProbeIndex       = m.bandwidthProbeIndex + 1
            m.retryCount = 4   ' reset so next error increments back to 5, staying in this block
            _applyContentAndPlay(freshContent)
        else
            m.retryCount = 5   ' will be incremented to 6 → hits else branch
            retryStream(reason)
        end if

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
