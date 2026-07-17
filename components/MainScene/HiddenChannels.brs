' ==================== HiddenChannels.brs ====================
' Per-playlist permanently-hidden channels.
'
' Storage: roRegistrySection "hiddenChannels", one key per playlist using its
' array index ("playlist_0", "playlist_1", ...), each value a JSON array of
' hidden channel URLs for that playlist. Mirrors Favorites.brs's storage
' shape exactly.
'
' UI: a 5th button on the fullscreen channel bar (see ChannelBar.brs) toggles
' hidden status on whatever channel is currently playing — same immediate,
' no-confirmation pattern as the Favorite button, and it's a toggle both
' ways, so unhiding is just: play that channel from the Hidden Channels view
' and press the same button again. "Show Hidden Channels" / "Show All
' Channels" lives in the playlist options dialog (options/* key on the
' playlist panel — see PlaylistEditDialogs.brs), only offered for whichever
' playlist is currently loaded.
'
' Hidden channels are excluded from the main grid AND the Favorites view
' entirely — see rebuildVisibleChannelTree(), called from SetContent() in
' MainScene.brs in place of assigning m.get_channel_list.content straight to
' m.allChannels. "Show Hidden Channels" switches the grid to a filtered view
' of only hidden channels for the current playlist (showHiddenChannelsView()),
' entered/exited the same way as the Favorites view.
'
' m.rawAllChannels holds the untouched parse from get_channel_list (set once
' per playlist load in SetContent) so both the visible tree and the hidden
' view can be rebuilt from the same source without re-fetching.
'
' (An earlier long-press-OK-on-the-grid design was dropped — the grid's
' LabelList fires its native selection on press-down regardless of hold
' duration, so there was no way to suppress the resulting preview/fullscreen
' jump before showing a confirmation dialog.)

function HIDDEN_CHANNELS_REG_SECTION() as String
    return "hiddenChannels"
end function

sub initHiddenChannels()
    m.hiddenOnly        = false
    m.currentHiddenUrls = []
end sub

' Loads the hidden-url list for m.currentPlaylist (the array index, same one
' used everywhere else for the active playlist). Call after m.currentPlaylist
' is set, same timing requirement as loadFavoritesForCurrentPlaylist().
sub loadHiddenChannelsForCurrentPlaylist()
    m.currentHiddenUrls = []
    reg = CreateObject("roRegistrySection", HIDDEN_CHANNELS_REG_SECTION())
    key = "playlist_" + m.currentPlaylist.ToStr()
    if reg.Exists(key) then
        jsonStr = reg.Read(key)
        if jsonStr <> invalid and jsonStr <> "" then
            parsed = ParseJSON(jsonStr)
            if parsed <> invalid and type(parsed) = "roArray" then
                m.currentHiddenUrls = parsed
            end if
        end if
    end if
end sub

sub _saveHiddenChannelsForCurrentPlaylist()
    reg = CreateObject("roRegistrySection", HIDDEN_CHANNELS_REG_SECTION())
    key = "playlist_" + m.currentPlaylist.ToStr()
    reg.Write(key, FormatJSON(m.currentHiddenUrls))
    reg.Flush()
end sub

function isChannelHidden(url as String) as Boolean
    if url = invalid or url = "" then return false
    for each hiddenUrl in m.currentHiddenUrls
        if hiddenUrl = url then return true
    end for
    return false
end function

' Toggles hidden status for the given channel and persists immediately.
' Returns the new state (true = now hidden). Caller is responsible for
' rebuilding whichever tree/view is currently on screen.
function toggleHiddenChannel(channel as Object) as Boolean
    if channel = invalid or channel.url = invalid or channel.url = "" then return false
    url        = channel.url
    newHidden  = []
    wasHidden  = false
    for each hiddenUrl in m.currentHiddenUrls
        if hiddenUrl = url then
            wasHidden = true
        else
            newHidden.Push(hiddenUrl)
        end if
    end for
    if not wasHidden then newHidden.Push(url)
    m.currentHiddenUrls = newHidden
    _saveHiddenChannelsForCurrentPlaylist()
    return not wasHidden
end function

' ---------- Shared tree-filtering helper ----------

' Walks m.rawAllChannels (same shape buildFlatChannelList() walks: top-level
' children are either bare leaf channels or SECTION nodes containing channel
' children) and returns a flat items array — same shape buildSortedChannelTree()
' expects — containing only channels whose hidden status matches
' wantHidden (true = only hidden channels, false = only non-hidden channels).
function _filteredChannelItems(wantHidden as Boolean) as Object
    items = []
    if m.rawAllChannels = invalid then return items
    for i = 0 to m.rawAllChannels.getChildCount() - 1
        section = m.rawAllChannels.getChild(i)
        if section = invalid then continue for
        if section.getChildCount() = 0 then
            if section.url <> invalid and section.url <> "" and isChannelHidden(section.url) = wantHidden then
                items.Push({ url: section.url, title: section.title, description: section.description, group: "" })
            end if
        else
            gName = section.title
            for j = 0 to section.getChildCount() - 1
                channel = section.getChild(j)
                if channel <> invalid and channel.url <> invalid and channel.url <> "" and isChannelHidden(channel.url) = wantHidden then
                    items.Push({ url: channel.url, title: channel.title, description: channel.description, group: gName })
                end if
            end for
        end if
    end for
    return items
end function

' ---------- Main grid (hidden channels excluded) ----------

' Rebuilds m.allChannels from m.rawAllChannels with hidden channels removed,
' then rebuilds the flat list and refreshes the grid on screen. Called from
' SetContent() on every playlist load, and again any time a channel's hidden
' status changes while the normal (non-hidden-only) grid is what's showing.
sub rebuildVisibleChannelTree()
    m.allChannels = buildSortedChannelTree(_filteredChannelItems(false))
end sub

' Same as rebuildVisibleChannelTree() but also pushes the result to the grid
' immediately and resets focus/header — for use after a hide/unhide toggle
' while the normal grid is already on screen (rebuildVisibleChannelTree()
' alone is enough during the initial SetContent() load, since the rest of
' that flow already assigns m.channelList.content afterward).
sub _refreshVisibleChannelGrid()
    rebuildVisibleChannelTree()
    buildFlatChannelList()
    _syncFavoriteStars()
    _updateChannelListHeader()
    if m.channelList <> invalid then
        m.channelList.content    = m.allChannels
        m.channelList.jumpToItem = 0
    end if
    m.currentChannelIndex = 0
end sub

' ---------- Hidden Channels grid view ----------
' Mirrors showFavoritesView()/_rebuildFavoritesGrid() in Favorites.brs.

sub showHiddenChannelsView()
    m.hiddenOnly = true
    _rebuildHiddenChannelsGrid()
    m.playlistPanelActive = false
    if m.channelList <> invalid then m.channelList.SetFocus(true)
    resetGridInactivityTimer()
end sub

sub _rebuildHiddenChannelsGrid()
    m.allChannels = buildSortedChannelTree(_filteredChannelItems(true))
    buildFlatChannelList()
    _syncFavoriteStars()
    _updateChannelListHeader()
    if m.channelList <> invalid then
        m.channelList.content    = m.allChannels
        m.channelList.jumpToItem = 0
    end if
    m.currentChannelIndex = 0
end sub

' Exits the Hidden Channels view back to the normal grid. Mirrors the note
' in Favorites.brs: there's no equivalent "exit favorites" function because
' picking a real playlist already resets favoritesOnly and rebuilds — but
' Hidden Channels is reached and left from a dialog button rather than the
' playlist panel, so it needs its own explicit exit.
sub exitHiddenChannelsView()
    m.hiddenOnly = false
    _refreshVisibleChannelGrid()
end sub

' Drops whichever filtered view (Favorites or Hidden Channels) is currently
' showing and returns to the standard grid, moving focus there the same way
' showHiddenChannelsView()/showFavoritesView() do when entering a view.
' Used when re-selecting the already-loaded playlist from the panel while
' browsing either filtered view — see onPlaylistSelected() in
' PlaylistManager.brs. Safe to call even if neither flag is set.
sub returnToStandardGridView()
    m.favoritesOnly = false
    m.hiddenOnly    = false
    _refreshVisibleChannelGrid()
    m.playlistPanelActive = false
    if m.channelList <> invalid then m.channelList.SetFocus(true)
    resetGridInactivityTimer()
end sub

' ---------- Hide/unhide the currently-playing channel (channel bar button) ----------
' Shared by: the channel bar's Hide button (fullscreen only). Mirrors
' toggleFavoriteForCurrentChannel() in ChannelBar.brs -- always acts on
' whatever channel is currently playing, toggles immediately, no
' confirmation. Unhiding works the same way: play the channel from the
' Hidden Channels view, press this same button again.
sub toggleHideForCurrentChannel()
    if m.flatChannelList = invalid or m.currentChannelIndex < 0 or m.currentChannelIndex >= m.flatChannelList.Count() then return
    channel = m.flatChannelList[m.currentChannelIndex]
    if channel = invalid then return

    nowHidden = toggleHiddenChannel(channel)
    _syncHideButtonIcon(channel)

    ' Everything below programmatically swaps channelList's content tree
    ' while (if fullscreen) m.top still holds scene focus -- same class of
    ' operation _exitFullscreen()/refreshFavoriteStarsDisplay() guard with
    ' m.suppressFocusChange, so this follows the same convention: raise the
    ' guard, do the swap, explicitly set whichever focus should end up
    ' correct, then lower the guard only after that -- matching
    ' _exitFullscreen()'s ordering exactly.
    m.suppressFocusChange = true

    if m.hiddenOnly then
        ' Browsing the Hidden Channels view and just unhid whatever's
        ' playing -- it simply drops out of this view once rebuilt.
        _rebuildHiddenChannelsGrid()
    else
        rebuildVisibleChannelTree()
        buildFlatChannelList()
        _syncFavoriteStars()
        _updateChannelListHeader()

        if nowHidden then
            ' Just hid the channel that's actively playing -- it no longer
            ' exists anywhere in the rebuilt list. Pin it back so playback/
            ' surfing (up/down, returning to the grid) still has a valid
            ' index to work from — same mechanism used when a playlist
            ' switch drops the playing channel (see _pinChannelAsNowPlaying()
            ' in Utils.brs). Cleared automatically once the user tunes away.
            _pinChannelAsNowPlaying(channel)
        else
            ' Just unhid it -- it's naturally back in the rebuilt list.
            newIdx = findChannelIndexByUrl(channel.url)
            if newIdx >= 0 then m.currentChannelIndex = newIdx
        end if

        if m.channelList <> invalid then m.channelList.content = m.allChannels
    end if

    ' Explicitly re-assert m.top's focus, same as _exitFullscreen() does
    ' before lowering the guard. This function is only ever reachable via
    ' the fullscreen channel bar (see ChannelBar.brs's channelBarActivate()),
    ' so m.isPlayingVideo is always true here -- no grid-focus case to
    ' handle.
    if m.channelList <> invalid then m.channelList.setFocus(false)
    m.top.setFocus(true)
    m.suppressFocusChange = false
end sub
