' ==================== SettingsCache.brs ====================
' Per-channel stream settings cache.
'
' Two layers:
'   Session cache  (m.sessionSettingsCache)  - in-memory, lost on exit, up to 50 entries
'   Persistent cache (m.persistentSettingsCache) - registry-backed, survives restarts, up to 50 entries
'
' Write rules:
'   - On successful play: check persistent cache first.
'     * If URL already in persistent cache: update it immediately (already earned its place).
'     * If not: add to session cache immediately, start 2-minute timer.
'       On timer fire: move entry from session to persistent registry.
'   - Session cache entry is removed once promoted to persistent.
'
' Read rules (retry step 0):
'   1. Persistent cache (keyed by URL)
'   2. Session cache (keyed by URL)
'   3. m.lastWorkingContent (current-session last-known-good)
'   4. Fall through to retry ladder step 1
'
' 2.0 note: favorites tier plugs in here as a protected persistent pool.

' Maximum entries in each cache layer
function SETTINGS_CACHE_MAX() as Integer
    return 50
end function

' Registry section name
function SETTINGS_CACHE_REG_SECTION() as String
    return "settingsCache"
end function

' ---------- Initialization ----------

sub initSettingsCache()
    m.sessionSettingsCache    = {}
    m.sessionCacheOrder       = []   ' tracks insertion order for LRU eviction
    m.persistentSettingsCache = {}
    m.persistentCacheOrder    = []
    m.settingsCacheTimer      = invalid
    m.pendingCacheUrl         = invalid   ' URL waiting for 2-minute promotion

    ' Load persistent cache from registry
    reg = CreateObject("roRegistrySection", SETTINGS_CACHE_REG_SECTION())
    if reg.Exists("data") then
        jsonStr = reg.Read("data")
        if jsonStr <> invalid and jsonStr <> "" then
            parsed = ParseJSON(jsonStr)
            if parsed <> invalid then
                if parsed.order <> invalid then m.persistentCacheOrder = parsed.order
                if parsed.entries <> invalid then
                    for each url in m.persistentCacheOrder
                        if parsed.entries.DoesExist(url) then
                            m.persistentSettingsCache[url] = parsed.entries[url]
                        end if
                    end for
                end if
            end if
        end if
    end if
    print ">>> CACHE: Loaded "; m.persistentCacheOrder.Count(); " persistent entries"
end sub

' ---------- On successful play ----------

sub onChannelPlayingSuccessfully(url as String, content as Object)
    if url = "" or url = invalid then return
    if content = invalid then return

    channel  = _currentChannel()
    cacheKey = url
    isProxy  = false

    if channel <> invalid and channel.url <> invalid then
        isProxy    = (Left(url, 7) = "http://" and url.InStr(":7171/") >= 0)
        isModified = (url.InStr("_HLS_skip") >= 0)
        if isProxy or isModified then
            cacheKey = channel.url
            print ">>> CACHE: Mapping play URL to channel URL for cache key: "; cacheKey
        end if
    end if

    entry = _buildCacheEntry(content)

    ' For proxy channels: fix the entry URL (it's the proxy URL, not the
    ' original stream URL) and force useProxy=true. Without this, the cached
    ' entry plays http://IP:7171/master directly next time without starting
    ' the proxy — stalling immediately.
    if isProxy then
        entry.url      = cacheKey   ' original channel URL, not proxy URL
        entry.useProxy = true
        print ">>> CACHE: Proxy channel — storing original URL with useProxy=true"
    else
        ' Non-proxy: preserve useProxy flag if it was set by a prior proxy play.
        ' Check both session and persistent caches since the flag may be in either.
        existing = invalid
        if m.persistentSettingsCache.DoesExist(cacheKey) then
            existing = m.persistentSettingsCache[cacheKey]
        else if m.sessionSettingsCache.DoesExist(cacheKey) then
            existing = m.sessionSettingsCache[cacheKey]
        end if
        if existing <> invalid and existing.useProxy = true then
            entry.useProxy = true
        end if
    end if

    if m.persistentSettingsCache.DoesExist(cacheKey) then
        m.persistentSettingsCache[cacheKey] = entry
        m.pendingCacheUrl = cacheKey
        _startNamedTimer("settingsCacheTimer", 120.0, false, "onSettingsCacheTimerFired")
        print ">>> CACHE: Updated persistent entry for: "; cacheKey
        return
    end if

    _addToSessionCache(cacheKey, entry)
    m.pendingCacheUrl = cacheKey
    _startNamedTimer("settingsCacheTimer", 120.0, false, "onSettingsCacheTimerFired")
    print ">>> CACHE: Session entry added, 2-min timer started for: "; cacheKey
end sub

' Called when the 2-minute timer fires — promote session entry to persistent
sub onSettingsCacheTimerFired()
    m.settingsCacheTimer = invalid
    url = m.pendingCacheUrl
    m.pendingCacheUrl = invalid
    if url = invalid or url = "" then return

    ' If it was a session entry, promote it to persistent now
    if m.sessionSettingsCache.DoesExist(url) then
        entry = m.sessionSettingsCache[url]
        _addToPersistentCache(url, entry)
        m.sessionSettingsCache.Delete(url)
        _removeFromOrder(m.sessionCacheOrder, url)
        print ">>> CACHE: Promoted to persistent: "; url
    end if

    ' Either way, flush the persistent cache to registry now
    ' (deferred from onChannelPlayingSuccessfully to avoid render-thread I/O)
    _savePersistentCache()
end sub

' ---------- Lookup ----------

' Returns a cache entry AA or invalid if not found.
' Checks persistent first, then session.
' Also fixes stale entries where url=http://IP:7171/... was incorrectly stored
' by pre-fix sessions — forces useProxy=true and restores the correct URL.
function lookupCachedSettings(url as String) as Object
    if url = "" or url = invalid then return invalid

    entry = invalid
    if m.persistentSettingsCache.DoesExist(url) then
        print ">>> CACHE HIT (persistent): "; url
        entry = m.persistentSettingsCache[url]
    else if m.sessionSettingsCache.DoesExist(url) then
        print ">>> CACHE HIT (session): "; url
        entry = m.sessionSettingsCache[url]
    end if

    if entry = invalid then return invalid

    ' Fix stale proxy URL entries: pre-fix sessions stored http://IP:7171/master
    ' as the content URL with useProxy=false. Playing this URL without the proxy
    ' running stalls immediately. Detect and fix on the way out of the cache.
    if entry.url <> invalid then
        lUrl = LCase(entry.url)
        if Left(lUrl, 7) = "http://" and entry.url.InStr(":7171/") >= 0 then
            print ">>> CACHE: Fixed stale proxy URL entry — restoring useProxy=true"
            entry.useProxy = true
            entry.url      = url   ' restore the correct channel URL (the cache key)
            ' Update the stored entry so we don't have to fix it again next time
            if m.persistentSettingsCache.DoesExist(url) then
                m.persistentSettingsCache[url] = entry
            else if m.sessionSettingsCache.DoesExist(url) then
                m.sessionSettingsCache[url] = entry
            end if
        end if
    end if

    return entry
end function

' Build a ContentNode from a cache entry, preserving the channel's custom headers.
' channel object is passed so customUserAgent / customReferrer are still applied.
function buildContentFromCache(entry as Object, channel as Object) as Object
    if entry = invalid then return invalid
    c = _makeContentNode(entry.url, entry.title, channel)
    c.streamFormat      = entry.streamFormat
    c.SwitchingStrategy = entry.switchingStrategy
    if entry.maxBandwidth > 0 then c.MaxBandwidth = entry.maxBandwidth
    return c
end function

' ---------- Cancel timer ----------

sub cancelSettingsCacheTimer()
    _cancelNamedTimer("settingsCacheTimer")
    m.pendingCacheUrl = invalid
end sub

' ---------- Private helpers ----------

function _buildCacheEntry(content as Object) as Object
    return {
        url              : content.url,
        title            : iif(content.title <> invalid, content.title, ""),
        streamFormat     : iif(content.streamFormat <> invalid, content.streamFormat, "hls"),
        switchingStrategy: iif(content.SwitchingStrategy <> invalid, content.SwitchingStrategy, "full-adaptation"),
        maxBandwidth     : 0,   ' always 0 — let ABR decide on reload; never cache a throttled state
        useProxy         : iif(content.useProxy = true, true, false)
    }
end function

sub _addToSessionCache(url as String, entry as Object)
    ' Evict oldest if at capacity
    if m.sessionCacheOrder.Count() >= SETTINGS_CACHE_MAX() then
        oldest = m.sessionCacheOrder[0]
        m.sessionSettingsCache.Delete(oldest)
        m.sessionCacheOrder.Delete(0)
    end if
    m.sessionSettingsCache[url] = entry
    m.sessionCacheOrder.Push(url)
end sub

sub _addToPersistentCache(url as String, entry as Object)
    ' Evict oldest NON-FAVORITED entry if at capacity. Favorited channels are
    ' a protected tier — they're only ever overwritten by a newer successful
    ' load of that same URL (the m.persistentSettingsCache[url] = entry line
    ' below already handles that case), never evicted to make room for others.
    '
    ' Note: isChannelFavorite() only knows about the CURRENTLY LOADED
    ' playlist's favorites (m.currentFavoriteUrls), since favorites are
    ' per-playlist but this cache is global/session-wide. A channel favorited
    ' in a different playlist than the one active right now won't be
    ' protected until that playlist is loaded again. This is an accepted
    ' limitation of keying the cache by URL alone.
    if m.persistentCacheOrder.Count() >= SETTINGS_CACHE_MAX() then
        evictIdx = -1
        for i = 0 to m.persistentCacheOrder.Count() - 1
            if not isChannelFavorite(m.persistentCacheOrder[i]) then
                evictIdx = i
                exit for
            end if
        end for
        if evictIdx >= 0 then
            oldest = m.persistentCacheOrder[evictIdx]
            m.persistentSettingsCache.Delete(oldest)
            m.persistentCacheOrder.Delete(evictIdx)
        end if
        ' If every entry is favorited, evictIdx stays -1 and the cache is
        ' allowed to grow past SETTINGS_CACHE_MAX() rather than evict one.
    end if
    m.persistentSettingsCache[url] = entry
    m.persistentCacheOrder.Push(url)
end sub

sub _removeFromOrder(order as Object, url as String)
    for i = 0 to order.Count() - 1
        if order[i] = url then
            order.Delete(i)
            return
        end if
    end for
end sub

sub _savePersistentCache()
    data = {
        order  : m.persistentCacheOrder,
        entries: m.persistentSettingsCache
    }
    jsonStr = FormatJSON(data)
    if jsonStr = invalid then return

    ' Guard against registry size limit (~16KB per channel)
    if Len(jsonStr) > 14000 then
        ' Trim oldest entries until it fits
        while Len(jsonStr) > 14000 and m.persistentCacheOrder.Count() > 1
            oldest = m.persistentCacheOrder[0]
            m.persistentSettingsCache.Delete(oldest)
            m.persistentCacheOrder.Delete(0)
            data.order   = m.persistentCacheOrder
            data.entries = m.persistentSettingsCache
            jsonStr = FormatJSON(data)
        end while
    end if

    reg = CreateObject("roRegistrySection", SETTINGS_CACHE_REG_SECTION())
    reg.Write("data", jsonStr)
    reg.Flush()
    print ">>> CACHE: Saved "; m.persistentCacheOrder.Count(); " persistent entries ("; Len(jsonStr); " bytes)"
end sub
