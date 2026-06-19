' ==================== StateManager.brs ====================
' Persists and restores the last-viewed playlist and channel
' using roRegistrySection so selections survive app restarts.

sub saveLastState()
    print ">>> SAVE STATE: Saving current state"

    reg = CreateObject("roRegistrySection", "lastState")

    reg.Write("playlistIndex", m.currentPlaylist.ToStr())

    if m.flatChannelList <> invalid and m.currentChannelIndex >= 0 and m.currentChannelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[m.currentChannelIndex]
        if channel <> invalid and channel.url <> invalid then
            reg.Write("channelUrl", channel.url)
            reg.Write("channelTitle", channel.title)
            print ">>> SAVE STATE: Channel saved = "; channel.title
        end if
    end if

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
    if m.pendingChannelUrl = invalid or m.pendingChannelUrl = "" then return

    print ">>> RESTORE: Finding pending channel: "; m.pendingChannelUrl

    for i = 0 to m.flatChannelList.Count() - 1
        channel = m.flatChannelList[i]
        if channel <> invalid and channel.url = m.pendingChannelUrl then
            m.currentChannelIndex = i
            m.lastFocusedChannel = i

            if m.channelList <> invalid then
                m.channelList.jumpToItem = i
            end if

            playPreviewChannel(i)

            print ">>> RESTORE: Channel found and selected in index "; i
            m.pendingChannelUrl = invalid
            return
        end if
    end for

    print ">>> RESTORE: No channel found, defaulting to first channel"
    m.pendingChannelUrl = invalid
end sub
