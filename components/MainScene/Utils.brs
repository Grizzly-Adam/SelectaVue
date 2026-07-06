' ==================== Utils.brs ====================
' Pure helper functions and constants with no side-effects.
' Safe to call from any other main-scene module.
'
' NOTE: iif() also has a private copy in ManifestPatcher.brs because
' that file runs in a separate Task node and cannot share this scope.

' Returns the number of built-in (non-deletable) playlists.
' Defined as a function rather than a file-scope variable because BrightScript
' SceneGraph components do not support file-scope variable assignments.
' UPDATE the return value if you add or remove built-in playlists.
function BUILTIN_PLAYLIST_COUNT() as Integer
    return 7
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

' Starts the LocalProxy task for a session-token or HLS-v7+ stream.
' Waits for any previous proxy thread to release port 7171 first.
' Called from RetryLadder (cache fast-path) and ManifestCallbacks (patcher result).
sub _startLocalProxy(masterUrl as String, pendingContent as Object)
    if masterUrl = invalid or masterUrl = "" then
        print ">>> PROXY: ERROR -- _startLocalProxy called with empty masterUrl"
        return
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

' ==================== Icon Helpers ====================

' Wraps an image URL through images.weserv.nl at w=400 for reliable loading.
' Only applies to http/https URLs; pkg: and other local schemes pass through.
' Strips the scheme prefix that weserv requires (it adds its own https://).
function _resizedIconUrl(url as String) as String
    if url = invalid or url = "" then return url
    lurl = LCase(url)
    if Left(lurl, 7) = "http://" then
        ' weserv needs the URL without scheme
        return "https://images.weserv.nl/?url=" + Mid(url, 8) + "&w=400"
    else if Left(lurl, 8) = "https://" then
        return "https://images.weserv.nl/?url=" + Mid(url, 9) + "&w=400"
    end if
    return url  ' pkg:, tmp:, etc. pass through unchanged
end function

' Returns the best icon URL for a channel:
'   1. Channel's own tvg-logo (resized through weserv)
'   2. Category icon matched from channel group name
'   3. General fallback icon
function _bestIconUrl(channel as Object) as String
    ' Try the channel's own logo first
    logoUrl = _channelLogoUrl(channel)
    if logoUrl <> "" then return _resizedIconUrl(logoUrl)

    ' Fall back to category icon based on group name
    return _categoryIconUrl(channel)
end function

' Maps a channel's group name to a category icon pkg: path.
' Falls back to general icon if no match.
function _categoryIconUrl(channel as Object) as String
    group = ""
    if channel <> invalid and channel.group <> invalid then
        group = LCase(channel.group)
    end if

    ' Category keyword matching (order matters -- more specific first)
    if group.InStr("anime") >= 0 then
        return "pkg:/images/icon_anime.svg"
    else if group.InStr("cartoon") >= 0 or group.InStr("animation") >= 0 then
        return "pkg:/images/icon_cartoons.svg"
    else if group.InStr("kids") >= 0 or group.InStr("children") >= 0 or group.InStr("family") >= 0 then
        return "pkg:/images/icon_kids.svg"
    else if group.InStr("comedy") >= 0 or group.InStr("humor") >= 0 or group.InStr("funny") >= 0 then
        return "pkg:/images/icon_comedy.svg"
    else if group.InStr("sitcom") >= 0 then
        return "pkg:/images/icon_sitcoms.svg"
    else if group.InStr("sport") >= 0 or group.InStr("football") >= 0 or group.InStr("soccer") >= 0 or group.InStr("cricket") >= 0 or group.InStr("basketball") >= 0 or group.InStr("baseball") >= 0 then
        return "pkg:/images/icon_sports.svg"
    else if group.InStr("weather") >= 0 or group.InStr("climate") >= 0 then
        return "pkg:/images/icon_weather.svg"
    else if group.InStr("edu") >= 0 or group.InStr("learn") >= 0 or group.InStr("school") >= 0 or group.InStr("document") >= 0 or group.InStr("science") >= 0 or group.InStr("history") >= 0 then
        return "pkg:/images/icon_educational.svg"
    else if group.InStr("network") >= 0 or group.InStr("broadcast") >= 0 or group.InStr("news") >= 0 or group.InStr("general") >= 0 then
        return "pkg:/images/icon_network.svg"
    end if

    ' General fallback
    return "pkg:/images/icon_general.svg"
end function

' Called when the channel bar logo Poster finishes loading.
' If the image failed (broken URL, network error), fall back to the category icon.
sub onChannelBarLogoStatus()
    if m.channelBarLogo = invalid then return
    status = m.channelBarLogo.loadStatus
    if status = "failed" then
        channel = _currentChannel()
        fallback = _categoryIconUrl(channel)
        print ">>> ICON: channelBarLogo failed, falling back to "; fallback
        m.channelBarLogo.uri = fallback
    end if
end sub

' Called when the preview logo Poster finishes loading.
' If the image failed, fall back to the category icon.
sub onPreviewLogoStatus()
    if m.previewChannelLogo = invalid then return
    status = m.previewChannelLogo.loadStatus
    if status = "failed" then
        channel = _currentChannel()
        fallback = _categoryIconUrl(channel)
        print ">>> ICON: previewChannelLogo failed, falling back to "; fallback
        m.previewChannelLogo.uri = fallback
    end if
end sub
