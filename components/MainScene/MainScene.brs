' ==================== MainScene.brs ====================
' Scene entry point: initialises node references, state variables,
' and kicks off the first playlist load.
'
' Business logic lives in the companion files:
'   Utils.brs          - pure helpers (isValidUrl, getFriendlyError, …)
'   StateManager.brs   - save / load / restore last playlist + channel
'   PlaylistManager.brs - playlist CRUD + dialogs
'   VideoPlayback.brs  - play, preview, reload, audio/subtitle menus
'   Overlays.brs       - every visual overlay
'   Timers.brs         - all inactivity + stall timers
'   InputHandler.brs   - onKeyEvent

sub init()
    m.top.backgroundURI   = ""
    m.top.backgroundColor = "0x024c48FF"

    ' ---- Node references ----
    m.get_channel_list    = m.top.FindNode("get_channel_list")
    m.playlistList        = m.top.FindNode("playlistList")
    m.channelList         = m.top.FindNode("channelList")
    m.sidePanel           = m.top.FindNode("sidePanel")
    m.loadingSpinnerContainer = m.top.FindNode("loadingSpinnerContainer")

    m.channelOverlay      = m.top.FindNode("channelOverlay")
    m.channelOverlayList  = m.top.FindNode("channelOverlayList")

    m.channelInfoOverlay  = m.top.FindNode("channelInfoOverlay")
    m.channelInfoLabel    = m.top.FindNode("channelInfoLabel")
    m.clockLabel          = m.top.FindNode("clockLabel")

    m.errorOverlay        = m.top.FindNode("errorOverlay")
    m.errorTitleLabel     = m.top.FindNode("errorTitleLabel")
    m.errorChannelLabel   = m.top.FindNode("errorChannelLabel")
    m.errorMessageLabel   = m.top.FindNode("errorMessageLabel")

    m.previewVideo        = m.top.FindNode("PreviewVideo")
    m.previewChannelName  = m.top.FindNode("previewChannelName")   ' legacy ref kept for compatibility

    m.screensaverOverlay        = m.top.FindNode("screensaverOverlay")
    m.fullscreenFailContainer   = m.top.FindNode("fullscreenFailContainer")
    m.fullscreenFailLabel       = m.top.FindNode("fullscreenFailLabel")
    m.fullscreenFailChannel     = m.top.FindNode("fullscreenFailChannel")
    m.previewErrorContainer     = m.top.FindNode("previewErrorContainer")
    m.previewHintLabel          = m.top.FindNode("previewHintLabel")
    m.muteIndicatorContainer    = m.top.FindNode("muteIndicatorContainer")
    m.muteIndicatorImage        = m.top.FindNode("muteIndicatorImage")
    m.videoClipLeft             = m.top.FindNode("VideoClipLeft")
    m.muteHintContainer         = m.top.FindNode("muteHintContainer")
    m.tvOverlay                 = m.top.FindNode("TV overlay")
    m.previewChannelNameContainer = m.top.FindNode("previewChannelNameContainer")
    m.previewChannelNameLabel   = m.top.FindNode("previewChannelNameLabel")
    m.bufferContainer           = m.top.FindNode("bufferContainer")
    m.bufferFill                = m.top.FindNode("bufferFill")
    m.bufferLabel               = m.top.FindNode("bufferLabel")
    m.bufferTrack               = m.top.FindNode("bufferTrack")
    m.focusTrap                 = m.top.FindNode("focusTrap")

    ' ---- Field observers ----
    m.get_channel_list.ObserveField("content", "SetContent")

    m.playlistList.ObserveField("itemSelected", "onPlaylistSelected")

    m.channelList.ObserveField("itemFocused",  "onChannelFocused")
    m.channelList.ObserveField("itemSelected", "onChannelSelected")

    m.channelOverlayList.ObserveField("itemSelected", "onOverlayChannelSelected")
    m.channelOverlayList.ObserveField("itemFocused",  "onOverlayItemFocused")

    ' ---- Video node setup ----
    if m.previewVideo <> invalid then
        m.previewVideo.EnableCookies()
        m.previewVideo.SetCertificatesFile("common:/certs/ca-bundle.crt")
        m.previewVideo.InitClientCertificates()
        m.previewVideo.ObserveField("state",           "checkState")
        m.previewVideo.ObserveField("bufferingStatus", "onBufferingStatus")
    end if

    if m.loadingSpinnerContainer <> invalid then m.loadingSpinnerContainer.visible = false

    ' ---- State variables ----
    m.allChannels         = invalid
    m.flatChannelList     = []
    m.currentChannelIndex = 0
    m.previewChannelIndex = -1
    m.playlists           = []
    m.currentPlaylist     = 0
    m.isPlayingVideo      = false
    m.overlayVisible      = false
    m.previewMuted        = false
    m.errorVisible        = false
    m.lastErrorMsg        = ""
    m.lastErrorChannelIndex = -1
    m.bufferVisible       = false
    m.bitrateRetryDone    = false
    m.playlistPanelActive = false
    m.playlistFocusIndex  = 0
    m.suppressFocusChange = false
    m.stallRetryCount     = 0
    m.lastBufferPct       = -1
    m.lastFocusedChannel  = -1
    m.pendingChannelUrl   = invalid
    m.suppressNextVideoOptionsMenu = false

    ' Timer handles (all start as invalid)
    m.stallTimer              = invalid
    m.muteIndicatorTimer      = invalid
    m.gridInactivityTimer     = invalid
    m.overlayInactivityTimer  = invalid
    m.fullscreenInactivityTimer = invalid
    m.optionsDialogTimer      = invalid
    m.bufferDelayTimer        = invalid
    m.overlayOkSuppressTimer  = invalid
    m.optionTimer             = invalid
    m.urlDialogTimer          = invalid
    m.channelInfoTimer        = invalid
    m.errorTimer              = invalid
    m.editUrlErrorTimer       = invalid

    updatePreviewHint()

    ' ---- Start-up ----
    loadSavedPlaylists()
    setupPlaylistMenu()

    lastState = loadLastState()

    if m.playlists.Count() > 0 then
        playlistIndex = 0
        if lastState.playlistIndex <> invalid and lastState.playlistIndex >= 0 and lastState.playlistIndex < m.playlists.Count() then
            playlistIndex = lastState.playlistIndex
        end if

        m.currentPlaylist          = playlistIndex
        m.playlistList.jumpToItem  = playlistIndex

        if lastState.channelUrl <> invalid and lastState.channelUrl <> "" then
            m.pendingChannelUrl = lastState.channelUrl
        end if

        loadPlaylist(m.playlists[playlistIndex].url)
    else
        showPlaylistManager()
    end if

    m.top.signalBeacon("AppLaunchComplete")
end sub

' Triggered by the get_channel_list task completing
sub SetContent()
    if m.loadingSpinnerContainer <> invalid then m.loadingSpinnerContainer.visible = false

    if m.get_channel_list.content <> invalid then
        m.allChannels = m.get_channel_list.content
        buildFlatChannelList()

        m.channelList.content    = m.allChannels
        m.channelList.jumpToItem = 0

        restorePendingChannel()

        m.playlistPanelActive = false
        m.channelList.SetFocus(true)
        resetGridInactivityTimer()
    else
        errorDialog         = CreateObject("roSGNode", "Dialog")
        errorDialog.title   = "Error"
        errorDialog.message = "Could not load the list. Check URL."
        m.top.dialog        = errorDialog
    end if
end sub

' Kick off the background task that fetches + parses the M3U
sub loadPlaylist(url as String)
    m.global.feedurl = url
    if m.loadingSpinnerContainer <> invalid then m.loadingSpinnerContainer.visible = true
    m.get_channel_list.control = "RUN"
end sub
