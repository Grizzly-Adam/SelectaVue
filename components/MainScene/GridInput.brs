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
            channel = invalid
            focusedIdx = m.channelList.itemFocused
            if m.flatChannelList <> invalid and focusedIdx >= 0 and focusedIdx < m.flatChannelList.Count() then
                channel = m.flatChannelList[focusedIdx]
            end if
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
        else if m.flatChannelList <> invalid and m.flatChannelList.Count() > 0 then
            ' Purely a selection operation -- never actually plays anything,
            ' just moves grid focus. Driven entirely by comparing current
            ' focus to what's actually playing (m.playingPreviewIndex), so
            ' it self-corrects on every press rather than relying on a
            ' separate toggle flag to remember which "side" we're on:
            '   - Not focused on what's playing?  Jump there.
            '   - Already focused on what's playing?  Jump to the previous
            '     channel instead.
            playingIdx = m.playingPreviewIndex
            focusedIdx = m.channelList.itemFocused

            if playingIdx >= 0 and playingIdx < m.flatChannelList.Count() and focusedIdx <> playingIdx then
                m.currentChannelIndex    = playingIdx
                m.channelList.jumpToItem = playingIdx
            else
                ' Already on what's playing -- jump to the previous channel:
                ' the surf-based one if there's been any surfing in this
                ' playlist, otherwise the last channel watched on THIS
                ' SPECIFIC playlist (see StateManager.brs) -- e.g. right
                ' after switching playlists, before surfing within it.
                targetIdx = -1
                if m.previousChannelIndex >= 0 and m.previousChannelIndex < m.flatChannelList.Count() and m.previousChannelIndex <> playingIdx then
                    targetIdx = m.previousChannelIndex
                else
                    lastUrl = lastWatchedUrlForCurrentPlaylist()
                    if lastUrl <> "" then
                        idx = findChannelIndexByUrl(lastUrl)
                        if idx >= 0 and idx <> playingIdx then targetIdx = idx
                    end if
                end if
                if targetIdx >= 0 then
                    m.currentChannelIndex    = targetIdx
                    m.channelList.jumpToItem = targetIdx
                end if
            end if
        end if
        return true
    end if

    return false
end function
