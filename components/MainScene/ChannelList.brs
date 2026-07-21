' ==================== ChannelList.brs ====================
' Build the flat channel list and look up channels by index or URL.

' ---------- Channel list helpers ----------

sub buildFlatChannelList()
    m.flatChannelList = []
    if m.allChannels = invalid then return
    for i = 0 to m.allChannels.getChildCount() - 1
        section = m.allChannels.getChild(i)
        if section = invalid then continue for
        if section.getChildCount() = 0 then
            ' Leaf node — only add if it has a url (skip bare section headers)
            if section.url <> invalid and section.url <> "" then
                m.flatChannelList.Push(section)
            end if
        else
            for j = 0 to section.getChildCount() - 1
                channel = section.getChild(j)
                if channel <> invalid and channel.url <> invalid and channel.url <> "" then
                    m.flatChannelList.Push(channel)
                end if
            end for
        end if
    end for
    print ">>> PLAYLIST: Total channels in flat list: "; m.flatChannelList.Count()
end sub

' Walks the ContentNode tree structurally to find what's at a given flat
' position -- O(n) from the front every call. m.flatChannelList is the same
' data kept in sync with this same tree by every rebuild path, so anything
' called per-keystroke (grid focus, most selections) should index into that
' array directly instead of calling this. Now only used as a fallback in
' playPreviewChannel() and by selectChannelFromList() (for the quick menu,
' where reading the list's own displayed content directly is the more
' correct source of truth than m.flatChannelList if the two were ever to
' drift — see the note on _showQuickMenu() in FullscreenInput.brs).
function getChannelByFocusIndex(focusIndex as Integer) as Object
    return getChannelFromListItem(m.channelList, focusIndex)
end function

function getChannelFromListItem(list as Object, itemIndex as Integer) as Object
    if list = invalid or list.content = invalid then return invalid
    content = list.content
    if content.getChildCount() = 0 then return invalid
    if content.getChild(0) = invalid then return invalid
    return getChannelFromFlatListItem(content, itemIndex)
end function

function getChannelFromFlatListItem(content as Object, itemIndex as Integer) as Object
    if content = invalid or itemIndex < 0 then return invalid
    channelIndex = 0
    for i = 0 to content.getChildCount() - 1
        section = content.getChild(i)
        if section = invalid then continue for
        if section.getChildCount() = 0 then
            ' Only counts as a flat position if it's a real leaf channel (has
            ' a url) -- a bare/empty section header (no children, no url)
            ' must be skipped entirely, same as buildFlatChannelList() above,
            ' or the two fall out of sync by one position per such node.
            if section.url <> invalid and section.url <> "" then
                if channelIndex = itemIndex then return section
                channelIndex = channelIndex + 1
            end if
        else
            ' Walk each child individually rather than trusting the raw
            ' child count -- buildFlatChannelList() also skips any child
            ' without a url, so a malformed entry inside a real category
            ' would otherwise throw the two out of sync by one position
            ' from that point on, same failure mode as the bare-section case
            ' above just one level deeper.
            for j = 0 to section.getChildCount() - 1
                channel = section.getChild(j)
                if channel <> invalid and channel.url <> invalid and channel.url <> "" then
                    if channelIndex = itemIndex then return channel
                    channelIndex = channelIndex + 1
                end if
            end for
        end if
    end for
    return invalid
end function

' Returns the flat-list index of the channel with the given URL, or -1 if
' not found. Shared by anything needing to resolve a URL back to an index
' (restoring the last-watched channel on launch, re-syncing the current
' index to whatever's actually playing).
function findChannelIndexByUrl(url as String) as Integer
    if m.flatChannelList = invalid then return -1
    for i = 0 to m.flatChannelList.Count() - 1
        channel = m.flatChannelList[i]
        if channel <> invalid and channel.url = url then return i
    end for
    return -1
end function
