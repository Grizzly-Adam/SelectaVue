' ==================== MainScene.brs ====================
' Scene entry point: initialises node references, state variables,
' and kicks off the first playlist load.
'
' Business logic lives in the companion files:
'   Utils.brs              - iif, detectStreamFormat, BUILTIN_PLAYLIST_COUNT, helpers
'   StateManager.brs        - save / load / restore last playlist + channel
'   PlaylistManager.brs      - playlist data: load/save, side-panel menu, selection
'   PlaylistEditDialogs.brs   - per-playlist Edit Name / Edit URL / Delete dialogs
'   PlaylistAddDialog.brs      - add-new-playlist flow + shared dialog helpers
'   ChannelList.brs              - flat channel list building + lookup
'   ChannelSelection.brs          - channel focus / selection event handlers
'   VideoCore.brs                  - content nodes, geometry, play/preview/fullscreen entry points
'   RetryLadder.brs                 - the unified retry ladder (steps 0-5+)
'   StreamOutageLoop.brs             - retry loop once the ladder is exhausted (stream was playing)
'   NetworkDownProtocol.brs           - network-down detection + polling
'   ErrorDelayTimer.brs                - brief pause before retrying on a clean error
'   ChannelNav.brs                      - channel navigation, reload, video state observer
'   Favorites.brs                        - per-playlist favorites: storage, toggle, favorites grid
'   ChannelBar.brs                        - bottom-third channel bar (Favorite/CC/Details/Live)
'   MediaMenus.brs                         - channel-details dialog
'   Overlays.brs                            - every visual overlay + reconnect overlay
'   BufferBar.brs                            - buffer progress bar + slow-buffer step-down
'   Timers.brs                                - UI inactivity timers (grid/fullscreen/overlay/dialog)
'   PlaybackHealthTimers.brs                   - stall/slow-buffer/countdown/OK-suppression timers
'   SessionRefreshTimer.brs                     - session-token stream refresh
'   InputHandler.brs                             - onKeyEvent: dialog intercept + dispatch
'   FullscreenInput.brs                           - fullscreen key handling
'   GridInput.brs                                  - grid key handling
'   SettingsCache.brs                               - per-channel stream settings cache
'   ManifestCallbacks.brs                            - ManifestPatcher / LocalProxy task callbacks
'   ManifestPatcher/                                  - Task: fetches and patches HLS manifests

sub onHeaderLabelVisibilityChange(event as Object)
    visibleState = event.getData()
    m.channelListHeaderLabelContainer.visible = visibleState
end sub

sub init()
    m.top.backgroundURI   = ""
    m.top.backgroundColor = "0x000000FF"  ' black at launch — teal restored when grid shows

    ' ---- Node references ----
    m.get_channel_list    = m.top.FindNode("get_channel_list")
    m.playlistList        = m.top.FindNode("playlistList")
    m.channelList         = m.top.FindNode("channelList")
    m.channelListHeaderLabel = m.top.findNode("channelListHeaderLabel")
    m.channelListHeaderLabelContainer = m.top.findNode("channelListHeaderLabelContainer")
    m.channelListHeaderLabel.observeField("visible", "onHeaderLabelVisibilityChange")
    m.sidePanel           = m.top.FindNode("sidePanel")
    m.gridBackgroundTexture = m.top.FindNode("gridBackgroundTexture")

    m.channelOverlay      = m.top.FindNode("channelOverlay")
    m.channelOverlayList  = m.top.FindNode("channelOverlayList")

    m.channelBar           = m.top.FindNode("channelBar")
    m.channelBarLogo       = m.top.FindNode("channelBarLogo")
    if m.channelBarLogo <> invalid then
        m.channelBarLogo.ObserveField("loadStatus", "onChannelBarLogoStatus")
    end if
    m.channelBarNameLabel  = m.top.FindNode("channelBarNameLabel")
    m.channelBarServerLabel = m.top.FindNode("channelBarServerLabel")
    ' Index order matches m.barFocusIndex (0=Favorite, 1=CC, 2=Live, 3=Details)
    m.channelBarButtons = [
        m.top.FindNode("channelBarFavoriteBtn"),
        m.top.FindNode("channelBarCCBtn"),
        m.top.FindNode("channelBarLiveBtn"),
        m.top.FindNode("channelBarDetailsBtn"),
        m.top.FindNode("channelBarHideBtn")
    ]
    m.channelBarFavoriteIcon  = m.top.FindNode("channelBarFavoriteIcon")
    m.channelBarCCIcon        = m.top.FindNode("channelBarCCIcon")
    m.channelBarHideIcon      = m.top.FindNode("channelBarHideIcon")

    m.previewVideo        = m.top.FindNode("PreviewVideo")


    m.screensaverOverlay        = m.top.FindNode("screensaverOverlay")
    m.loadingOverlay             = m.top.FindNode("loadingOverlay")
    m.loadingOverlayBorder       = m.top.FindNode("loadingOverlayBorder")
    m.loadingOverlayLabel        = m.top.FindNode("loadingOverlayLabel")
    m.previewErrorContainer     = m.top.FindNode("previewErrorContainer")
    m.videoClipLeft             = m.top.FindNode("VideoClipLeft")
    m.tvOverlay                 = m.top.FindNode("TV overlay")
    m.previewChannelNameLabel   = m.top.FindNode("previewChannelNameLabel")
    m.previewChannelNameContainer = m.top.FindNode("previewChannelNameContainer")
    m.previewChannelLogo        = m.top.FindNode("previewChannelLogo")
    if m.previewChannelLogo <> invalid then
        m.previewChannelLogo.ObserveField("loadStatus", "onPreviewLogoStatus")
    end if
    m.bufferContainer           = m.top.FindNode("bufferContainer")
    m.bufferFill                = m.top.FindNode("bufferFill")
    m.bufferLabel               = m.top.FindNode("bufferLabel")
    m.bufferTrack               = m.top.FindNode("bufferTrack")

    ' Reconnect overlay nodes
    m.reconnectOverlay        = m.top.FindNode("reconnectOverlay")
    m.reconnectOverlayBorder  = m.top.FindNode("reconnectOverlayBorder")
    m.reconnectSpinner        = m.top.FindNode("reconnectSpinner")
    m.reconnectChannelLabel   = m.top.FindNode("reconnectChannelLabel")
    m.reconnectStatusLabel    = m.top.FindNode("reconnectStatusLabel")
    m.reconnectErrorLabel     = m.top.FindNode("reconnectErrorLabel")
    m.reconnectCountdownLabel = m.top.FindNode("reconnectCountdownLabel")
    m.reconnectActionLabel   = m.top.FindNode("reconnectActionLabel")
    m.reconnectDialogShade   = m.top.FindNode("reconnectDialogShade")

    ' ManifestPatcher task node
    m.manifestPatcher = m.top.FindNode("manifestPatcher")
    if m.manifestPatcher <> invalid then
        m.manifestPatcher.ObserveField("result", "onManifestPatched")
    end if

    ' LocalProxy task node — HTTP server that serves version-patched HLS live
    m.localProxy = m.top.FindNode("localProxy")
    if m.localProxy <> invalid then
        m.localProxy.ObserveField("status", "onProxyStatusChanged")
    end if

    ' ---- Field observers ----
    m.get_channel_list.ObserveField("content", "SetContent")
    m.playlistList.ObserveField("itemSelected", "onPlaylistSelected")
    m.playlistList.ObserveField("itemFocused",  "onPlaylistFocused")
    m.channelList.ObserveField("itemFocused",   "onChannelFocused")
    m.channelList.ObserveField("itemSelected",  "onChannelSelected")
    m.channelOverlayList.ObserveField("itemSelected", "onOverlayChannelSelected")
    m.channelOverlayList.ObserveField("itemFocused",  "onOverlayItemFocused")
    ' Pauses the grid/fullscreen inactivity timers for as long as a text-entry
    ' dialog is up (see onDialogChanged in Timers.brs) — observing m.top.dialog
    ' itself, rather than hooking every dialog open/close call site, so it
    ' works the same whether the dialog is dismissed via its buttons or the
    ' Back key (m.top.dialog reverts to invalid automatically either way).
    m.top.ObserveField("dialog", "onDialogChanged")

    ' ---- Video node setup ----
    if m.previewVideo <> invalid then
        m.previewVideo.EnableCookies()
        m.previewVideo.SetCertificatesFile("common:/certs/ca-bundle.crt")
        m.previewVideo.InitClientCertificates()
        m.previewVideo.ObserveField("state",           "checkState")
        m.previewVideo.ObserveField("bufferingStatus", "onBufferingStatus")
    end if

    ' ---- Playback state ----
    m.allChannels           = invalid
    m.flatChannelList       = []
    m.currentChannelIndex   = 0
    m.playlists             = []
    m.currentPlaylist       = 0
    m.isPlayingVideo        = false
    m.overlayVisible        = false
    m.lastError             = { msg: "", channelIndex: -1 }   ' merged from lastErrorMsg/lastErrorChannelIndex — always set/read together
    m.bufferVisible         = false
    m.playlistPanelActive   = false
    m.playlistFocusIndex    = 0
    m.suppressFocusChange   = false
    m.lastBufferPct         = -1
    m.pendingChannelUrl         = invalid
    m.pendingPreviousChannelUrl = invalid   ' restored previous channel for instant replay
    m.pendingDeepLinkUrl        = invalid   ' deferred deep link URL (playlist not ready yet)
    m.pendingDeepLinkTitle      = invalid   ' deferred deep link title
    m.pendingHeaders        = { ua: "", ref: "", cookie: "" }   ' merged from pendingUA/pendingRef/pendingCookie — always set/read together
    m.suppressNextVideoOptionsMenu = false
    m.initialLaunch = true   ' true until first playlist loads and we go fullscreen
    m.loadingDialogVisible = false   ' true while the playlist-loading Dialog is up (see _showLoadingDialog)
    m.videoHiddenForLoadingDialog = false   ' true if _showLoadingDialog() hid previewVideo and still needs to restore it
    m.suppressLoadingDialogDismissOnce = false   ' see _showLoadingDialog()
    m.textEntryDialogVisible = false   ' true while a StandardKeyboardDialog is up (see onDialogChanged in Timers.brs)
    m.isFirstRunSetupDialog = false   ' true only for the very-first-run add-playlist dialog (see below + PlaylistAddDialog.brs)

    ' ---- Channel bar state ----
    m.barVisible    = false
    m.barFocusIndex = 0      ' 0=Favorite, 1=CC, 2=Live, 3=Details
    m.ccEnabled     = false
    if m.previewVideo <> invalid then
        ' Sync CC button to actual system caption state so the button
        ' reflects reality from the first frame — not always dimmed.
        sysCC = m.previewVideo.globalCaptionMode
        if sysCC = "On" or sysCC = "Instant replay" then
            m.ccEnabled = true
        end if
    end if
    _syncCCButtonLabel()   ' sync icon brightness to match ccEnabled

    ' ---- Channel tracking ----
    ' m.loadingChannelIndex  - channel index currently being loaded (set when load starts)
    ' m.playingPreviewIndex  - channel index confirmed playing in preview (set on state=playing)
    ' m.previousChannelIndex - channel index that was playing before the current one
    m.loadingChannelIndex  = -1
    m.playingPreviewIndex  = -1
    m.previousChannelIndex = -1
    ' m.replayFallbackActive - true when replay (grid or fullscreen) last
    ' jumped to the per-playlist last-watched fallback rather than a
    ' surf-based previousChannelIndex target -- lets a second replay press
    ' toggle back to what's actually playing without changing the channel.
    ' See GridInput.brs's replay handler and jumpToPreviousChannel() in
    ' ChannelNav.brs.
    m.replayFallbackActive = false

    ' ---- Unified retry state ----
    m.retryCount             = 0
    m.manifestPatchAttempted = false
    m.pendingRetryContent    = invalid
    m.lastWorkingContent     = invalid
    m.cacheWasAttempted      = false
    m.savedErrorMsg          = ""
    m.savedErrorStr          = ""

    ' ---- Stream outage / network state ----
    m.streamWasPlaying    = false
    m.reconnectState       = "idle"   ' merged from gaveUp/streamRetryActive/waitingForNetwork (mutually exclusive) — values: idle/ladder/outage/network/gaveup
    m.reconnectCountdown  = 0
    m.outageLoopCycleCount = 0   ' counts entries into the outage loop, for the "second cycle" dialog-shade trigger

    ' ---- Session-token stream state ----
    m.pendingProxyContent       = invalid
    m.proxyOriginalUrl          = ""   ' original channel URL when proxy is active
    m.channelBarLogoChannel     = invalid   ' channel whose logo is currently loading
    m.previewChannelLogoChannel = invalid   ' channel whose logo is currently loading
    m.surfDwellTimer            = invalid   '2s timer for previousChannelIndex commit
    m.surfStartChannelIndex     = -1        'channel at start of current surf session

    ' ---- Soft step-down state ----
    m.softStepCount     = 0
    m.softStepBandwidth = 0
    m.slowBufferStartTime = invalid

    ' ---- Timer handles ----
    m.stallTimer              = invalid
    m.gridInactivityTimer     = invalid
    m.overlayInactivityTimer  = invalid
    m.fullscreenInactivityTimer = invalid
    m.optionsDialogTimer      = invalid
    m.bufferDelayTimer        = invalid
    m.overlayOkSuppressTimer  = invalid
    m.optionTimer             = invalid
    m.channelInfoTimer        = invalid
    m.slowBufferRecoveryTimer = invalid
    m.errorDelayTimer         = invalid
    m.networkPollTimer        = invalid
    m.streamRetryTimer        = invalid
    m.countdownTickTimer      = invalid
    m.settingsCacheTimer      = invalid
    m.channelBarTimer         = invalid

    ' ---- Start-up ----
    initSettingsCache()
    initFavorites()
    initHiddenChannels()
    loadSavedPlaylists()
    setupPlaylistMenu()
    ' Deep linking — launch args are read synchronously here (they were set
    ' before CreateScene). The observer handles runtime deep links only.
    ' This avoids the race where the render-thread observer fires after
    ' restorePendingChannel() has already run.
    launchDeepLink = m.global.deepLinkArgs
    m.global.deepLinkArgs = invalid   ' clear so observer doesn't re-fire for launch args
    m.global.observeField("deepLinkArgs", "onDeepLinkArgs")   ' runtime deep links only
    m.global.observeField("memoryPressure", "onMemoryPressure")   ' see main.brs's _setupMemoryMonitor
    if launchDeepLink <> invalid then
        print ">>> DEEPLINK: Synchronous launch args detected"
        m.global.deepLinkArgs = launchDeepLink   ' set back so onDeepLinkArgs processes it
        onDeepLinkArgs()
        m.global.deepLinkArgs = invalid           ' consumed
    end if

    lastState = loadLastState()
    print ">>> STATE: Loaded from registry -- playlistIndex="; lastState.playlistIndex; " channelUrl="; lastState.channelUrl; " channelTitle="; lastState.channelTitle

    if m.playlists.Count() > 0 then
        playlistIndex = 0
        if lastState.playlistIndex <> invalid and lastState.playlistIndex >= 0 and lastState.playlistIndex < m.playlists.Count() then
            playlistIndex = lastState.playlistIndex
        end if
        m.currentPlaylist         = playlistIndex
        m.playlistList.jumpToItem = playlistIndex + 1   ' +1 for the Favorites entry at index 0
        if lastState.channelUrl <> invalid and lastState.channelUrl <> "" then
            m.pendingChannelUrl = lastState.channelUrl
        end if
        if lastState.previousChannelUrl <> invalid and lastState.previousChannelUrl <> "" then
            m.pendingPreviousChannelUrl = lastState.previousChannelUrl
        end if
        loadPlaylist(m.playlists[playlistIndex].url)
    else
        ' No playlists configured yet — the add-playlist dialog appears
        ' before anything resembling a home screen. Roku's AppDialogInitiate/
        ' AppDialogComplete beacons (cert criteria 3.2) subtract the time
        ' spent in that dialog from the measured launch time; the matching
        ' AppDialogComplete fires at every exit point of the flow in
        ' PlaylistAddDialog.brs, gated on m.isFirstRunSetupDialog so it
        ' fires exactly once and not on later in-app "add playlist" uses.
        m.isFirstRunSetupDialog = true
        m.top.signalBeacon("AppDialogInitiate")
        showPlaylistManager()
    end if

    _buildGridBackgroundTexture()

    ' ── Hide all grid UI at startup — app opens directly in fullscreen ──────────
    m.channelList.visible = false
    if m.channelListHeaderLabel <> invalid then m.channelListHeaderLabel.visible = false
    if m.gridBackgroundTexture <> invalid then m.gridBackgroundTexture.visible = false
    m.sidePanel.visible   = false
    if m.previewVideo <> invalid then m.previewVideo.visible = false
    hideGridOverlays()   ' tvOverlay, previewChannelNameContainer, videoClipLeft

    m.top.signalBeacon("AppLaunchComplete")
end sub

' Triggered when the get_channel_list task finishes
sub SetContent()
    print ">>> LOADDLG: SetContent called -- fetch task finished"
    _hideLoadingDialog()

    if m.get_channel_list.content <> invalid then
        m.rawAllChannels = m.get_channel_list.content   ' untouched parse -- Favorites/Hidden views rebuild from this
        m.favoritesOnly = false
        m.hiddenOnly    = false
        m.fullFlatChannelList = invalid   ' new playlist — re-capture fresh on next favorites-view open
        loadFavoritesForCurrentPlaylist()
        loadHiddenChannelsForCurrentPlaylist()
        rebuildVisibleChannelTree()   ' m.allChannels = raw tree minus hidden channels
        buildFlatChannelList()

        ' If a channel was actively playing when the user picked a different
        ' playlist (or reloaded the current one) from the side panel, make
        ' sure it's still represented correctly here -- resolved to its
        ' natural entry if the same channel/URL also exists in this playlist,
        ' otherwise pinned under a "Now Playing" section at the tail of the
        ' grid (tail, not front -- see the comment in Utils.brs for why).
        ' Must run before _syncFavoriteStars() so a pinned copy gets its star
        ' computed the same way as everything else (and only once, not
        ' doubled up with a separate natural entry for the same channel). See
        ' _resyncOrPinChannelAfterPlaylistSwitch() in Utils.brs.
        jumpIndex = _resyncOrPinChannelAfterPlaylistSwitch()

        _syncFavoriteStars()
        _updateChannelListHeader()
        m.channelList.content    = m.allChannels
        m.channelList.jumpToItem = jumpIndex
        restorePendingChannel()
        ' If no channel was restored (no last-channel, no deep link, no pending URL),
        ' launch the first channel fullscreen as a sensible default.
        ' Guard: if deep link or restorePendingChannel already started playback,
        ' m.isPlayingVideo will be true — don't override with channel 0.
        if m.initialLaunch and m.flatChannelList.Count() > 0 and not m.isPlayingVideo then
            m.initialLaunch = false
            _launchFullscreen(0)
        end if
        m.playlistPanelActive = false
        if not m.isPlayingVideo then
            m.channelList.SetFocus(true)
            resetGridInactivityTimer()
        end if
    else
        _showSimpleDialog("Error", "Could not load the list. Check URL.", ["OK"])
    end if
end sub

' Kick off the background task that fetches + parses the M3U
sub loadPlaylist(url as String)
    print ">>> LOADDLG: loadPlaylist called, url="; url; " isPlayingVideo="; m.isPlayingVideo; " previewVideo.visible="; (m.previewVideo <> invalid and m.previewVideo.visible)
    m.global.feedurl = url
    _showLoadingDialog()
    m.get_channel_list.control = "RUN"
end sub

' ---------- Loading indicator ----------
' Plain overlay, not a native Dialog — see the comment on loadingOverlay in
' MainScene.xml for why. Dim is manual (screensaverOverlay), key handling is
' manual (onKeyEvent in InputHandler.brs, checking m.loadingDialogVisible),
' same proven pattern as reconnectOverlay elsewhere in this file/Overlays.brs.
'
' m.loadingDialogVisible is the source of truth for "a playlist load is in
' progress" — independent of whether the overlay itself is currently shown,
' since dismissing via up/down/left/OK/back hides the overlay but the fetch
' keeps running; SetContent() cleans up properly (via _hideLoadingDialog)
' whenever it actually finishes.

sub _showLoadingDialog()
    print ">>> LOADDLG: _showLoadingDialog called"
    print ">>> LOADDLG: m.loadingOverlay="; m.loadingOverlay; " m.loadingOverlayBorder="; m.loadingOverlayBorder; " m.loadingOverlayLabel="; m.loadingOverlayLabel; " m.screensaverOverlay="; m.screensaverOverlay
    m.loadingDialogVisible = true
    ' The same physical OK press that selects a playlist (natively consumed
    ' by the focused playlistList, firing itemSelected -> onPlaylistSelected()
    ' -> loadPlaylist() -> here) also still reaches Scene.onKeyEvent()
    ' afterward as a raw key event -- InputHandler.brs's dismiss-on-input
    ' check would then see m.loadingDialogVisible just turned true and
    ' immediately hide everything below, all within the same key press,
    ' before a frame ever renders. This flag tells that check to ignore the
    ' very next key event (the trailing echo of this same press) rather
    ' than treating it as a genuine, separate dismiss request.
    m.suppressLoadingDialogDismissOnce = true
    ' previewVideo keeps playing uninterrupted during a mid-session playlist
    ' switch (by design — the same stream, no visual/audio interruption).
    ' On some Roku models, actively-playing video renders via a hardware
    ' overlay plane that sits ABOVE regular 2D SceneGraph elements
    ' regardless of z-order, so this dialog could be genuinely
    ' visible=true and still invisible underneath it — which is exactly why
    ' it only ever showed up at boot (nothing playing yet, previewVideo
    ' hidden) and never during a real switch. Hiding just the visual output
    ' here doesn't touch playback or audio at all; restored in
    ' _hideLoadingDialog()/_dismissLoadingDialogForInput() below.
    m.videoHiddenForLoadingDialog = false
    if m.previewVideo <> invalid and m.previewVideo.visible then
        print ">>> LOADDLG: hiding previewVideo (was visible)"
        m.previewVideo.visible = false
        m.videoHiddenForLoadingDialog = true
    else
        print ">>> LOADDLG: previewVideo not visible or invalid, nothing to hide"
    end if
    if m.loadingOverlay       <> invalid then m.loadingOverlay.visible       = true
    if m.loadingOverlayBorder <> invalid then m.loadingOverlayBorder.visible = true
    if m.loadingOverlayLabel  <> invalid then m.loadingOverlayLabel.visible  = true
    if m.screensaverOverlay   <> invalid then m.screensaverOverlay.visible   = true
    print ">>> LOADDLG: after show -- loadingOverlay.visible="; (m.loadingOverlay <> invalid and m.loadingOverlay.visible); " loadingOverlayBorder.visible="; (m.loadingOverlayBorder <> invalid and m.loadingOverlayBorder.visible); " screensaverOverlay.visible="; (m.screensaverOverlay <> invalid and m.screensaverOverlay.visible); " previewVideo.visible="; (m.previewVideo <> invalid and m.previewVideo.visible)
end sub

sub _hideLoadingDialog()
    print ">>> LOADDLG: _hideLoadingDialog called"
    m.loadingDialogVisible = false
    if m.loadingOverlay       <> invalid then m.loadingOverlay.visible       = false
    if m.loadingOverlayBorder <> invalid then m.loadingOverlayBorder.visible = false
    if m.screensaverOverlay <> invalid and (m.reconnectOverlay = invalid or not m.reconnectOverlay.visible) then
        m.screensaverOverlay.visible = false
    end if
    if m.videoHiddenForLoadingDialog then
        print ">>> LOADDLG: restoring previewVideo visibility"
        if m.previewVideo <> invalid then m.previewVideo.visible = true
        m.videoHiddenForLoadingDialog = false
    end if
end sub

' Fires when main.brs's memory monitor (roAppMemoryMonitor, or the
' roDeviceInfo fallback on models that don't support it) reports rising
' memory pressure. Logged prominently so it's easy to correlate against
' proxy/retry-ladder activity during testing. Not currently doing anything
' destructive beyond logging — SelectaVue doesn't hold large in-memory
' caches (channel lists and settings cache are small associative data, not
' bitmaps/textures), so there's no obvious safe thing to release yet. If
' real low-memory reports show up in the field, this is the place to add
' a response (e.g. dropping non-visible cached channel logos).
sub onMemoryPressure()
    pressure = m.global.memoryPressure
    if pressure = invalid then return
    print ">>> MEMORY: onMemoryPressure "; FormatJson(pressure)
end sub
