' ==================== ManifestPatcherHelpers.brs ====================
' Private helper functions for ManifestPatcher task:
' HTTP fetch, CR stripping, Flussonic URL builders, fMP4 detection,
' URL absolutising, tmp: writer, iif, and segment truncation.

' ---------- Private helpers ----------

function _fetch(url as String, userAgent as String, referer = "" as String) as String
    http = CreateObject("roUrlTransfer")
    http.SetUrl(url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.EnableCookies()
    http.AddHeader("User-Agent", userAgent)
    if referer <> "" then http.AddHeader("Referer", referer)
    http.RetainBodyOnError(true)
    result = http.GetToString()
    ' Strip CR bytes via byte array - roRegex Chr(13) pattern is unreliable on some firmware
    return _stripCR(result)
end function

' Strip all CR (0x0D) bytes from a string via roByteArray
function _stripCR(s as String) as String
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(s)
    out = CreateObject("roByteArray")
    for i = 0 to ba.Count() - 1
        if ba[i] <> 13 then out.Push(ba[i])
    end for
    return out.ToAsciiString()
end function

function _buildFlussonicMpegtsUrl(url as String) as String
    qPos  = url.InStr("?")
    clean = iif(qPos > 0, Left(url, qPos), url)  ' qPos is 0-based, so Left(url, qPos) is everything before "?"
    for i = Len(clean) to 1 step -1
        if Mid(clean, i, 1) = "/" then return Left(clean, i) + "mpegts"
    end for
    return ""
end function

function _buildFlussonicVideoUrl(url as String) as String
    ' Given any Flussonic URL, return the video.m3u8 equivalent for MPEG-TS delivery
    ' e.g. http://host:port/STREAM_NAME/index.m3u8 → http://host:port/STREAM_NAME/video.m3u8
    ' Strips query string, removes the filename, appends video.m3u8
    qPos  = url.InStr("?")
    clean = iif(qPos > 0, Left(url, qPos), url)  ' qPos is 0-based, so Left(url, qPos) is everything before "?"
    ' Find the last slash and replace everything after it with video.m3u8
    for i = Len(clean) to 1 step -1
        if Mid(clean, i, 1) = "/" then
            return Left(clean, i) + "video.m3u8"
        end if
    end for
    return ""
end function

function _bodyHasFmp4Segments(body as String) as Boolean
    if LCase(body).InStr("ext-x-map") >= 0 then return true
    mp4Reg = CreateObject("roRegex", "\.(mp4|m4s)(\?|$)", "i")
    for each line in body.Split(Chr(10))
        trimmed = _trim(line)
        if trimmed <> "" and Left(trimmed, 1) <> "#" then
            if mp4Reg.isMatch(trimmed) then return true
        end if
    end for
    return false
end function

function _getBaseUrl(url as String) as String
    qPos  = url.InStr("?")
    clean = iif(qPos > 0, Left(url, qPos), url)  ' qPos is 0-based, so Left(url, qPos) is everything before "?"
    for i = Len(clean) to 1 step -1
        if Mid(clean, i, 1) = "/" then return Left(clean, i)
    end for
    return url
end function

function _makeAbsolute(path as String, baseUrl as String) as String
    if path = invalid or path = "" then return path
    lp = LCase(path)
    if Left(lp, 7) = "http://" or Left(lp, 8) = "https://" then return path
    if Left(path, 2) = "//" then return "https:" + path
    if Left(path, 1) = "/" then
        ' Extract origin (scheme+host) from baseUrl using string parsing -- no roRegex
        slashCount = 0
        i = 1
        while i <= Len(baseUrl)
            if Mid(baseUrl, i, 1) = "/" then
                slashCount = slashCount + 1
                if slashCount = 3 then
                    return Left(baseUrl, i - 1) + path
                end if
            end if
            i = i + 1
        end while
        return baseUrl + path
    end if
    return baseUrl + path
end function

function _trim(s as String) as String
    ' Strip CR bytes first
    s = _stripCR(s)
    ' Trim leading whitespace
    i = 1
    while i <= Len(s) and (Mid(s, i, 1) = " " or Mid(s, i, 1) = Chr(9))
        i = i + 1
    end while
    if i > 1 then s = Mid(s, i)
    ' Trim trailing whitespace
    j = Len(s)
    while j > 0 and (Mid(s, j, 1) = " " or Mid(s, j, 1) = Chr(9))
        j = j - 1
    end while
    if j < Len(s) then s = Left(s, j)
    return s
end function

sub _writeTmp(content as String, path as String)
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(content)
    ba.WriteFile(path)
end sub

' Local copy of iif() — ManifestPatcher is a separate Task node
' and cannot share Utils.brs with the main scene scripts.
function iif(condition as Boolean, trueVal as Dynamic, falseVal as Dynamic) as Dynamic
    if condition then return trueVal
    return falseVal
end function

' Truncates a media playlist to the first N EXTINF segments.
' Keeps all header tags (#EXTM3U, #EXT-X-VERSION, #EXT-X-MAP, etc.)
' and drops trailing segments beyond the limit.
' Does NOT add EXT-X-ENDLIST -- keeps it a live playlist.
function _truncateToSegments(body as String, maxSegs as Integer) as String
    lines    = body.Split(Chr(10))
    out      = []
    segCount = 0
    i        = 0

    while i < lines.Count()
        line    = lines[i]
        trimmed = _trim(line)

        if segCount < maxSegs then
            if Left(trimmed, 8) = "#EXTINF:" then
                ' Only include EXTINF if we still have room for one more segment
                out.Push(line)
            else if trimmed <> "" and Left(trimmed, 1) <> "#" then
                ' Segment URL
                out.Push(line)
                segCount = segCount + 1
            else
                ' Header tag or empty line
                out.Push(line)
            end if
        end if
        ' If segCount >= maxSegs, skip everything (no trailing EXTINF, no extra segments)

        i = i + 1
    end while

    result = ""
    j = 0
    while j < out.Count()
        result = result + out[j] + Chr(10)
        j = j + 1
    end while
    return result
end function
