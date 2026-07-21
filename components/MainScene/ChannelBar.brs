' ==================== ChannelBar.brs ====================
' Bottom-third interactive bar shown in fullscreen: channel logo, name,
' and five buttons (Favorite toggle, CC toggle, Live/reload, Details, Hide).
'
' Replaces the old channel info banner (auto-shown on channel change) AND
' the OK options dialog (Audio Settings / Subtitles / Channel Details / Close).
' Audio and subtitle track selection now live in Roku's own system overlay
' (the * button on most remotes/devices) instead of a custom dialog.
'
' State:
'   m.barVisible    - true while the bar is shown
'   m.barFocusIndex - which button is focused: 0=Favorite, 1=CC, 2=Live, 3=Details, 4=Hide
'   m.ccEnabled     - current captions on/off state, mirrors previewVideo.suppressCaptions
'
' The bar auto-shows on every channel change in fullscreen (surf, replay-jump,
' playChannel/launch) and can also be toggled with OK. Whenever visible it owns
' Left/Right (button nav) and OK (activate); Up/Down still change channels and
' that channel change re-shows/refreshes the bar. Back dismisses the bar only.
' Auto-hides after 3 seconds of no input.
'
' Left on the leftmost (Favorite) button dismisses the bar and opens the
' quick channel menu instead of wrapping around to Live — see
' _handleFullscreenKey in FullscreenInput.brs.
'
' * key toggles favorite on the current channel — in fullscreen (bar visible
' or hidden, see FullscreenInput.brs) and separately on the grid's channel
' list (not the playlist panel, see GridInput.brs). Two independent bindings
' for the same action in their respective screens.

' ---------- Show / hide ----------

' Shows the bar for whatever's cached in m.playingChannel and (re)starts the
' 3s auto-hide timer. Safe to call repeatedly — e.g. on every channel surf —
' it just refreshes. No longer takes a channel param: every caller used to
' derive one from m.flatChannelList[m.currentChannelIndex] independently,
' which is exactly the field that can drift from what's actually playing
' (see m.playingChannel's comment in MainScene.brs). Reading the cache here
' instead means every caller shows the same, correct channel.
sub showChannelBar()
    if m.channelBar = invalid then return
    channel = m.playingChannel
    if channel = invalid then return

    ' Bar and quick channel menu are mutually exclusive
    if m.overlayVisible then
        hideOverlay()
    end if

    if m.channelBarNameLabel <> invalid then m.channelBarNameLabel.text = cleanChannelTitle(channel)
    _updateChannelBarServerLabel()
    _updateChannelBarLogo(channel)
    _syncCCButtonLabel()
    _syncFavoriteButtonLabel(channel)
    _syncHideButtonIcon(channel)

    ' Always start on the first button rather than remembering wherever focus
    ' was left last time the bar was shown.
    _setBarFocusIndex(0)

    m.channelBar.visible = true
    m.barVisible          = true
    _resetChannelBarTimer()
end sub

' Toggles the bar via OK. If hidden, shows it for the current channel.
' If shown, hides it immediately (no need to wait out the timer).
sub toggleChannelBar()
    if m.barVisible then
        hideChannelBar()
    else
        if m.playingChannel <> invalid then showChannelBar()
    end if
end sub

sub hideChannelBar()
    if m.channelBar <> invalid then m.channelBar.visible = false
    m.barVisible = false
    _cancelChannelBarTimer()
end sub

sub _resetChannelBarTimer()
    _startNamedTimer("channelBarTimer", 4.0, false, "hideChannelBar")
end sub

sub _cancelChannelBarTimer()
    _cancelNamedTimer("channelBarTimer")
end sub

' ---------- Button focus / navigation ----------
' Left/Right move between the 4 buttons while the bar is visible.
' Wraps around at each end rather than stopping.

sub channelBarFocusLeft()
    newIndex = m.barFocusIndex - 1
    if newIndex < 0 then newIndex = 4
    _setBarFocusIndex(newIndex)
    _resetChannelBarTimer()
end sub

sub channelBarFocusRight()
    newIndex = m.barFocusIndex + 1
    if newIndex > 4 then newIndex = 0
    _setBarFocusIndex(newIndex)
    _resetChannelBarTimer()
end sub

sub _setBarFocusIndex(index as Integer)
    m.barFocusIndex = index
    focusedColor   = ACCENT_TEAL()
    unfocusedColor = ACCENT_TEAL_DARK()
    if m.channelBarButtons <> invalid then
        for i = 0 to m.channelBarButtons.Count() - 1
            btn = m.channelBarButtons[i]
            if btn <> invalid then btn.color = iif(i = index, focusedColor, unfocusedColor)
        end for
    end if
end sub

' OK while the bar is visible — activates whichever button is focused.
sub channelBarActivate()
    if m.barFocusIndex = 0 then
        toggleFavoriteForCurrentChannel()
        _resetChannelBarTimer()   ' bar stays visible — refresh its countdown
    else if m.barFocusIndex = 1 then
        _toggleCaptions()
        _resetChannelBarTimer()   ' bar stays visible — refresh its countdown
    else if m.barFocusIndex = 2 then
        hideChannelBar()
        reloadCurrentChannel()
    else if m.barFocusIndex = 3 then
        hideChannelBar()
        showCurrentChannelInfo()
    else if m.barFocusIndex = 4 then
        toggleHideForCurrentChannel()
        _resetChannelBarTimer()   ' bar stays visible — refresh its countdown
    end if
end sub

' ---------- Favorite toggle ----------
' Shared by: * key (bar visible or not, fullscreen), and the bar's
' Favorite button. Always acts on whatever channel is currently playing.

sub toggleFavoriteForCurrentChannel()
    channel = m.playingChannel
    if channel = invalid then return
    toggleFavorite(channel)
    _syncFavoriteButtonLabel(channel)
    if m.favoritesOnly then
        _rebuildFavoritesGrid()
    else
        refreshFavoriteStarsDisplay()
    end if
end sub

sub _syncFavoriteButtonLabel(channel as Object)
    if m.channelBarFavoriteIcon = invalid then return
    isFav = false
    if channel <> invalid then isFav = isChannelFavorite(channel.url)
    m.channelBarFavoriteIcon.blendColor = iif(isFav, "0xFFFFFFFF", ICON_DIM_COLOR())
end sub

' ---------- Hide toggle ----------
' Shared by: the bar's Hide button only (no separate key binding, unlike
' Favorite). Always acts on whatever channel is currently playing — see
' toggleHideForCurrentChannel() in HiddenChannels.brs for the actual toggle
' and tree/pin bookkeeping.
'
' Icon brightness is INVERTED from Favorite/CC above: there, bright means
' "this toggle is on" (favorited/captions on). Here, bright means "this
' channel is currently visible" (not hidden) — dimmed means hidden. Per
' Adam: the icon reads as an eye, so bright/open-eye = showing, dim = hidden
' reads more naturally than mapping brightness to "hidden" being the "on" state.

sub _syncHideButtonIcon(channel as Object)
    if m.channelBarHideIcon = invalid then return
    isHidden = false
    if channel <> invalid then isHidden = isChannelHidden(channel.url)
    m.channelBarHideIcon.blendColor = iif(isHidden, ICON_DIM_COLOR(), "0xFFFFFFFF")
end sub

' ---------- CC toggle ----------
' Simple on/off toggle, no sub-menu. Mirrors the old Subtitles dialog's
' "off" vs first-available-track behavior, but as a single button press.

sub _toggleCaptions()
    if m.previewVideo = invalid then return
    m.ccEnabled = not m.ccEnabled
    if m.ccEnabled then
        m.previewVideo.globalCaptionMode = "On"
    else
        m.previewVideo.globalCaptionMode = "Off"
    end if
    _syncCCButtonLabel()
end sub

sub _syncCCButtonLabel()
    if m.channelBarCCIcon = invalid then return
    m.channelBarCCIcon.blendColor = iif(m.ccEnabled, "0xFFFFFFFF", ICON_DIM_COLOR())
end sub

' Re-applies captions when a new stream reaches "playing" if CC is enabled.
' Needed because channel changes reset the Video node state.
sub _reapplyCaptionsIfEnabled()
    if m.previewVideo = invalid then return
    if not m.ccEnabled then return
    tracks = m.previewVideo.availableCaptionTracks
    if tracks <> invalid and tracks.Count() > 0 and tracks[0] <> invalid and tracks[0].TrackName <> invalid then
        m.previewVideo.selectCaptionTrack = tracks[0].TrackName
    end if
    m.previewVideo.globalCaptionMode = "On"
end sub

' ---------- Server / playlist name ----------
' Mirrors _updateChannelListHeader()'s serverName lookup in Favorites.brs —
' both now pull from the shared currentServerName() in Utils.brs, just
' shown on the channel bar instead of above the grid.
sub _updateChannelBarServerLabel()
    if m.channelBarServerLabel = invalid then return
    m.channelBarServerLabel.text = currentServerName()
end sub

' ---------- Logo ----------

sub _updateChannelBarLogo(channel as Object)
    if m.channelBarLogo = invalid then return
    m.channelBarLogoChannel  = channel
    m.channelBarLogoRetried  = false

    if channel <> invalid and channel.url <> invalid and channel.url = m.iconResolvedUrl and m.iconResolvedUri <> "" then
        ' previewChannelLogo already resolved this exact channel's icon --
        ' they're never on screen together, so just copy the result across
        ' rather than fetching the identical remote image a second time.
        m.channelBarLogoRequestedUri = m.iconResolvedUri
        m.channelBarLogo.uri        = m.iconResolvedUri
        m.channelBarLogo.visible    = true
        return
    end if

    m.channelBarLogo.uri     = ""
    m.channelBarLogo.visible = false
    iconUrl = _bestIconUrl(channel)
    m.channelBarLogoRequestedUri = iconUrl
    if iconUrl <> "" then
        m.channelBarLogo.uri     = iconUrl
        m.channelBarLogo.visible = true
    end if
end sub
