' ==================== LocalProxy.brs ====================
' Task node: local HTTP/1.0 server (roStreamSocket) serving patched HLS
' playlists over http://localIP:7171/ -- bypasses the tmp: sandbox since
' Roku's HLS engine fetches from our local server instead.
' Helpers (_fetch/_makeAbsolute/_stripCR/_trim/iif/_join) are duplicated
' from ManifestPatcherHelpers.brs -- Task nodes can't share code.
'
' Endpoints:
'   /master -> synthetic v6 master with EXT-X-MEDIA audio group
'   /video  -> patched v6 video media playlist (fresh session tokens)
'   /audio  -> patched v6 audio media playlist (fresh session tokens)

sub init()
    m.top.functionName = "runProxy"
end sub

sub runProxy()
    proxyPort = 7171
    masterUrl = m.top.masterUrl
    userAgent = m.top.userAgent
    referer   = m.top.referrer
    cookie    = m.top.cookie

    print ">>> PROXY [task]: Starting roStreamSocket server on port "; proxyPort
    print ">>> PROXY [task]: masterUrl = "; masterUrl

    if masterUrl = "" or masterUrl = invalid then
        m.top.status = "error: no masterUrl"
        return
    end if

    ' cookieCheck=1 gets a fresh hlsSession cookie for this Task's own
    ' roUrlTransfer -- the Video node's cookie jar isn't shared with Tasks.
    cookieUrl = masterUrl
    if cookieUrl.InStr("cookieCheck") < 0 then
        if cookieUrl.InStr("?") >= 0 then
            cookieUrl = cookieUrl + "&cookieCheck=1"
        else
            cookieUrl = cookieUrl + "?cookieCheck=1"
        end if
    end if
    print ">>> PROXY [task]: Performing cookieCheck: "; cookieUrl
    ' Persistent roUrlTransfer -- all proxy fetches reuse it so cookies persist.
    m.http = CreateObject("roUrlTransfer")
    m.http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    m.http.InitClientCertificates()
    m.http.EnableCookies()
    m.http.RetainBodyOnError(true)
    if userAgent <> "" then m.http.AddHeader("User-Agent", userAgent)
    if referer   <> "" then m.http.AddHeader("Referer", referer)
    ' Prime the cookie jar
    m.http.SetUrl(cookieUrl)
    cookieResult = m.http.GetToString()
    print ">>> PROXY [task]: cookieCheck response ("; Len(cookieResult); "b) -- cookie jar primed"

    ' Get local IP -- try all available interfaces
    deviceInfo = CreateObject("roDeviceInfo")
    addrs      = deviceInfo.GetIPAddrs()
    localIp    = ""
    print ">>> PROXY [task]: Available interfaces:"
    for each iface in addrs
        print ">>> PROXY [task]:   "; iface; " = "; addrs[iface]
        if localIp = "" and addrs[iface] <> "" and addrs[iface] <> "127.0.0.1" then
            localIp = addrs[iface]
        end if
    end for
    if localIp = "" then
        print ">>> PROXY [task]: ERROR -- could not get local IP"
        m.top.status = "error: no local IP"
        return
    end if
    print ">>> PROXY [task]: Using IP = "; localIp

    ' Create listening socket using roStreamSocket (NOT roServerSocket)
    messagePort = CreateObject("roMessagePort")
    tcpListen   = CreateObject("roStreamSocket")
    if tcpListen = invalid then
        print ">>> PROXY [task]: ERROR -- roStreamSocket not available"
        m.top.status = "error: roStreamSocket unavailable"
        return
    end if

    addr = CreateObject("roSocketAddress")
    addr.setPort(proxyPort)
    tcpListen.setAddress(addr)
    tcpListen.notifyReadable(true)
    tcpListen.setMessagePort(messagePort)
    tcpListen.listen(5)

    if not tcpListen.eOK() then
        print ">>> PROXY [task]: ERROR -- listen() failed on port "; proxyPort
        m.top.status = "error: listen failed"
        return
    end if

    proxyBase      = "http://" + localIp + ":" + proxyPort.ToStr()
    connections    = {}
    m.top.proxyUrl = proxyBase + "/master"
    m.top.status   = "ready:" + proxyBase + "/master"
    print ">>> PROXY [task]: Listening at "; proxyBase
    print ">>> PROXY [task]: Signalled ready"

    reqCount = 0
    m.top.stopProxy = false  ' clear any stale stop signal from previous run
    while not m.top.stopProxy
        event = wait(500, messagePort)
        if event = invalid then
            ' timeout -- just loop and check control
        else if type(event) = "roSocketEvent" then
            changedId = event.getSocketID()

            ' New incoming connection
            if changedId = tcpListen.getID() and tcpListen.isReadable() then
                newConn = tcpListen.accept()
                if newConn = invalid then
                    print ">>> PROXY [task]: accept() failed"
                else
                    reqCount = reqCount + 1
                    print ">>> PROXY [task]: Connection #"; reqCount; " accepted"
                    newConn.notifyReadable(true)
                    newConn.setMessagePort(messagePort)
                    connections[newConn.getID().ToStr()] = newConn
                end if

            else
                ' Data on existing connection
                conn = connections[changedId.ToStr()]
                if conn <> invalid then
                    if conn.isReadable() then
                        buf = CreateObject("roByteArray")
                        buf[4096] = 0
                        received = conn.receive(buf, 0, 4096)
                        if received > 0 then
                            request = buf.ToAsciiString()
                            path = _parsePath(request)
                            print ">>> PROXY [handler]: Request path="; path
                            response = _handleRequest(path, masterUrl, userAgent, referer, cookie, proxyBase)
                            conn.sendStr(response)
                        end if
                    end if
                    ' Always close and remove after handling -- HTTP/1.0 is one request per connection
                    conn.close()
                    connections.delete(changedId.ToStr())
                end if
            end if
        end if
    end while

    tcpListen.close()
    m.top.status = "stopped"
    print ">>> PROXY [task]: Server stopped after "; reqCount; " requests"
    ' Brief pause to ensure OS releases port 7171 before potential restart
    sleep(500)
end sub

function _parsePath(request as String) as String
    ' Extract path from "GET /path HTTP/1.x"
    if Left(request, 3) <> "GET" then return "/"
    parts = request.Split(" ")
    if parts.Count() >= 2 then return parts[1]
    return "/"
end function

function _handleRequest(path as String, masterUrl as String, userAgent as String, referer as String, cookie as String, proxyBase as String) as String
    ' Strip query string for routing
    qPos = path.InStr("?")
    route = path
    if qPos > 0 then route = Left(path, qPos)

    body = ""
    if route = "/master" or route = "/stream" then
        body = _serveMaster(masterUrl, userAgent, referer, cookie, proxyBase)
    else if route = "/video" then
        body = _serveMedia(masterUrl, userAgent, referer, cookie, "video")
    else if route = "/audio" then
        body = _serveMedia(masterUrl, userAgent, referer, cookie, "audio")
    else
        body = "Not Found"
        return "HTTP/1.0 404 Not Found" + Chr(13) + Chr(10) + "Content-Length: 9" + Chr(13) + Chr(10) + Chr(13) + Chr(10) + "Not Found"
    end if

    header = "HTTP/1.0 200 OK" + Chr(13) + Chr(10)
    header = header + "Content-Type: application/vnd.apple.mpegurl" + Chr(13) + Chr(10)
    header = header + "Content-Length: " + Len(body).ToStr() + Chr(13) + Chr(10)
    header = header + "Cache-Control: no-cache" + Chr(13) + Chr(10)
    header = header + Chr(13) + Chr(10)
    return header + body
end function

function _serveMaster(masterUrl as String, userAgent as String, referer as String, cookie as String, proxyBase as String) as String
    masterBody = _fetch(masterUrl, userAgent, referer, cookie)
    if masterBody = invalid or masterBody = "" then return "#EXTM3U" + Chr(10) + "' fetch failed"

    bwVal     = "2000000"
    codecsVal = "avc1.64001f,mp4a.40.2"
    resVal    = ""
    bwReg = CreateObject("roRegex", "BANDWIDTH=(\d+)", "i")
    bwM   = bwReg.Match(masterBody)
    if bwM <> invalid and bwM.Count() > 1 then bwVal = bwM[1]
    coReg = CreateObject("roRegex", "CODECS=""([^""]+)""", "i")
    coM   = coReg.Match(masterBody)
    if coM <> invalid and coM.Count() > 1 then codecsVal = coM[1]
    resReg = CreateObject("roRegex", "RESOLUTION=([0-9x]+)", "i")
    resM   = resReg.Match(masterBody)
    if resM <> invalid and resM.Count() > 1 then resVal = resM[1]

    ' Check if audio stream exists
    hasAudio = masterBody.InStr("TYPE=AUDIO") >= 0

    master = "#EXTM3U" + Chr(10)
    master = master + "#EXT-X-VERSION:6" + Chr(10)
    master = master + "#EXT-X-INDEPENDENT-SEGMENTS" + Chr(10) + Chr(10)
    if hasAudio then
        master = master + "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=""audio"",NAME=""audio"",AUTOSELECT=YES,DEFAULT=YES,URI=""" + proxyBase + "/audio""" + Chr(10) + Chr(10)
    end if
    streamInf = "#EXT-X-STREAM-INF:BANDWIDTH=" + bwVal + ",CODECS=""" + codecsVal + """"
    if resVal <> "" then streamInf = streamInf + ",RESOLUTION=" + resVal
    if hasAudio then streamInf = streamInf + ",AUDIO=""audio"""
    master = master + streamInf + Chr(10)
    master = master + proxyBase + "/video" + Chr(10)

    print ">>> PROXY [master]: Served ("; Len(master); "b)"
    return master
end function

function _serveMedia(masterUrl as String, userAgent as String, referer as String, cookie as String, mediaType as String) as String
    ' Fetch fresh master to get current session token
    masterBody = _fetch(masterUrl, userAgent, referer, cookie)
    if masterBody = invalid or masterBody = "" then return "#EXTM3U" + Chr(10) + "' master fetch failed"

    baseDir = _getBaseDir(masterUrl)

    ' Extract the correct media playlist URL
    variantUrl = ""
    if mediaType = "video" then
        variantUrl = _extractVariantUrl(masterBody, baseDir)
    else
        variantUrl = _extractAudioUrl(masterBody, baseDir)
    end if

    if variantUrl = "" then
        print ">>> PROXY [media]: No "; mediaType; " URL found"
        return "#EXTM3U" + Chr(10) + "' no " + mediaType + " URL"
    end if
    print ">>> PROXY ["; mediaType; "]: Fetching "; Left(variantUrl, 80)

    variantBody = _fetch(variantUrl, userAgent, referer, cookie)
    if variantBody = invalid or variantBody = "" then
        print ">>> PROXY ["; mediaType; "]: Fetch failed"
        return "#EXTM3U" + Chr(10) + "' fetch failed"
    end if

    patched = _patchPlaylist(variantBody, variantUrl)
    print ">>> PROXY ["; mediaType; "]: Served ("; Len(patched); "b)"
    return patched
end function

function _patchPlaylist(body as String, baseUrl as String) as String
    baseDir = _getBaseDir(baseUrl)
    lines   = _stripCR(body).Split(Chr(10))
    out     = []
    uriReg  = CreateObject("roRegex", "URI=""([^""]+)""", "i")

    for each line in lines
        t = _trim(line)
        skip = false
        repl = ""

        if Left(t, 15) = "#EXT-X-VERSION:" then
            repl = "#EXT-X-VERSION:6"
        else if t.InStr("EXT-X-PART") >= 0 or t.InStr("CAN-BLOCK-RELOAD") >= 0 or t.InStr("EXT-X-PRELOAD-HINT") >= 0 or t.InStr("EXT-X-RENDITION-REPORT") >= 0 or t.InStr("EXT-X-PART-INF") >= 0 or t.InStr("EXT-X-SERVER-CONTROL") >= 0 then
            skip = true
        else if Left(t, 11) = "#EXT-X-MAP:" then
            mm = uriReg.Match(t)
            if mm <> invalid and mm.Count() > 1 then
                repl = uriReg.ReplaceAll(t, "URI=""" + _makeAbsolute(mm[1], baseDir) + """")
            end if
        else if t <> "" and Left(t, 1) <> "#" then
            repl = _makeAbsolute(t, baseDir)
        end if

        if not skip then
            if repl <> "" then out.Push(repl) else out.Push(line)
        end if
    end for

    return _join(out, Chr(10))
end function

function _extractVariantUrl(body as String, baseDir as String) as String
    lines   = _stripCR(body).Split(Chr(10))
    isNext  = false
    for each line in lines
        t = _trim(line)
        if Left(t, 18) = "#EXT-X-STREAM-INF:" then
            isNext = true
        else if isNext and t <> "" and Left(t, 1) <> "#" then
            return _makeAbsolute(t, baseDir)
        else if t <> "" and Left(t, 1) <> "#" then
            isNext = false
        end if
    end for
    return ""
end function

function _extractAudioUrl(body as String, baseDir as String) as String
    uriReg = CreateObject("roRegex", "URI=""([^""]+)""", "i")
    for each line in _stripCR(body).Split(Chr(10))
        t = _trim(line)
        if Left(t, 12) = "#EXT-X-MEDIA" and t.InStr("TYPE=AUDIO") >= 0 then
            mm = uriReg.Match(t)
            if mm <> invalid and mm.Count() > 1 then
                return _makeAbsolute(mm[1], baseDir)
            end if
        end if
    end for
    return ""
end function

function _fetch(url as String, userAgent as String, referer as String, cookie as String) as String
    ' Use shared http instance (m.http) if available -- it has the primed cookie jar.
    ' Fall back to creating a new instance if called outside proxy context.
    if m.http <> invalid then
        m.http.SetUrl(url)
        return _stripCR(m.http.GetToString())
    end if
    http = CreateObject("roUrlTransfer")
    http.SetUrl(url)
    http.SetCertificatesFile("common:/certs/ca-bundle.crt")
    http.InitClientCertificates()
    http.EnableCookies()
    http.RetainBodyOnError(true)
    if userAgent <> "" then http.AddHeader("User-Agent", userAgent)
    if referer   <> "" then http.AddHeader("Referer", referer)
    if cookie    <> "" then http.AddHeader("Cookie", cookie)
    return _stripCR(http.GetToString())
end function

function _getBaseDir(url as String) as String
    qPos  = url.InStr("?")
    clean = iif(qPos > 0, Left(url, qPos), url)
    i = Len(clean)
    while i > 0
        if Mid(clean, i, 1) = "/" then return Left(clean, i)
        i = i - 1
    end while
    return url
end function

function _makeAbsolute(path as String, baseDir as String) as String
    if path = invalid or path = "" then return path
    lp = LCase(path)
    if Left(lp, 7) = "http://" or Left(lp, 8) = "https://" then return path
    if Left(path, 2) = "//" then return "https:" + path
    if Left(path, 1) = "/" then
        ' Extract scheme+host from baseDir (always absolute) -- find the 3rd slash
        slashCount = 0
        i = 1
        while i <= Len(baseDir)
            if Mid(baseDir, i, 1) = "/" then
                slashCount = slashCount + 1
                if slashCount = 3 then
                    return Left(baseDir, i - 1) + path
                end if
            end if
            i = i + 1
        end while
        return baseDir + path
    end if
    return baseDir + path
end function

function _stripCR(s as String) as String
    ba  = CreateObject("roByteArray")
    ba.FromAsciiString(s)
    out = CreateObject("roByteArray")
    i   = 0
    while i < ba.Count()
        if ba[i] <> 13 then out.Push(ba[i])
        i = i + 1
    end while
    return out.ToAsciiString()
end function

function _trim(s as String) as String
    s = _stripCR(s)
    i = 1
    while i <= Len(s) and (Mid(s, i, 1) = " " or Mid(s, i, 1) = Chr(9))
        i = i + 1
    end while
    if i > 1 then s = Mid(s, i)
    j = Len(s)
    while j > 0 and (Mid(s, j, 1) = " " or Mid(s, j, 1) = Chr(9))
        j = j - 1
    end while
    if j < Len(s) then s = Left(s, j)
    return s
end function

function _join(arr as Object, sep as String) as String
    result = ""
    i = 0
    while i < arr.Count()
        result = result + arr[i] + sep
        i = i + 1
    end while
    return result
end function

function iif(condition as Boolean, trueVal as Dynamic, falseVal as Dynamic) as Dynamic
    if condition then return trueVal
    return falseVal
end function
