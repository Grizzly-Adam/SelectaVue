' ==================== StateManager.brs ====================
' Persists and restores the last-viewed playlist and channel
' using roRegistrySection so selections survive app restarts.

function LAST_STATE_REG_SECTION() as String
    return "lastState"
end function

sub saveLastState()
    reg = CreateObject("roRegistrySection", LAST_STATE_REG_SECTION())
    reg.Write("playlistIndex", m.currentPlaylist.ToStr())
    if m.flatChannelList <> invalid and m.currentChannelIndex >= 0 and m.currentChannelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[m.currentChannelIndex]
        if channel <> invalid and channel.url <> invalid then
            reg.Write("channelUrl",   channel.url)
            reg.Write("channelTitle", cleanChannelTitle(channel))
            print ">>> STATE: Saved currentChannelIndex="; m.currentChannelIndex; " url="; channel.url; " title="; cleanChannelTitle(channel); " playlistIndex="; m.currentPlaylist
        else
            print ">>> STATE: currentChannelIndex="; m.currentChannelIndex; " has no channel/url -- channelUrl/channelTitle NOT written this call"
        end if
    else
        print ">>> STATE: currentChannelIndex="; m.currentChannelIndex; " out of range for flatChannelList (count="; iif(m.flatChannelList <> invalid, m.flatChannelList.Count(), -1); ") -- channelUrl/channelTitle NOT written this call"
    end if
    ' Persist previous channel for instant-replay across reboots
    if m.flatChannelList <> invalid and m.previousChannelIndex >= 0 and m.previousChannelIndex < m.flatChannelList.Count() then
        prevChannel = m.flatChannelList[m.previousChannelIndex]
        if prevChannel <> invalid and prevChannel.url <> invalid then
            reg.Write("previousChannelUrl", prevChannel.url)
        else
            reg.Delete("previousChannelUrl")
        end if
    else
        reg.Delete("previousChannelUrl")
    end if
    reg.Flush()
end sub

function loadLastState() as Object
    state = { playlistIndex: 0, channelUrl: "", channelTitle: "", previousChannelUrl: "" }
    reg   = CreateObject("roRegistrySection", LAST_STATE_REG_SECTION())
    if reg.Exists("playlistIndex")       then state.playlistIndex       = reg.Read("playlistIndex").ToInt()
    if reg.Exists("channelUrl")          then state.channelUrl          = reg.Read("channelUrl")
    if reg.Exists("channelTitle")        then state.channelTitle        = reg.Read("channelTitle")
    if reg.Exists("previousChannelUrl")  then state.previousChannelUrl  = reg.Read("previousChannelUrl")
    return state
end function

sub restorePendingChannel()
    ' Safety net for launch deep link race condition:
    ' main.brs sets m.global.deepLinkArgs after screen.show(), but the render
    ' thread may reach restorePendingChannel() before the observer fires.
    ' Calling onDeepLinkArgs() here catches that case. onDeepLinkArgs() clears
    ' the field immediately, so if the observer also fires later it's a no-op.
    if m.global.deepLinkArgs <> invalid then
        print ">>> DEEPLINK: Catching args in restorePendingChannel (observer race)"
        onDeepLinkArgs()
    end if

    ' Check for a pending deep link first — it takes priority over last-watched restore.
    ' Clear the last-channel pending vars so they don't re-fire on the next playlist load.
    if (m.pendingDeepLinkUrl <> invalid and m.pendingDeepLinkUrl <> "") or (m.pendingDeepLinkTitle <> invalid and m.pendingDeepLinkTitle <> "") then
        print ">>> STATE: Deep link pending (url="; m.pendingDeepLinkUrl; " title="; m.pendingDeepLinkTitle; ") -- using last-watched channel as flashback target (was pendingChannelUrl="; m.pendingChannelUrl; ")"
        ' Whatever channel the last session was actually on becomes the
        ' "previous channel" for this deep-linked session, so Replay/
        ' flashback works immediately — without this, m.previousChannelIndex
        ' stayed at its default (-1) after a deep link until the user
        ' surfed at least once.
        if m.pendingChannelUrl <> invalid and m.pendingChannelUrl <> "" then
            prevIdx = findChannelIndexByUrl(m.pendingChannelUrl)
            if prevIdx >= 0 then
                m.previousChannelIndex = prevIdx
                print ">>> STATE: Deep link flashback target -> index="; prevIdx; " ("; m.pendingChannelUrl; ")"
            end if
        end if
        m.pendingChannelUrl         = invalid
        m.pendingPreviousChannelUrl = invalid
        m.initialLaunch             = false   ' prevent fallback to channel 0 after deep link
        checkPendingDeepLink()
        return
    end if

    if m.pendingChannelUrl = invalid or m.pendingChannelUrl = "" then return
    i = findChannelIndexByUrl(m.pendingChannelUrl)
    print ">>> STATE: Restoring last channel, url="; m.pendingChannelUrl; " -> index="; i
    if i >= 0 then
        m.currentChannelIndex = i
        if m.channelList <> invalid then m.channelList.jumpToItem = i
        ' Restore previous channel index for instant replay
        if m.pendingPreviousChannelUrl <> invalid and m.pendingPreviousChannelUrl <> "" then
            prevIdx = findChannelIndexByUrl(m.pendingPreviousChannelUrl)
            if prevIdx >= 0 and prevIdx <> i then
                m.previousChannelIndex = prevIdx
                print ">>> STATE: Restored previousChannelIndex="; prevIdx; " ("; m.pendingPreviousChannelUrl; ")"
            end if
            m.pendingPreviousChannelUrl = invalid
        end if
        if m.initialLaunch then
            m.initialLaunch = false
            _launchFullscreen(i)
        else
            playPreviewChannel(i)
        end if
        m.pendingChannelUrl = invalid
        return
    end if
    m.pendingChannelUrl = invalid
    m.pendingPreviousChannelUrl = invalid
end sub

' ---------- Per-playlist last-watched channel ----------
' Separate from the app-wide "lastState" above (which restores exactly one
' channel across app restarts, regardless of playlist) -- this remembers,
' for EACH playlist independently, the last channel that reached "playing"
' state while that playlist was loaded (saved from checkState() in
' ChannelNav.brs). Used by GridInput.brs's replay key on the grid screen: if
' there's no surf-based m.previousChannelIndex yet (e.g. you just switched to
' this playlist and haven't surfed within it), pressing replay falls back to
' whatever you last watched on THIS SPECIFIC playlist -- selecting it in the
' grid without starting playback, unlike the normal surf-based case.

function LAST_CHANNEL_PER_PLAYLIST_REG_SECTION() as String
    return "lastChannelPerPlaylist"
end function

sub saveLastWatchedChannelForCurrentPlaylist(url as String)
    if m.currentPlaylist = invalid or m.currentPlaylist < 0 then return
    if url = invalid or url = "" then return
    reg = CreateObject("roRegistrySection", LAST_CHANNEL_PER_PLAYLIST_REG_SECTION())
    reg.Write("playlist_" + m.currentPlaylist.ToStr(), url)
    reg.Flush()
end sub

function lastWatchedUrlForCurrentPlaylist() as String
    if m.currentPlaylist = invalid or m.currentPlaylist < 0 then return ""
    reg = CreateObject("roRegistrySection", LAST_CHANNEL_PER_PLAYLIST_REG_SECTION())
    key = "playlist_" + m.currentPlaylist.ToStr()
    if reg.Exists(key) then return reg.Read(key)
    return ""
end function



