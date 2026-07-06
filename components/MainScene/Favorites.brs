' ==================== Favorites.brs ====================
' Per-playlist favorites.
'
' Storage: roRegistrySection "favorites", one key per playlist using its
' array index ("playlist_0", "playlist_1", ...), each value a JSON array
' of favorited channel URLs for that playlist.
'
' UI:
'   - "★ Favorites" entry at the top of the playlist panel (index 0 in
'     m.playlistList, handled in PlaylistManager.brs's onPlaylistSelected).
'     Selecting it filters the grid to only favorited channels from
'     whichever playlist is currently loaded.
'   - * key toggles favorite on the current channel: on the grid it acts on
'     whichever channel has focus (channel list only, not the playlist
'     panel — see GridInput.brs); in fullscreen it acts on the playing
'     channel, whether or not the channel bar is visible (see
'     FullscreenInput.brs and ChannelBar.brs's Favorite button).
'
' The filtered Favorites list is built directly as a ContentNode tree from
' the already-parsed m.flatChannelList — not a synthetic M3U re-parse — so
' custom headers (UA/Referer/Cookie/etc, carried in each channel's
' description string) are preserved untouched, and there's no registry size
' concern since only channel URLs are stored, not full channel data.

function FAVORITES_REG_SECTION() as String
    return "favorites"
end function

' ---------- Favorite star display (grid + quick channel menu) ----------
' Both m.channelList and m.channelOverlayList are bound to ContentNode trees
' that share the same leaf channel nodes (m.allChannels / m.flatChannelList),
' so mutating a channel's title in one place is enough to affect both views.
' The original title is cached in a custom "baseTitle" field the first time
' a channel is synced, so toggling favorite on/off never stacks up stars.

sub _syncFavoriteStars()
    if m.flatChannelList = invalid then return
    for each channel in m.flatChannelList
        if channel = invalid then continue for
        base = channel.baseTitle
        if base = invalid or base = "" then
            base = channel.title
            channel.AddFields({ baseTitle: base })
        end if
        if isChannelFavorite(channel.url) then
            channel.title = "★ " + base
        else
            channel.title = base
        end if
    end for
end sub

' Bounces a list's content field to force a redraw after mutating a child
' ContentNode's fields in place (setting m.list.content = value doesn't
' otherwise repaint on its own), while preserving focus/scroll position.
sub _bounceListContent(list as Object)
    if list = invalid or list.content = invalid then return
    content = list.content
    focused = list.itemFocused
    list.content = invalid
    list.content = content
    list.itemFocused = focused
    list.jumpToItem  = focused
end sub

' Call after toggling a favorite while the grid/quick-menu content is
' already on screen — mutating a child ContentNode's fields in place doesn't
' by itself repaint a LabelList/MarkupList, so the content field is bounced
' to force a redraw. Focus/scroll position is preserved.
sub refreshFavoriteStarsDisplay()
    _syncFavoriteStars()
    m.suppressFocusChange = true
    _bounceListContent(m.channelList)
    _bounceListContent(m.channelOverlayList)
    m.suppressFocusChange = false
end sub

' Keeps the small label above the grid in sync with what's currently being
' browsed — the playlist/server name normally, or "★ Favorites — <server>"
' while viewing the favorites-only filter. Without this there was no way to
' tell which server's favorites you were looking at.
sub _updateChannelListHeader()
    if m.channelListHeaderLabel = invalid then return
    serverName = currentServerName()
    if m.favoritesOnly then
        m.channelListHeaderLabel.text = "Loaded playlist: " + serverName + "   ★ Favorites"
    else
        m.channelListHeaderLabel.text = "Loaded playlist: " + serverName
    end if
end sub

' ---------- Init / load ----------

sub initFavorites()
    m.favoritesOnly        = false
    m.currentFavoriteUrls  = []
    m.fullFlatChannelList  = invalid   ' captured lazily on first favorites-view rebuild
end sub

' Loads the favorite URL list for m.currentPlaylist (the array index, same
' one used everywhere else for the active playlist). Call after the
' playlist's channel list has loaded, since m.currentPlaylist must be set.
sub loadFavoritesForCurrentPlaylist()
    m.currentFavoriteUrls = []
    reg = CreateObject("roRegistrySection", FAVORITES_REG_SECTION())
    key = "playlist_" + m.currentPlaylist.ToStr()
    if reg.Exists(key) then
        jsonStr = reg.Read(key)
        if jsonStr <> invalid and jsonStr <> "" then
            parsed = ParseJSON(jsonStr)
            if parsed <> invalid and type(parsed) = "roArray" then
                m.currentFavoriteUrls = parsed
            end if
        end if
    end if
end sub

sub _saveFavoritesForCurrentPlaylist()
    reg = CreateObject("roRegistrySection", FAVORITES_REG_SECTION())
    key = "playlist_" + m.currentPlaylist.ToStr()
    reg.Write(key, FormatJSON(m.currentFavoriteUrls))
    reg.Flush()
end sub

' ---------- Query / toggle ----------

function isChannelFavorite(url as String) as Boolean
    if url = invalid or url = "" then return false
    for each favUrl in m.currentFavoriteUrls
        if favUrl = url then return true
    end for
    return false
end function

' Toggles favorite status for the given channel and persists immediately.
' Returns the new state (true = now a favorite). Caller is responsible for
' refreshing any UI that depends on favorite state (bar label, grid if the
' favorites-only filter is active).
function toggleFavorite(channel as Object) as Boolean
    if channel = invalid or channel.url = invalid or channel.url = "" then return false
    url          = channel.url
    newFavorites = []
    wasFavorite  = false
    for each favUrl in m.currentFavoriteUrls
        if favUrl = url then
            wasFavorite = true
        else
            newFavorites.Push(favUrl)
        end if
    end for
    if not wasFavorite then newFavorites.Push(url)
    m.currentFavoriteUrls = newFavorites
    _saveFavoritesForCurrentPlaylist()
    return not wasFavorite
end function

' ---------- Favorites grid view ----------

' Builds a ContentNode tree containing only favorited channels from
' m.flatChannelList (already-parsed, with descriptions/headers intact) and
' shows it in the channel grid. Entered via the "★ Favorites" playlist-panel
' entry; exited the same way any other "playlist" is exited (Left → panel,
' pick the real playlist again, or Back).
sub showFavoritesView()
    m.favoritesOnly = true
    _rebuildFavoritesGrid()
    m.playlistPanelActive = false
    if m.channelList <> invalid then m.channelList.SetFocus(true)
    resetGridInactivityTimer()
end sub

' Rebuilds the favorites ContentNode tree from the current
' m.currentFavoriteUrls + the playlist's full (unfiltered) channel list.
' Call this any time favorites change while the favorites view is showing.
' Always derives from m.fullFlatChannelList (captured the first time the
' favorites view opens) rather than m.flatChannelList, since the latter
' becomes the filtered favorites list itself after the first rebuild —
' filtering that again would happen to work today (filtering is monotonic
' here) but would silently break if this logic ever changes.
sub _rebuildFavoritesGrid()
    if m.fullFlatChannelList = invalid then m.fullFlatChannelList = m.flatChannelList

    ' Group favorited channels by their original category (found via
    ' GetParent() — each channel is a child of its category's SECTION node
    ' in the source tree). buildSortedChannelTree() (shared with the M3U
    ' parser — see components/Shared/PlaylistSort.brs) sorts categories A-Z
    ' and channels A-Z within each, same rules as the main list. Channels
    ' with no real category (ungrouped playlist) fall into a plain trailing
    ' list.
    items = []
    if m.fullFlatChannelList <> invalid then
        for each ch in m.fullFlatChannelList
            if ch <> invalid and isChannelFavorite(ch.url) then
                chTitle = iif(ch.baseTitle <> invalid and ch.baseTitle <> "", ch.baseTitle, ch.title)
                gName   = ""
                parent  = ch.GetParent()
                if parent <> invalid and parent.title <> invalid and parent.title <> "" then gName = parent.title
                items.Push({ url: ch.url, title: chTitle, description: ch.description, group: gName })
            end if
        end for
    end if

    m.allChannels = buildSortedChannelTree(items)
    buildFlatChannelList()
    _syncFavoriteStars()
    _updateChannelListHeader()
    if m.channelList <> invalid then
        m.channelList.content    = m.allChannels
        m.channelList.jumpToItem = 0
    end if
    m.currentChannelIndex = 0
end sub

' Note: there's no separate "exit favorites view" function. Selecting any
' real playlist from the panel (onPlaylistSelected → loadPlaylist → SetContent)
' already resets m.favoritesOnly = false and rebuilds the grid from that
' playlist's actual content, which is exactly the exit path.
