' ==================== PlaylistEditDialogs.brs ====================
' Per-playlist options dialog (Edit Name / Edit URL / Delete) and the
' three follow-up dialog flows it triggers. Built-in playlists get the same
' dialog as custom ones -- see loadSavedPlaylists() in PlaylistManager.brs
' for how their edits/deletes persist per-device without ever touching the
' hardcoded defaults or affecting other installs.

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

    buttons = ["Edit Name", "Edit URL", "Delete"]
    if isCurrentlyLoaded then buttons.Push(viewToggleLabel)
    buttons.Push("Cancel")
    _showThemedMenuDialog("Options: " + selectedPlaylist.name, buttons, "onPlaylistOptionSelected")
    resetOptionsDialogTimer()
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

sub onPlaylistOptionSelected()
    buttonIdx = m.themedMenuDialog.buttonSelected
    if buttonIdx = -1 then return   ' -1 is the reset default, never a real press
    hasHiddenToggle = (m.themedMenuDialog.buttons.Count() = 5)
    _closeThemedMenuDialog()
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
    _showPhoneKeyboardDialog("EDIT NAME", "Enter new name for playlist", playlist.name, "Save", "onEditNameComplete", true)
end sub

sub onEditNameComplete()
    buttonSelected = m.phoneKeyboardDialog.buttonSelected
    if buttonSelected = -1 then return
    if buttonSelected = 0 then
        newName = m.phoneKeyboardDialog.text
        if newName = "" or newName = invalid then
            _showKeyboardErrorDialog("Name Required", "Playlist name cannot be empty", false, "onSimpleErrorPhoneAction")
            return
        end if
        _closePhoneKeyboardDialog()
        playlist = m.playlists[m.selectedPlaylistIndex]
        playlist.name = newName
        reg = CreateObject("roRegistrySection", PLAYLISTS_REG_SECTION())
        if playlist.isDefault = true then
            reg.Write("builtin_name_" + playlist.builtinSlot.ToStr(), newName)
            reg.Flush()
        else
            regIndex = m.selectedPlaylistIndex - BUILTIN_PLAYLIST_COUNT()
            if regIndex >= 0 then
                reg.Write("name_" + regIndex.ToStr(), newName)
                reg.Flush()
            end if
        end if
        setupPlaylistMenu()
        _returnToPlaylistPanel()
    else
        _closePhoneKeyboardDialog()
        _returnToPlaylistPanel()
    end if
end sub

' ---------- Edit URL ----------

sub editPlaylistUrl()
    _clearOptionTimer()
    if m.selectedPlaylistIndex = invalid then return
    playlist = m.playlists[m.selectedPlaylistIndex]
    _showPhoneKeyboardDialog("EDIT URL", "New URL for the M3U playlist", playlist.url, "Save", "onEditUrlComplete")
end sub

sub onEditUrlComplete()
    buttonSelected = m.phoneKeyboardDialog.buttonSelected
    if buttonSelected = -1 then return
    if buttonSelected = 0 then
        newUrl = m.phoneKeyboardDialog.text
        if newUrl = "" or newUrl = invalid then
            _showKeyboardErrorDialog("URL Required", "Playlist URL cannot be empty", false, "onSimpleErrorPhoneAction")
            return
        end if
        if Left(LCase(newUrl), 7) <> "http://" and Left(LCase(newUrl), 8) <> "https://" then
            newUrl = "http://" + newUrl
        end if
        _closePhoneKeyboardDialog()
        playlist = m.playlists[m.selectedPlaylistIndex]
        playlist.url = newUrl
        reg = CreateObject("roRegistrySection", PLAYLISTS_REG_SECTION())
        if playlist.isDefault = true then
            reg.Write("builtin_url_" + playlist.builtinSlot.ToStr(), newUrl)
            reg.Flush()
        else
            regIndex = m.selectedPlaylistIndex - BUILTIN_PLAYLIST_COUNT()
            if regIndex >= 0 then
                reg.Write("url_" + regIndex.ToStr(), newUrl)
                reg.Flush()
            end if
        end if
        m.currentPlaylist = m.selectedPlaylistIndex
        _captureCurrentlyPlayingChannel()   ' see the matching fix/comment in onPlaylistUrlEntered() (PlaylistAddDialog.brs)
        loadPlaylist(newUrl)
    else
        _closePhoneKeyboardDialog()
        _returnToPlaylistPanel()
    end if
end sub

' ---------- Delete ----------

sub confirmDeletePlaylist()
    _clearOptionTimer()
    if m.selectedPlaylistIndex = invalid then return
    playlist = m.playlists[m.selectedPlaylistIndex]
    _showThemedMessageDialog("Are you sure?", "Delete '" + playlist.name + "'?", ["Delete", "Cancel"], "onDeleteConfirmed", 700, 360)
end sub

sub onDeleteConfirmed()
    buttonSelected = m.themedMessageDialog.buttonSelected
    if buttonSelected = -1 then return   ' -1 is the reset default, never a real press
    _closeThemedMessageDialog()
    if buttonSelected = 0 then
        deletedPlaylist = m.playlists[m.selectedPlaylistIndex]
        m.playlists.Delete(m.selectedPlaylistIndex)
        reg = CreateObject("roRegistrySection", PLAYLISTS_REG_SECTION())
        if deletedPlaylist.isDefault = true then
            ' Tombstone this slot so loadSavedPlaylists() skips it on future
            ' loads -- separate namespace from the custom-playlist rewrite
            ' below, so it can't disturb any custom playlist's registry keys.
            reg.Write("builtin_deleted_" + deletedPlaylist.builtinSlot.ToStr(), "true")
            reg.Flush()
        end if
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
            _captureCurrentlyPlayingChannel()   ' see the matching fix/comment in onPlaylistUrlEntered() (PlaylistAddDialog.brs)
            loadPlaylist(m.playlists[0].url)
        else
            m.currentPlaylist = 0
        end if
    end if
    _returnToPlaylistPanel()
end sub
