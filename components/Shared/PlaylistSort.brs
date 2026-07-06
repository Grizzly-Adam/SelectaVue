' ==================== PlaylistSort.brs ====================
' Shared between get_channel_list.brs (the M3U-parsing Task, its own
' isolated scope) and Favorites.brs (MainScene scope, rebuilding the
' favorites-only grid) — both need to build a ContentNode tree grouped by
' category and sorted alphabetically (categories A-Z, channels A-Z within
' each), and previously reimplemented the same grouping/sorting logic
' independently. Referenced via <script> in both components' .xml files
' rather than copy-pasted, since a Task's scope can't call into the Scene's
' shared .brs files directly (and vice versa).

' Builds a sorted, grouped ContentNode tree from a flat list of channel
' data. `items` must be an array of associative arrays, each with at least
' `url` and `title` keys, an optional `description` key, and a `group` key
' (its category name — "" or invalid for ungrouped/no category). Categories
' are sorted A-Z; channels within each category, and any ungrouped
' channels, are sorted A-Z by title.
function buildSortedChannelTree(items as Object) as Object
    groupsMap = {}
    ungrouped = []
    for each it in items
        gName = it.group
        if gName <> invalid and gName <> "" then
            if groupsMap[gName] = invalid then groupsMap[gName] = []
            groupsMap[gName].Push(it)
        else
            ungrouped.Push(it)
        end if
    end for

    result = CreateObject("roSGNode", "ContentNode")

    groupNameList = groupsMap.Keys()
    groupNameList.Sort("i")
    for each gName in groupNameList
        chArr = groupsMap[gName]
        chArr.SortBy("title", "i")
        groupNode = result.CreateChild("ContentNode")
        groupNode.contenttype = "SECTION"
        groupNode.title = gName
        groupNode.id    = gName
        for each chData in chArr
            _appendChannelChild(groupNode, chData)
        end for
    end for

    if ungrouped.Count() > 0 then
        ungrouped.SortBy("title", "i")
        for each chData in ungrouped
            _appendChannelChild(result, chData)
        end for
    end if

    return result
end function

sub _appendChannelChild(parent as Object, chData as Object)
    item       = parent.CreateChild("ContentNode")
    item.url   = chData.url
    item.title = chData.title
    if chData.description <> invalid then item.description = chData.description
end sub
