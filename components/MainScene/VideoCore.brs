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
    m.retryCount             = 0
    m.manifestPatchAttempted = false
    m.isNimbleStream         = false
    m.pendingHeaders          = { ua: "", ref: "", cookie: "" }
    m.cacheWasAttempted      = false
    m.pendingRetryContent    = invalid
    m.bandwidthProbeIndex    = 0
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
    ' Stop LocalProxy so port 7171 is freed -- allows clean restart on return
    if m.localProxy <> invalid then
        if m.localProxy.status <> "idle" and m.localProxy.status <> "stopped" then
            print ">>> PROXY: Stopping LocalProxy on reset (was: "; m.localProxy.status; ")"
            m.localProxy.stopProxy = true  ' signals running thread to exit cleanly
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
    hideReconnectingOverlay()
end sub

' ---------- Internal: apply a content node and start playback ----------

sub _applyContentAndPlay(content as Object)
    ' Always enable cookies -- cookieCheck=1 stores hlsSession which is needed
    ' for cookie-auth segment requests (segments without ?session= token)
    m.previewVideo.EnableCookies()
    m.previewVideo.SetCertificatesFile("common:/certs/ca-bundle.crt")
    m.previewVideo.InitClientCertificates()
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

    channel = getChannelByFocusIndex(channelIndex)
    if channel = invalid and channelIndex >= 0 and channelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[channelIndex]
    end if
    if channel = invalid or channel.url = invalid then return

    ' Skip reload if already actively playing this channel
    if _isChannelActivelyLoaded(channel.url) then return

    ' Save outgoing channel as previous before reset clears loading index
    if m.loadingChannelIndex >= 0 then
        m.previousChannelIndex = m.loadingChannelIndex
    else if m.currentChannelIndex >= 0 then
        m.previousChannelIndex = m.currentChannelIndex
    end if

    _resetRetryState()
    hidePreviewError()
    m.loadingChannelIndex = channelIndex
    startChannelLoadBufferTimer()

    print ">>> PREVIEW: "; channel.title

    if m.previewChannelNameLabel     <> invalid then m.previewChannelNameLabel.text      = cleanChannelTitle(channel)
    if m.previewChannelNameContainer <> invalid then m.previewChannelNameContainer.visible = true
    _updatePreviewLogo(channel)

    ' Check settings cache first
    cached = lookupCachedSettings(channel.url)
    if cached <> invalid then
        previewContent = buildContentFromCache(cached, channel)
        previewContent.MaxBandwidth = 5000000   ' conservative cap for preview even when cached
        print ">>> PREVIEW: Using cached settings"
    else
        previewContent = _makeContentNode(channel.url, channel.title, channel)
        previewContent.MaxBandwidth = 5000000
    end if

    _setPreviewGeometry()
    ' Set pending headers so _applyContentAndPlay can AddHeader correctly
    m.pendingHeaders = _resolveHeaders(channel)
    _applyContentAndPlay(previewContent)
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
    if m.previewVideo = invalid or m.previewVideo.content = invalid then return false
    state = m.previewVideo.state
    if state <> "playing" and state <> "buffering" and state <> "paused" then return false
    ' Direct URL match (normal streams)
    if m.previewVideo.content.url = url then return true
    ' Proxy streams: content.url is http://IP:7171/master but the channel url
    ' is the original https:// stream. Match via m.proxyOriginalUrl.
    if m.proxyOriginalUrl <> "" and m.proxyOriginalUrl = url then return true
    return false
end function

sub playChannel(content as Object)
    hideChannelBar()

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
        print ">>> PLAY: "; content.title

        ' Save the channel we're LEAVING as previous, before loadingChannelIndex is overwritten
        if m.loadingChannelIndex >= 0 then
            m.previousChannelIndex = m.loadingChannelIndex
        end if
        m.loadingChannelIndex = m.currentChannelIndex

        ' Check settings cache
        cached = invalid
        if channel <> invalid then cached = lookupCachedSettings(channel.url)
        if cached <> invalid then
            freshContent = buildContentFromCache(cached, channel)
            freshContent.MaxBandwidth = 0
            print ">>> PLAY: Using cached settings"
        else
            freshContent = _makeContentNode(content.url, content.title, channel)
            freshContent.MaxBandwidth = 0
        end if

        _resetRetryState()
        m.loadingChannelIndex = m.currentChannelIndex   ' restore after reset

        ' Set pending headers for _applyContentAndPlay
        m.pendingHeaders = _resolveHeaders(channel)
        _applyContentAndPlay(freshContent)
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

    if channel <> invalid then showChannelBar(channel)

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
    iconUrl = _bestIconUrl(channel)
    m.previewChannelLogo.uri     = iconUrl
    m.previewChannelLogo.visible = (iconUrl <> "")
end sub
