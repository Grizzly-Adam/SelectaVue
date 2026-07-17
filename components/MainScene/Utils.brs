' ==================== Utils.brs ====================
' Pure helper functions and constants with no side-effects.
' Safe to call from any other main-scene module.
'
' NOTE: iif() also has a private copy in ManifestPatcher.brs because
' that file runs in a separate Task node and cannot share this scope.

' Returns the number of built-in (non-deletable) playlists.
' Derived from m.playlists' isDefault flags rather than a hardcoded number,
' so it can never drift out of sync with loadSavedPlaylists() again — add or
' remove a built-in entry there and this just reflects it automatically.
' Returns 0 if m.playlists hasn't been populated yet (loadSavedPlaylists()
' always pushes built-ins first, so this is safe to call any time after that).
function BUILTIN_PLAYLIST_COUNT() as Integer
    count = 0
    if m.playlists <> invalid then
        for each pl in m.playlists
            if pl.isDefault = true then count = count + 1
        end for
    end if
    return count
end function

' Inline ternary helper — BrightScript has no ?: operator.
' Returns a channel's clean display title — the star prefix Favorites.brs
' adds to channel.title (via _syncFavoriteStars) is only meant for the
' channel list and quick menu. Every other label (preview name, channel bar,
' details dialog, error/reconnect overlays) should use this instead.
function cleanChannelTitle(channel as Object) as String
    if channel = invalid then return ""
    if channel.baseTitle <> invalid and channel.baseTitle <> "" then return channel.baseTitle
    if channel.title <> invalid then return channel.title
    return ""
end function

' Returns the display name of the currently-loaded playlist/server (e.g.
' "Southdale Labs", "United States") or "" if none is loaded yet. Shared by
' the grid header (Favorites.brs), the fullscreen channel bar
' (ChannelBar.brs), and the channel details dialog (MediaMenus.brs) so
' there's a single source of truth for "what server am I looking at".
function currentServerName() as String
    if m.playlists = invalid or m.currentPlaylist < 0 or m.currentPlaylist >= m.playlists.Count() then return ""
    return m.playlists[m.currentPlaylist].name
end function

' ---------- Generic named-timer helpers ----------
' Nearly every one-shot/repeating timer in this app follows the exact same
' create/observe/start and stop/unobserve/clear pattern, just against a
' different m.<field> each time (m.stallTimer, m.errorDelayTimer, etc).
' These two collapse that into one call each via m's associative-array
' bracket access — m[fieldName] reads/writes the same field as m.fieldName
' would, just with the field name as a runtime string instead of a literal.
' Individual startXTimer()/cancelXTimer() functions elsewhere now call
' these instead of repeating the 5-6 lines each time; their own names and
' call sites are unchanged.

sub _startNamedTimer(fieldName as String, duration as Float, repeatFlag as Boolean, fireCallback as String)
    _cancelNamedTimer(fieldName)
    t = CreateObject("roSGNode", "Timer")
    t.duration = duration
    t.repeat   = repeatFlag
    t.ObserveField("fire", fireCallback)
    t.control  = "start"
    m[fieldName] = t
end sub

sub _cancelNamedTimer(fieldName as String)
    t = m[fieldName]
    if t <> invalid then
        t.control = "stop"
        t.unobserveField("fire")
        m[fieldName] = invalid
    end if
end sub

' ---------- Simple dialog helper ----------
' Creates and shows a basic message Dialog (title + optional message +
' button list), optionally observing buttonSelected. Unifies the ~6
' near-identical CreateObject("roSGNode", "Dialog")/title/message/buttons/
' m.top.dialog assignments scattered across the playlist and media-info
' dialog flows. Returns the dialog node in case the caller needs it.
function _showSimpleDialog(title as String, message as String, buttons as Object, buttonCallback = "" as String) as Object
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = title
    if message <> "" then dialog.message = message
    dialog.buttons = buttons
    m.top.dialog = dialog
    if buttonCallback <> "" then dialog.observeField("buttonSelected", buttonCallback)
    return dialog
end function

' ---------- Keyboard dialog helper ----------
' Same idea as _showSimpleDialog but for StandardKeyboardDialog (title +
' optional message + initial text + buttons). Unifies the 4 near-identical
' creation sites across the playlist add/edit name-and-URL entry flows.
function _showKeyboardDialog(title as String, message as String, initialText as String, buttons as Object, buttonCallback = "" as String) as Object
    dialog = createObject("roSGNode", "StandardKeyboardDialog")
    dialog.backgroundUri = ""
    dialog.title = title
    if message <> "" then dialog.message = message
    dialog.text = initialText
    dialog.buttons = buttons
    m.top.dialog = dialog
    if buttonCallback <> "" then dialog.observeField("buttonSelected", buttonCallback)
    return dialog
end function

' ---------- Shared color constants ----------
' These specific colors exist both as XML default paint (channel bar
' buttons, icon tints, background) and as BRS runtime values that
' overwrite those defaults every time the bar shows/focus changes/etc.
' The XML values can't reference these (no expression evaluation in
' SceneGraph markup — a platform limitation, not fixable without a build
' step), so they still exist as separate literals there. But the BRS side
' now has exactly one source of truth instead of several, which is what
' actually matters: this is the value in effect during real usage, since
' _setBarFocusIndex() (and friends) overwrite the XML default within a
' frame of the bar ever showing. This is also the exact bug pattern that
' bit the channel bar colors once already — they'd drifted out of sync.

function ACCENT_TEAL() as String
    return "0x8fcdc1FF"   ' focused button background, section dividers, header label
end function

function ACCENT_TEAL_DARK() as String
    return "0x3D5C56FF"   ' unfocused button background
end function

function ICON_DIM_COLOR() as String
    return "0x999999FF"   ' off-state tint for toggle icons (Favorite/CC)
end function

function APP_BACKGROUND_TEAL() as String
    return "0x024c48FF"   ' restored on m.top.backgroundColor whenever leaving fullscreen/video
end function

function iif(condition as Boolean, trueVal as Dynamic, falseVal as Dynamic) as Dynamic
    if condition then return trueVal
    return falseVal
end function

' Sniff the stream format from a URL's file extension.
' Strips query strings and fragments before checking.
' Returns a streamFormat string suitable for ContentNode.streamFormat.
' Defaults to "hls" when the extension is unrecognised — the most
' common format in public IPTV playlists.
function detectStreamFormat(url as String) as String
    cleanUrl = url
    qPos = cleanUrl.InStr("?")
    if qPos > 0 then cleanUrl = Left(cleanUrl, qPos)  ' qPos is 0-based, so Left(cleanUrl, qPos) is everything before "?"
    hPos = cleanUrl.InStr("#")
    if hPos > 0 then cleanUrl = Left(cleanUrl, hPos)  ' same fix for "#"
    cleanUrl = LCase(cleanUrl)

    if cleanUrl.EndsWith(".m3u8") then return "hls"
    if cleanUrl.EndsWith(".mpd")  then return "dash"
    if cleanUrl.EndsWith(".mp4")  then return "mp4"
    if cleanUrl.EndsWith(".m4v")  then return "mp4"
    if cleanUrl.EndsWith(".mov")  then return "mp4"
    if cleanUrl.EndsWith(".ts")   then return "hls"  ' .ts in IPTV playlists is almost always HLS, not raw transport stream
    if cleanUrl.EndsWith(".mp3")  then return "mp3"
    if cleanUrl.EndsWith(".m4a")  then return "mp3"
    if cleanUrl.EndsWith(".aac")  then return "mp3"
    if cleanUrl.EndsWith("/mpegts") or cleanUrl.EndsWith("mpegts") then return "ts"  ' Flussonic raw MPEG-TS endpoint
    if cleanUrl.InStr(":9981/stream/") > 0 then return "ts"                          ' TVHeadend raw MPEG-TS stream

    ' Check original URL for TVHeadend passthrough profile (query string already stripped above so check original)
    if url.InStr("profile=pass") > 0 then return "ts"                                ' TVHeadend ?profile=pass is always raw MPEG-TS

    return "hls"
end function

' Parses the channel description field which encodes custom HTTP headers
' written by get_channel_list.brs from #EXTVLCOPT tags in M3U playlists.
' Format: "UA:user-agent-value||REF:referrer-value||COOKIE:cookie-string"
' The double-pipe delimiter avoids false matches inside UA/Referer strings.
' Returns an AA with "ua", "ref", and "cookie" keys. Any may be "".
' Returns invalid if description is empty, invalid, or not in this format.
function parseChannelDescription(description as String) as Object
    if description = invalid or description = "" then return invalid
    if Left(description, 3) <> "UA:" then return invalid
    result = { ua: "", ref: "", cookie: "", tvgid: "", logo: "" }

    workStr = description

    ' Split off LOGO (rightmost field, if present)
    logoPos = workStr.InStr("||LOGO:")
    if logoPos > 0 then
        result.logo = Mid(workStr, logoPos + 7)
        workStr     = Left(workStr, logoPos)
    end if

    ' Split off TVGID
    tvgPos = workStr.InStr("||TVGID:")
    if tvgPos > 0 then
        result.tvgid = Mid(workStr, tvgPos + 8)
        workStr      = Left(workStr, tvgPos)
    end if

    ' Split off COOKIE
    cookiePos = workStr.InStr("||COOKIE:")
    if cookiePos > 0 then
        result.cookie = Mid(workStr, cookiePos + 9)
        workStr       = Left(workStr, cookiePos)
    end if

    ' Now split UA and REF from what remains
    pipePos = workStr.InStr("||REF:")
    if pipePos > 0 then
        result.ua  = _stripLeadingColons(Mid(workStr, 4, pipePos - 3))  ' pipePos is 0-based; add 1 vs naive formula
        result.ref = _stripLeadingColons(Mid(workStr, pipePos + 6))
    else
        result.ua = _stripLeadingColons(Mid(workStr, 4))
    end if
    if result.cookie <> "" then result.cookie = _stripLeadingColons(result.cookie)
    if result.tvgid  <> "" then result.tvgid  = _stripLeadingColons(result.tvgid)
    if result.logo   <> "" then result.logo   = _stripLeadingColons(result.logo)

    return result
end function

' Strips leading colons and spaces — e.g. ":https://..." → "https://..."
' Some M3U sources write "#EXTVLCOPT:http-referrer=:https://..." by mistake.
function _stripLeadingColons(s as String) as String
    if s = "" or s = invalid then return ""
    i = 1
    while i <= Len(s)
        c = Mid(s, i, 1)
        if c = ":" or c = " " then
            i = i + 1
        else
            exit while
        end if
    end while
    return Mid(s, i)
end function

function isValidUrl(url as String) as Boolean
    if url = "" then return false
    httpReg = CreateObject("roRegex", "^https?://", "i")
    if not httpReg.isMatch(url) then return false
    urlReg = CreateObject("roRegex", "^https?://[^\s/$.?#].[^\s]*$", "i")
    return urlReg.isMatch(url)
end function

function getFriendlyError(errorMsg as String) as String
    if errorMsg = invalid or errorMsg = "" then
        return "The stream could not be loaded. The channel may be offline or the URL may be invalid."
    end if
    msg = LCase(errorMsg)
    if msg.InStr("404") >= 0 or msg.InStr("not found") >= 0 then
        return "Stream not found (404). The channel URL may be incorrect or the stream has moved."
    else if msg.InStr("403") >= 0 or msg.InStr("forbidden") >= 0 then
        return "Access denied (403). This stream may be geo-restricted or require authentication."
    else if msg.InStr("401") >= 0 or msg.InStr("unauthorized") >= 0 then
        return "Unauthorized (401). This stream requires a login or subscription."
    else if msg.InStr("500") >= 0 or msg.InStr("server error") >= 0 then
        return "Server error (500). The streaming server is having problems. Try again later."
    else if msg.InStr("timeout") >= 0 or msg.InStr("timed out") >= 0 then
        return "Connection timed out. The stream is taking too long to respond. Check your network."
    else if msg.InStr("network") >= 0 or msg.InStr("connect") >= 0 then
        return "Network error. Check your internet connection and try again."
    else if msg.InStr("drm") >= 0 or msg.InStr("license") >= 0 then
        return "DRM / copy protection error. This stream uses a protection scheme that is not supported."
    else if msg.InStr("format") >= 0 or msg.InStr("codec") >= 0 or msg.InStr("unsupported") >= 0 then
        return "Unsupported format. This stream uses a codec or container that cannot be played."
    else if msg.InStr("empty") >= 0 or msg.InStr("no data") >= 0 then
        return "Empty stream. The channel URL returned no playable content."
    else if msg.InStr("ssl") >= 0 or msg.InStr("certificate") >= 0 then
        return "SSL / certificate error. There was a problem with the stream's security certificate."
    else if msg.InStr("dns") >= 0 or msg.InStr("resolve") >= 0 then
        return "DNS error. The stream's server address could not be found. Check your network."
    end if
    return "Playback error: " + errorMsg
end function

' Returns the channel AA at m.loadingChannelIndex, or invalid if out of bounds.
' Replaces the repeated boilerplate:
'   channel = invalid
'   if m.flatChannelList <> invalid and m.loadingChannelIndex >= 0 ...
'       channel = m.flatChannelList[m.loadingChannelIndex]
function _currentChannel() as Dynamic
    if m.flatChannelList = invalid then return invalid
    if m.loadingChannelIndex < 0 then return invalid
    if m.loadingChannelIndex >= m.flatChannelList.Count() then return invalid
    return m.flatChannelList[m.loadingChannelIndex]
end function

' Returns the logo URL for a channel, or "" if none.
function _channelLogoUrl(channel as Object) as String
    if channel = invalid then return ""
    parsed = parseChannelDescription(channel.description)
    if parsed <> invalid and parsed.logo <> "" then return parsed.logo
    return ""
end function

' ---------- Playlist-switch channel continuity ("Now Playing" pin) ----------
' m.currentChannelIndex is an index into m.flatChannelList, which is rebuilt
' from scratch every time a playlist loads. If a channel is actively playing
' when the user picks a different playlist (or reloads the current one) from
' the side panel, that index becomes meaningless the moment the new list is
' built.
'
' _resyncOrPinChannelAfterPlaylistSwitch() (called from SetContent(), AFTER
' the new playlist's normal buildFlatChannelList() pass) handles this two ways:
'   - If the same channel/URL is already naturally present in the new
'     playlist (e.g. it happens to exist in both), just point
'     currentChannelIndex at that existing entry. No duplicate row, so no
'     risk of the same channel showing up starred twice.
'   - Otherwise, pin a copy of it under a real "Now Playing" SECTION node
'     APPENDED at the very END of the grid (last child, not first). It MUST
'     carry contenttype="SECTION" (and an id) exactly like every real
'     category node does (see buildSortedChannelTree() in PlaylistSort.brs)
'     -- LabelList uses that field, not "has children", to tell a section
'     header apart from a plain leaf row.
'
'     It goes at the END specifically so it can later be removed cleanly:
'     removing/inserting at the FRONT shifts every other index down/up by
'     one, and several callers (changeChannel()'s surf-dwell capture,
'     checkState()'s playingPreviewIndex/loadingChannelIndex bookkeeping in
'     ChannelNav.brs) grab an index before calling into
'     playChannel()/playPreviewChannel() and use it after -- an earlier
'     front-inserted version of this corrupted m.previousChannelIndex and
'     broke the flashback/replay button. Appending at the tail means
'     removing it later only invalidates indices that were already pointing
'     AT it (which safely no-op via the existing ">= Count()" guards
'     elsewhere) and leaves every other index's meaning completely
'     unaffected.
' Once pinned, m.currentChannelIndex points at a real channel node with real
' title/url/description/logo -- so the channel bar, preview name/logo, and
' favorite toggle all keep working completely unchanged, with no fallback
' special-casing needed anywhere else.
'
' The pin is removed outright the instant the user actually tunes to a
' DIFFERENT channel -- see _clearNowPlayingPinIfChanging(), called from
' playChannel()/playPreviewChannel() in VideoCore.brs -- so nothing from the
' previous playlist lingers once you've moved on.

' Captures the channel to carry over BEFORE a playlist switch. Deliberately
' prefers m.loadingChannelIndex (the channel currently being tuned to, set
' the instant a load starts) over m.playingPreviewIndex (the last one that
' actually reached "playing"), over m.currentChannelIndex. If the user just
' changed channel and it's still buffering when the playlist switch happens,
' playingPreviewIndex is still the PREVIOUS channel — checkState() hasn't
' fired "playing" for the new one yet — so preferring it would capture the
' wrong (stale, already-left) channel instead of the one actually being
' tuned to. loadingChannelIndex is also preferred over currentChannelIndex
' for a related but separate reason -- while browsing the grid (not
' fullscreen), m.currentChannelIndex also doubles as the grid CURSOR
' position (onChannelFocused() in ChannelSelection.brs updates it on every
' highlight move), which can differ from what's actually loading/playing in
' the preview window if the user moved the highlight after selecting a
' channel without picking a new one. Capturing the cursor position instead
' of what's really playing showed the wrong channel (or no pin at all, if
' the highlighted channel happened to exist in the destination playlist)
' after switching back. GridInput.brs already has to re-sync
' currentChannelIndex from playingPreviewIndex for the same reason in a
' couple of places.
sub _captureChannelBeforePlaylistSwitch()
    m.channelBeforePlaylistSwitch = invalid
    idx = m.loadingChannelIndex
    if idx = invalid or idx < 0 then idx = m.playingPreviewIndex
    if idx = invalid or idx < 0 then idx = m.currentChannelIndex   ' nothing loaded/confirmed yet -- best guess
    if m.flatChannelList <> invalid and idx >= 0 and idx < m.flatChannelList.Count() then
        channel = m.flatChannelList[idx]
        if channel <> invalid and channel.url <> invalid and channel.url <> "" then
            m.channelBeforePlaylistSwitch = channel
        end if
    end if
end sub

' Called from SetContent() right after the new playlist's own
' buildFlatChannelList() pass. Returns the grid index the channel list
' should jump to (0 if there's nothing special to restore). Always consumes
' (clears) m.channelBeforePlaylistSwitch, and always resets any stale pin
' bookkeeping left over from a previous load first.
'
' Also re-points m.playingPreviewIndex and m.loadingChannelIndex at the same
' resolved index, not just m.currentChannelIndex -- GridInput.brs uses
' playingPreviewIndex to re-correct currentChannelIndex back to "what's
' actually playing" when you press back/right on the grid (see the comment
' on _captureChannelBeforePlaylistSwitch() above for why that variable
' exists). Left stale after a switch, it points at some unrelated channel in
' the new list and clobbers the very index we just fixed the moment the user
' presses one of those keys.
function _resyncOrPinChannelAfterPlaylistSwitch() as Integer
    m.pinnedNowPlayingUrl      = invalid
    m.pinnedNowPlayingNode     = invalid
    m.replayFallbackActive = false   ' fresh playlist -- start the replay toggle clean

    channel = m.channelBeforePlaylistSwitch
    m.channelBeforePlaylistSwitch = invalid
    if channel = invalid or channel.url = invalid or channel.url = "" then return 0

    ' Already naturally in the new playlist -- just point at it, no pin needed.
    existingIdx = findChannelIndexByUrl(channel.url)
    if existingIdx >= 0 then
        m.currentChannelIndex  = existingIdx
        m.previousChannelIndex = -1
        m.playingPreviewIndex  = existingIdx
        m.loadingChannelIndex  = existingIdx
        print ">>> NAV: Playlist switch -- "; channel.url; " already present in new playlist at "; existingIdx
        return existingIdx
    end if

    if m.allChannels = invalid then return 0

    pinIdx = _pinChannelAsNowPlaying(channel)
    m.previousChannelIndex = -1
    print ">>> NAV: Playlist switch -- pinned now-playing channel under a Now Playing section at tail index "; pinIdx; " ("; channel.url; ")"
    return pinIdx
end function

' Pins `channel` as a "Now Playing" tail section in m.allChannels/
' m.flatChannelList when it isn't naturally present there, pointing all the
' "what's currently playing" index bookkeeping at it (currentChannelIndex,
' playingPreviewIndex, loadingChannelIndex — see the comment on
' _resyncOrPinChannelAfterPlaylistSwitch() above for why those three all need
' to agree). Shared by that playlist-switch resync and by hiding the
' currently-playing channel (toggleHideForCurrentChannel() in
' HiddenChannels.brs) — same underlying problem: a channel that needs to
' keep playing/surfing correctly even though it just dropped out of the
' displayed tree. Cleared later by _clearNowPlayingPinIfChanging() once the
' user tunes away. Returns the new pin index, or -1 if there's nothing to pin.
function _pinChannelAsNowPlaying(channel as Object) as Integer
    if m.allChannels = invalid or channel = invalid or channel.url = invalid or channel.url = "" then return -1

    pinSection             = CreateObject("roSGNode", "ContentNode")
    pinSection.contenttype = "SECTION"
    pinSection.title       = "Now Playing"
    pinSection.id          = "now_playing_pin"
    pin                    = pinSection.CreateChild("ContentNode")
    pin.title              = channel.title
    pin.url                = channel.url
    if channel.description <> invalid then pin.description = channel.description
    if channel.baseTitle   <> invalid then pin.baseTitle   = channel.baseTitle
    if channel.group       <> invalid then pin.group       = channel.group
    m.allChannels.AppendChild(pinSection)   ' tail, not front -- see comment above
    buildFlatChannelList()                  ' rebuild so the pin (now last) is included

    m.pinnedNowPlayingUrl  = channel.url
    m.pinnedNowPlayingNode = pinSection
    pinIdx                 = m.flatChannelList.Count() - 1
    m.currentChannelIndex  = pinIdx
    m.playingPreviewIndex  = pinIdx
    m.loadingChannelIndex  = pinIdx
    return pinIdx
end function

' Called once the user has actually tuned away from the pinned channel.
' Because the pin sits at the TAIL of the list (see comment above), removing
' it only invalidates indices that were pointing AT it -- which safely no-op
' via the existing ">= Count()" guards in jumpToPreviousChannel()/
' GridInput.brs/ChannelBar.brs etc -- rather than shifting every other
' index's meaning the way a front-removal did. No-op if there's no pin, or
' if newUrl IS the pin (re-selecting what's already playing isn't a change).
sub _clearNowPlayingPinIfChanging(newUrl as String)
    if m.pinnedNowPlayingUrl = invalid then return
    if newUrl = m.pinnedNowPlayingUrl then return

    ' Capture what's focused now (the channel the user just clicked) before
    ' touching anything -- the pin sat at the TAIL, so removing it doesn't
    ' shift anything before it, and this index is still correct once the
    ' list is rebuilt.
    focusedBefore = -1
    if m.channelList <> invalid then focusedBefore = m.channelList.itemFocused

    if m.allChannels <> invalid and m.pinnedNowPlayingNode <> invalid then
        m.allChannels.removeChild(m.pinnedNowPlayingNode)
    end if
    m.pinnedNowPlayingUrl  = invalid
    m.pinnedNowPlayingNode = invalid
    buildFlatChannelList()

    if m.channelList <> invalid then
        ' Reassigning .content resets a LabelList's focus/scroll to the top.
        ' jumpToItem alone right after wasn't reliable on-device -- setting
        ' content to invalid first, then back, then setting BOTH
        ' itemFocused and jumpToItem is the same repaint-while-preserving-
        ' focus pattern _bounceListContent() already uses elsewhere in this
        ' codebase (see Favorites.brs).
        m.channelList.content = invalid
        m.channelList.content = m.allChannels
        if focusedBefore >= 0 and m.flatChannelList <> invalid and focusedBefore < m.flatChannelList.Count() then
            m.channelList.itemFocused = focusedBefore
            m.channelList.jumpToItem  = focusedBefore
        end if
    end if
    print ">>> NAV: Now-playing pin removed -- tuning to a different channel"
end sub

' Starts the LocalProxy task for a session-token or HLS-v7+ stream.
' Waits for any previous proxy thread to release port 7171 first.
' Called from RetryLadder (cache fast-path) and ManifestCallbacks (patcher result).
sub _startLocalProxy(masterUrl as String, pendingContent as Object)
    if masterUrl = invalid or masterUrl = "" then
        print ">>> PROXY: ERROR -- _startLocalProxy called with empty masterUrl"
        return
    end if
    ' Set a content node on the Video node with the channel URL so that
    ' retryStream() has a valid base URL if the proxy fails before playing.
    ' Without this, previewVideo.content is stale (previous channel) and
    ' cleanUrl resolution would use the wrong URL.
    if m.previewVideo <> invalid and pendingContent <> invalid then
        m.previewVideo.content = pendingContent
    end if
    if m.localProxy = invalid then
        print ">>> PROXY: ERROR -- localProxy node is invalid"
        return
    end if
    ' Wait for any previous proxy thread to release port 7171
    if m.localProxy.status <> "idle" and m.localProxy.status <> "stopped" and Left(m.localProxy.status, 6) <> "error:" then
        print ">>> PROXY: Waiting for previous proxy to stop..."
        waitCount = 0
        while m.localProxy.status <> "stopped" and Left(m.localProxy.status, 6) <> "error:" and waitCount < 20
            sleep(100)
            waitCount = waitCount + 1
        end while
        print ">>> PROXY: Previous proxy done ("; m.localProxy.status; " after "; waitCount * 100; "ms)"
    end if
    m.pendingProxyContent    = pendingContent
    channel                  = _currentChannel()
    headers                  = _resolveHeaders(channel)
    m.localProxy.stopProxy   = false
    m.localProxy.masterUrl   = masterUrl
    m.localProxy.userAgent   = headers.ua
    m.localProxy.referrer    = headers.ref
    m.localProxy.cookie      = headers.cookie
    m.localProxy.control     = "RUN"
    print ">>> PROXY: Started -- masterUrl="; Left(masterUrl, 60)
    print ">>> PROXY: UA="; headers.ua
end sub


' Returns the URL of the channel currently being loaded (m.loadingChannelIndex),
' or "" if none. Used to detect stale state callbacks from abandoned channels.
' For proxy channels, returns m.proxyOriginalUrl (the original stream URL)
' since previewVideo.content.url is the proxy URL http://IP:7171/master.
function _currentLoadingChannelUrl() as String
    if m.flatChannelList = invalid then return ""
    if m.loadingChannelIndex < 0 or m.loadingChannelIndex >= m.flatChannelList.Count() then return ""
    ch = m.flatChannelList[m.loadingChannelIndex]
    if ch = invalid or ch.url = invalid then return ""
    if m.proxyOriginalUrl <> "" then return m.proxyOriginalUrl
    return ch.url
end function
