' ==================== ManifestPatcher.brs ====================
' Task node: fetches and recursively patches HLS manifests to fix Roku's
' "no valid bitrates" and "malformed data" errors.
'
' Level 1 (master/variant): fix missing/zero BANDWIDTH, strip LL-HLS tags,
' fetch+patch each variant (Level 2), rewrite variant URLs to patched tmp: files.
' Level 2 (media playlist): relative segment URLs -> absolute, add
' EXT-X-VERSION:6 for fMP4, absolutize EXT-X-MAP URI.
' Flat manifest (no EXT-X-STREAM-INF): patch as media playlist, wrap in a
' synthetic variant. Flussonic tracks-vXaX/mono.m3u8: redirect to index.m3u8 first.
'
' Writes tmp:/patched.m3u8 (master) and tmp:/patched_media.m3u8 (media, if needed).
' result fields: url, patched (bool), error (non-empty if fetch failed).

sub init()
    m.top.functionName = "patchManifest"
end sub

sub patchManifest()
    url       = m.top.url
    userAgent = m.top.userAgent
    referer   = m.top.referrer   ' note: XML field is "referrer", local var stays "referer" for consistency

    if url = "" or url = invalid then
        m.top.result = { url: "", patched: false, error: "No URL provided" }
        return
    end if

    ' Never fetch an mpegts URL — it's a continuous stream that never completes
    ' Return it directly so onManifestPatched plays it with streamFormat=ts
    if url.EndsWith("mpegts") or url.EndsWith("/mpegts") then
        print ">>> PATCHER: Raw MPEG-TS URL detected, returning directly without fetch"
        m.top.result = { url: url, patched: true, error: "", isNimble: false }
        return
    end if

    ' Flussonic tracks-vXaX/mono.m3u8 → redirect to index.m3u8
    flussonicReg = CreateObject("roRegex", "tracks-v\d+a\d+/mono\.m3u8(\?.*)?$", "i")
    if flussonicReg.isMatch(url) then
        url = flussonicReg.ReplaceAll(url, "index.m3u8")
        print ">>> PATCHER: Flussonic tracks URL → "; url
    end if

    ' Fetch the top-level manifest
    body = _fetch(url, userAgent, referer)
    if body = invalid or body = "" then
        m.top.result = { url: url, patched: false, error: "Empty response from server" }
        return
    end if

    ' Strip CR bytes so all Split(Chr(10)) calls work cleanly
    body = _stripCR(body)

    if Left(LCase(body), 7) <> "#extm3u" then
        ' Not an M3U8 — direct media file, pass through unchanged
        m.top.result = { url: url, patched: false, error: "" }
        return
    end if

    hasVariants = body.InStr("#EXT-X-STREAM-INF") >= 0

    print ">>> PATCHER INSPECT: hasVariants="; hasVariants; " isFmp4="; _bodyHasFmp4Segments(body); " hasLLHLS="; (body.InStr("EXT-X-PART") >= 0)
    print ">>> PATCHER MANIFEST FIRST 800: "; Left(body, 800)

    ' Flussonic timestamped live playlists (PROGRAM-DATE-TIME + .ts segments):
    ' redirect to video.m3u8 so Roku polls it natively instead of us caching
    ' a snapshot of expiring segment URLs.
    if body.InStr("EXT-X-PROGRAM-DATE-TIME") >= 0 and body.InStr(".ts") >= 0 then
        videoUrl = _buildFlussonicVideoUrl(url)
        print ">>> PATCHER: Flussonic detection: input="; url; " videoUrl="; videoUrl
        if videoUrl <> "" and videoUrl <> url then
            print ">>> PATCHER: Flussonic live stream detected, redirecting to: "; videoUrl
            m.top.result = { url: videoUrl, patched: true, error: "", isNimble: true }
            return
        end if
        ' Already on video.m3u8 — try raw MPEG-TS endpoint as last resort
        mpegtsUrl = _buildFlussonicMpegtsUrl(url)
        print ">>> PATCHER: Already on Flussonic TS endpoint, trying raw MPEG-TS: "; mpegtsUrl
        m.top.result = { url: mpegtsUrl, patched: true, error: "", isNimble: false }
        return
    end if

    ' Flussonic nested masters (index.m3u8 -> tracks-v1a1/mono.m3u8): fetch
    ' mono.m3u8, patch its segment URLs, wrap in a synthetic master.
    isNimble = hasVariants and (body.InStr("tracks-v") >= 0 or body.InStr("mono.m3u") >= 0)
    if isNimble then
        baseUrl = _getBaseUrl(url)
        ' InStr is 0-based; Mid is 1-based. Convert once up front so all the
        ' walking below operates in consistent 1-based coordinates.
        monoPartPos0 = body.InStr("mono.m3u")
        monoUrlFull  = ""
        if monoPartPos0 >= 0 then
            monoPartPos = monoPartPos0 + 1   ' 0-based → 1-based
            lineStart1 = 1
            for si = monoPartPos to 1 step -1
                bch = Asc(Mid(body, si, 1))
                if bch = 10 or bch = 13 then
                    lineStart1 = si + 1
                    exit for
                end if
            end for
            lineEnd1 = Len(body)
            for si = monoPartPos + 9 to Len(body)
                bch = Asc(Mid(body, si, 1))
                if bch <= 32 or bch = 13 or bch = 10 then
                    lineEnd1 = si - 1
                    exit for
                end if
            end for
            rawFull = Mid(body, lineStart1, lineEnd1 - lineStart1 + 1)
            monoUrlFull = _makeAbsolute(rawFull, baseUrl)
        else
            print ">>> PATCHER: mono.m3u not found in body"
        end if

        if monoUrlFull <> "" then

            print ">>> PATCHER: Fetching mono.m3u8 (with session): "; monoUrlFull
            monoBody = _fetch(monoUrlFull, userAgent, referer)
            if monoBody <> invalid and monoBody <> "" and Left(LCase(monoBody), 7) = "#extm3u" then
                print ">>> PATCHER: mono.m3u8 fetch OK"
                monoBody = _stripCR(monoBody)

                ' Patch media playlist (absolute segment URLs) and wrap in synthetic master
                mediaResult = _patchMediaPlaylist(monoBody, monoUrlFull, userAgent, referer)
                bwVal     = "2000000"
                codecsVal = "avc1.42c01e,mp4a.40.2"
                bwReg = CreateObject("roRegex", "BANDWIDTH=(\d+)", "i")
                bwM   = bwReg.Match(body)
                if bwM <> invalid and bwM.Count() > 1 then bwVal = bwM[1]
                coReg = CreateObject("roRegex", "CODECS=""([^""]+)""", "i")
                coM   = coReg.Match(body)
                if coM <> invalid and coM.Count() > 1 then codecsVal = coM[1]
                syntheticMaster = "#EXTM3U" + Chr(10) + "#EXT-X-STREAM-INF:BANDWIDTH=" + bwVal + ",CODECS=""" + codecsVal + """" + Chr(10) + "tmp:/patched_media.m3u8" + Chr(10)
                _writeTmp(mediaResult.content, "tmp:/patched_media.m3u8")
                _writeTmp(syntheticMaster, "tmp:/patched.m3u8")
                print ">>> PATCHER: Nimble synthetic master written"
                m.top.result = { url: "tmp:/patched.m3u8", patched: true, error: "", isNimble: true }
                return
            else
                print ">>> PATCHER: mono.m3u8 fetch failed, falling through"
            end if
        end if
    end if  ' end if isNimble

    if hasVariants then
        ' Some servers embed a short-lived ?session=UUID in variant/audio URLs --
        ' patching those into a tmp: file lets the token expire before Roku plays
        ' it. Detected here, we hand the original URL back so Roku fetches fresh.
        sessionReg = CreateObject("roRegex", "[?&]session=[a-f0-9\-]{36}", "i")
        if sessionReg.isMatch(body) then
            print ">>> PATCHER: Session-token master detected"
            print ">>> PATCHER: Master URL: "; url
            print ">>> PATCHER: UserAgent: "; userAgent
            print ">>> PATCHER: Referrer: "; referer
            ' Tells ManifestCallbacks to start LocalProxy -- serves a real http://
            ' URL Roku can fetch natively, no tmp: sandbox restriction.
            print ">>> PATCHER: Signalling useProxy=true to MainScene"
            m.top.result = { url: url, patched: true, error: "", isNimble: false, useProxy: true }
            return
        end if

        ' High-version HLS over https:// -- the tmp: sandbox will block it, so
        ' signal useProxy to serve it via LocalProxy instead.
        hlsVersionReg = CreateObject("roRegex", "#EXT-X-VERSION:(\d+)", "i")
        hlsVersionM   = hlsVersionReg.Match(body)
        hlsVersion    = 0
        if hlsVersionM <> invalid and hlsVersionM.Count() > 1 then hlsVersion = hlsVersionM[1].ToInt()
        if hlsVersion > 6 and Left(LCase(url), 5) = "https" then
            print ">>> PATCHER: HLS version "; hlsVersion; " > 6 on https:// stream -- signalling useProxy"
            m.top.result = { url: url, patched: true, error: "", isNimble: false, useProxy: true }
            return
        end if
        result = _patchMasterPlaylist(body, url, userAgent, referer)
        if result.patched then
            _writeTmp(result.content, "tmp:/patched.m3u8")
            m.top.result = { url: "tmp:/patched.m3u8", patched: true, error: "", isNimble: isNimble }
        else
            m.top.result = { url: url, patched: false, error: "", isNimble: isNimble }
        end if
    else
        ' Flat media playlist: fetch fresh (live Flussonic segments expire
        ' quickly) and patch segment URLs directly.
        freshBody = _fetch(url, userAgent, referer)
        if freshBody <> invalid and freshBody <> "" and Left(LCase(freshBody), 7) = "#extm3u" then
            print ">>> PATCHER: Refreshed flat manifest before patching"
            body = freshBody
        end if
        result = _patchMediaPlaylist(body, url, userAgent, referer)
        _writeTmp(result.content, "tmp:/patched.m3u8")
        m.top.result = { url: "tmp:/patched.m3u8", patched: true, error: "", isNimble: isNimble }
    end if
end sub

' ---------- Level 1: patch a master/variant playlist ----------
' Fixes BANDWIDTH, strips LL-HLS, and for each variant URL:
'   - Fetches and patches the media playlist (Level 2)
'   - Rewrites the variant entry to point to tmp:/patched_media.m3u8

function _patchMasterPlaylist(body as String, masterUrl as String, userAgent as String, referer as String) as Object
    lines    = body.Split(Chr(10))
    baseUrl  = _getBaseUrl(masterUrl)
    newLines = []
    patched  = false
    i        = 0

    while i < lines.Count()
        line    = lines[i]
        trimmed = _trim(line)

        ' Strip LL-HLS extension tags
        if trimmed.InStr("EXT-X-PART") >= 0 or trimmed.InStr("CAN-BLOCK-RELOAD") >= 0 or trimmed.InStr("EXT-X-PRELOAD-HINT") >= 0 or trimmed.InStr("EXT-X-RENDITION-REPORT") >= 0 then
            patched = true
            i = i + 1
            continue while
        end if

        ' Fix missing or zero BANDWIDTH
        if Left(trimmed, 18) = "#EXT-X-STREAM-INF:" then
            if trimmed.InStr("BANDWIDTH=0") >= 0 or trimmed.InStr("BANDWIDTH=") < 0 then
                if trimmed.InStr("BANDWIDTH=0") >= 0 then
                    bwReg = CreateObject("roRegex", "BANDWIDTH=0\b", "i")
                    line  = bwReg.ReplaceAll(line, "BANDWIDTH=2000000")
                else
                    line = line + ",BANDWIDTH=2000000"
                end if
                patched = true
            end if
            newLines.Push(line)
            i = i + 1

            ' Process the variant URL on the next line
            if i < lines.Count() then
                variantLine = _trim(lines[i])
                if variantLine <> "" and Left(variantLine, 1) <> "#" then
                    absVariantUrl = _makeAbsolute(variantLine, baseUrl)
                    if absVariantUrl <> variantLine then patched = true

                    ' Fetch and patch the media playlist
                    print ">>> PATCHER L2: Fetching variant: "; absVariantUrl
                    mediaBody = _fetch(absVariantUrl, userAgent, referer)
                    if mediaBody <> invalid and mediaBody <> "" and Left(LCase(mediaBody), 7) = "#extm3u" then
                        mediaResult = _patchMediaPlaylist(mediaBody, absVariantUrl, userAgent, referer)
                        if mediaResult.patched then
                            _writeTmp(mediaResult.content, "tmp:/patched_media.m3u8")
                            newLines.Push("tmp:/patched_media.m3u8")
                            patched = true
                        else
                            newLines.Push(absVariantUrl)
                        end if
                    else
                        ' Couldn't fetch media playlist — use absolute URL as-is
                        newLines.Push(absVariantUrl)
                    end if
                    i = i + 1
                end if
            end if
            continue while
        end if

        ' Pass through all other lines unchanged
        newLines.Push(line)
        i = i + 1
    end while

    content = ""
    for each l in newLines
        content = content + l + Chr(10)
    end for

    return { content: content, patched: patched }
end function

' ---------- Level 2: patch a media playlist ----------
' Rewrites relative segment URLs to absolute, adds VERSION:6 for fMP4,
' preserves and absolutizes EXT-X-MAP URI.

function _patchMediaPlaylist(body as String, mediaUrl as String, userAgent = "" as String, referer = "" as String) as Object
    lines    = body.Split(Chr(10))
    baseUrl  = _getBaseUrl(mediaUrl)
    newLines = []
    patched  = false
    isFmp4   = _bodyHasFmp4Segments(body)
    hasVersion = body.InStr("EXT-X-VERSION") >= 0
    i        = 0
    ' userAgent and referer are accepted for API consistency with _patchMasterPlaylist
    ' but this function only rewrites URLs and makes no HTTP calls, so they go unused.
    _ = userAgent
    _ = referer

    while i < lines.Count()
        line    = lines[i]
        trimmed = _trim(line)

        ' Strip LL-HLS extension tags
        if trimmed.InStr("EXT-X-PART") >= 0 or trimmed.InStr("CAN-BLOCK-RELOAD") >= 0 or trimmed.InStr("EXT-X-PRELOAD-HINT") >= 0 or trimmed.InStr("EXT-X-RENDITION-REPORT") >= 0 then
            patched = true
            i = i + 1
            continue while
        end if

        ' Inject or upgrade EXT-X-VERSION for fMP4
        if Left(trimmed, 15) = "#EXT-X-VERSION:" then
            if isFmp4 then
                currentVer = Mid(trimmed, 16).ToInt()
                if currentVer < 6 then
                    newLines.Push("#EXT-X-VERSION:6")
                    patched = true
                    i = i + 1
                    continue while
                end if
            end if
            newLines.Push(line)
            i = i + 1
            continue while
        end if

        ' Absolutize EXT-X-MAP URI
        if Left(trimmed, 11) = "#EXT-X-MAP:" then
            mapReg = CreateObject("roRegex", "URI=""([^""]+)""", "i")
            m2 = mapReg.Match(trimmed)
            if m2 <> invalid and m2.Count() > 1 then
                absMap = _makeAbsolute(m2[1], baseUrl)
                if absMap <> m2[1] then
                    line = "#EXT-X-MAP:URI=""" + absMap + """"
                    patched = true
                end if
            end if
            newLines.Push(line)
            i = i + 1
            continue while
        end if

        ' Pass EXT-X-KEY lines through unchanged
        if Left(trimmed, 11) = "#EXT-X-KEY:" then
            newLines.Push(line)
            i = i + 1
            continue while
        end if

        ' Rewrite relative segment URLs to absolute
        if trimmed <> "" and Left(trimmed, 1) <> "#" then
            abs = _makeAbsolute(trimmed, baseUrl)
            if abs <> trimmed then patched = true
            newLines.Push(abs)
            i = i + 1
            continue while
        end if

        newLines.Push(line)
        i = i + 1
    end while

    ' Inject EXT-X-VERSION:6 after #EXTM3U if fMP4 and no version tag present
    if isFmp4 and not hasVersion then
        injected = []
        for each l in newLines
            injected.Push(l)
            if _trim(l) = "#EXTM3U" then
                injected.Push("#EXT-X-VERSION:6")
                patched = true
            end if
        end for
        newLines = injected
    end if

    content = ""
    for each l in newLines
        content = content + l + Chr(10)
    end for

    return { content: content, patched: patched }
end function
