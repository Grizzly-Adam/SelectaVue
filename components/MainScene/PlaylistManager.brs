' ==================== PlaylistManager.brs ====================
' Handles the built-in and user-added playlists:
'   - Loading/saving from roRegistrySection
'   - The playlist side-panel menu
'   - Add / Edit name / Edit URL / Delete dialogs

' ---------- Load & Save ----------

sub loadSavedPlaylists()
    reg = CreateObject("roRegistrySection", "playlists")
    m.playlists = []

    ' Built-in playlists (isDefault = true, never written to registry)
    m.playlists.Push({ name: "Grizz",          url: "https://grizz.atwebpages.com/grizz.m3u",                   isDefault: true })
    m.playlists.Push({ name: "United States",   url: "https://iptv-org.github.io/iptv/countries/us.m3u",         isDefault: true })
    m.playlists.Push({ name: "Canada",          url: "https://iptv-org.github.io/iptv/countries/ca.m3u",         isDefault: true })
    m.playlists.Push({ name: "United Kingdom",  url: "https://iptv-org.github.io/iptv/countries/uk.m3u",         isDefault: true })
    m.playlists.Push({ name: "Australia",       url: "https://iptv-org.github.io/iptv/countries/au.m3u",         isDefault: true })

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
    reg = CreateObject("roRegistrySection", "playlists")

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

    for each playlist in m.playlists
        item = content.CreateChild("ContentNode")
        item.title = playlist.name
    end for

    item = content.CreateChild("ContentNode")
    item.title = "+ Add new playlist"

    m.playlistList.content = content
    m.playlistFocusIndex = m.currentPlaylist
    m.playlistList.jumpToItem = m.playlistFocusIndex
end sub

sub onPlaylistSelected()
    selectedIdx = m.playlistList.itemSelected

    if selectedIdx = m.playlists.Count() then
        showPlaylistManager()
    else if selectedIdx >= 0 and selectedIdx < m.playlists.Count() then
        m.currentPlaylist = selectedIdx
        m.pendingChannelUrl = invalid
        loadPlaylist(m.playlists[selectedIdx].url)
        saveLastState()
    end if
end sub

' ---------- Options dialog (per playlist) ----------

sub showPlaylistOptions()
    selectedIdx = m.playlistList.itemFocused
    if selectedIdx < 0 or selectedIdx >= m.playlists.Count() then return

    selectedPlaylist = m.playlists[selectedIdx]

    if selectedPlaylist.isDefault = true then
        dialog = CreateObject("roSGNode", "Dialog")
        dialog.title   = selectedPlaylist.name
        dialog.message = "Built-in playlists cannot be edited or removed."
        dialog.buttons = ["OK"]
        m.top.dialog = dialog
        m.top.dialog.observeField("buttonSelected", "onDefaultPlaylistDialogClosed")
        return
    end if

    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title   = "Options: " + selectedPlaylist.name
    dialog.buttons = ["Edit Name", "Edit URL", "Delete", "Cancel"]
    m.top.dialog = dialog
    m.selectedPlaylistIndex = m.playlistList.itemFocused
    m.top.dialog.observeField("buttonSelected", "onPlaylistOptionSelected")
end sub

sub onDefaultPlaylistDialogClosed()
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true
    m.playlistList.setFocus(true)
    m.playlistPanelActive = true
end sub

sub onPlaylistOptionSelected()
    buttonIdx = m.top.dialog.buttonSelected
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true

    if buttonIdx = 0 then
        _delayedCall("editPlaylistName", 0.2)
    else if buttonIdx = 1 then
        _delayedCall("editPlaylistUrl", 0.2)
    else if buttonIdx = 2 then
        _delayedCall("confirmDeletePlaylist", 0.2)
    else
        m.playlistList.setFocus(true)
        m.playlistPanelActive = true
    end if
end sub

' ---------- Edit name ----------

sub editPlaylistName()
    _clearOptionTimer()
    if m.selectedPlaylistIndex = invalid then return

    playlist = m.playlists[m.selectedPlaylistIndex]

    keyboard = createObject("roSGNode", "StandardKeyboardDialog")
    keyboard.backgroundUri = ""
    keyboard.title   = "EDIT NAME"
    keyboard.message = "Enter new name for playlist"
    keyboard.text    = playlist.name
    keyboard.buttons = ["Save", "Cancel"]
    m.top.dialog = keyboard
    m.top.dialog.observeField("buttonSelected", "onEditNameComplete")
end sub

sub onEditNameComplete()
    buttonSelected = m.top.dialog.buttonSelected

    if buttonSelected = 0 then
        newName = m.top.dialog.text
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true

        if newName <> "" and newName <> invalid then
            playlist = m.playlists[m.selectedPlaylistIndex]
            playlist.name = newName

            reg = CreateObject("roRegistrySection", "playlists")
            regIndex = m.selectedPlaylistIndex - 6   ' offset past the 5 built-ins (0-indexed) — adjust if built-in count changes
            if regIndex >= 0 then
                reg.Write("name_" + regIndex.ToStr(), newName)
                reg.Flush()
            end if

            setupPlaylistMenu()
        end if
    else
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
    end if

    m.playlistList.setFocus(true)
    m.playlistPanelActive = true
end sub

' ---------- Edit URL ----------

sub editPlaylistUrl()
    _clearOptionTimer()
    if m.selectedPlaylistIndex = invalid then return

    playlist = m.playlists[m.selectedPlaylistIndex]

    keyboard = createObject("roSGNode", "StandardKeyboardDialog")
    keyboard.backgroundUri = ""
    keyboard.title   = "EDIT URL"
    keyboard.message = "New URL for the M3U playlist"
    keyboard.text    = playlist.url
    keyboard.buttons = ["Save", "Cancel"]
    m.top.dialog = keyboard
    m.top.dialog.observeField("buttonSelected", "onEditUrlComplete")
end sub

sub onEditUrlComplete()
    buttonSelected = m.top.dialog.buttonSelected

    if buttonSelected = 0 then
        newUrl = m.top.dialog.text
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true

        if isValidUrl(newUrl) then
            playlist = m.playlists[m.selectedPlaylistIndex]
            playlist.url = newUrl

            reg = CreateObject("roRegistrySection", "playlists")
            regIndex = m.selectedPlaylistIndex - 6
            if regIndex >= 0 then
                reg.Write("url_" + regIndex.ToStr(), newUrl)
                reg.Flush()
            end if

            loadPlaylist(newUrl)
        else
            m.pendingErrorMessage = "URL invalid. Must start with http:// or https://"
            _delayedCall("showEditUrlError", 0.3)
        end if
    else
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
        m.playlistList.setFocus(true)
        m.playlistPanelActive = true
    end if
end sub

sub showEditUrlError()
    if m.editUrlErrorTimer <> invalid then
        m.editUrlErrorTimer.unobserveField("fire")
        m.editUrlErrorTimer = invalid
    end if

    errorDialog = CreateObject("roSGNode", "Dialog")
    errorDialog.title   = "Error"
    errorDialog.message = "URL invalid. Must start with http:// or https://"
    errorDialog.buttons = ["OK"]
    m.top.dialog = errorDialog
    m.top.dialog.observeField("buttonSelected", "onEditUrlErrorClosed")
end sub

sub onEditUrlErrorClosed()
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true
    m.playlistList.setFocus(true)
    m.playlistPanelActive = true
end sub

' ---------- Delete playlist ----------

sub confirmDeletePlaylist()
    _clearOptionTimer()
    if m.selectedPlaylistIndex = invalid then return

    playlist = m.playlists[m.selectedPlaylistIndex]

    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title   = "Are you sure?"
    dialog.message = "Delete '" + playlist.name + "'?"
    dialog.buttons = ["Delete", "Cancel"]
    m.top.dialog = dialog
    m.top.dialog.observeField("buttonSelected", "onDeleteConfirmed")
end sub

sub onDeleteConfirmed()
    buttonSelected = m.top.dialog.buttonSelected
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true

    if buttonSelected = 0 then
        m.playlists.Delete(m.selectedPlaylistIndex)

        ' Re-write all user playlists to registry
        reg = CreateObject("roRegistrySection", "playlists")
        newIndex = 0
        for i = 6 to m.playlists.Count() - 1   ' skip 5 built-ins (0-indexed)
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

        if m.playlists.Count() > 0 then loadPlaylist(m.playlists[0].url)
    end if

    m.playlistList.setFocus(true)
    m.playlistPanelActive = true
end sub

' ---------- Add new playlist (two-step dialog) ----------

sub showPlaylistManager()
    print ">>> PLAYLIST MANAGER: Starting step one: NAME <<<"

    if m.top.dialog <> invalid then
        m.top.dialog.close = true
        m.top.dialog = invalid
    end if

    if m.urlDialogTimer <> invalid then
        m.urlDialogTimer.control = "stop"
        m.urlDialogTimer = invalid
    end if

    m.tempPlaylistName = invalid

    keyboardDialog = createObject("roSGNode", "StandardKeyboardDialog")
    keyboardDialog.backgroundUri = ""
    keyboardDialog.title   = "NEW PLAYLIST - STEP 1/2: Enter name (ex: My list)"
    keyboardDialog.message = "Enter name (ex: My list)"
    keyboardDialog.buttons = ["Next", "Cancel"]
    keyboardDialog.text    = ""
    m.top.dialog = keyboardDialog
    m.top.dialog.observeField("buttonSelected", "onPlaylistNameEntered")
end sub

sub onPlaylistNameEntered()
    buttonSelected = m.top.dialog.buttonSelected

    if buttonSelected = 0 then
        name = m.top.dialog.text
        if name = "" or name = invalid then name = "New Playlist"

        m.tempPlaylistName = name
        print ">>> PLAYLIST NAME: Name saved = "; m.tempPlaylistName

        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true

        _delayedCall("showUrlDialog", 0.3)
    else
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
        m.tempPlaylistName = invalid
        m.playlistList.setFocus(true)
        m.playlistPanelActive = true
    end if
end sub

sub showUrlDialog()
    if m.urlDialogTimer <> invalid then
        m.urlDialogTimer.unobserveField("fire")
        m.urlDialogTimer = invalid
    end if

    if m.tempPlaylistName = invalid then
        print ">>> URL DIALOG ERROR: No name saved"
        m.playlistList.setFocus(true)
        m.playlistPanelActive = true
        return
    end if

    urlDialog = createObject("roSGNode", "StandardKeyboardDialog")
    urlDialog.backgroundUri = ""
    urlDialog.title   = "NEW PLAYLIST - PART 2/2: ENTER URL (http://...)"
    urlDialog.buttons = ["Add", "Cancel"]
    urlDialog.text    = ""
    m.top.dialog = urlDialog
    m.top.dialog.observeField("buttonSelected", "onPlaylistUrlEntered")
end sub

sub onPlaylistUrlEntered()
    buttonSelected = m.top.dialog.buttonSelected

    if buttonSelected = 0 then
        url = m.top.dialog.text
        print ">>> PLAYLIST URL: URL entered = "; url

        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true

        if url = "" or url = invalid then
            showUrlErrorMessage("URL cannot be empty")
            return
        end if

        if not isValidUrl(url) then
            showUrlErrorMessage("URL invalid. Must start with http:// or https://")
            return
        end if

        if m.tempPlaylistName <> invalid then
            savePlaylist(m.tempPlaylistName, url)
            loadPlaylist(url)
        end if

        m.tempPlaylistName = invalid
        m.playlistList.setFocus(true)
        m.playlistPanelActive = true
    else
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
        m.tempPlaylistName = invalid
        m.playlistList.setFocus(true)
        m.playlistPanelActive = true
    end if
end sub

sub showUrlErrorMessage(message as String)
    m.pendingErrorMessage = message
    _delayedCall("showUrlError", 0.3)
end sub

sub showUrlError()
    if m.errorTimer <> invalid then
        m.errorTimer.unobserveField("fire")
        m.errorTimer = invalid
    end if

    message = "URL invalid. Must start with http:// or https://"
    if m.pendingErrorMessage <> invalid then
        message = m.pendingErrorMessage
        m.pendingErrorMessage = invalid
    end if

    errorDialog = CreateObject("roSGNode", "Dialog")
    errorDialog.title   = "Error"
    errorDialog.message = message
    errorDialog.buttons = ["OK"]
    m.top.dialog = errorDialog
    m.top.dialog.observeField("buttonSelected", "onErrorDialogClosed")
end sub

sub onErrorDialogClosed()
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true
    m.playlistList.setFocus(true)
    m.playlistPanelActive = true
end sub

' ---------- Private helpers ----------

' Creates a one-shot timer that calls `callbackName` after `delaySec` seconds.
' Stores the timer in m.optionTimer so it can be cancelled if needed.
sub _delayedCall(callbackName as String, delaySec as Float)
    m.optionTimer = CreateObject("roSGNode", "Timer")
    m.optionTimer.duration = delaySec
    m.optionTimer.repeat  = false
    m.optionTimer.observeField("fire", callbackName)
    m.optionTimer.control = "start"
end sub

sub _clearOptionTimer()
    if m.optionTimer <> invalid then
        m.optionTimer.unobserveField("fire")
        m.optionTimer = invalid
    end if
end sub
