sub init()
    m.top.backgroundURI = ""
    m.top.backgroundColor = "0x024c48FF"

    m.get_channel_list = m.top.FindNode("get_channel_list")
    m.get_channel_list.ObserveField("content", "SetContent")
    
    m.playlistList = m.top.FindNode("playlistList")
    m.playlistList.ObserveField("itemSelected", "onPlaylistSelected")
    
    m.channelList = m.top.FindNode("channelList")
    m.channelList.ObserveField("itemFocused", "onChannelFocused")
    m.channelList.ObserveField("itemSelected", "onChannelSelected")
    
    m.sidePanel = m.top.FindNode("sidePanel")
    m.loadingSpinnerContainer = m.top.FindNode("loadingSpinnerContainer")
    
    m.channelOverlay = m.top.FindNode("channelOverlay")
    m.channelOverlayList = m.top.FindNode("channelOverlayList")
    m.channelOverlayList.ObserveField("itemSelected", "onOverlayChannelSelected")
    m.channelOverlayList.ObserveField("itemFocused", "onOverlayItemFocused")
    
    m.channelInfoOverlay = m.top.FindNode("channelInfoOverlay")
    m.channelInfoLabel = m.top.FindNode("channelInfoLabel")
    m.clockLabel = m.top.FindNode("clockLabel")
    m.errorOverlay = m.top.FindNode("errorOverlay")
    m.errorTitleLabel = m.top.FindNode("errorTitleLabel")
    m.errorChannelLabel = m.top.FindNode("errorChannelLabel")
    m.errorMessageLabel = m.top.FindNode("errorMessageLabel")
    
    ' Single video node used for both preview and fullscreen
    m.PreviewVideo = m.top.FindNode("PreviewVideo")
    m.previewVideo = m.top.FindNode("PreviewVideo")
    m.previewChannelName = m.top.FindNode("previewChannelName")
    
    if m.previewVideo <> invalid then
        m.previewVideo.EnableCookies()
        m.previewVideo.SetCertificatesFile("common:/certs/ca-bundle.crt")
        m.previewVideo.InitClientCertificates()
        m.previewVideo.ObserveField("state", "checkState")
        m.previewVideo.ObserveField("bufferingStatus", "onBufferingStatus")
    end if

    if m.loadingSpinnerContainer <> invalid then
        m.loadingSpinnerContainer.visible = false
    end if
    
    m.allChannels = invalid
    m.flatChannelList = []
    m.currentChannelIndex = 0
    m.previewChannelIndex = -1
    m.playlists = []
    m.currentPlaylist = 0
    m.isPlayingVideo = false
    m.overlayVisible = false
    m.previewMuted = false
    m.errorVisible = false
    m.lastErrorMsg = ""
    m.lastErrorChannelIndex = -1
    m.bufferVisible = false
    m.bitrateRetryDone = false
    m.playlistPanelActive = false
    m.playlistFocusIndex = 0
    m.suppressFocusChange = false
    m.stallRetryCount = 0
    m.lastBufferPct = -1
    m.stallTimer = invalid
    m.muteIndicatorTimer = invalid
    m.gridInactivityTimer = invalid
    m.overlayInactivityTimer = invalid
    m.fullscreenInactivityTimer = invalid
    m.optionsDialogTimer = invalid
    m.screensaverOverlay = m.top.FindNode("screensaverOverlay")
    m.fullscreenFailContainer = m.top.FindNode("fullscreenFailContainer")
    m.fullscreenFailLabel = m.top.FindNode("fullscreenFailLabel")
    m.fullscreenFailChannel = m.top.FindNode("fullscreenFailChannel")
    m.previewErrorContainer = m.top.FindNode("previewErrorContainer")
    m.previewHintLabel = m.top.FindNode("previewHintLabel")
    m.muteIndicatorContainer = m.top.FindNode("muteIndicatorContainer")
    m.muteIndicatorImage = m.top.FindNode("muteIndicatorImage")
    m.videoClipLeft = m.top.FindNode("VideoClipLeft")
    m.muteHintContainer = m.top.FindNode("muteHintContainer")
    m.tvOverlay = m.top.FindNode("TV overlay")
    m.previewChannelNameContainer = m.top.FindNode("previewChannelNameContainer")
    m.previewChannelNameLabel = m.top.FindNode("previewChannelNameLabel")
    m.bufferContainer = m.top.FindNode("bufferContainer")
    m.bufferFill = m.top.FindNode("bufferFill")
    m.bufferLabel = m.top.FindNode("bufferLabel")
    m.bufferTrack = m.top.FindNode("bufferTrack")
    m.focusTrap = m.top.FindNode("focusTrap")
    updatePreviewHint()
    m.lastFocusedChannel = -1
    m.pendingChannelUrl = invalid
    m.suppressNextVideoOptionsMenu = false
    
    loadSavedPlaylists()
    setupPlaylistMenu()
    
    ' Load the last saved state
    lastState = loadLastState()
    
    if m.playlists.Count() > 0 then
        ' Use the last playlist if it exists; otherwise, use the first one.
        playlistIndex = 0
        if lastState.playlistIndex <> invalid and lastState.playlistIndex >= 0 and lastState.playlistIndex < m.playlists.Count() then
            playlistIndex = lastState.playlistIndex
        end if
        
        m.currentPlaylist = playlistIndex
        m.playlistList.jumpToItem = playlistIndex
        
        ' Keep the last channel URL so it can be selected again after loading.
        if lastState.channelUrl <> invalid and lastState.channelUrl <> "" then
            m.pendingChannelUrl = lastState.channelUrl
        end if
        
        loadPlaylist(m.playlists[playlistIndex].url)
    else
        showPlaylistManager()
    end if
    
    ' Signal that the app launch is complete and UI is ready
    m.top.signalBeacon("AppLaunchComplete")
End sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    print ">>> KEYEVENT: key = '"; key; "', press = "; press; ", isPlayingVideo = "; m.isPlayingVideo
    result = false
    
    if(press)
        ' If screensaver is visible, dismiss it and consume the key - do nothing else
        if m.screensaverOverlay <> invalid and m.screensaverOverlay.visible then
            m.screensaverOverlay.visible = false
            resetGridInactivityTimer()
            return true
        end if

        ' Reset inactivity timers on any key press
        if not m.isPlayingVideo then resetGridInactivityTimer()
        if m.isPlayingVideo and (m.fullscreenFailContainer = invalid or not m.fullscreenFailContainer.visible) then resetFullscreenInactivityTimer()
        if m.overlayVisible then resetOverlayInactivityTimer()

        ' If error overlay is visible, dismiss it on any key (grid/preview only)
        if m.errorVisible and not m.isPlayingVideo then
            hideErrorOverlay()
            m.channelList.SetFocus(true)
            resetGridInactivityTimer()
            return true
        end if

        if m.isPlayingVideo then
            if(key = "back")
                ' Resize video back to preview window
                m.suppressFocusChange = true
                m.previewVideo.translation = [1380, 145]
                m.previewVideo.width = 444
                m.previewVideo.height = 250
                m.previewVideo.mute = m.previewMuted
                m.previewVideo.trickplaybarvisibilityauto = true
                hideBufferBar()
                cancelStallTimer()
                m.lastBufferPct = -1
                if m.fullscreenFailContainer <> invalid then m.fullscreenFailContainer.visible = false

                ' Restore preview error if this channel previously failed
                if m.lastErrorMsg <> "" and m.lastErrorChannelIndex = m.currentChannelIndex then
                    showPreviewError(m.lastErrorMsg)
                end if

                ' Only reshow buffer bar if channel is buffering AND has no error
                if m.previewVideo.state = "buffering" and m.lastErrorChannelIndex <> m.currentChannelIndex then
                    m.bufferContainer.translation = [1467, 252]
                    m.bufferContainer.width = 283
                    m.bufferTrack.width = 277
                    m.bufferLabel.width = 283
                    m.bufferContainer.visible = true
                    m.bufferVisible = true
                    status = m.previewVideo.bufferingStatus
                    if status <> invalid and status.percentage <> invalid then
                        updateBufferBar(status.percentage)
                    end if
                end if

                hideOverlay()
                m.channelList.visible = true
                m.sidePanel.visible = true
                showGridOverlays()
                m.isPlayingVideo = false
                m.top.backgroundURI = ""
    m.top.backgroundColor = "0x024c48FF"

                if m.currentChannelIndex >= 0 then
                    m.channelList.jumpToItem = m.currentChannelIndex
                end if
                m.channelList.SetFocus(true)
                m.suppressFocusChange = false
                resetGridInactivityTimer()
                result = true
            else if(key = "left")
                print ">>> QUICKMENU: Left arrow - toggling quick menu"
                print ">>> QUICKMENU: quickMenuVisible = "; m.overlayVisible
                print ">>> QUICKMENU: allChannels = "; m.allChannels
                
                if m.overlayVisible then
                    print ">>> QUICKMENU: Hiding quick menu"
                    hideOverlay()
                    m.top.setFocus(true)
                else
                    print ">>> QUICKMENU: Showing quick menu"
                    if m.allChannels <> invalid then
                        m.channelOverlay.visible = true
                        m.overlayVisible = true
                        m.channelOverlayList.content = m.allChannels
                        m.channelOverlayList.jumpToItem = m.currentChannelIndex
                        m.channelOverlayList.itemFocused = m.currentChannelIndex
                        m.channelOverlayList.SetFocus(true)
                        resetOverlayInactivityTimer()
                        print ">>> QUICKMENU: Quick menu visible, channels loaded"
                    else
                        print ">>> OVERLAY ERROR: No channels available for quick menu"
                    end if
                end if
                result = true
            else if(key = "right" and m.overlayVisible)
                hideOverlay()
                m.top.setFocus(true)
                result = true
            else if(key = "right" and not m.overlayVisible)
                ' Toggle mute for fullscreen video
                m.previewMuted = not m.previewMuted
                m.previewVideo.mute = m.previewMuted
                showMuteIndicator()
                result = true
            else if(key = "up")
                if not m.overlayVisible then
                    changeChannel(-1)
                    result = true
                end if
            else if(key = "down")
                if not m.overlayVisible then
                    changeChannel(1)
                    result = true
                end if
            else if(key = "OK")
                ' Display the options menu only when the video is already playing
                if m.suppressNextVideoOptionsMenu then
                    print ">>> KEY OK: Suppressing options menu after quick menu channel selection"
                    clearOverlayOkSuppression()
                    result = true
                else if m.overlayVisible then
                    channel = m.flatChannelList[m.currentChannelIndex]
                    if channel <> invalid then
                        m.suppressNextVideoOptionsMenu = true
                        startOverlayOkSuppressionTimer()
                        hideOverlay()
                        playChannel(channel)
                    end if
                    result = true
                else if m.previewVideo.state = "playing" or m.previewVideo.state = "paused" or m.previewVideo.state = "buffering" then
                    showVideoOptionsMenu()
                    result = true
                end if
            else if(key = "play")
                ' Play/Pause the video
                if m.previewVideo.state = "playing" then
                    m.previewVideo.control = "pause"
                else
                    m.previewVideo.control = "resume"
                end if
                result = true
            else if(key = "replay")
                ' Reload the current channel (Instant Replay)
                reloadCurrentChannel()
                result = true
            end if
        else
            if(key = "back")
                if m.playlistPanelActive then
                    ' On playlist panel - go fullscreen if preview playing, otherwise consume
                    if m.previewVideo.state = "playing" then
                        m.top.backgroundURI = ""
                        m.top.backgroundColor = "0x024c48FF"
                        m.previewVideo.trickplaybarvisibilityauto = false
                        m.previewVideo.translation = [0, 0]
                        m.previewVideo.width = 1920
                        m.previewVideo.height = 1080
                        m.channelList.visible = false
                        m.sidePanel.visible = false
                        hideGridOverlays()
                        m.isPlayingVideo = true
                        m.suppressNextVideoOptionsMenu = true
                        startOverlayOkSuppressionTimer()
                        m.top.setFocus(true)
                        saveLastState()
                    else
                        ' Nothing playing, just consume the key
                    end if
                    result = true
                else
                    ' Move focus to playlist panel
                    m.sidePanel.visible = true
                    m.playlistPanelActive = true
                    m.playlistList.SetFocus(true)
                    result = true
                end if
            else if(key = "right")
                if m.playlistPanelActive then
                    m.playlistPanelActive = false
                    m.channelList.SetFocus(true)
                else
                    m.previewMuted = not m.previewMuted
                    if m.previewVideo <> invalid then
                        m.previewVideo.mute = m.previewMuted
                    end if
                    updatePreviewHint()
                    showMuteIndicator()
                end if
                result = true
            else if(key = "left")
                m.sidePanel.visible = true
                m.playlistPanelActive = true
                m.playlistList.SetFocus(true)
                result = true
            else if(key = "options")
                if m.playlistPanelActive then
                    m.playlistFocusIndex = m.playlistList.itemFocused
                    showPlaylistOptions()
                    result = true
                end if
            else if(key = "replay")
                if m.playlistPanelActive then
                    reloadCurrentPlaylist()
                else
                    reloadCurrentChannel()
                end if
                result = true
            end if
        end if
    end if
    
    return result 
end function

sub loadSavedPlaylists()
    reg = CreateObject("roRegistrySection", "playlists")
    m.playlists = []
    
    m.playlists.Push({
        name: "Grizz",
        url: "https://grizz.atwebpages.com/grizz.m3u",
        isDefault: true
    })

    m.playlists.Push({
        name: "United States",
        url: "https://iptv-org.github.io/iptv/countries/us.m3u",
        isDefault: true
    })

    m.playlists.Push({
        name: "Canada",
        url: "https://iptv-org.github.io/iptv/countries/ca.m3u",
        isDefault: true
    })

    m.playlists.Push({
        name: "United Kingdom",
        url: "https://iptv-org.github.io/iptv/countries/uk.m3u",
        isDefault: true
    })

    m.playlists.Push({
        name: "Australia",
        url: "https://iptv-org.github.io/iptv/countries/au.m3u",
        isDefault: true
    })
    
    if reg.Exists("count") then
        count = reg.Read("count").ToInt()
        for i = 0 to count - 1
            name = reg.Read("name_" + i.ToStr())
            url = reg.Read("url_" + i.ToStr())
            if name <> invalid and url <> invalid then
                m.playlists.Push({name: name, url: url, isDefault: false})
            end if
        end for
    end if
end sub

sub savePlaylist(name as String, url as String)
    reg = CreateObject("roRegistrySection", "playlists")
    
    count = 0
    if reg.Exists("count") then
        count = reg.Read("count").ToInt()
    end if
    
    reg.Write("name_" + count.ToStr(), name)
    reg.Write("url_" + count.ToStr(), url)
    reg.Write("count", (count + 1).ToStr())
    reg.Flush()
    
    m.playlists.Push({name: name, url: url, isDefault: false})
    setupPlaylistMenu()
end sub

sub loadPlaylist(url as String)
    m.global.feedurl = url
    
    if m.loadingSpinnerContainer <> invalid then
        m.loadingSpinnerContainer.visible = true
    end if
    
    m.get_channel_list.control = "RUN"
end sub

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
        m.pendingChannelUrl = invalid ' Clear queued channel when changing playlist
        loadPlaylist(m.playlists[selectedIdx].url)
        
        ' Save the selected playlist
        saveLastState()
    end if
end sub

sub showPlaylistOptions()
    selectedIdx = m.playlistList.itemFocused
    
    if selectedIdx < 0 or selectedIdx >= m.playlists.Count() then
        return
    end if
    
    selectedPlaylist = m.playlists[selectedIdx]
    
    if selectedPlaylist.isDefault = true then
        dialog = CreateObject("roSGNode", "Dialog")
        dialog.title = selectedPlaylist.name
        dialog.message = "Built-in playlists cannot be edited or removed."
        dialog.buttons = ["OK"]
        m.top.dialog = dialog
        m.top.dialog.observeField("buttonSelected", "onDefaultPlaylistDialogClosed")
        return
    end if
    
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Options: " + selectedPlaylist.name
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
        ' Use a timer to wait for the dialog to close.
        m.optionTimer = CreateObject("roSGNode", "Timer")
        m.optionTimer.duration = 0.2
        m.optionTimer.repeat = false
        m.optionTimer.observeField("fire", "editPlaylistName")
        m.optionTimer.control = "start"
    else if buttonIdx = 1 then
        m.optionTimer = CreateObject("roSGNode", "Timer")
        m.optionTimer.duration = 0.2
        m.optionTimer.repeat = false
        m.optionTimer.observeField("fire", "editPlaylistUrl")
        m.optionTimer.control = "start"
    else if buttonIdx = 2 then
        m.optionTimer = CreateObject("roSGNode", "Timer")
        m.optionTimer.duration = 0.2
        m.optionTimer.repeat = false
        m.optionTimer.observeField("fire", "confirmDeletePlaylist")
        m.optionTimer.control = "start"
    else
        m.playlistList.setFocus(true)
    m.playlistPanelActive = true
    end if
end sub

sub editPlaylistName()
    print ">>> EDIT NAME: Initializing"
    
    ' Clear timer if it exists
    if m.optionTimer <> invalid then
        m.optionTimer.unobserveField("fire")
        m.optionTimer = invalid
    end if
    
    if m.selectedPlaylistIndex = invalid then return
    
    playlist = m.playlists[m.selectedPlaylistIndex]
    
    keyboard = createObject("roSGNode", "StandardKeyboardDialog")
    keyboard.backgroundUri = ""
    keyboard.title = "EDIT NAME"
    keyboard.message = "Enter new name for playlist"
    keyboard.text = playlist.name
    keyboard.buttons = ["Save", "Cancel"]
    
    m.top.dialog = keyboard
    m.top.dialog.observeField("buttonSelected", "onEditNameComplete")
end sub

sub onEditNameComplete()
    print ">>> EDIT NAME: buttonSelected = "; m.top.dialog.buttonSelected
    
    buttonSelected = m.top.dialog.buttonSelected
    
    if buttonSelected = 0 then
        newName = m.top.dialog.text
        
        ' Unregister and close the dialog
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
        
        if newName <> "" and newName <> invalid then
            playlist = m.playlists[m.selectedPlaylistIndex]
            playlist.name = newName
            
            reg = CreateObject("roRegistrySection", "playlists")
            regIndex = m.selectedPlaylistIndex - 6
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

sub editPlaylistUrl()
    print ">>> EDIT URL: Initializing"
    
    ' Clear time if exists
    if m.optionTimer <> invalid then
        m.optionTimer.unobserveField("fire")
        m.optionTimer = invalid
    end if
    
    if m.selectedPlaylistIndex = invalid then return
    
    playlist = m.playlists[m.selectedPlaylistIndex]
    
    keyboard = createObject("roSGNode", "StandardKeyboardDialog")
    keyboard.backgroundUri = ""
    keyboard.title = "EDIT URL"
    keyboard.message = "New URL for the M3U playlist"
    keyboard.text = playlist.url
    keyboard.buttons = ["Save", "Cancel"]
    
    m.top.dialog = keyboard
    m.top.dialog.observeField("buttonSelected", "onEditUrlComplete")
end sub

sub onEditUrlComplete()
    print ">>> EDIT URL: buttonSelected = "; m.top.dialog.buttonSelected
    
    buttonSelected = m.top.dialog.buttonSelected
    
    if buttonSelected = 0 then
        newUrl = m.top.dialog.text
        
        ' Unregister and close the dialog first
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
            ' Show error
            m.pendingErrorMessage = "URL invalid. Must start with http:// or https://"
            m.editUrlErrorTimer = CreateObject("roSGNode", "Timer")
            m.editUrlErrorTimer.duration = 0.3
            m.editUrlErrorTimer.repeat = false
            m.editUrlErrorTimer.observeField("fire", "showEditUrlError")
            m.editUrlErrorTimer.control = "start"
        end if
    else
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
        m.playlistList.setFocus(true)
    m.playlistPanelActive = true
    end if
end sub

sub showEditUrlError()
    print ">>> EDIT URL ERROR: Showing error dialog"
    
    if m.editUrlErrorTimer <> invalid then
        m.editUrlErrorTimer.unobserveField("fire")
        m.editUrlErrorTimer = invalid
    end if
    
    errorDialog = CreateObject("roSGNode", "Dialog")
    errorDialog.title = "Error"
    errorDialog.message = "URL invalid Must start with http:// or https://"
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

sub confirmDeletePlaylist()
    print ">>> DELETE: Showing confirmation"
    
    ' Clear timer if it exists
    if m.optionTimer <> invalid then
        m.optionTimer.unobserveField("fire")
        m.optionTimer = invalid
    end if
    
    if m.selectedPlaylistIndex = invalid then return
    
    playlist = m.playlists[m.selectedPlaylistIndex]
    
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Are you sure?"
    dialog.message = "Delete '" + playlist.name + "'?"
    dialog.buttons = ["Delete", "Cancel"]
    
    m.top.dialog = dialog
    m.top.dialog.observeField("buttonSelected", "onDeleteConfirmed")
end sub

sub onDeleteConfirmed()
    print ">>> DELETE: buttonSelected = "; m.top.dialog.buttonSelected
    
    buttonSelected = m.top.dialog.buttonSelected
    
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true
    
    if buttonSelected = 0 then
        regIndex = m.selectedPlaylistIndex - 6
        
        m.playlists.Delete(m.selectedPlaylistIndex)
        
        reg = CreateObject("roRegistrySection", "playlists")
        
        newIndex = 0
        for i = 6 to m.playlists.Count() - 1
            pl = m.playlists[i]
            if pl.isDefault = false then
                reg.Write("name_" + newIndex.ToStr(), pl.name)
                reg.Write("url_" + newIndex.ToStr(), pl.url)
                newIndex = newIndex + 1
            end if
        end for
        
        reg.Write("count", newIndex.ToStr())
        reg.Flush()
        
        setupPlaylistMenu()
        
        if m.playlists.Count() > 0 then
            loadPlaylist(m.playlists[0].url)
        end if
    end if
    
    m.playlistList.setFocus(true)
    m.playlistPanelActive = true
end sub

sub showPlaylistManager()
    print ">>> PLAYLIST MANAGER: Starting step one: NAME <<<"
    
    ' Clear previous dialogs
    if m.top.dialog <> invalid then
        m.top.dialog.close = true
        m.top.dialog = invalid
    end if
    
    ' Clear previous timers
    if m.urlDialogTimer <> invalid then
        m.urlDialogTimer.control = "stop"
        m.urlDialogTimer = invalid
    end if
    
    m.tempPlaylistName = invalid
    
    keyboardDialog = createObject("roSGNode", "StandardKeyboardDialog")
    keyboardDialog.backgroundUri = ""
    keyboardDialog.title = "NEW PLAYLIST - STEP 1/2: Enter name (ex: My list)"
    keyboardDialog.message = "Enter name (ex: My list)"
    keyboardDialog.buttons = ["Next", "Cancel"]
    keyboardDialog.text = ""
    
    m.top.dialog = keyboardDialog
    m.top.dialog.observeField("buttonSelected", "onPlaylistNameEntered")
    
    print ">>> PLAYLIST MANAGER: Showing NAME dialog"
end sub

sub onPlaylistNameEntered()
    print ">>> PLAYLIST NAME: buttonSelected = "; m.top.dialog.buttonSelected
    
    buttonSelected = m.top.dialog.buttonSelected
    
    if buttonSelected = 0 then
        ' "Next" button pressed
        name = m.top.dialog.text
        if name = "" or name = invalid then
            name = "New Playlist"
        end if
        
        m.tempPlaylistName = name
        print ">>> PLAYLIST NAME: Name saved = "; m.tempPlaylistName
        
        ' Close current dialog
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
        
        ' Wait a moment before showing the next dialog
        m.urlDialogTimer = CreateObject("roSGNode", "Timer")
        m.urlDialogTimer.duration = 0.3
        m.urlDialogTimer.repeat = false
        m.urlDialogTimer.observeField("fire", "showUrlDialog")
        m.urlDialogTimer.control = "start"
    else
        ' "Cancel" button pressed
        print ">>> PLAYLIST NAME: Cancel"
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
        m.tempPlaylistName = invalid
        
        ' Restore focus to the list
        m.playlistList.setFocus(true)
    m.playlistPanelActive = true
    end if
end sub

sub showUrlDialog()
    print ">>> URL DIALOG: Starting part 2 - URL <<<"
    
    ' Clear timer
    if m.urlDialogTimer <> invalid then
        m.urlDialogTimer.unobserveField("fire")
        m.urlDialogTimer = invalid
    end if
    
    ' Check if name already exists
    if m.tempPlaylistName = invalid then
        print ">>> URL DIALOG ERROR: No name saved"
        m.playlistList.setFocus(true)
    m.playlistPanelActive = true
        return
    end if
    
    urlDialog = createObject("roSGNode", "StandardKeyboardDialog")
    urlDialog.backgroundUri = ""
    urlDialog.title = "NEW PLAYLIST - PART 2/2: ENTER URL (http://...)"
    urlDialog.buttons = ["Add", "Cancel"]
    urlDialog.text = ""
    
    m.top.dialog = urlDialog
    m.top.dialog.observeField("buttonSelected", "onPlaylistUrlEntered")
    
    print ">>> URL DIALOG: URL dialog displayed"
end sub

sub onPlaylistUrlEntered()
    print ">>> PLAYLIST URL: buttonSelected = "; m.top.dialog.buttonSelected
    
    buttonSelected = m.top.dialog.buttonSelected
    
    if buttonSelected = 0 then
        ' "Add" button pressed
        url = m.top.dialog.text
        print ">>> PLAYLIST URL: URL entered = "; url
        
        ' Remove observer and close dialog
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
        
        ' Validar URL
        if url = "" or url = invalid then
            print ">>> PLAYLIST URL ERROR: Empty URL"
            showUrlErrorMessage("URL cannot be empty")
            return
        end if
        
        if not isValidUrl(url) then
            print ">>> PLAYLIST URL ERROR: URL empty"
            showUrlErrorMessage("URL invalid. Must start with http:// or https://")
            return
        end if
        
        ' Save and load the playlist
        if m.tempPlaylistName <> invalid then
            print ">>> PLAYLIST URL: Saving playlist - Name: "; m.tempPlaylistName; ", URL: "; url
            savePlaylist(m.tempPlaylistName, url)
            loadPlaylist(url)
        end if
        
        m.tempPlaylistName = invalid
        m.playlistList.setFocus(true)
    m.playlistPanelActive = true
    else
        ' Cancel button pressed
        print ">>> PLAYLIST URL: Canceled"
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
        m.tempPlaylistName = invalid
        m.playlistList.setFocus(true)
    m.playlistPanelActive = true
    end if
end sub

sub showUrlErrorMessage(message as String)
    print ">>> URL ERROR: Displaying error message"
    
    ' Use a timer to show the error
    m.pendingErrorMessage = message
    m.errorTimer = CreateObject("roSGNode", "Timer")
    m.errorTimer.duration = 0.3
    m.errorTimer.repeat = false
    m.errorTimer.observeField("fire", "showUrlError")
    m.errorTimer.control = "start"
end sub

sub showUrlError()
    print ">>> URL ERROR: Timer triggered, showing dialog"
    
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
    errorDialog.title = "Error"
    errorDialog.message = message
    errorDialog.buttons = ["OK"]
    
    m.top.dialog = errorDialog
    m.top.dialog.observeField("buttonSelected", "onErrorDialogClosed")
end sub

sub onErrorDialogClosed()
    print ">>> ERROR DIALOG: Closed"
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true
    m.playlistList.setFocus(true)
    m.playlistPanelActive = true
end sub

sub checkState()
    state = m.previewVideo.state
    if state = "playing" then
        hideBufferBar()
        cancelStallTimer()
        m.bitrateRetryDone = false
        m.stallRetryCount = 0
        if m.fullscreenFailContainer <> invalid then m.fullscreenFailContainer.visible = false
    else if state = "error" then
        hideBufferBar()
        cancelStallTimer()
        errorMsg = m.previewVideo.errorMsg
        ' Auto-retry on bitrate errors before showing error
        if not m.bitrateRetryDone and LCase(errorMsg).InStr("bitrate") >= 0 then
            print ">>> BITRATE RETRY: No valid bitrates, retrying with relaxed constraints"
            m.bitrateRetryDone = true
            retryContent = m.previewVideo.content
            if retryContent <> invalid then
                retryContent.SwitchingStrategy = "no-adaptation"
                m.previewVideo.maxBandwidth = 0
                m.previewVideo.content = invalid
                m.previewVideo.content = retryContent
                m.previewVideo.control = "play"
                return
            end if
        end if
        showChannelError(errorMsg)
    end if
end sub

sub showChannelError(errorMsg as String)
    friendlyMsg = getFriendlyError(errorMsg)
    
    ' Remember the error for this channel
    m.lastErrorMsg = friendlyMsg
    m.lastErrorChannelIndex = m.currentChannelIndex

    ' Hide progress bar - no point showing it alongside an error
    hideBufferBar()
    cancelStallTimer()

    ' Start inactivity/shade timer immediately
    if m.isPlayingVideo then resetFullscreenInactivityTimer() else resetGridInactivityTimer()

    if m.isPlayingVideo then
        ' Fullscreen: show undismissable text only (no dialog)
        showFullscreenError(friendlyMsg)
    else
        ' Grid/preview: show persistent overlay first, then dismissable dialog
        showPreviewError(friendlyMsg)
        showErrorOverlay(errorMsg)
    end if
end sub

sub showFullscreenError(friendlyMsg as String)
    if m.fullscreenFailContainer = invalid then return
    channel = m.flatChannelList[m.currentChannelIndex]
    channelName = "Unknown Channel"
    if channel <> invalid and channel.title <> invalid then channelName = channel.title
    channelNum = (m.currentChannelIndex + 1).ToStr() + "/" + m.flatChannelList.Count().ToStr()
    if m.fullscreenFailChannel <> invalid then m.fullscreenFailChannel.text = channelNum + "  -  " + channelName
    if m.fullscreenFailLabel <> invalid then m.fullscreenFailLabel.text = friendlyMsg
    m.fullscreenFailContainer.visible = true
end sub

sub showPreviewError(friendlyMsg as String)
    if m.previewErrorContainer = invalid then return
    m.previewErrorContainer.visible = true
end sub

sub hidePreviewError()
    if m.previewErrorContainer <> invalid then m.previewErrorContainer.visible = false
end sub

sub SetContent()
    if m.loadingSpinnerContainer <> invalid then
        m.loadingSpinnerContainer.visible = false
    end if
    
    if m.get_channel_list.content <> invalid then
        m.allChannels = m.get_channel_list.content
        buildFlatChannelList()
        
        if m.flatChannelList.Count() > 0 and m.currentChannelIndex = 0 then
            m.currentChannelIndex = 0
            print ">>> SETCONTENT: Initializing currentChannelIndex = 0"
        end if
        
        m.channelList.content = m.allChannels
        m.channelList.jumpToItem = 0
        
        restorePendingChannel()
        
        m.playlistPanelActive = false
        m.channelList.SetFocus(true)
        resetGridInactivityTimer()
    else
        errorDialog = CreateObject("roSGNode", "Dialog")
        errorDialog.title = "Error"
        errorDialog.message = "Could not load the list. Check URL."
        m.top.dialog = errorDialog
    end if
end sub

sub buildFlatChannelList()
    m.flatChannelList = []

    if m.allChannels = invalid then return

    for i = 0 to m.allChannels.getChildCount() - 1
        section = m.allChannels.getChild(i)
        if section = invalid then continue for

        if section.getChildCount() = 0 then
            m.flatChannelList.Push(section)
        else
            for j = 0 to section.getChildCount() - 1
                channel = section.getChild(j)
                if channel <> invalid then
                    m.flatChannelList.Push(channel)
                end if
            end for
        end if
    end for

    print ">>> PLAYLIST: Total channels in flat list: "; m.flatChannelList.Count()
end sub

sub changeChannel(direction as Integer)
    hideChannelInfo()
    print ">>> CHANGECHANNEL: flatChannelList.Count() = "; m.flatChannelList.Count()
    print ">>> CHANGECHANNEL: currentChannelIndex = "; m.currentChannelIndex
    
    if m.flatChannelList.Count() = 0 then 
        print ">>> CHANGECHANNEL ERROR: flatChannelList is empty!"
        return
    end if
    
    m.currentChannelIndex = m.currentChannelIndex + direction
    
    if m.currentChannelIndex < 0 then
        m.currentChannelIndex = m.flatChannelList.Count() - 1
    else if m.currentChannelIndex >= m.flatChannelList.Count() then
        m.currentChannelIndex = 0
    end if
    
    print ">>> CHANGECHANNEL: New index = "; m.currentChannelIndex
    
    channel = m.flatChannelList[m.currentChannelIndex]
    if channel <> invalid then
        print ">>> CHANGECHANNEL: Playing channel: "; channel.title
        showChannelInfo(channel)
        playChannel(channel)
    else
        print ">>> CHANGECHANNEL ERROR: No valid channel at index "; m.currentChannelIndex
    end if
end sub

sub showChannelInfoPersistent(channel as Object)
    if m.channelInfoOverlay = invalid or m.channelInfoLabel = invalid then return
    ' Stop any existing auto-hide timer
    if m.channelInfoTimer <> invalid then
        m.channelInfoTimer.control = "stop"
        m.channelInfoTimer = invalid
    end if
    channelNumber = (m.currentChannelIndex + 1).ToStr()
    totalChannels = m.flatChannelList.Count().ToStr()
    m.channelInfoLabel.text = channelNumber + "/" + totalChannels + " - " + channel.title
    showClock()
    m.channelInfoOverlay.visible = true
end sub

sub showChannelInfo(channel as Object)
    if m.channelInfoOverlay = invalid or m.channelInfoLabel = invalid then return
    
    channelNumber = (m.currentChannelIndex + 1).ToStr()
    totalChannels = m.flatChannelList.Count().ToStr()
    m.channelInfoLabel.text = channelNumber + "/" + totalChannels + " - " + channel.title
    showClock()
    m.channelInfoOverlay.visible = true
    
    ' Create a timer to hide the quick menu after 3 seconds
    if m.channelInfoTimer <> invalid then
        m.channelInfoTimer.control = "stop"
    end if
    
    m.channelInfoTimer = CreateObject("roSGNode", "Timer")
    m.channelInfoTimer.duration = 3
    m.channelInfoTimer.repeat = false
    m.channelInfoTimer.ObserveField("fire", "hideChannelInfo")
    m.channelInfoTimer.control = "start"
end sub

sub hideChannelInfo()
    if m.channelInfoOverlay <> invalid then
        m.channelInfoOverlay.visible = false
    end if
    if m.clockLabel <> invalid then
        m.clockLabel.text = ""
    end if
end sub

' ==================== Video settings menu ====================

sub showVideoOptionsMenu()
    print ">>> VIDEO OPTIONS: Showing options menu"
    
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Playback options"
    dialog.buttons = ["Audio Settings", "Subtitles", "Channel Details", "Close"]
    
    m.top.dialog = dialog
    m.top.dialog.observeField("buttonSelected", "onVideoOptionSelected")
    resetOptionsDialogTimer()
end sub

sub onVideoOptionSelected()
    buttonIdx = m.top.dialog.buttonSelected
    
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true
    
    if buttonIdx = 0 then
        ' Change audio track
        showAudioTracksMenu()
    else if buttonIdx = 1 then
        ' Subtitles
        showSubtitlesMenu()
    else if buttonIdx = 2 then
        ' Channel info
        showCurrentChannelInfo()
    end if
    
    m.top.setFocus(true)
end sub

sub showAudioTracksMenu()
    print ">>> AUDIO TRACKS: Fetching audio tracks"
    
    if m.previewVideo = invalid then return
    
    ' Get available audio track info and try multiple properties for compatibility
    audioTracks = m.previewVideo.audioTracks
    
    print ">>> AUDIO: audioTracks = "; audioTracks
    
    if audioTracks = invalid or audioTracks.Count() = 0 then
        ' Try availableAudioTracks as fallback
        audioTracks = m.previewVideo.availableAudioTracks
        print ">>> AUDIO: availableAudioTracks = "; audioTracks
    end if
    
    ' Debug: Show stream information
    print ">>> AUDIO: streamInfo = "; m.previewVideo.streamInfo
    print ">>> AUDIO: audioFormat = "; m.previewVideo.audioFormat
    
    if audioTracks = invalid or audioTracks.Count() = 0 then
        ' how debug information
        message = "No alternate audio tracks detected." + chr(10) + chr(10)
        message = message + "Audio format: " + toStr(m.previewVideo.audioFormat) + chr(10)
        message = message + "Video status: " + m.previewVideo.state
        
        dialog = CreateObject("roSGNode", "Dialog")
        dialog.title = "🔊 Audio tracks"
        dialog.message = message
        dialog.buttons = ["OK"]
        m.top.dialog = dialog
        m.top.dialog.observeField("buttonSelected", "onSimpleDialogClosed")
    resetOptionsDialogTimer()
        return
    end if
    
    ' Create list of audio tracks
    m.audioTracksList = []
    buttons = []
    
    ' Get current audio track
    currentTrackIndex = -1
    if m.previewVideo.currentAudioTrack <> invalid then
        currentTrackIndex = m.previewVideo.currentAudioTrack
    end if
    
    for i = 0 to audioTracks.Count() - 1
        track = audioTracks[i]
        trackName = ""
        
        print ">>> AUDIO TRACK "; i; ": "; track
        
        ' Generate track name using different properties
        language = ""
        if type(track) = "roAssociativeArray" then
            if track.Language <> invalid and track.Language <> "" then
                language = track.Language
            else if track.language <> invalid and track.language <> "" then
                language = track.language
            end if
            
            if language <> "" then
                trackName = getLanguageName(language)
            else
                trackName = "Track " + (i + 1).ToStr()
            end if
            
            ' Add name if available
            if track.Name <> invalid and track.Name <> "" then
                trackName = trackName + " (" + track.Name + ")"
            else if track.name <> invalid and track.name <> "" then
                trackName = trackName + " (" + track.name + ")"
            end if
        else if type(track) = "String" or type(track) = "roString" then
            trackName = getLanguageName(track)
        else
            trackName = "List " + (i + 1).ToStr()
        end if
        
        ' Highlight current track
        if i = currentTrackIndex then
            trackName = "✓ " + trackName
        end if
        
        buttons.Push(trackName)
        m.audioTracksList.Push(i)
    end for
    
    buttons.Push("Cancel")
    
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Select audio track (" + audioTracks.Count().ToStr() + " available)"
    dialog.buttons = buttons
    
    m.top.dialog = dialog
    m.top.dialog.observeField("buttonSelected", "onAudioTrackSelected")
    resetOptionsDialogTimer()
end sub

function toStr(value as Dynamic) as String
    if value = invalid then return "N/A"
    if type(value) = "String" or type(value) = "roString" then return value
    if type(value) = "Integer" or type(value) = "roInt" then return value.ToStr()
    if type(value) = "Float" or type(value) = "roFloat" then return Str(value)
    return type(value)
end function

sub onAudioTrackSelected()
    buttonIdx = m.top.dialog.buttonSelected
    
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true
    
    if m.audioTracksList <> invalid and buttonIdx < m.audioTracksList.Count() then
        trackIndex = m.audioTracksList[buttonIdx]
        print ">>> AUDIO: Changing tracks "; trackIndex
        
        ' Try changing the audio track using different methods.
        ' Method 1: audioTrack (direct index)
        m.previewVideo.audioTrack = trackIndex
        
        ' Method 2: selectAudioTrack
        m.previewVideo.selectAudioTrack = trackIndex
        
        ' Show confirmation message
        showChannelInfoMessage("Audio: Track " + (trackIndex + 1).ToStr() + " selected")
    end if
    
    m.top.setFocus(true)
end sub

sub showSubtitlesMenu()
    print ">>> SUBTITLES: Fetching subtitles"
    
    if m.previewVideo = invalid then return
    
    ' Get available subtitle track information
    subtitleTracks = m.previewVideo.availableCaptionTracks
    
    buttons = ["Subtitles off"]
    m.subtitleTracksList = [-1] ' -1 = desactivar
    
    if subtitleTracks <> invalid and subtitleTracks.Count() > 0 then
        for i = 0 to subtitleTracks.Count() - 1
            track = subtitleTracks[i]
            trackName = ""
            
            if track.Language <> invalid and track.Language <> "" then
                trackName = getLanguageName(track.Language)
            else
                trackName = "Subtitle " + (i + 1).ToStr()
            end if
            
            if track.Description <> invalid and track.Description <> "" then
                trackName = trackName + " (" + track.Description + ")"
            end if
            
            buttons.Push(trackName)
            m.subtitleTracksList.Push(i)
        end for
    end if
    
    buttons.Push("Cancel")
    
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Subtitles"
    
    if subtitleTracks = invalid or subtitleTracks.Count() = 0 then
        dialog.message = "No subtitles available for this channel."
    end if
    
    dialog.buttons = buttons
    
    m.top.dialog = dialog
    m.top.dialog.observeField("buttonSelected", "onSubtitleTrackSelected")
    resetOptionsDialogTimer()
end sub

sub onSubtitleTrackSelected()
    buttonIdx = m.top.dialog.buttonSelected
    
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true
    
    if m.subtitleTracksList <> invalid and buttonIdx < m.subtitleTracksList.Count() then
        trackIndex = m.subtitleTracksList[buttonIdx]
        
        if trackIndex = -1 then
            print ">>> SUBTITLES: Disabling subtitles"
            m.previewVideo.suppressCaptions = true
            showChannelInfoMessage("Subtitles off")
        else
            print ">>> SUBTITLES: Turning subtitles on "; trackIndex
            m.previewVideo.suppressCaptions = false
            m.previewVideo.selectCaptionTrack = trackIndex
            showChannelInfoMessage("Subtitles on")
        end if
    end if
    
    m.top.setFocus(true)
end sub

sub showCurrentChannelInfo()
    if m.flatChannelList = invalid or m.flatChannelList.Count() = 0 then return
    if m.currentChannelIndex < 0 or m.currentChannelIndex >= m.flatChannelList.Count() then return
    
    channel = m.flatChannelList[m.currentChannelIndex]
    if channel = invalid then return
    
    message = "Channel: " + channel.title + chr(10)
    message = message + "Position: " + (m.currentChannelIndex + 1).ToStr() + " of " + m.flatChannelList.Count().ToStr() + chr(10)
    
    if m.previewVideo <> invalid then
        state = m.previewVideo.state
        message = message + "State: " + state + chr(10)
        
        ' Audio information
        audioTracks = m.previewVideo.availableAudioTracks
        if audioTracks <> invalid then
            message = message + "Audio tracks: " + audioTracks.Count().ToStr() + chr(10)
        end if
        
        ' Subtitle information
        captionTracks = m.previewVideo.availableCaptionTracks
        if captionTracks <> invalid then
            message = message + "Subtitles: " + captionTracks.Count().ToStr()
        end if
    end if
    
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Channel information"
    dialog.message = message
    dialog.buttons = ["OK"]
    
    m.top.dialog = dialog
    m.top.dialog.observeField("buttonSelected", "onSimpleDialogClosed")
    resetOptionsDialogTimer()
end sub

sub onSimpleDialogClosed()
    m.top.dialog.unobserveField("buttonSelected")
    m.top.dialog.close = true
    m.top.setFocus(true)
end sub

sub showChannelInfoMessage(message as String)
    if m.channelInfoOverlay = invalid or m.channelInfoLabel = invalid then return
    
    m.channelInfoLabel.text = message
    showClock()
    m.channelInfoOverlay.visible = true
    
    if m.channelInfoTimer <> invalid then
        m.channelInfoTimer.control = "stop"
    end if
    
    m.channelInfoTimer = CreateObject("roSGNode", "Timer")
    m.channelInfoTimer.duration = 2
    m.channelInfoTimer.repeat = false
    m.channelInfoTimer.ObserveField("fire", "hideChannelInfo")
    m.channelInfoTimer.control = "start"
end sub

function getLanguageName(code as String) as String
    languages = {
        "es": "Spanish",
        "spa": "Spanish",
        "spanish": "Spanish",
        "en": "English",
        "eng": "English",
        "english": "English",
        "pt": "Portugues",
        "por": "Portugues",
        "portuguese": "Portugues",
        "fr": "French",
        "fra": "French",
        "fre": "French",
        "french": "French",
        "de": "German",
        "deu": "German",
        "ger": "German",
        "german": "German",
        "it": "Italian",
        "ita": "Italian",
        "italian": "Italian",
        "ja": "Japanese",
        "jpn": "Japanese",
        "japanese": "Japanese",
        "ko": "Korean",
        "kor": "Korean",
        "korean": "Korean",
        "zh": "Chinese",
        "chi": "Chinese",
        "zho": "Chinese",
        "chinese": "Chinese",
        "ru": "Russian",
        "rus": "Russian",
        "russian": "Russian",
        "ar": "Arab",
        "ara": "Arab",
        "arabic": "Arab",
        "und": "Unknown",
        "mul": "Multipe"
    }
    
    lowerCode = LCase(code)
    if languages.DoesExist(lowerCode) then
        return languages[lowerCode]
    end if
    
    return code
end function

' ==================== Channel Preview ====================

sub onChannelFocused()
    if m.isPlayingVideo then return
    if m.channelList = invalid then return
    if m.suppressFocusChange then return

    ' Dismiss screensaver on any navigation
    if m.screensaverOverlay <> invalid and m.screensaverOverlay.visible then
        m.screensaverOverlay.visible = false
        resetGridInactivityTimer()
        return
    end if

    focusedIndex = m.channelList.itemFocused
    print ">>> GRID: Channel focused = "; focusedIndex

    channel = getChannelByFocusIndex(focusedIndex)
    if channel <> invalid then
        m.lastFocusedChannel = focusedIndex
        ' If moving to a different channel, hide buffer bar and preview error
        if focusedIndex <> m.currentChannelIndex then
            hideBufferBar()
            cancelStallTimer()
        end if
        m.currentChannelIndex = focusedIndex
    end if
    resetGridInactivityTimer()
end sub

function getChannelByFocusIndex(focusIndex as Integer) as Object
    return getChannelFromListItem(m.channelList, focusIndex)
end function

function getChannelFromListItem(list as Object, itemIndex as Integer) as Object
    if list = invalid or list.content = invalid then return invalid

    content = list.content
    if content.getChildCount() = 0 then return invalid

    firstChild = content.getChild(0)
    if firstChild = invalid then return invalid

    return getChannelFromFlatListItem(content, itemIndex)
end function

function getSectionChildIndexForListItem(content as Object, sectionIndex as Integer, itemIndex as Integer) as Integer
    if content = invalid then return -1
    if sectionIndex < 0 or sectionIndex >= content.getChildCount() then return -1

    section = content.getChild(sectionIndex)
    if section = invalid then return -1

    sectionCount = section.getChildCount()
    if sectionCount = 0 then return -1

    previousChannelCount = 0
    if sectionIndex > 0 then
        for i = 0 to sectionIndex - 1
            previousSection = content.getChild(i)
            if previousSection <> invalid then
                previousChannelCount = previousChannelCount + previousSection.getChildCount()
            end if
        end for
    end if

    flatItemIndex = itemIndex - previousChannelCount
    if flatItemIndex >= 0 and flatItemIndex < sectionCount then
        return flatItemIndex
    end if

    if itemIndex >= 0 and itemIndex < sectionCount then
        return itemIndex
    end if

    return -1
end function

function getChannelFromFlatListItem(content as Object, itemIndex as Integer) as Object
    if content = invalid or itemIndex < 0 then return invalid

    channelIndex = 0
    for i = 0 to content.getChildCount() - 1
        section = content.getChild(i)
        if section = invalid then continue for

        if section.getChildCount() = 0 then
            if channelIndex = itemIndex then return section
            channelIndex = channelIndex + 1
        else
            sectionCount = section.getChildCount()
            if itemIndex < channelIndex + sectionCount then
                return section.getChild(itemIndex - channelIndex)
            end if
            channelIndex = channelIndex + sectionCount
        end if
    end for

    return invalid
end function

sub playPreviewChannel(channelIndex as Integer)
    if m.previewVideo = invalid then return
    if m.flatChannelList = invalid or m.flatChannelList.Count() = 0 then return
    
    channel = getChannelByFocusIndex(channelIndex)
    if channel = invalid and channelIndex >= 0 and channelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[channelIndex]
    end if
    
    if channel = invalid or channel.url = invalid then 
        print ">>> PREVIEW: Failed to retrieve channel"
        return
    end if
    
    ' Skip preview reload if the channel is unchanged
    if m.previewVideo.content <> invalid and m.previewVideo.content.url = channel.url then
        return
    end if
    
    ' Reset error/retry state for new channel
    m.bitrateRetryDone = false
    m.stallRetryCount = 0
    m.lastBufferPct = -1
    m.lastErrorMsg = ""
    m.lastErrorChannelIndex = -1
    cancelStallTimer()
    hidePreviewError()
    
    print ">>> PREVIEW: Starting preview playback: "; channel.title
    
    ' Update channel name label under preview
    if m.previewChannelNameLabel <> invalid then
        m.previewChannelNameLabel.text = channel.title
    end if
    if m.previewChannelNameContainer <> invalid then
        m.previewChannelNameContainer.visible = true
    end if
    
    ' Create preview content
    previewContent = CreateObject("roSGNode", "ContentNode")
    previewContent.url = channel.url
    previewContent.title = channel.title
    previewContent.streamFormat = "hls"
    previewContent.HttpSendClientCertificates = true
    previewContent.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    
    ' Ensure node is in preview size/position
    m.previewVideo.translation = [1380, 145]
    m.previewVideo.width = 444
    m.previewVideo.height = 250
    m.previewVideo.trickplaybarvisibilityauto = true

    m.previewVideo.content = previewContent
    m.previewVideo.control = "play"
    m.previewVideo.mute = m.previewMuted
end sub

sub stopPreviewVideo()
    if m.previewVideo <> invalid then
        m.previewVideo.control = "stop"
    end if
end sub

sub hideOverlay()
    m.channelOverlay.visible = false
    m.overlayVisible = false
    m.channelOverlayList.setFocus(false)
    m.top.setFocus(true)
    if m.overlayInactivityTimer <> invalid then
        m.overlayInactivityTimer.control = "stop"
        m.overlayInactivityTimer.unobserveField("fire")
        m.overlayInactivityTimer = invalid
    end if
end sub

sub showMuteIndicator()
    if m.muteIndicatorContainer = invalid or m.muteIndicatorImage = invalid then return

    if m.previewMuted then
        m.muteIndicatorImage.uri = "pkg:/images/muteon.png"
    else
        m.muteIndicatorImage.uri = "pkg:/images/muteoff.png"
    end if

    m.muteIndicatorContainer.visible = true

    if m.muteIndicatorTimer <> invalid then
        m.muteIndicatorTimer.control = "stop"
        m.muteIndicatorTimer.unobserveField("fire")
    end if

    m.muteIndicatorTimer = CreateObject("roSGNode", "Timer")
    m.muteIndicatorTimer.duration = 2
    m.muteIndicatorTimer.repeat = false
    m.muteIndicatorTimer.ObserveField("fire", "hideMuteIndicator")
    m.muteIndicatorTimer.control = "start"
end sub

sub hideMuteIndicator()
    if m.muteIndicatorContainer <> invalid then
        m.muteIndicatorContainer.visible = false
    end if
end sub

sub onBufferingStatus()
    status = m.previewVideo.bufferingStatus
    if status = invalid then return

    pct = 0
    if status.percentage <> invalid then pct = status.percentage

    ' Start the display delay timer on first buffering signal if not already running
    if not m.bufferVisible and pct < 100 then
        if m.bufferDelayTimer = invalid then
            m.bufferDelayTimer = CreateObject("roSGNode", "Timer")
            m.bufferDelayTimer.duration = 1.0
            m.bufferDelayTimer.repeat = false
            m.bufferDelayTimer.ObserveField("fire", "showBufferBar")
            m.bufferDelayTimer.control = "start"
        end if
    end if

    ' Update bar width and label if visible
    if m.bufferVisible then
        updateBufferBar(pct)
    end if

    ' Stall detection — restart stall timer whenever percentage moves
    if pct <> m.lastBufferPct and pct < 100 then
        m.lastBufferPct = pct
        ' Reset stall timer since progress is being made
        if m.stallTimer <> invalid then
            m.stallTimer.control = "stop"
            m.stallTimer.unobserveField("fire")
            m.stallTimer = invalid
        end if
        ' Start a fresh stall timer
        m.stallTimer = CreateObject("roSGNode", "Timer")
        m.stallTimer.duration = 5.0
        m.stallTimer.repeat = false
        m.stallTimer.ObserveField("fire", "onBufferStall")
        m.stallTimer.control = "start"
    end if

    ' Hide when done
    if pct >= 100 then
        hideBufferBar()
        cancelStallTimer()
    end if
end sub

sub cancelStallTimer()
    if m.stallTimer <> invalid then
        m.stallTimer.control = "stop"
        m.stallTimer.unobserveField("fire")
        m.stallTimer = invalid
    end if
end sub

sub onBufferStall()
    m.stallTimer = invalid
    if m.previewVideo.state <> "buffering" then return

    pct = 0
    status = m.previewVideo.bufferingStatus
    if status <> invalid and status.percentage <> invalid then pct = status.percentage
    if pct >= 100 then return

    print ">>> STALL: Buffer stalled at "; pct; "%, retry count = "; m.stallRetryCount

    content = m.previewVideo.content
    if content = invalid then return

    if m.stallRetryCount = 0 then
        print ">>> STALL: Retrying with MaxBandwidth 2.5Mbps"
        m.previewVideo.maxBandwidth = 2500000
        m.stallRetryCount = 1
    else if m.stallRetryCount = 1 then
        print ">>> STALL: Retrying with MaxBandwidth 1Mbps"
        m.previewVideo.maxBandwidth = 1000000
        m.stallRetryCount = 2
    else
        print ">>> STALL: All retries exhausted, showing error"
        hideBufferBar()
        showChannelError("Stream stalled and could not recover. The channel may require more bandwidth than is available.")
        if m.isPlayingVideo then resetFullscreenInactivityTimer() else resetGridInactivityTimer()
        return
    end if

    ' Force reload with new bandwidth cap
    m.lastBufferPct = -1
    m.previewVideo.content = invalid
    m.previewVideo.content = content
    m.previewVideo.control = "play"
end sub

sub showBufferBar()
    if m.bufferDelayTimer <> invalid then
        m.bufferDelayTimer.unobserveField("fire")
        m.bufferDelayTimer = invalid
    end if

    ' Only show if still buffering
    if m.previewVideo.state <> "buffering" then return

    ' Position bar depending on mode
    if m.isPlayingVideo then
        ' Fullscreen - centered near bottom
        m.bufferContainer.translation = [560, 980]
        m.bufferContainer.width = 800
        m.bufferTrack.width = 794
        m.bufferLabel.width = 800
    else
        ' Grid - centered in visible 4:3 preview area (x=1440, width=384)
        m.bufferContainer.translation = [1467, 252]
        m.bufferContainer.width = 283
        m.bufferTrack.width = 277
        m.bufferLabel.width = 283
    end if

    m.bufferContainer.visible = true
    m.bufferVisible = true

    ' Seed the bar with current value
    status = m.previewVideo.bufferingStatus
    if status <> invalid and status.percentage <> invalid then
        updateBufferBar(status.percentage)
    end if
end sub

sub updateBufferBar(pct as Integer)
    if m.bufferFill = invalid or m.bufferLabel = invalid then return
    trackWidth = m.bufferTrack.width
    fillWidth = Int(trackWidth * pct / 100)
    if fillWidth < 0 then fillWidth = 0
    if fillWidth > trackWidth then fillWidth = trackWidth
    m.bufferFill.width = fillWidth
    m.bufferLabel.text = pct.ToStr() + "%"
end sub

sub hideBufferBar()
    if m.bufferDelayTimer <> invalid then
        m.bufferDelayTimer.control = "stop"
        m.bufferDelayTimer.unobserveField("fire")
        m.bufferDelayTimer = invalid
    end if
    if m.bufferContainer <> invalid then
        m.bufferContainer.visible = false
    end if
    if m.bufferFill <> invalid then
        m.bufferFill.width = 0
    end if
    if m.bufferLabel <> invalid then
        m.bufferLabel.text = ""
    end if
    m.bufferVisible = false
end sub

sub showGridOverlays()
    if m.videoClipLeft <> invalid then m.videoClipLeft.visible = true
    if m.muteHintContainer <> invalid then m.muteHintContainer.visible = true
    if m.tvOverlay <> invalid then m.tvOverlay.visible = true
    if m.previewChannelNameContainer <> invalid then m.previewChannelNameContainer.visible = true
    ' Restore preview error if channel had one
    if m.lastErrorMsg <> "" and m.lastErrorChannelIndex = m.currentChannelIndex then
        showPreviewError(m.lastErrorMsg)
    end if
    m.playlistPanelActive = false
    m.channelList.SetFocus(true)
end sub

sub hideGridOverlays()
    if m.videoClipLeft <> invalid then m.videoClipLeft.visible = false
    if m.muteHintContainer <> invalid then m.muteHintContainer.visible = false
    if m.tvOverlay <> invalid then m.tvOverlay.visible = false
    if m.previewChannelNameContainer <> invalid then m.previewChannelNameContainer.visible = false
    hidePreviewError()
end sub

sub showClock()
    if m.clockLabel = invalid then return
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    hours = dt.GetHours()
    minutes = dt.GetMinutes()
    ampm = "AM"
    if hours >= 12 then
        ampm = "PM"
        if hours > 12 then hours = hours - 12
    end if
    if hours = 0 then hours = 12
    minStr = minutes.ToStr()
    if minutes < 10 then minStr = "0" + minStr
    m.clockLabel.text = hours.ToStr() + ":" + minStr + " " + ampm
end sub

sub showErrorOverlay(errorMsg as String)
    if m.errorOverlay = invalid then return

    channel = m.flatChannelList[m.currentChannelIndex]
    channelName = "Unknown Channel"
    channelNum = (m.currentChannelIndex + 1).ToStr() + "/" + m.flatChannelList.Count().ToStr()
    if channel <> invalid and channel.title <> invalid then
        channelName = channel.title
    end if

    if m.errorTitleLabel <> invalid then
        m.errorTitleLabel.text = "Channel Unavailable"
    end if
    if m.errorChannelLabel <> invalid then
        m.errorChannelLabel.text = channelNum + "  -  " + channelName
    end if
    if m.errorMessageLabel <> invalid then
        ' If already friendly (from showChannelError), use as-is; otherwise convert
        if m.lastErrorMsg <> "" and m.lastErrorChannelIndex = m.currentChannelIndex then
            m.errorMessageLabel.text = m.lastErrorMsg
        else
            m.errorMessageLabel.text = getFriendlyError(errorMsg)
        end if
    end if

    m.errorOverlay.visible = true
    m.errorVisible = true
    if m.focusTrap <> invalid then
        m.focusTrap.SetFocus(true)
    end if
end sub

sub hideErrorOverlay()
    if m.errorOverlay <> invalid then
        m.errorOverlay.visible = false
    end if
    m.errorVisible = false
end sub

function getFriendlyError(errorMsg as String) as String
    if errorMsg = invalid or errorMsg = "" then
        return "The stream could not be loaded. The channel may be offline or the URL may be invalid."
    end if

    msg = LCase(errorMsg)

    if msg.InStr("404") >= 0 or msg.InStr("not found") >= 0 then
        return "Stream not found (404). The channel URL may be incorrect or the stream has moved."
    else if msg.InStr("403") >= 0 or msg.InStr("forbidden") >= 0 then
        return "Access denied (403). This stream may be geo-restricted or require authentication."
    else if msg.InStr("401") >= 0 or msg.InStr("unauthorized") >= 0 then
        return "Unauthorized (401). This stream requires a login or subscription."
    else if msg.InStr("500") >= 0 or msg.InStr("server error") >= 0 then
        return "Server error (500). The streaming server is having problems. Try again later."
    else if msg.InStr("timeout") >= 0 or msg.InStr("timed out") >= 0 then
        return "Connection timed out. The stream is taking too long to respond. Check your network."
    else if msg.InStr("network") >= 0 or msg.InStr("connect") >= 0 then
        return "Network error. Check your internet connection and try again."
    else if msg.InStr("drm") >= 0 or msg.InStr("license") >= 0 then
        return "DRM / copy protection error. This stream uses a protection scheme that is not supported."
    else if msg.InStr("format") >= 0 or msg.InStr("codec") >= 0 or msg.InStr("unsupported") >= 0 then
        return "Unsupported format. This stream uses a codec or container that cannot be played."
    else if msg.InStr("empty") >= 0 or msg.InStr("no data") >= 0 then
        return "Empty stream. The channel URL returned no playable content."
    else if msg.InStr("ssl") >= 0 or msg.InStr("certificate") >= 0 then
        return "SSL / certificate error. There was a problem with the stream's security certificate."
    else if msg.InStr("dns") >= 0 or msg.InStr("resolve") >= 0 then
        return "DNS error. The stream's server address could not be found. Check your network."
    end if

    return "Playback error: " + errorMsg
end function

sub resetFullscreenInactivityTimer()
    if m.fullscreenInactivityTimer <> invalid then
        m.fullscreenInactivityTimer.control = "stop"
        m.fullscreenInactivityTimer.unobserveField("fire")
    end if
    if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = false
    m.fullscreenInactivityTimer = CreateObject("roSGNode", "Timer")
    m.fullscreenInactivityTimer.duration = 45.0
    m.fullscreenInactivityTimer.repeat = false
    m.fullscreenInactivityTimer.ObserveField("fire", "onFullscreenInactivity")
    m.fullscreenInactivityTimer.control = "start"
end sub

sub onFullscreenInactivity()
    m.fullscreenInactivityTimer = invalid
    if m.screensaverOverlay = invalid then return
    ' Shade if fullscreen error text is showing
    if m.fullscreenFailContainer <> invalid and m.fullscreenFailContainer.visible then
        m.screensaverOverlay.visible = true
    end if
end sub

sub resetOptionsDialogTimer()
    if m.optionsDialogTimer <> invalid then
        m.optionsDialogTimer.control = "stop"
        m.optionsDialogTimer.unobserveField("fire")
    end if
    m.optionsDialogTimer = CreateObject("roSGNode", "Timer")
    m.optionsDialogTimer.duration = 30.0
    m.optionsDialogTimer.repeat = false
    m.optionsDialogTimer.ObserveField("fire", "onOptionsDialogTimeout")
    m.optionsDialogTimer.control = "start"
end sub

sub onOptionsDialogTimeout()
    m.optionsDialogTimer = invalid
    if m.top.dialog <> invalid then
        m.top.dialog.close = true
    end if
end sub

sub onOverlayItemFocused()
    if m.screensaverOverlay <> invalid and m.screensaverOverlay.visible then
        m.screensaverOverlay.visible = false
        return
    end if
    if m.overlayVisible then
        m.currentChannelIndex = m.channelOverlayList.itemFocused
        resetOverlayInactivityTimer()
    end if
end sub

sub resetGridInactivityTimer()
    if m.isPlayingVideo then return
    if m.gridInactivityTimer <> invalid then
        m.gridInactivityTimer.control = "stop"
        m.gridInactivityTimer.unobserveField("fire")
    end if
    ' Dismiss screensaver if visible
    if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = false
    m.gridInactivityTimer = CreateObject("roSGNode", "Timer")
    m.gridInactivityTimer.duration = 45.0
    m.gridInactivityTimer.repeat = false
    m.gridInactivityTimer.ObserveField("fire", "onGridInactivity")
    m.gridInactivityTimer.control = "start"
end sub

sub onGridInactivity()
    m.gridInactivityTimer = invalid
    if m.errorVisible then
        if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = true
        return
    end if
    if m.isPlayingVideo then return
    if m.previewVideo.state = "playing" then
        ' Resize preview to fullscreen directly - no reload needed
        m.top.backgroundURI = ""
        m.top.backgroundColor = "0x024c48FF"
        m.previewVideo.trickplaybarvisibilityauto = false
        m.previewVideo.translation = [0, 0]
        m.previewVideo.width = 1920
        m.previewVideo.height = 1080
        m.channelList.visible = false
        m.sidePanel.visible = false
        hideGridOverlays()
        m.isPlayingVideo = true
        m.suppressNextVideoOptionsMenu = true
        startOverlayOkSuppressionTimer()
        m.top.setFocus(true)
        saveLastState()
    else
        if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = true
    end if
end sub

sub resetOverlayInactivityTimer()
    if m.overlayInactivityTimer <> invalid then
        m.overlayInactivityTimer.control = "stop"
        m.overlayInactivityTimer.unobserveField("fire")
    end if
    m.overlayInactivityTimer = CreateObject("roSGNode", "Timer")
    m.overlayInactivityTimer.duration = 10.0
    m.overlayInactivityTimer.repeat = false
    m.overlayInactivityTimer.ObserveField("fire", "onOverlayInactivity")
    m.overlayInactivityTimer.control = "start"
end sub

sub onOverlayInactivity()
    m.overlayInactivityTimer = invalid
    if m.overlayVisible then
        hideOverlay()
        if m.isPlayingVideo then
            m.top.setFocus(true)
            resetFullscreenInactivityTimer()
        end if
    end if
end sub

sub updatePreviewHint()
    if m.previewHintLabel = invalid then return
    if m.previewMuted then
        m.previewHintLabel.text = "Press RIGHT to unmute"
    else
        m.previewHintLabel.text = "Press RIGHT to mute"
    end if
end sub

sub onChannelSelected()
    if m.channelList = invalid then return
    if m.suppressFocusChange then return
    focusedIndex = m.channelList.itemFocused
    channel = getChannelByFocusIndex(focusedIndex)
    if channel = invalid then return

    ' If preview is already playing this channel, go fullscreen (double OK)
    if m.previewVideo.content <> invalid and m.previewVideo.content.url = channel.url then
        print ">>> GRID: Double OK - going fullscreen"
        m.suppressNextVideoOptionsMenu = true
        startOverlayOkSuppressionTimer()
        playChannel(channel)
    else
        ' Single OK - load preview
        print ">>> GRID: Single OK - loading preview"
        m.currentChannelIndex = focusedIndex
        playPreviewChannel(focusedIndex)
    end if
end sub

sub onOverlayChannelSelected()
    m.suppressNextVideoOptionsMenu = true
    startOverlayOkSuppressionTimer()
    hideOverlay()
    selectChannelFromList(m.channelOverlayList)
end sub

sub startOverlayOkSuppressionTimer()
    if m.overlayOkSuppressTimer <> invalid then
        m.overlayOkSuppressTimer.control = "stop"
        m.overlayOkSuppressTimer.unobserveField("fire")
        m.overlayOkSuppressTimer = invalid
    end if

    m.overlayOkSuppressTimer = CreateObject("roSGNode", "Timer")
    m.overlayOkSuppressTimer.duration = 0.5
    m.overlayOkSuppressTimer.repeat = false
    m.overlayOkSuppressTimer.observeField("fire", "clearOverlayOkSuppression")
    m.overlayOkSuppressTimer.control = "start"
end sub

sub clearOverlayOkSuppression()
    if m.overlayOkSuppressTimer <> invalid then
        m.overlayOkSuppressTimer.control = "stop"
        m.overlayOkSuppressTimer.unobserveField("fire")
        m.overlayOkSuppressTimer = invalid
    end if

    m.suppressNextVideoOptionsMenu = false
end sub

sub selectChannelFromList(list as Object)
    print ">>> SELECTCHANNEL: Selecting channel from list"
    
    if list.content = invalid or list.content.getChildCount() = 0 then
        print ">>> SELECTCHANNEL ERROR: Invalid or empty channel list"
        return
    end if
    
    firstChild = list.content.getChild(0)
    if firstChild = invalid then 
        print ">>> SELECTCHANNEL ERROR: firstChild invalid"
        return
    end if
    
    content = getChannelFromListItem(list, list.itemSelected)
    print ">>> SELECTCHANNEL: section = "; list.currFocusSection; ", item = "; list.itemSelected
    
    if content = invalid then 
        print ">>> SELECTCHANNEL ERROR: Selected content is invalid"
        return
    end if
    
    print ">>> SELECTCHANNEL: Selecting channel: "; content.title
    print ">>> SELECTCHANNEL: URL: "; content.url
    
    findChannelIndexByUrl(content.url)
    
    print ">>> SELECTCHANNEL: currentChannelIndex set to = "; m.currentChannelIndex
    playChannel(content)
end sub
sub findChannelIndexByUrl(url as String)
    if m.flatChannelList = invalid or m.flatChannelList.Count() = 0 then
        print ">>> FINDINDEX ERROR: flatChannelList contains no channels"
        m.currentChannelIndex = 0
        return
    end if
    
    for i = 0 to m.flatChannelList.Count() - 1
        channel = m.flatChannelList[i]
        if channel <> invalid and channel.url = url then
            m.currentChannelIndex = i
            print ">>> FINDINDEX: Channel located in index "; i
            return
        end if
    end for
    
    print ">>> FINDINDEX: No channel found, falling back to index 0"
    m.currentChannelIndex = 0
end sub

sub reloadCurrentPlaylist()
    if m.playlists = invalid or m.playlists.Count() = 0 then return
    idx = m.playlistList.itemFocused
    if idx >= 0 and idx < m.playlists.Count() then
        loadPlaylist(m.playlists[idx].url)
    end if
end sub

sub reloadCurrentChannel()
    print ">>> RELOAD: Reloading current channel"
    
    if m.flatChannelList = invalid or m.currentChannelIndex < 0 then
        print ">>> RELOAD ERROR: There is no channel to reload."
        return
    end if
    
    channel = m.flatChannelList[m.currentChannelIndex]
    if channel = invalid then
        print ">>> RELOAD ERROR: Invalid channel"
        return
    end if
    
    ' Stop the current video.
    m.previewVideo.control = "stop"
    
    ' Create new content
    content = CreateObject("roSGNode", "ContentNode")
    content.title = channel.title
    content.url = channel.url
    content.streamFormat = "hls"
    
    print ">>> RELOAD: Reloading: "; channel.title
    
    ' Force the reload, skipping the check for the same channel
    m.previewVideo.content = invalid
    
    ' Small delay and then play
    content.HttpSendClientCertificates = true
    content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    content.SwitchingStrategy = "full-adaptation"
    m.previewVideo.EnableCookies()
    m.previewVideo.SetCertificatesFile("common:/certs/ca-bundle.crt")
    m.previewVideo.InitClientCertificates()
    m.previewVideo.maxBandwidth = 0
    m.previewVideo.content = content
    m.previewVideo.control = "play"
    m.top.setFocus(true)
    m.bitrateRetryDone = false
    m.stallRetryCount = 0
    m.lastBufferPct = -1
    cancelStallTimer()
    
    print ">>> RELOAD: Channel reloaded successfully"
end sub

sub playChannel(content as Object)
	hideChannelInfo()
	if m.fullscreenFailContainer <> invalid then m.fullscreenFailContainer.visible = false
	content.streamFormat = "hls, mp4, mkv, mp3, avi, m4v, ts, mpeg-4, flv, vob, ogg, ogv, webm, mov, wmv, asf, amv, mpg, mp2, mpeg, mpe, mpv, mpeg2"

	' If already playing this channel, just expand to fullscreen — no reload
	if m.previewVideo.content = invalid or m.previewVideo.content.url <> content.url then
		' Reset buffer state for new channel
		hideBufferBar()
		cancelStallTimer()
		m.lastBufferPct = -1
		print ">>> PLAY: Loading channel: "; content.title
		content.HttpSendClientCertificates = true
		content.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
		content.SwitchingStrategy = "full-adaptation"
		m.previewVideo.EnableCookies()
		m.previewVideo.SetCertificatesFile("common:/certs/ca-bundle.crt")
		m.previewVideo.InitClientCertificates()
		m.previewVideo.maxBandwidth = 0
		m.previewVideo.content = content
		m.previewVideo.control = "play"
		m.bitrateRetryDone = false
		m.stallRetryCount = 0
		m.lastBufferPct = -1
		cancelStallTimer()
	else
		print ">>> PLAY: Already playing, expanding to fullscreen"
	end if

	' Unmute when going fullscreen only if not already muted
	m.previewVideo.mute = m.previewMuted

	m.top.backgroundURI = ""
	m.top.backgroundColor = "0x024c48FF"
	m.previewVideo.trickplaybarvisibilityauto = false
	m.previewVideo.visible = true
	m.previewVideo.translation = [0, 0]
	m.previewVideo.width = 1920
	m.previewVideo.height = 1080

	m.channelList.visible = false
	m.sidePanel.visible = false
	hideGridOverlays()
	if m.gridInactivityTimer <> invalid then
		m.gridInactivityTimer.control = "stop"
		m.gridInactivityTimer.unobserveField("fire")
		m.gridInactivityTimer = invalid
	end if
	resetFullscreenInactivityTimer()

	' If buffer bar is visible, reposition it for fullscreen instead of hiding it
	if m.bufferVisible then
		m.bufferContainer.translation = [560, 980]
		m.bufferContainer.width = 800
		m.bufferTrack.width = 794
		m.bufferLabel.width = 800
	end if

	hideOverlay()

	m.isPlayingVideo = true

	' Show channel info overlay
	channel = m.flatChannelList[m.currentChannelIndex]
	if channel <> invalid then showChannelInfo(channel)

	' Restore fullscreen error text if this channel previously failed
	if m.lastErrorMsg <> "" and m.lastErrorChannelIndex = m.currentChannelIndex then
		showFullscreenError(m.lastErrorMsg)
	end if

	' Ensure Scene focus for keyboard event handling
	m.previewVideo.setFocus(false)
	m.channelList.setFocus(false)
	m.playlistList.setFocus(false)
	m.channelOverlayList.setFocus(false)
	m.top.setFocus(true)

	' Save current state (last playlist and channel)
	saveLastState()

	print ">>> PLAY: Video fullscreen, scene focused"
end sub

function isValidUrl(url as String) as Boolean
    if url = "" then return false
    
    httpReg = CreateObject("roRegex", "^https?://", "i")
    if not httpReg.isMatch(url) then return false
    
    urlReg = CreateObject("roRegex", "^https?://[^\s/$.?#].[^\s]*$", "i")
    return urlReg.isMatch(url)
end function

' ==================== Save/Restore previous state ====================

sub saveLastState()
    print ">>> SAVE STATE: Saving current state"
    
    reg = CreateObject("roRegistrySection", "lastState")
    
    ' Store current playlist index
    reg.Write("playlistIndex", m.currentPlaylist.ToStr())
    
    ' Save active channel URL
    if m.flatChannelList <> invalid and m.currentChannelIndex >= 0 and m.currentChannelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[m.currentChannelIndex]
        if channel <> invalid and channel.url <> invalid then
            reg.Write("channelUrl", channel.url)
            reg.Write("channelTitle", channel.title)
            print ">>> SAVE STATE: Channel saved = "; channel.title
        end if
    end if
    
    ' Save channel index as backup”
    reg.Write("channelIndex", m.currentChannelIndex.ToStr())
    
    reg.Flush()
    print ">>> SAVE STATE: Successfully saved state"
end sub

function loadLastState() as Object
    print ">>> LOAD STATE: Loading saved state"
    
    state = {
        playlistIndex: 0,
        channelUrl: "",
        channelTitle: "",
        channelIndex: 0
    }
    
    reg = CreateObject("roRegistrySection", "lastState")
    
    if reg.Exists("playlistIndex") then
        state.playlistIndex = reg.Read("playlistIndex").ToInt()
        print ">>> LOAD STATE: playlistIndex = "; state.playlistIndex
    end if
    
    if reg.Exists("channelUrl") then
        state.channelUrl = reg.Read("channelUrl")
        print ">>> LOAD STATE: channelUrl = "; state.channelUrl
    end if
    
    if reg.Exists("channelTitle") then
        state.channelTitle = reg.Read("channelTitle")
        print ">>> LOAD STATE: channelTitle = "; state.channelTitle
    end if
    
    if reg.Exists("channelIndex") then
        state.channelIndex = reg.Read("channelIndex").ToInt()
        print ">>> LOAD STATE: channelIndex = "; state.channelIndex
    end if
    
    return state
end function

sub restorePendingChannel()
    ' Restore pending channel after loading the list
    if m.pendingChannelUrl = invalid or m.pendingChannelUrl = "" then return
    
    print ">>> RESTORE: Finding pending channel: "; m.pendingChannelUrl
    
    ' Retrieve channel using URL
    for i = 0 to m.flatChannelList.Count() - 1
        channel = m.flatChannelList[i]
        if channel <> invalid and channel.url = m.pendingChannelUrl then
            m.currentChannelIndex = i
            m.lastFocusedChannel = i
            
            ' Go to channel in list
            if m.channelList <> invalid then
                m.channelList.jumpToItem = i
            end if
            
            ' Start channel preview
            playPreviewChannel(i)
            
            print ">>> RESTORE: Channel found and selected in index "; i
            m.pendingChannelUrl = invalid
            return
        end if
    end for
    
    print ">>> RESTORE: No channel found, defaulting to first channel"
    m.pendingChannelUrl = invalid
end sub
