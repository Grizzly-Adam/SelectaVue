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
        end if
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
    if m.pendingChannelUrl = invalid or m.pendingChannelUrl = "" then return
    i = findChannelIndexByUrl(m.pendingChannelUrl)
    if i >= 0 then
        m.currentChannelIndex = i
        if m.channelList <> invalid then m.channelList.jumpToItem = i
        ' Restore previous channel index for instant replay
        ' Only set if it's a different channel and valid
        if m.pendingPreviousChannelUrl <> invalid and m.pendingPreviousChannelUrl <> "" then
            prevIdx = findChannelIndexByUrl(m.pendingPreviousChannelUrl)
            if prevIdx >= 0 and prevIdx <> i then
                m.previousChannelIndex = prevIdx
                print ">>> STATE: Restored previousChannelIndex="; prevIdx; " ("; m.pendingPreviousChannelUrl; ")"
            end if
            m.pendingPreviousChannelUrl = invalid
        end if
        if m.initialLaunch then
            ' First load after app start — go straight to fullscreen
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
