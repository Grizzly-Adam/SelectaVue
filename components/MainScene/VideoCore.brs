' ==================== VideoCore.brs ====================
' User-agent constant, content node factory, geometry helpers, pending headers,
'  play/preview/fullscreen entry points, and header-resolution helpers.

function USER_AGENT_DEFAULT() as String
    return "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36"
end function

' ---------- Shared video geometry helpers ----------

sub _setPreviewGeometry()
    m.previewVideo.translation = [1380, 145]
    m.previewVideo.width       = 444
    m.previewVideo.height      = 250
    ' Clips the left edge (60px) of the preview — this node is shared with
    ' fullscreen, so _setFullscreenGeometry() must explicitly reset this to
    ' a full-frame rect or the clip carries over and mangles the fullscreen
    ' video.
    m.previewVideo.clippingRect = [60, 0, 384, 250]
    m.previewVideo.trickplaybarvisibilityauto = true
end sub

sub _setFullscreenGeometry()
    m.previewVideo.translation  = [0, 0]
    m.previewVideo.width        = 1920
    m.previewVideo.height       = 1080
    ' Explicit full-frame rect rather than [] — makes "unclipped" concrete
    ' instead of relying on empty-array semantics, which the Video node's
    ' hardware overlay plane may not honor as reliably as a real rect.
    m.previewVideo.clippingRect = [0, 0, 1920, 1080]
    m.previewVideo.trickplaybarvisibilityauto = false
end sub

' ---------- Content node factory ----------

function _makeContentNode(url as String, title as String, channel as Object) as Object
    c = CreateObject("roSGNode", "ContentNode")
    c.url                        = url
    c.title                      = title
    c.streamFormat               = detectStreamFormat(url)
    c.SwitchingStrategy          = "full-adaptation"
    c.live                       = true         ' treat as live — correct for IPTV; minor side-effect on VOD
    c.MinBandwidth               = 0            ' explicit default prevents Roku rejecting low-bitrate variants
    c.HttpSendClientCertificates = false        ' public IPTV streams don't use client certs; sending them can cause handshake issues
    c.HttpCertificatesFile       = "common:/certs/ca-bundle.crt"

    m.pendingHeaders = _resolveHeaders(channel)

    ' Apply soft step-down bandwidth cap if active
    if m.softStepBandwidth > 0 then
        c.MaxBandwidth = m.softStepBandwidth
    end if

    return c
end function

' ---------- Reset all retry/outage state for a new channel ----------

sub _resetRetryState()
    _resetRetryCounters()
    hideReconnectingOverlay()
end sub

' Resets all retry counters and in-flight async state without touching the
' reconnect overlay. Used internally and by reloadCurrentChannel so a RETRY
' press can reset the ladder while keeping the overlay visible.
sub _resetRetryCounters()
    m.retryCount             = 0
    m.manifestPatchAttempted = false
    m.isNimbleStream         = false
    m.pendingHeaders          = { ua: "", ref: "", cookie: "" }
    m.cacheWasAttempted      = false
    m.pendingRetryContent    = invalid
    m.softStepCount          = 0
    m.softStepBandwidth      = 0
    m.slowBufferStartTime    = invalid
    m.lastBufferPct          = -1
    m.lastError              = { msg: "", channelIndex: -1 }
    m.lastWorkingContent     = invalid
    m.streamWasPlaying       = false
    m.reconnectState         = "idle"
    m.reconnectCountdown     = 0
    m.loadingChannelIndex    = -1
    m.savedErrorMsg          = ""
    m.savedErrorStr          = ""
    ' Stop LocalProxy so port 7171 is freed — allows clean restart on return
    if m.localProxy <> invalid then
        if m.localProxy.status <> "idle" and m.localProxy.status <> "stopped" then
            print ">>> PROXY: Stopping LocalProxy on reset (was: "; m.localProxy.status; ")"
            m.localProxy.stopProxy = true
        end if
        m.pendingProxyContent = invalid
        m.proxyOriginalUrl    = ""
    end if
    m.outageLoopCycleCount   = 0
    _cancelNamedTimer("sessionRefreshTimer")
    cancelStallTimer()
    cancelSlowBufferRecoveryTimer()
    cancelErrorDelayTimer()
    cancelNetworkPollTimer()
    cancelStreamRetryTimer()
    cancelCountdownTickTimer()
    cancelSettingsCacheTimer()
end sub

' ---------- Internal: apply a content node and start playback ----------

sub _applyContentAndPlay(content as Object)
    stopPreviewVideo()
    m.previewVideo.content = invalid
    ' Apply headers via AddHeader BEFORE content assignment
    ' ContentNode.HttpHeaders is unreliable on this firmware (stores as [[]])
    if m.pendingHeaders.ua <> invalid and m.pendingHeaders.ua <> "" then
        m.previewVideo.AddHeader("User-Agent", m.pendingHeaders.ua)
        print ">>> VIDEO AddHeader User-Agent=["; m.pendingHeaders.ua; "]"
    end if
    if m.pendingHeaders.ref <> invalid and m.pendingHeaders.ref <> "" then
        m.previewVideo.AddHeader("Referer", m.pendingHeaders.ref)
        print ">>> VIDEO AddHeader Referer=["; m.pendingHeaders.ref; "]"
    end if
    if m.pendingHeaders.cookie <> invalid and m.pendingHeaders.cookie <> "" then
        m.previewVideo.AddHeader("Cookie", m.pendingHeaders.cookie)
        print ">>> VIDEO AddHeader Cookie=["; m.pendingHeaders.cookie; "]"
    end if
    m.previewVideo.content = content
    print ">>> VIDEO PLAY: url="; content.url; " format="; content.streamFormat; " live="; content.live
    m.previewVideo.control = "play"
end sub



' ---------- Preview ----------

sub playPreviewChannel(channelIndex as Integer)
    if m.previewVideo = invalid then return
    if m.flatChannelList = invalid or m.flatChannelList.Count() = 0 then return

    channel = invalid
    if channelIndex >= 0 and channelIndex < m.flatChannelList.Count() then channel = m.flatChannelList[channelIndex]
    if channel = invalid then channel = getChannelByFocusIndex(channelIndex)   ' fallback -- shouldn't normally be needed
    if channel = invalid or channel.url = invalid then return

    ' Same pin-removal as playChannel() (see comment there). Safe here too --
    ' the pin lives at the tail of flatChannelList, so removing it doesn't
    ' shift channelIndex/currentChannelIndex, which both refer to a position
    ' earlier in the list (this genuinely different channel).
    _clearNowPlayingPinIfChanging(channel.url)
    m.replayFallbackActive = false   ' a real channel action -- exit replay-toggle mode

    ' Skip reload if already actively playing this channel
    if _isChannelActivelyLoaded(channel.url) then return

    _resetRetryState()
    hidePreviewError()
    m.loadingChannelIndex = channelIndex
    startChannelLoadBufferTimer()

    print ">>> PREVIEW: "; channel.title

    if m.previewChannelNameLabel     <> invalid then m.previewChannelNameLabel.text      = cleanChannelTitle(channel)
    if m.previewChannelNameContainer <> invalid then m.previewChannelNameContainer.visible = true
    _updatePreviewLogo(channel)

    ' Check settings cache. For proxy channels, skip the doomed plain URL
    ' attempt and go straight to the proxy.
    cached = lookupCachedSettings(channel.url)
    if cached <> invalid then
        if cached.useProxy = true then
            print ">>> PREVIEW: Cache says useProxy=true — starting proxy immediately"
            m.cacheWasAttempted      = true
            m.manifestPatchAttempted = true
            m.pendingHeaders         = _resolveHeaders(channel)
            _setPreviewGeometry()   ' must be called before proxy starts playing
            _startLocalProxy(channel.url, _makeContentNode(channel.url, channel.title, channel))
        else
            previewContent = buildContentFromCache(cached, channel)
            previewContent.MaxBandwidth = 5000000
            m.cacheWasAttempted = true
            print ">>> PREVIEW: Using cached settings"
            _setPreviewGeometry()
            m.pendingHeaders = _resolveHeaders(channel)
            _applyContentAndPlay(previewContent)
        end if
    else
        previewContent = _makeContentNode(channel.url, channel.title, channel)
        previewContent.MaxBandwidth = 5000000
        _setPreviewGeometry()
        m.pendingHeaders = _resolveHeaders(channel)
        _applyContentAndPlay(previewContent)
    end if
end sub

sub stopPreviewVideo()
    if m.previewVideo <> invalid then m.previewVideo.control = "stop"
end sub

' ---------- Fullscreen playback ----------

' Returns true only if the given URL matches what's currently loaded on
' m.previewVideo AND the video is actually in an active state (playing/
' buffering/paused) — not just a stale content reference. Stopping
' playback (e.g. cancelling a retry ladder via up/down) does NOT clear
' m.previewVideo.content, so a bare URL-match check alone wrongly treats a
' channel that failed and was dismissed as "still playing" — which was
' sending a second selection of that same channel straight to fullscreen
' ("Double OK") instead of actually retrying the load.
function _isChannelActivelyLoaded(url as String) as Boolean
    if m.previewVideo = invalid then return false
    state = m.previewVideo.state
    if state = "playing" or state = "buffering" or state = "paused" then
        if m.previewVideo.content = invalid then return false
        ' Direct URL match (normal streams)
        if m.previewVideo.content.url = url then return true
        ' Proxy streams: content.url is channel.url (set in _startLocalProxy) while the
        ' proxy is starting, but state won't be playing/buffering yet — the state check
        ' above correctly gates this. Once the proxy is playing, content.url = proxy URL
        ' and m.proxyOriginalUrl = channel.url — match via that.
        if m.proxyOriginalUrl <> "" and m.proxyOriginalUrl = url then return true
        return false
    end if
    ' Not currently playing/buffering/paused — e.g. between an error and the
    ' retry ladder's first visible step (the ~1.5s error-delay pause in
    ' ErrorDelayTimer.brs), or the video engine briefly resetting its own
    ' state string right after a failure. Rather than gate on the exact
    ' state value (which can bounce unpredictably, e.g. through "none",
    ' right after an error and made this check unreliable), match on
    ' m.loadingChannelIndex — it only gets cleared to -1 by an explicit
    ' cancel or channel change, so it correctly tells us whether we're
    ' still actively working on THIS channel regardless of the video
    ' node's momentary state. Without this, a fast double-OK landing in
    ' that gap looked like "channel not loaded" and restarted
    ' playPreviewChannel() from scratch instead of expanding to fullscreen.
    if m.loadingChannelIndex >= 0 and m.reconnectState <> "gaveup" then
        if m.flatChannelList <> invalid and m.loadingChannelIndex < m.flatChannelList.Count() then
            loadingChannel = m.flatChannelList[m.loadingChannelIndex]
            if loadingChannel <> invalid and loadingChannel.url = url then return true
        end if
    end if
    return false
end function

sub playChannel(content as Object)
    hideChannelBar()

    ' If a "now playing" pin is sitting at the tail of the grid (see
    ' _resyncOrPinCurrentChannel() in Utils.brs) and this is a
    ' genuinely different channel, remove it now -- it's gone the moment we
    ' tune away from it. This runs before the resync block below so that
    ' block re-derives m.currentChannelIndex against the already-updated
    ' (post-removal) flatChannelList.
    if content <> invalid and content.url <> invalid then _clearNowPlayingPinIfChanging(content.url)
    m.replayFallbackActive = false   ' a real channel action -- exit replay-toggle mode

    ' Keep m.currentChannelIndex in sync with what's actually being played.
    ' Everything below (preview name/logo, cached-settings lookup, HTTP
    ' headers, loadingChannelIndex used by the error/reconnect UI) keys off
    ' m.currentChannelIndex rather than the content parameter directly — so
    ' if it had drifted out of sync with content (e.g. a transient
    ' itemFocused event fired with the wrong index during a favorites-star
    ' content-list refresh), all of that would silently show/use the WRONG
    ' channel's info while the right URL still played. Re-deriving the index
    ' from content.url, which is always correct, closes that gap.
    ' Only re-sync if the current index doesn't already point at this URL —
    ' a channel can legitimately appear more than once in the flat list
    ' (e.g. tagged under multiple categories), so blindly taking the first
    ' matching URL would snap back to an earlier duplicate every time and
    ' get channel surfing stuck looping between the same couple of indexes.
    if content <> invalid and content.url <> invalid and m.flatChannelList <> invalid then
        alreadyCorrect = false
        if m.currentChannelIndex >= 0 and m.currentChannelIndex < m.flatChannelList.Count() then
            existing = m.flatChannelList[m.currentChannelIndex]
            if existing <> invalid and existing.url = content.url then alreadyCorrect = true
        end if
        if not alreadyCorrect then
            foundIdx = findChannelIndexByUrl(content.url)
            if foundIdx >= 0 then m.currentChannelIndex = foundIdx
        end if
    end if

    channel = invalid
    if m.flatChannelList <> invalid and m.currentChannelIndex >= 0 and m.currentChannelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[m.currentChannelIndex]
    end if

    ' This is the one place m.playingChannel gets set -- see the field's
    ' comment in MainScene.brs's init block for why it exists separately
    ' from m.currentChannelIndex.
    m.playingChannel = channel

    ' Keep the grid's preview name/logo in sync with whatever is actually
    ' playing, since playChannel() is the entry point for fullscreen launch
    ' (app boot) and channel changes while fullscreen — not just grid preview.
    if channel <> invalid then
        if m.previewChannelNameLabel <> invalid then m.previewChannelNameLabel.text = cleanChannelTitle(channel)
        _updatePreviewLogo(channel)
    end if

    if not _isChannelActivelyLoaded(content.url) then
        hideBufferBar()
        cancelStallTimer()
        startChannelLoadBufferTimer()
        m.channelLoadTimer = CreateObject("roTimespan")
        print ">>> PLAY: "; content.title

        m.loadingChannelIndex = m.currentChannelIndex

        _resetRetryState()
        m.loadingChannelIndex = m.currentChannelIndex   ' restore after reset

        ' Check settings cache AFTER reset so flags survive into the ladder.
        cached = invalid
        if channel <> invalid then cached = lookupCachedSettings(channel.url)
        if cached <> invalid then
            if cached.useProxy = true then
                ' Proxy channel — skip the guaranteed-to-fail plain URL attempt
                ' and go straight to the proxy. Saves one full error + delay cycle.
                print ">>> PLAY: Cache says useProxy=true — starting proxy immediately"
                m.cacheWasAttempted    = true
                m.manifestPatchAttempted = true
                m.pendingHeaders       = _resolveHeaders(channel)
                _startLocalProxy(channel.url, _makeContentNode(channel.url, channel.title, channel))
            else
                freshContent = buildContentFromCache(cached, channel)
                freshContent.MaxBandwidth = 0
                m.cacheWasAttempted = true
                print ">>> PLAY: Using cached settings"
                m.pendingHeaders = _resolveHeaders(channel)
                _applyContentAndPlay(freshContent)
            end if
        else
            freshContent = _makeContentNode(content.url, content.title, channel)
            freshContent.MaxBandwidth = 0
            m.pendingHeaders = _resolveHeaders(channel)
            _applyContentAndPlay(freshContent)
        end if
    else
        print ">>> PLAY: Already playing, expanding to fullscreen"
    end if

    m.top.backgroundURI   = ""
    m.top.backgroundColor = APP_BACKGROUND_TEAL()
    m.previewVideo.visible = true
    _setFullscreenGeometry()

    m.channelList.visible = false
    if m.channelListHeaderLabel <> invalid then m.channelListHeaderLabel.visible = false
    if m.gridBackgroundTexture <> invalid then m.gridBackgroundTexture.visible = false
    m.sidePanel.visible   = false
    hideGridOverlays()

    if m.gridInactivityTimer <> invalid then
        m.gridInactivityTimer.control = "stop"
        m.gridInactivityTimer.unobserveField("fire")
        m.gridInactivityTimer = invalid
    end if
    resetFullscreenInactivityTimer()

    if m.bufferVisible then
        ' Kept in sync with showBufferBar() in BufferBar.brs — above the channel bar.
        m.bufferContainer.translation = [560, 760]
        m.bufferContainer.width       = 800
        m.bufferTrack.width           = 794
        m.bufferLabel.width           = 800
    end if

    hideOverlay()
    m.isPlayingVideo = true

    if channel <> invalid then showChannelBar()

    m.previewVideo.setFocus(false)
    m.channelList.setFocus(false)
    m.playlistList.setFocus(false)
    m.channelOverlayList.setFocus(false)
    m.top.setFocus(true)

    saveLastState()
    print ">>> PLAY: Fullscreen, scene focused"
end sub

' Resolves User-Agent/Referer/Cookie for a channel in one call. The three
' individual resolvers this replaced each independently called
' parseChannelDescription() on the same channel.description string, so
' every "resolve headers" call site was parsing it three times over for
' no reason — this parses it once and returns all three.
function _resolveHeaders(channel as Object) as Object
    ua     = USER_AGENT_DEFAULT()
    ref    = ""
    cookie = ""
    if channel <> invalid then
        parsed = parseChannelDescription(channel.description)
        if parsed <> invalid then
            if parsed.ua <> "" then ua = parsed.ua
            ref    = parsed.ref
            cookie = parsed.cookie
        end if
    end if
    return { ua: ua, ref: ref, cookie: cookie }
end function

' Updates the channel logo Poster shown below the grid preview.
' Hides the Poster entirely if the channel has no tvg-logo, since a
' missing/broken image would otherwise leave a blank or error-state square.
sub _updatePreviewLogo(channel as Object)
    if m.previewChannelLogo = invalid then return
    ' Store the channel this logo belongs to so the loadStatus fallback
    ' uses the right category even if the user surfs away before it loads.
    m.previewChannelLogoChannel = channel
    m.previewChannelLogoRetried = false

    if channel <> invalid and channel.url <> invalid and channel.url = m.iconResolvedUrl and m.iconResolvedUri <> "" then
        ' channelBarLogo already resolved this exact channel's icon -- reuse
        ' it directly, same reasoning as _updateChannelBarLogo() above.
        m.previewChannelLogoRequestedUri = m.iconResolvedUri
        m.previewChannelLogo.uri        = m.iconResolvedUri
        m.previewChannelLogo.visible    = true
        return
    end if

    m.previewChannelLogo.uri     = ""
    m.previewChannelLogo.visible = false
    iconUrl = _bestIconUrl(channel)
    m.previewChannelLogoRequestedUri = iconUrl
    if iconUrl <> "" then
        m.previewChannelLogo.uri     = iconUrl
        m.previewChannelLogo.visible = true
    end if
end sub
