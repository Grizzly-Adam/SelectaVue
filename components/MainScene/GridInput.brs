' ==================== GridInput.brs ====================
' Grid key handling: channel list navigation, the playlist side panel,
' favorite toggle, and replay (jump to previously watched channel / reload playlist).
'
' Key map — GRID (channel list focused):
'   back        → return to playing preview channel (if not already there); else open playlist panel
'   left        → open playlist panel
'   right       → go fullscreen with current preview (if playing)
'   OK          → load preview / go fullscreen
'   options (*) → toggle favorite on focused channel
'   replay      → jump focus to previously watched channel
'
' Key map — GRID (playlist panel focused):
'   back        → go fullscreen if preview is playing; else consume
'   right       → move focus to channel list
'   options     → show playlist options
'   replay      → reload current playlist

' ---------- Grid key handling ----------

function _handleGridKey(key as String) as Boolean
    if key = "back" then
        if m.playlistPanelActive then
            ' Playlist panel is focused
            if m.previewVideo.state = "playing" then _goFullscreenFromGrid()
            ' consume key either way
        else
            ' Channel list is focused
            ' If preview is playing and focus is not on the playing channel,
            ' first press returns to the playing channel.
            ' If already on the playing channel (or nothing playing), open playlist panel.
            if m.playingPreviewIndex >= 0 and m.previewVideo.state = "playing" and m.currentChannelIndex <> m.playingPreviewIndex then
                m.channelList.jumpToItem  = m.playingPreviewIndex
                m.currentChannelIndex     = m.playingPreviewIndex
            else
                m.sidePanel.visible   = true
                m.playlistPanelActive = true
                m.playlistList.SetFocus(true)
            end if
        end if
        return true

    else if key = "right" then
        if m.playlistPanelActive then
            m.playlistPanelActive = false
            m.channelList.SetFocus(true)
        else
            ' Go fullscreen with current preview if something is playing.
            ' Re-sync currentChannelIndex to what's actually playing first
            ' — the user may have navigated to a different, not-yet-selected
            ' channel without changing what's actually playing, and without
            ' this the channel bar (and subsequent surfing) would reflect
            ' the highlighted channel instead of the one shown/played.
            if m.previewVideo.state = "playing" then
                if m.playingPreviewIndex >= 0 then m.currentChannelIndex = m.playingPreviewIndex
                _goFullscreenFromGrid()
            end if
        end if
        return true

    else if key = "left" then
        m.sidePanel.visible   = true
        m.playlistPanelActive = true
        m.playlistList.SetFocus(true)
        return true

    else if key = "options" then
        if m.playlistPanelActive then
            m.playlistFocusIndex = m.playlistList.itemFocused
            showPlaylistOptions()
            return true
        else
            channel = getChannelByFocusIndex(m.channelList.itemFocused)
            if channel <> invalid then
                toggleFavorite(channel)
                ' If currently viewing the favorites-only filter and this
                ' channel just got un-favorited, it needs to disappear from
                ' the list immediately rather than linger until next visit.
                if m.favoritesOnly then
                    _rebuildFavoritesGrid()
                else
                    refreshFavoriteStarsDisplay()
                end if
            end if
            return true
        end if

    else if key = "replay" then
        if m.playlistPanelActive then
            reloadCurrentPlaylist()
        else
            ' Jump focus to previously watched channel and start preview
            if m.previousChannelIndex >= 0 and m.flatChannelList <> invalid and m.previousChannelIndex < m.flatChannelList.Count() then
                m.currentChannelIndex = m.previousChannelIndex
                m.channelList.jumpToItem = m.previousChannelIndex
                playPreviewChannel(m.previousChannelIndex)
            end if
        end if
        return true
    end if

    return false
end function
