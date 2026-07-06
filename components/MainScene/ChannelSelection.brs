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
