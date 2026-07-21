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
' themed=true applies the same teal color scheme used by the retry ladder
' overlay (reconnectOverlay in MainScene.xml: ACCENT_TEAL border/text,
' ACCENT_TEAL_DARK-ish fill) via dialog_bg_teal.9.png and
' dialog_btn_focus_teal.9.png. Only opt-in callers are affected; existing
' calls with the default (false) keep the stock Roku Dialog look.
function _showSimpleDialog(title as String, message as String, buttons as Object, buttonCallback = "" as String, themed = false as Boolean) as Object
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = title
    if message <> "" then dialog.message = message
    dialog.buttons = buttons
    if themed then
        dialog.backgroundUri = "pkg:/images/dialog_bg_teal.9.png"
        dialog.titleColor = ACCENT_TEAL()
        dialog.messageColor = "0xE8F5F3FF"
        ' Match the retry ladder's CANCEL/RETRY label, which stays the same
        ' teal regardless of focus state (it's a static label, not a real
        ' focused/unfocused Button) -- so keep our text color constant too.
        dialog.buttonGroup.textColor = ACCENT_TEAL()
        dialog.buttonGroup.focusedTextColor = ACCENT_TEAL()
        dialog.buttonGroup.focusBitmapUri = "pkg:/images/dialog_btn_focus_teal.9.png"
        if buttons <> invalid and buttons.Count() = 1 then
            ' Single-button (OK-only) dialogs: show the same teal highlight
            ' as the "footprint" (pre-focus) look, so the button reads as
            ' selected immediately on open instead of only after the user
            ' arrows onto it -- there's nothing else to navigate to anyway.
            ' Skipped for multi-button menus (playlist options, etc.) since
            ' forcing every button to look focused at once would defeat the
            ' point of showing which one is actually selected.
            dialog.buttonGroup.focusFootprintBitmapUri = "pkg:/images/dialog_btn_focus_teal.9.png"
            for each btn in dialog.buttonGroup.getChildren(-1, 0)
                btn.showFocusFootprint = true
                btn.iconUri = ""
                btn.focusedIconUri = ""
            end for
        else
            ' Multi-button menus still get the leading bullet/icon cleared,
            ' just not the always-on footprint highlight.
            for each btn in dialog.buttonGroup.getChildren(-1, 0)
                btn.iconUri = ""
                btn.focusedIconUri = ""
            end for
        end if
    end if
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

' ---------- ThemedMessageDialog helper (title + message + 1-2 buttons) ----------
' Replaces _showSimpleDialog for Name/URL Required errors and channel info,
' where the stock Dialog's native title-divider didn't match this app's
' theme -- see ThemedMessageDialog.xml's header comment.
function _showThemedMessageDialog(title as String, message as String, buttons as Object, buttonCallback = "" as String, width = 700 as Float, height = 280 as Float, messageAlign = "center" as String) as Object
    dialog = m.themedMessageDialog
    if dialog = invalid then return invalid
    dialog.dialogTitle  = title
    dialog.message      = message
    dialog.buttons      = buttons
    dialog.dialogWidth  = width
    dialog.dialogHeight = height
    dialog.messageAlign = messageAlign
    if buttonCallback <> "" then dialog.observeField("buttonSelected", buttonCallback)
    dialog.show = true
    return dialog
end function

sub _closeThemedMessageDialog()
    if m.themedMessageDialog <> invalid then
        m.themedMessageDialog.unobserveField("buttonSelected")
        m.themedMessageDialog.show = false
    end if
end sub

' ---------- ThemedMenuDialog helper (title + vertical button list) ----------
' Replaces _showSimpleDialog's buttons array for the playlist options menu.
' Panel height is computed by the component itself from the button count.
function _showThemedMenuDialog(title as String, buttons as Object, buttonCallback = "" as String, width = 640 as Float) as Object
    dialog = m.themedMenuDialog
    if dialog = invalid then return invalid
    dialog.dialogTitle = title
    dialog.buttons     = buttons
    dialog.dialogWidth = width
    if buttonCallback <> "" then dialog.observeField("buttonSelected", buttonCallback)
    dialog.show = true
    return dialog
end function

sub _closeThemedMenuDialog()
    if m.themedMenuDialog <> invalid then
        m.themedMenuDialog.unobserveField("buttonSelected")
        m.themedMenuDialog.show = false
    end if
end sub

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

' ---------- Diagnostic timing (buffer-stall investigation) ----------
' Milliseconds since m.channelLoadTimer was started (playChannel()'s fresh-load
' branch, and reloadCurrentChannel()) -- NOT reset per retry-ladder step, so
' every BUFFER/STALL/RETRY/SOFT STEP-DOWN print's timestamp is on one shared
' timeline for the whole load+retry sequence. Lets us read off real elapsed
' durations between log lines instead of guessing from timer configs. Returns
' -1 if no load is in progress (timer never started, or print is stale).
function _loadElapsedMs() as Integer
    if m.channelLoadTimer = invalid then return -1
    return m.channelLoadTimer.TotalMilliseconds()
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

    ' Stalker/Ministra portal play.php?...&extension=ts&... (the mac=-address-based
    ' "line" portals MAG boxes use) -- extension=ts here is a query parameter value
    ' signaling a raw continuous MPEG-TS response, not a ".ts" file extension on the
    ' path (that's live.php, so none of the .EndsWith() checks above ever catch it).
    ' Forcing "hls" on this made Roku's strict HLS demuxer choke trying to parse a
    ' raw TS stream as HLS-segmented content -- errorCode=-3 "reader pick stream
    ' error:bad:parsing failed" -- while VLC played the same URL fine since it
    ' auto-detects content type from the byte stream rather than assuming from the URL.
    if url.InStr("extension=ts") > 0 then return "ts"

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

    ' The short errorMsg Roku hands us here (e.g. "malformed data") doesn't
    ' carry the actual decoder detail -- that only shows up in errorStr
    ' (e.g. "decoder:pump:Unsupported AAC stream."), saved separately as
    ' m.savedErrorStr alongside m.savedErrorMsg in ChannelNav.brs. Check both
    ' so a genuine hardware-decoder rejection gets its own clear message
    ' instead of falling through to the generic "format/codec" case below or,
    ' worse, the raw "Playback error: malformed data" fallback.
    detail = ""
    if m.savedErrorStr <> invalid then detail = LCase(m.savedErrorStr)
    if detail.InStr("unsupported aac") >= 0 or (detail.InStr("decoder") >= 0 and detail.InStr("aac") >= 0) then
        return "Audio format not supported by this device. Ask the provider for a plain AAC audio version, or try a different Roku model."
    end if

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

' ---------- Channel continuity across a tree rebuild ("Now Playing" pin) ----------
' A tree rebuild (playlist switch, Favorites/Hidden view toggle, hide/unhide)
' can leave m.currentChannelIndex pointing at the wrong channel. Fix:
' _resyncOrPinCurrentChannel() either re-points the index at the same
' channel if it's still in the new tree, or pins a copy under a "Now
' Playing" SECTION node appended at the END of the grid (must be appended,
' not prepended -- prepending shifts every other index and broke replay/
' flashback). Removed once the user tunes to a different channel -- see
' _clearNowPlayingPinIfChanging() in VideoCore.brs.

' Captures whichever channel is actually playing/loading right now, BEFORE
' the tree gets rebuilt for any reason (playlist switch/reload, entering or
' leaving Favorites/Hidden Channels, a hide/unhide toggle). Deliberately
' prefers m.loadingChannelIndex (the channel currently being tuned to, set
' the instant a load starts) over m.playingPreviewIndex (the last one that
' actually reached "playing"), over m.currentChannelIndex. If the user just
' changed channel and it's still buffering when the rebuild happens,
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
' the highlighted channel happened to exist in the destination tree) after
' rebuilding. GridInput.brs already has to re-sync currentChannelIndex from
' playingPreviewIndex for the same reason in a couple of places.
sub _captureCurrentlyPlayingChannel()
    m.channelBeforeRebuild = invalid
    idx = m.loadingChannelIndex
    if idx = invalid or idx < 0 then idx = m.playingPreviewIndex
    if idx = invalid or idx < 0 then idx = m.currentChannelIndex   ' nothing loaded/confirmed yet -- best guess
    if m.flatChannelList <> invalid and idx >= 0 and idx < m.flatChannelList.Count() then
        channel = m.flatChannelList[idx]
        if channel <> invalid and channel.url <> invalid and channel.url <> "" then
            m.channelBeforeRebuild = channel
        end if
    end if
end sub

' Called right after a fresh buildFlatChannelList() pass, whatever triggered
' the rebuild. Returns the grid index the channel list should jump to (0 if
' there's nothing special to restore). Always consumes (clears)
' m.channelBeforeRebuild, and always resets any stale pin bookkeeping left
' over from a previous rebuild first.
'
' Also re-points playingPreviewIndex/loadingChannelIndex at the same index,
' not just currentChannelIndex -- GridInput.brs uses playingPreviewIndex to
' re-correct focus back to "what's actually playing", so a stale value there
' would clobber the fix the moment the user presses back/right.
function _resyncOrPinCurrentChannel() as Integer
    m.pinnedNowPlayingUrl      = invalid
    m.pinnedNowPlayingNode     = invalid
    m.replayFallbackActive = false   ' fresh tree -- start the replay toggle clean

    channel = m.channelBeforeRebuild
    m.channelBeforeRebuild = invalid
    if channel = invalid or channel.url = invalid or channel.url = "" then return 0

    ' Already naturally in the new tree -- just point at it, no pin needed.
    existingIdx = findChannelIndexByUrl(channel.url)
    if existingIdx >= 0 then
        m.currentChannelIndex  = existingIdx
        m.previousChannelIndex = -1
        m.playingPreviewIndex  = existingIdx
        m.loadingChannelIndex  = existingIdx
        print ">>> NAV: Tree rebuild -- "; channel.url; " already present at "; existingIdx
        return existingIdx
    end if

    if m.allChannels = invalid then return 0

    pinIdx = _pinChannelAsNowPlaying(channel)
    m.previousChannelIndex = -1
    print ">>> NAV: Tree rebuild -- pinned now-playing channel under a Now Playing section at tail index "; pinIdx; " ("; channel.url; ")"
    return pinIdx
end function

' Pins `channel` as a "Now Playing" tail section when it isn't naturally in
' the tree, pointing currentChannelIndex/playingPreviewIndex/loadingChannelIndex
' all at it. Shared by playlist-switch resync and hiding the playing channel
' (HiddenChannels.brs). Cleared by _clearNowPlayingPinIfChanging() once the
' user tunes away. Returns the new pin index, or -1 if nothing to pin.
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

' Called once the user tunes away from the pinned channel. The pin sits at
' the TAIL, so removing it only invalidates indices pointing AT it (safe
' no-ops via existing ">= Count()" guards) rather than shifting others.
' No-op if there's no pin, or newUrl IS the pin.
sub _clearNowPlayingPinIfChanging(newUrl as String)
    if m.pinnedNowPlayingUrl = invalid then return
    if newUrl = m.pinnedNowPlayingUrl then return

    ' Capture current focus before removing the tail pin -- still correct after rebuild.
    focusedBefore = -1
    if m.channelList <> invalid then focusedBefore = m.channelList.itemFocused

    if m.allChannels <> invalid and m.pinnedNowPlayingNode <> invalid then
        m.allChannels.removeChild(m.pinnedNowPlayingNode)
    end if
    m.pinnedNowPlayingUrl  = invalid
    m.pinnedNowPlayingNode = invalid
    buildFlatChannelList()

    if m.channelList <> invalid then
        ' Reassigning .content resets scroll/focus -- bounce content then
        ' restore focus, same pattern as _bounceListContent() (Favorites.brs).
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

' Strips RetryLadder's &_HLS_skip=NO suffix and resolves a proxy session URL
' back to the original channel URL. Used both for the clean retry base and
' for staleness comparisons -- without normalizing both sides the same way,
' a genuine error from the compat step or an active proxy session would
' never match and get wrongly discarded as belonging to an abandoned channel.
function _normalizeChannelUrl(url as String) as String
    cleanUrl = url
    if m.proxyOriginalUrl <> "" and Left(LCase(cleanUrl), 7) = "http://" and cleanUrl.InStr(":7171/") >= 0 then
        cleanUrl = m.proxyOriginalUrl
    end if
    sepPos = cleanUrl.InStr("&_HLS_skip")
    if sepPos > 0 then cleanUrl = Left(cleanUrl, sepPos)
    sepPos = cleanUrl.InStr("?_HLS_skip")
    if sepPos > 0 then cleanUrl = Left(cleanUrl, sepPos)
    return cleanUrl
end function
