' ==================== DeepLink.brs ====================
' Handles Roku deep linking — both launch-time (Main args) and runtime (roInputEvent).
' main.brs sets m.global.deepLinkArgs in both cases; we observe it here.
'
' Roku deep link parameters (spec: developer.roku.com/dev/docs/implementing-deep-linking):
'   contentId   — identifies the content to tune to
'   mediaType   — how to handle the link (liveFeed, sportsEvent for IPTV)
'
' For IPTV we accept liveFeed and sportsEvent as valid mediaTypes.
' Any other mediaType (movie, episode, etc.) routes to the home screen per spec.
' If contentId maps to no channel, routes to home screen per spec.
'
' SelectaVue extension (for direct deep linking without Roku Search):
'   channelUrl   — explicit stream URL (takes priority over contentId)
'   channelTitle — channel title to match (fallback)
'
' Resolution order:
'   1. channelUrl  — direct URL match in flatChannelList
'   2. contentId   — try as URL first, then exact title match, then substring
'   3. channelTitle — title substring match

' Valid mediaTypes for an IPTV live streaming app.
' Other types (movie, episode, etc.) have no mapping in our channel list.
function _isValidLiveMediaType(mediaType as String) as Boolean
    mt = LCase(mediaType)
    return mt = "livefeed" or mt = "sportsevent" or mt = "tvspecial" or mt = "shortformvideo" or mt = ""
end function

sub onDeepLinkArgs()
    args = m.global.deepLinkArgs
    if args = invalid then return
    ' Consume immediately — prevents double-processing if restorePendingChannel()
    ' also calls us directly as a race-condition safety net.
    m.global.deepLinkArgs = invalid
    print ">>> DEEPLINK: Processing args: "; FormatJson(args)

    ' Extract and validate mediaType
    ' Per spec: invalid mediaType → home screen
    mediaType = ""
    if args.DoesExist("mediaType") and args.mediaType <> invalid then
        mediaType = args.mediaType
    else if args.DoesExist("mediatype") and args.mediatype <> invalid then
        mediaType = args.mediatype
    end if

    if mediaType <> "" and not _isValidLiveMediaType(mediaType) then
        print ">>> DEEPLINK: mediaType '"; mediaType; "' not applicable for IPTV — going to home"
        _goToHome()
        return
    end if

    ' Extract contentId
    contentId = ""
    if args.DoesExist("contentId") and args.contentId <> invalid and args.contentId <> "" then
        contentId = args.contentId
    else if args.DoesExist("contentid") and args.contentid <> invalid and args.contentid <> "" then
        contentId = args.contentid
    end if

    ' SelectaVue extensions
    targetUrl   = ""
    targetTitle = ""

    if args.DoesExist("channelUrl") and args.channelUrl <> "" then
        targetUrl = args.channelUrl
    end if

    if contentId <> "" then
        lc = LCase(contentId)
        if Left(lc, 7) = "http://" or Left(lc, 8) = "https://" then
            if targetUrl = "" then targetUrl = contentId
        else
            targetTitle = contentId
        end if
    end if

    if args.DoesExist("channelTitle") and args.channelTitle <> "" then
        if targetTitle = "" then targetTitle = args.channelTitle
    end if

    ' Per spec: no usable contentId → home screen
    if targetUrl = "" and targetTitle = "" then
        print ">>> DEEPLINK: No usable contentId — going to home"
        _goToHome()
        return
    end if

    ' Defer if playlist not loaded yet
    if m.flatChannelList = invalid or m.flatChannelList.Count() = 0 then
        print ">>> DEEPLINK: Playlist not ready — deferring"
        m.pendingDeepLinkUrl   = targetUrl
        m.pendingDeepLinkTitle = targetTitle
        return
    end if

    _resolveAndTuneDeepLink(targetUrl, targetTitle)
end sub

' Called from restorePendingChannel() after playlist finishes loading.
sub checkPendingDeepLink()
    hasPendingUrl   = m.pendingDeepLinkUrl   <> invalid and m.pendingDeepLinkUrl   <> ""
    hasPendingTitle = m.pendingDeepLinkTitle <> invalid and m.pendingDeepLinkTitle <> ""
    if not hasPendingUrl and not hasPendingTitle then return
    print ">>> DEEPLINK: Playlist ready — processing deferred deep link"
    _resolveAndTuneDeepLink(m.pendingDeepLinkUrl, m.pendingDeepLinkTitle)
    m.pendingDeepLinkUrl   = invalid
    m.pendingDeepLinkTitle = invalid
end sub

' Resolves a target URL or title to a channel index and tunes to it.
' If no match found, navigates to home screen per Roku spec.
sub _resolveAndTuneDeepLink(targetUrl as String, targetTitle as String)
    if targetUrl = invalid then targetUrl = ""
    if targetTitle = invalid then targetTitle = ""
    idx = -1

    ' 1. Direct URL match
    if targetUrl <> "" then
        idx = findChannelIndexByUrl(targetUrl)
        if idx >= 0 then print ">>> DEEPLINK: Matched by URL"
    end if

    ' 2. Exact title match (case-insensitive)
    if idx < 0 and targetTitle <> "" then
        lowerTarget = LCase(targetTitle)
        for i = 0 to m.flatChannelList.Count() - 1
            ch = m.flatChannelList[i]
            if ch <> invalid and ch.title <> invalid then
                if LCase(ch.title) = lowerTarget then
                    idx = i
                    print ">>> DEEPLINK: Matched by exact title: "; ch.title
                    exit for
                end if
            end if
        end for
    end if

    ' 3. Substring title match (case-insensitive)
    if idx < 0 and targetTitle <> "" then
        lowerTarget = LCase(targetTitle)
        for i = 0 to m.flatChannelList.Count() - 1
            ch = m.flatChannelList[i]
            if ch <> invalid and ch.title <> invalid then
                if LCase(ch.title).InStr(lowerTarget) >= 0 then
                    idx = i
                    print ">>> DEEPLINK: Matched by title substring: "; ch.title
                    exit for
                end if
            end if
        end for
    end if

    ' Per spec: no match → home screen
    if idx < 0 then
        print ">>> DEEPLINK: No channel match for url=["; targetUrl; "] title=["; targetTitle; "] — going to home"
        _goToHome()
        return
    end if

    print ">>> DEEPLINK: Tuning to index "; idx; " — "; m.flatChannelList[idx].title
    m.currentChannelIndex = idx
    channel = m.flatChannelList[idx]

    if m.isPlayingVideo then
        ' Already in fullscreen — switch channels
        playChannel(channel)
    else
        ' From grid — launch fullscreen
        _launchFullscreen(idx)
    end if
end sub

' Navigate to the app home screen (the channel grid).
' Called on invalid/unmatched deep links per Roku certification spec.
sub _goToHome()
    ' Use _exitFullscreen() which correctly stops video, restores geometry,
    ' clears overlays, and refocuses the grid — avoids duplicating that logic
    ' and leaving the video running in background.
    if m.isPlayingVideo then
        _exitFullscreen()
    else
        if m.channelList <> invalid then m.channelList.setFocus(true)
    end if
end sub
