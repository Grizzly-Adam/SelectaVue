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
    ' BUILTIN_PLAYLIST_COUNT() in Utils.brs counts these automatically via
    ' isDefault, so no separate constant to keep in sync when editing this list.
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
    ' Jump panel focus to the newly added playlist so user sees it immediately
    newIdx = m.playlists.Count()   ' +1 for Favorites entry at index 0
    m.playlistList.jumpToItem = newIdx
    m.playlistFocusIndex      = newIdx
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
    print ">>> LOADDLG: onPlaylistSelected called, loadingDialogVisible="; m.loadingDialogVisible; " isPlayingVideo="; m.isPlayingVideo
    if m.loadingDialogVisible then
        print ">>> LOADDLG: onPlaylistSelected -- dialog already visible, dismissing for input and returning without loading"
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
        playlistIdx = selectedIdx - 1
        ' Re-selecting the already-loaded playlist is the "refresh this
        ' playlist" gesture, but only in the standard grid. While browsing
        ' Favorites or Hidden Channels, it's not a refresh action — those
        ' are filtered views layered on top of whatever's loaded, and
        ' reloading here would just be an unwanted interruption (loading
        ' dialog, re-parse) for someone who didn't ask for one.
        if playlistIdx = m.currentPlaylist and (m.favoritesOnly or m.hiddenOnly) then
            ' Not a reload/refresh request -- browsing a filtered view and
            ' re-selecting the playlist that's already loaded means "take
            ' me back to the standard grid", no playlist reload/reparse.
            returnToStandardGridView()
            return
        end if
        m.currentPlaylist   = playlistIdx
        m.pendingChannelUrl = invalid
        _captureChannelBeforePlaylistSwitch()
        print ">>> LOADDLG: onPlaylistSelected -- about to call loadPlaylist for playlistIdx="; playlistIdx
        loadPlaylist(m.playlists[playlistIdx].url)
        saveLastState()
    end if
end sub
