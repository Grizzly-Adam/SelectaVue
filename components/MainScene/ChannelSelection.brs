' ==================== ChannelSelection.brs ====================
' Handle channel focus, selection, and overlay list events.

' ---------- Channel focus / selection ----------

sub onChannelFocused()
    if m.isPlayingVideo then return
    if m.channelList = invalid then return
    if m.suppressFocusChange then return
    if m.loadingDialogVisible then _dismissLoadingDialogForInput()
    ' Up/down on the grid list is consumed natively (fires this observer)
    ' before it would ever reach onKeyEvent's reconnectOverlay handling —
    ' same underlying issue as the loading overlay. Cancel any in-flight
    ' retry ladder/outage loop/gave-up state here too, or it just keeps
    ' running (and the overlay stays up) while the user browses away from it.
    cancelAnyInFlightRetry()
    if _dismissScreensaverIfVisible() then return
    focusedIndex = m.channelList.itemFocused
    channel = getChannelByFocusIndex(focusedIndex)
    if channel <> invalid then
        if focusedIndex <> m.currentChannelIndex then
            hideBufferBar()
            cancelStallTimer()
        end if
        m.currentChannelIndex = focusedIndex
    end if
    resetGridInactivityTimer()
end sub

sub onChannelSelected()
    if m.channelList = invalid then return
    if m.suppressFocusChange then return
    if m.loadingDialogVisible then
        _dismissLoadingDialogForInput()
        return
    end if
    if _dismissScreensaverIfVisible() then return

    ' OK on the reconnect overlay is supposed to mean "cancel" (ladder actively
    ' retrying) or "retry" (gave-up state) — see onKeyEvent's RECONNECT DIALOG
    ' key map. But m.channelList has focus the whole time we're on the grid,
    ' so the LabelList consumes OK natively and fires this observer instead of
    ' ever reaching onKeyEvent's reconnect-overlay intercept. Without this
    ' check, that OK fell through to the normal select-channel logic below,
    ' which cancels the ladder SILENTLY (no error shown) and then immediately
    ' reloads the exact channel that just failed — which looks like the
    ' Cancel button doing nothing and the channel reconnecting on its own a
    ' moment later. Handle both reconnect-overlay states here first so the
    ' CHANNEL UNAVAILABLE overlay actually shows instead of being skipped.
    if m.reconnectOverlay <> invalid and m.reconnectOverlay.visible and m.reconnectState = "ladder" then
        cancelRetryOverlay()
        return
    end if
    if m.reconnectState = "gaveup" then
        showRetryStatus("Retrying...")
        reloadCurrentChannel()
        return
    end if

    ' LabelList fires itemSelected internally on OK press — this can happen
    ' independently of onKeyEvent's dialog intercept, so cancel any in-flight
    ' retry here too before acting on the selection.
    cancelAnyInFlightRetry()
    focusedIndex = m.channelList.itemFocused
    channel      = getChannelByFocusIndex(focusedIndex)
    if channel = invalid then return
    if _isChannelActivelyLoaded(channel.url) then
        print ">>> GRID: Double OK - going fullscreen"
        m.suppressNextVideoOptionsMenu = true
        startOverlayOkSuppressionTimer()
        playChannel(channel)
    else
        print ">>> GRID: Single OK - loading preview"
        ' Record what's actually playing right now as the departure point --
        ' picking a channel directly (not surfing via up/down) has no dwell
        ' mechanism of its own to do this. Without it, previousChannelIndex
        ' stayed stale and the grid's replay key broke after the first
        ' direct selection like this (its fallback target had, by then,
        ' also been overwritten to this same just-selected channel once it
        ' started playing).
        if m.playingPreviewIndex >= 0 and m.flatChannelList <> invalid and m.playingPreviewIndex < m.flatChannelList.Count() then
            playingChannel = m.flatChannelList[m.playingPreviewIndex]
            if playingChannel <> invalid and playingChannel.url <> channel.url then
                m.previousChannelIndex = m.playingPreviewIndex
            end if
        end if
        m.currentChannelIndex = focusedIndex
        playPreviewChannel(focusedIndex)
    end if
end sub

sub onOverlayChannelSelected()
    m.suppressNextVideoOptionsMenu = true
    startOverlayOkSuppressionTimer()
    hideOverlay()
    ' Quick menu owns input while open — cancel any in-flight retry before
    ' the new channel loads, so the old channel's retry timers don't keep
    ' firing against a video node that's about to play something else.
    cancelAnyInFlightRetry()
    selectChannelFromList(m.channelOverlayList)
end sub

sub onOverlayItemFocused()
    cancelAnyInFlightRetry()
    if _dismissScreensaverIfVisible() then return
    if m.overlayVisible then
        m.currentChannelIndex = m.channelOverlayList.itemFocused
        resetOverlayInactivityTimer()
    end if
end sub

sub selectChannelFromList(list as Object)
    if list.content = invalid or list.content.getChildCount() = 0 then return
    if list.content.getChild(0) = invalid then return
    content = getChannelFromListItem(list, list.itemSelected)
    if content = invalid then return
    print ">>> SELECTCHANNEL: "; content.title
    ' Record what's actually playing right now as the departure point --
    ' same gap and fix as onChannelSelected()'s single-OK branch: picking a
    ' channel directly here has no dwell mechanism of its own to do this.
    if m.playingPreviewIndex >= 0 and m.flatChannelList <> invalid and m.playingPreviewIndex < m.flatChannelList.Count() then
        playingChannel = m.flatChannelList[m.playingPreviewIndex]
        if playingChannel <> invalid and playingChannel.url <> content.url then
            m.previousChannelIndex = m.playingPreviewIndex
        end if
    end if
    ' Use the list's own selected index directly — it's already the correct
    ' position in m.allChannels (the same tree m.flatChannelList is built
    ' from), so there's no need to re-derive it by URL. Re-deriving by URL
    ' used to land on whichever section listed this channel's URL FIRST,
    ' which is wrong whenever the same channel appears in multiple sections
    ' (e.g. picking a channel from its "News" listing would silently snap
    ' the grid/quick-menu back to its "Sports" listing if Sports came first).
    m.currentChannelIndex = list.itemSelected
    playChannel(content)
end sub
