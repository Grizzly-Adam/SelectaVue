' ==================== PlaylistManager.brs ====================
' Built-in + user-added playlist data: load/save from roRegistrySection,
' the side-panel menu (with the "★ Favorites" entry at index 0 — see
' Favorites.brs), and playlist selection.
'
' Uses BUILTIN_PLAYLIST_COUNT from Utils.brs to calculate registry offsets.
' Edit/Delete dialogs live in PlaylistEditDialogs.brs; the add-new-playlist
' flow and shared dialog helpers live in PlaylistAddDialog.brs.

' ---------- Load & Save ----------

function PLAYLISTS_REG_SECTION() as String
    return "playlists"
end function

sub loadSavedPlaylists()
    reg = CreateObject("roRegistrySection", PLAYLISTS_REG_SECTION())
    m.playlists = []

    ' Built-in playlists — isDefault = true, never written to registry.
    ' If you add or remove entries here, update BUILTIN_PLAYLIST_COUNT in Utils.brs.
    m.playlists.Push({ name: "Southdale Labs", url: "https://grizz.atwebpages.com/grizz.m3u",           isDefault: true })
    m.playlists.Push({ name: "United States",  url: "https://iptv-org.github.io/iptv/countries/us.m3u", isDefault: true })
    m.playlists.Push({ name: "Canada",         url: "https://iptv-org.github.io/iptv/countries/ca.m3u", isDefault: true })
    m.playlists.Push({ name: "United Kingdom", url: "https://iptv-org.github.io/iptv/countries/uk.m3u", isDefault: true })
    m.playlists.Push({ name: "Australia",      url: "https://iptv-org.github.io/iptv/countries/au.m3u", isDefault: true })

    ' User-added playlists from registry
    if reg.Exists("count") then
        count = reg.Read("count").ToInt()
        for i = 0 to count - 1
            name = reg.Read("name_" + i.ToStr())
            url  = reg.Read("url_"  + i.ToStr())
            if name <> invalid and url <> invalid then
                m.playlists.Push({ name: name, url: url, isDefault: false })
            end if
        end for
    end if
end sub

sub savePlaylist(name as String, url as String)
    reg   = CreateObject("roRegistrySection", PLAYLISTS_REG_SECTION())
    count = 0
    if reg.Exists("count") then count = reg.Read("count").ToInt()
    reg.Write("name_" + count.ToStr(), name)
    reg.Write("url_"  + count.ToStr(), url)
    reg.Write("count", (count + 1).ToStr())
    reg.Flush()
    m.playlists.Push({ name: name, url: url, isDefault: false })
    setupPlaylistMenu()
end sub

' ---------- Menu setup ----------

sub setupPlaylistMenu()
    content = CreateObject("roSGNode", "ContentNode")
    favItem = content.CreateChild("ContentNode")
    favItem.title = "★ Favorites"
    for each playlist in m.playlists
        item = content.CreateChild("ContentNode")
        item.title = playlist.name
    end for
    item = content.CreateChild("ContentNode")
    item.title = "+ Add new playlist"
    m.playlistList.content = content
    ' +1 because index 0 is now the Favorites entry, not the first real playlist
    m.playlistFocusIndex   = m.currentPlaylist + 1
    m.playlistList.jumpToItem = m.playlistFocusIndex
end sub

' Up/down navigation on the side panel — mirrors onChannelFocused /
' onOverlayItemFocused; without this, the shader could only be dismissed
' from the playlist panel via OK/back/left/right/replay/options, not up/down.
sub onPlaylistFocused()
    if m.loadingDialogVisible then _dismissLoadingDialogForInput()
    cancelAnyInFlightRetry()
    _dismissScreensaverIfVisible()
end sub

sub onPlaylistSelected()
    if m.loadingDialogVisible then
        _dismissLoadingDialogForInput()
        return
    end if
    if _dismissScreensaverIfVisible() then return
    cancelAnyInFlightRetry()
    selectedIdx = m.playlistList.itemSelected
    if selectedIdx = 0 then
        showFavoritesView()
    else if selectedIdx = m.playlists.Count() + 1 then
        showPlaylistManager()
    else if selectedIdx >= 1 and selectedIdx <= m.playlists.Count() then
        playlistIdx         = selectedIdx - 1
        m.currentPlaylist   = playlistIdx
        m.pendingChannelUrl = invalid
        loadPlaylist(m.playlists[playlistIdx].url)
        saveLastState()
    end if
end sub
