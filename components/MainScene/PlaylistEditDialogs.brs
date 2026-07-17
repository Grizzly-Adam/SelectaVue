' ==================== PlaylistEditDialogs.brs ====================
' Per-playlist options dialog (Edit Name / Edit URL / Delete) and the
' three follow-up dialog flows it triggers. Built-in playlists show a
' read-only notice instead of the options dialog.

' ---------- Per-playlist options dialog ----------

sub showPlaylistOptions()
    rawIdx = m.playlistList.itemFocused
    if rawIdx = 0 then return   ' Favorites entry has no edit/delete options
    selectedIdx = rawIdx - 1
    if selectedIdx < 0 or selectedIdx >= m.playlists.Count() then return
    m.selectedPlaylistIndex = selectedIdx
    selectedPlaylist = m.playlists[selectedIdx]

    ' "Show Hidden Channels" only makes sense for whichever playlist is
    ' actually loaded right now -- hidden channels are checked against
    ' m.rawAllChannels, which only ever holds ONE playlist's parsed data at
    ' a time (see HiddenChannels.brs). Omitted when browsing options for a
    ' different, not-currently-loaded playlist in the list.
    isCurrentlyLoaded = (selectedIdx = m.currentPlaylist)
    viewToggleLabel   = iif(m.hiddenOnly, "Show All Channels", "Show Hidden Channels")

    if selectedPlaylist.isDefault = true then
        if isCurrentlyLoaded then
            _showSimpleDialog(selectedPlaylist.name, "Built-in playlists cannot be edited or removed.", [viewToggleLabel, "OK"], "onDefaultPlaylistDialogClosed")
        else
            _showSimpleDialog(selectedPlaylist.name, "Built-in playlists cannot be edited or removed.", ["OK"], "onDefaultPlaylistDialogClosed")
        end if
        return
    end if

    if isCurrentlyLoaded then
        _showSimpleDialog("Options: " + selectedPlaylist.name, "", ["Edit Name", "Edit URL", "Delete", viewToggleLabel, "Cancel"], "onPlaylistOptionSelected")
    else
        _showSimpleDialog("Options: " + selectedPlaylist.name, "", ["Edit Name", "Edit URL", "Delete", "Cancel"], "onPlaylistOptionSelected")
    end if
end sub

' Shared by both dialog variants above -- toggles between the Hidden
' Channels view and the normal grid. Safe to call unconditionally from the
' playlist panel: that panel only exists in the grid, never fullscreen, so
' there's no fullscreen-exit transition to worry about here (unlike the
' Details-dialog version this replaced, which had to back out of fullscreen
' first).
sub _toggleHiddenChannelsViewFromPlaylistMenu()
    if m.hiddenOnly then
        exitHiddenChannelsView()
    else
        showHiddenChannelsView()
    end if
end sub

sub onDefaultPlaylistDialogClosed()
    buttonIdx   = m.top.dialog.buttonSelected
    buttonCount = m.top.dialog.buttons.Count()
    _closeDialog()
    if buttonCount = 2 and buttonIdx = 0 then
        _toggleHiddenChannelsViewFromPlaylistMenu()
    else
        _returnToPlaylistPanel()
    end if
end sub

sub onPlaylistOptionSelected()
    buttonIdx       = m.top.dialog.buttonSelected
    hasHiddenToggle = (m.top.dialog.buttons.Count() = 5)
    _closeDialog()
    if buttonIdx = 0 then
        _delayedCall("editPlaylistName", 0.2)
    else if buttonIdx = 1 then
        _delayedCall("editPlaylistUrl", 0.2)
    else if buttonIdx = 2 then
        _delayedCall("confirmDeletePlaylist", 0.2)
    else if hasHiddenToggle and buttonIdx = 3 then
        _toggleHiddenChannelsViewFromPlaylistMenu()
    else
        _returnToPlaylistPanel()
    end if
end sub

' ---------- Edit name ----------

sub editPlaylistName()
    _clearOptionTimer()
    if m.selectedPlaylistIndex = invalid then return
    playlist = m.playlists[m.selectedPlaylistIndex]
    _showKeyboardDialog("EDIT NAME", "Enter new name for playlist", playlist.name, ["Save", "Cancel"], "onEditNameComplete")
end sub

sub onEditNameComplete()
    buttonSelected = m.top.dialog.buttonSelected
    if buttonSelected = 0 then
        newName = m.top.dialog.text
        _closeDialog()
        if newName <> "" and newName <> invalid then
            playlist = m.playlists[m.selectedPlaylistIndex]
            playlist.name = newName
            reg      = CreateObject("roRegistrySection", PLAYLISTS_REG_SECTION())
            regIndex = m.selectedPlaylistIndex - BUILTIN_PLAYLIST_COUNT()
            if regIndex >= 0 then
                reg.Write("name_" + regIndex.ToStr(), newName)
                reg.Flush()
            end if
            setupPlaylistMenu()
        end if
    else
        _closeDialog()
    end if
    _returnToPlaylistPanel()
end sub

' ---------- Edit URL ----------

sub editPlaylistUrl()
    _clearOptionTimer()
    if m.selectedPlaylistIndex = invalid then return
    playlist = m.playlists[m.selectedPlaylistIndex]
    _showKeyboardDialog("EDIT URL", "New URL for the M3U playlist", playlist.url, ["Save", "Cancel"], "onEditUrlComplete")
end sub

sub onEditUrlComplete()
    buttonSelected = m.top.dialog.buttonSelected
    if buttonSelected = 0 then
        newUrl = m.top.dialog.text
        _closeDialog()
        if isValidUrl(newUrl) then
            playlist = m.playlists[m.selectedPlaylistIndex]
            playlist.url = newUrl
            reg      = CreateObject("roRegistrySection", PLAYLISTS_REG_SECTION())
            regIndex = m.selectedPlaylistIndex - BUILTIN_PLAYLIST_COUNT()
            if regIndex >= 0 then
                reg.Write("url_" + regIndex.ToStr(), newUrl)
                reg.Flush()
            end if
            m.currentPlaylist = m.selectedPlaylistIndex
            loadPlaylist(newUrl)
        else
            _showPlaylistError("URL invalid. Must start with http:// or https://")
        end if
    else
        _closeDialog()
        _returnToPlaylistPanel()
    end if
end sub

' ---------- Delete ----------

sub confirmDeletePlaylist()
    _clearOptionTimer()
    if m.selectedPlaylistIndex = invalid then return
    playlist = m.playlists[m.selectedPlaylistIndex]
    _showSimpleDialog("Are you sure?", "Delete '" + playlist.name + "'?", ["Delete", "Cancel"], "onDeleteConfirmed")
end sub

sub onDeleteConfirmed()
    buttonSelected = m.top.dialog.buttonSelected
    _closeDialog()
    if buttonSelected = 0 then
        m.playlists.Delete(m.selectedPlaylistIndex)
        reg      = CreateObject("roRegistrySection", PLAYLISTS_REG_SECTION())
        newIndex = 0
        for i = BUILTIN_PLAYLIST_COUNT() to m.playlists.Count() - 1
            pl = m.playlists[i]
            if pl.isDefault = false then
                reg.Write("name_" + newIndex.ToStr(), pl.name)
                reg.Write("url_"  + newIndex.ToStr(), pl.url)
                newIndex = newIndex + 1
            end if
        end for
        reg.Write("count", newIndex.ToStr())
        reg.Flush()
        setupPlaylistMenu()
        ' Deleting shifts every index after the deleted one — if the deleted
        ' playlist was at or before m.currentPlaylist, that index no longer
        ' points at the same playlist. Fall back to playlist 0 and keep
        ' m.currentPlaylist in sync with whatever we actually load below.
        if m.playlists.Count() > 0 then
            m.currentPlaylist = 0
            loadPlaylist(m.playlists[0].url)
        else
            m.currentPlaylist = 0
        end if
    end if
    _returnToPlaylistPanel()
end sub
