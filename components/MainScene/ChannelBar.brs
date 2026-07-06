' ==================== ChannelBar.brs ====================
' Bottom-third interactive bar shown in fullscreen: channel logo, name,
' and four buttons (Favorite toggle, CC toggle, Details, Live/reload).
'
' Replaces the old channel info banner (auto-shown on channel change) AND
' the OK options dialog (Audio Settings / Subtitles / Channel Details / Close).
' Audio and subtitle track selection now live in Roku's own system overlay
' (the * button on most remotes/devices) instead of a custom dialog.
'
' State:
'   m.barVisible    - true while the bar is shown
'   m.barFocusIndex - which button is focused: 0=Favorite, 1=CC, 2=Live, 3=Details
'   m.ccEnabled     - current captions on/off state. Treat as a cache, not a
'                     source of truth — it's verified against previewVideo's
'                     actual globalCaptionMode on boot and any time that
'                     field changes (see _syncCCStateFromVideo() below),
'                     since the system caption overlay can change captions
'                     without going through this code at all.
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

' Shows the bar for the given channel and (re)starts the 3s auto-hide timer.
' Safe to call repeatedly — e.g. on every channel surf — it just refreshes.
sub showChannelBar(channel as Object)
    if m.channelBar = invalid then return
    if channel = invalid then return

    ' Bar and quick channel menu are mutually exclusive
    if m.overlayVisible then
        hideOverlay()
    end if

    if m.channelBarNameLabel <> invalid then m.channelBarNameLabel.text = cleanChannelTitle(channel)
    _updateChannelBarServerLabel()
    _updateChannelBarLogo(channel)
    _syncCCStateFromVideo()
    _syncFavoriteButtonLabel(channel)

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
        channel = invalid
        if m.flatChannelList <> invalid and m.currentChannelIndex >= 0 and m.currentChannelIndex < m.flatChannelList.Count() then
            channel = m.flatChannelList[m.currentChannelIndex]
        end if
        if channel <> invalid then showChannelBar(channel)
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
    if newIndex < 0 then newIndex = 3
    _setBarFocusIndex(newIndex)
    _resetChannelBarTimer()
end sub

sub channelBarFocusRight()
    newIndex = m.barFocusIndex + 1
    if newIndex > 3 then newIndex = 0
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
    end if
end sub

' ---------- Favorite toggle ----------
' Shared by: * key (bar visible or not, fullscreen), and the bar's
' Favorite button. Always acts on whatever channel is currently playing.

sub toggleFavoriteForCurrentChannel()
    if m.flatChannelList = invalid or m.currentChannelIndex < 0 or m.currentChannelIndex >= m.flatChannelList.Count() then return
    channel = m.flatChannelList[m.currentChannelIndex]
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

' ---------- CC toggle ----------
' Simple on/off toggle, no sub-menu. Mirrors the old Subtitles dialog's
' "off" vs first-available-track behavior, but as a single button press.

sub _toggleCaptions()
    if m.previewVideo = invalid then return
    m.ccEnabled = not m.ccEnabled
    if m.ccEnabled then
        m.previewVideo.suppressCaptions = false
        ' Select the first available caption track, if any.
        ' selectCaptionTrack expects the track's TrackName (string), not an
        ' index — passing an integer here silently failed to select a track,
        ' which is why captions only worked via the Roku system (*) menu.
        tracks = m.previewVideo.availableCaptionTracks
        if tracks <> invalid and tracks.Count() > 0 and tracks[0] <> invalid and tracks[0].TrackName <> invalid then
            m.previewVideo.selectCaptionTrack = tracks[0].TrackName
        end if
        m.previewVideo.globalCaptionMode = "On"
    else
        m.previewVideo.suppressCaptions = true
        m.previewVideo.globalCaptionMode = "Off"
    end if
    _syncCCButtonLabel()
end sub

sub _syncCCButtonLabel()
    if m.channelBarCCIcon = invalid then return
    m.channelBarCCIcon.blendColor = iif(m.ccEnabled, "0xFFFFFFFF", ICON_DIM_COLOR())
end sub

' ---------- CC state sync (keeps m.ccEnabled truthful) ----------
' m.ccEnabled is our own bookkeeping of on/off, mirrored in the bar's icon.
' It can drift from the real video state in two places:
'   1) App boot — the video node's globalCaptionMode field initializes to
'      whatever the system Settings > Accessibility > Captions mode is
'      set to, but m.ccEnabled used to always start hardcoded to false —
'      so a device with system captions already on would boot with the
'      icon showing "off" while captions were actually displaying.
'   2) The Roku system caption overlay (* button while video is playing)
'      lets the user change captions directly on the video node, bypassing
'      our button entirely.
' Rather than trust m.ccEnabled as the source of truth, this re-reads the
' video node's actual globalCaptionMode and re-syncs m.ccEnabled + the icon
' to match. Safe to call any time (boot, or from the field observer below).
sub _syncCCStateFromVideo()
    if m.previewVideo = invalid then return
    mode = m.previewVideo.globalCaptionMode
    if mode = invalid then mode = "Off"
    m.ccEnabled = (mode = "On")
    _syncCCButtonLabel()
end sub

' Observer callback for previewVideo's "globalCaptionMode" field (wired up
' in MainScene.brs init()). Fires whether WE changed the field
' (_toggleCaptions / _reapplyCaptionsIfEnabled) or the system overlay did —
' either way m.ccEnabled and the icon get corrected to match reality.
sub onGlobalCaptionModeChanged(event as Object)
    _syncCCStateFromVideo()
end sub

' Called from ChannelNav.brs's checkState() when a new stream reaches
' "playing" and m.ccEnabled is already true (user had captions on before
' changing channels). Re-selects the first available track on the new
' content — same logic as _toggleCaptions(), without flipping m.ccEnabled.
sub _reapplyCaptionsIfEnabled()
    if m.previewVideo = invalid then return
    m.previewVideo.suppressCaptions = false
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
    iconUrl = _bestIconUrl(channel)
    m.channelBarLogo.uri     = iconUrl
    m.channelBarLogo.visible = (iconUrl <> "")
end sub
