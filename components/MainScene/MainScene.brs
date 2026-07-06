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
        m.top.FindNode("channelBarDetailsBtn")
    ]
    m.channelBarFavoriteIcon  = m.top.FindNode("channelBarFavoriteIcon")
    m.channelBarCCIcon        = m.top.FindNode("channelBarCCIcon")

    m.previewVideo        = m.top.FindNode("PreviewVideo")


    m.screensaverOverlay        = m.top.FindNode("screensaverOverlay")
    m.loadingOverlay             = m.top.FindNode("loadingOverlay")
    m.loadingOverlayBorder       = m.top.FindNode("loadingOverlayBorder")
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

    ' ---- Video node setup ----
    if m.previewVideo <> invalid then
        m.previewVideo.EnableCookies()
        m.previewVideo.SetCertificatesFile("common:/certs/ca-bundle.crt")
        m.previewVideo.InitClientCertificates()
        m.previewVideo.ObserveField("state",              "checkState")
        m.previewVideo.ObserveField("bufferingStatus",    "onBufferingStatus")
        m.previewVideo.ObserveField("globalCaptionMode",  "onGlobalCaptionModeChanged")
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
    m.pendingHeaders        = { ua: "", ref: "", cookie: "" }   ' merged from pendingUA/pendingRef/pendingCookie — always set/read together
    m.suppressNextVideoOptionsMenu = false
    m.initialLaunch = true   ' true until first playlist loads and we go fullscreen
    m.loadingDialogVisible = false   ' true while the playlist-loading Dialog is up (see _showLoadingDialog)

    ' ---- Channel bar state ----
    m.barVisible    = false
    m.barFocusIndex = 0      ' 0=Favorite, 1=CC, 2=Live, 3=Details
    m.ccEnabled     = false  ' safe default; corrected immediately below
    ' Check the real state on boot up rather than assuming "off" — the video
    ' node's globalCaptionMode initializes from the system-wide Settings >
    ' Accessibility > Captions mode, so a device with system captions
    ' already on must not have the bar's CC icon lie and show "off".
    _syncCCStateFromVideo()

    ' ---- Channel tracking ----
    ' m.loadingChannelIndex  - channel index currently being loaded (set when load starts)
    ' m.playingPreviewIndex  - channel index confirmed playing in preview (set on state=playing)
    ' m.previousChannelIndex - channel index that was playing before the current one
    m.loadingChannelIndex  = -1
    m.playingPreviewIndex  = -1
    m.previousChannelIndex = -1

    ' ---- Unified retry state ----
    m.retryCount             = 0
    m.manifestPatchAttempted = false
    m.pendingRetryContent    = invalid
    m.bandwidthProbeIndex    = 0
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
    m.pendingProxyContent = invalid
    m.proxyOriginalUrl    = ""   ' original channel URL when proxy is active

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
    loadSavedPlaylists()
    setupPlaylistMenu()

    lastState = loadLastState()

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
    _hideLoadingDialog()

    if m.get_channel_list.content <> invalid then
        m.allChannels = m.get_channel_list.content
        m.favoritesOnly = false
        m.fullFlatChannelList = invalid   ' new playlist — re-capture fresh on next favorites-view open
        buildFlatChannelList()
        loadFavoritesForCurrentPlaylist()
        _syncFavoriteStars()
        _updateChannelListHeader()
        m.channelList.content    = m.allChannels
        m.channelList.jumpToItem = 0
        restorePendingChannel()
        ' If pendingChannelUrl wasn't found or wasn't set, launch first channel fullscreen
        if m.initialLaunch and m.flatChannelList.Count() > 0 then
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
    m.loadingDialogVisible = true
    if m.loadingOverlay       <> invalid then m.loadingOverlay.visible       = true
    if m.loadingOverlayBorder <> invalid then m.loadingOverlayBorder.visible = true
    if m.screensaverOverlay   <> invalid then m.screensaverOverlay.visible   = true
end sub

sub _hideLoadingDialog()
    m.loadingDialogVisible = false
    if m.loadingOverlay       <> invalid then m.loadingOverlay.visible       = false
    if m.loadingOverlayBorder <> invalid then m.loadingOverlayBorder.visible = false
    if m.screensaverOverlay <> invalid and (m.reconnectOverlay = invalid or not m.reconnectOverlay.visible) then
        m.screensaverOverlay.visible = false
    end if
end sub
