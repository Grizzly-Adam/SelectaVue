' ==================== PhoneEntryServer.brs ====================
' Task node: local HTTP/1.0 server (roStreamSocket, same pattern as
' LocalProxy.brs) serving a mobile text-entry page.
'
' Endpoints:
'   GET /                          -> entry page, or error/done page if set
'   GET /submit?text=<urlencoded>  -> stores m.top.submittedText, returns confirmation
'   GET /error-ok, GET /error-back -> sets m.top.errorAction, auto-reloads "/"
'
' Helpers below are self-contained -- Task nodes can't share code.

sub init()
    m.top.functionName = "runServer"
end sub

sub runServer()
    serverPort   = 7172   ' distinct from LocalProxy's 7171 -- never both running at once in practice, but keep separate to be safe

    print ">>> PHONEENTRY [task]: Starting roStreamSocket server on port "; serverPort

    deviceInfo = CreateObject("roDeviceInfo")
    addrs      = deviceInfo.GetIPAddrs()
    localIp    = ""
    for each iface in addrs
        if localIp = "" and addrs[iface] <> "" and addrs[iface] <> "127.0.0.1" then
            localIp = addrs[iface]
        end if
    end for
    if localIp = "" then
        print ">>> PHONEENTRY [task]: ERROR -- could not get local IP"
        m.top.status = "error: no local IP"
        return
    end if
    print ">>> PHONEENTRY [task]: Using IP = "; localIp

    messagePort = CreateObject("roMessagePort")
    tcpListen   = CreateObject("roStreamSocket")
    if tcpListen = invalid then
        print ">>> PHONEENTRY [task]: ERROR -- roStreamSocket not available"
        m.top.status = "error: roStreamSocket unavailable"
        return
    end if

    addr = CreateObject("roSocketAddress")
    addr.setPort(serverPort)
    tcpListen.setAddress(addr)
    tcpListen.notifyReadable(true)
    tcpListen.setMessagePort(messagePort)
    tcpListen.listen(5)

    if not tcpListen.eOK() then
        print ">>> PHONEENTRY [task]: ERROR -- listen() failed on port "; serverPort
        m.top.status = "error: listen failed"
        return
    end if

    serverBase    = "http://" + localIp + ":" + serverPort.ToStr()
    connections   = {}
    m.top.status  = "ready:" + serverBase + "/"
    print ">>> PHONEENTRY [task]: Listening at "; serverBase

    reqCount = 0
    m.top.stopServer = false   ' clear any stale stop signal from a previous run
    while not m.top.stopServer
        event = wait(500, messagePort)
        if event = invalid then
            ' timeout -- just loop and check control
        else if type(event) = "roSocketEvent" then
            changedId = event.getSocketID()

            if changedId = tcpListen.getID() and tcpListen.isReadable() then
                newConn = tcpListen.accept()
                if newConn = invalid then
                    print ">>> PHONEENTRY [task]: accept() failed"
                else
                    reqCount = reqCount + 1
                    newConn.notifyReadable(true)
                    newConn.setMessagePort(messagePort)
                    connections[newConn.getID().ToStr()] = newConn
                end if
            else
                conn = connections[changedId.ToStr()]
                if conn <> invalid then
                    if conn.isReadable() then
                        buf = CreateObject("roByteArray")
                        buf[4096] = 0
                        received = conn.receive(buf, 0, 4096)
                        if received > 0 then
                            request = buf.ToAsciiString()
                            path = _peParsePath(request)
                            print ">>> PHONEENTRY [handler]: Request path="; path
                            response = _peHandleRequest(path)
                            conn.sendStr(response)
                            reqRoute = _peRoute(path)
                            if reqRoute = "/submit" then
                                submitted = _peQueryParam(path, "text")
                                if submitted <> invalid then
                                    m.top.submittedText = _peUrlDecode(submitted)
                                end if
                            else if reqRoute = "/error-ok" then
                                m.top.errorAction = "ok"
                            else if reqRoute = "/error-back" then
                                m.top.errorAction = "back"
                            end if
                        end if
                    end if
                    conn.close()
                    connections.delete(changedId.ToStr())
                end if
            end if
        end if
    end while

    tcpListen.close()
    m.top.status = "stopped"
    print ">>> PHONEENTRY [task]: Server stopped after "; reqCount; " requests"
    sleep(500)
end sub

function _peParsePath(request as String) as String
    if Left(request, 3) <> "GET" then return "/"
    parts = request.Split(" ")
    if parts.Count() >= 2 then return parts[1]
    return "/"
end function

function _peRoute(path as String) as String
    qPos = path.InStr("?")
    if qPos >= 0 then return Left(path, qPos)
    return path
end function

' Small query-string reader for our one "text" param. Deliberately does NOT
' split on "&" first -- an unescaped "&" inside the value would otherwise
' truncate it. Finds "text=" directly and takes everything after it.
function _peQueryParam(path as String, key as String) as Dynamic
    marker = key + "="
    idx = path.InStr(marker)
    if idx < 0 then return invalid
    return Mid(path, idx + Len(marker) + 1)
end function

' Decodes application/x-www-form-urlencoded text: '+' -> space, %XX -> byte.
function _peUrlDecode(s as String) as String
    s = s.Replace("+", " ")
    out = ""
    i = 1
    n = s.Len()
    while i <= n
        ch = Mid(s, i, 1)
        if ch = "%" and i + 2 <= n then
            hex = Mid(s, i + 1, 2)
            code = Val("&H" + hex)
            out = out + Chr(code)
            i = i + 3
        else
            out = out + ch
            i = i + 1
        end if
    end while
    return out
end function

' Escapes text for safe embedding inside an HTML attribute value.
function _peHtmlEscape(s as String) as String
    if s = invalid then return ""
    s = s.Replace("&", "&amp;")
    s = s.Replace("""", "&quot;")
    s = s.Replace("<", "&lt;")
    s = s.Replace(">", "&gt;")
    return s
end function

' Reads a packaged image file and returns it as a data: URI, so the phone
' page is fully self-contained (no separate image request/route needed).
function _peLogoDataUri() as String
    ba = CreateObject("roByteArray")
    ok = ba.ReadFile("pkg:/images/selectaview.png")
    if not ok then return ""
    return "data:image/png;base64," + ba.ToBase64String()
end function

function _peHandleRequest(path as String) as String
    route = _peRoute(path)
    body = ""
    if route = "/" then
        if m.top.doneMessage <> "" then
            body = _peDonePage()
        else if m.top.errorTitle <> "" then
            body = _peErrorPage()
        else
            body = _peEntryPage()
        end if
    else if route = "/submit" then
        body = _peSentPage()
    else if route = "/error-ok" or route = "/error-back" then
        body = _peErrorDismissedPage()
    else
        return "HTTP/1.0 404 Not Found" + Chr(13) + Chr(10) + "Content-Length: 9" + Chr(13) + Chr(10) + Chr(13) + Chr(10) + "Not Found"
    end if

    header = "HTTP/1.0 200 OK" + Chr(13) + Chr(10)
    header = header + "Content-Type: text/html; charset=utf-8" + Chr(13) + Chr(10)
    header = header + "Content-Length: " + Len(body).ToStr() + Chr(13) + Chr(10)
    header = header + "Cache-Control: no-cache" + Chr(13) + Chr(10)
    header = header + Chr(13) + Chr(10)
    return header + body
end function

' Shown while an error is active. OK/Back are plain links to their own routes.
function _peErrorPage() as String
    safeTitle = _peHtmlEscape(m.top.errorTitle)
    safeMsg   = _peHtmlEscape(m.top.errorMessage)

    html = "<!DOCTYPE html><html><head><meta name=""viewport"" content=""width=device-width, initial-scale=1"">"
    html = html + "<title>SelectaVue</title><style>"
    html = html + "body{background:#024c48;color:#e8f5f3;font-family:sans-serif;text-align:center;padding:24px}"
    html = html + "img.logo{max-width:220px;margin-bottom:8px}"
    html = html + "h2{color:#8fcdc1;margin:4px 0}"
    html = html + "p.msg{color:#e8f5f3;font-size:16px;margin:8px 0 24px}"
    html = html + "a.btn{display:block;width:90%;margin:12px auto 0;font-size:20px;padding:14px;background:#8fcdc1;color:#024c48;border-radius:6px;font-weight:bold;text-decoration:none}"
    html = html + "a.btn.secondary{background:transparent;border:2px solid #8fcdc1;color:#8fcdc1}"
    html = html + "</style></head><body>"
    html = html + "<img class=""logo"" src=""" + _peLogoDataUri() + """ alt=""SelectaVue"">"
    html = html + "<h2>" + safeTitle + "</h2>"
    html = html + "<p class=""msg"">" + safeMsg + "</p>"
    html = html + "<a class=""btn"" href=""/error-ok"">OK</a>"
    if m.top.errorShowBack then html = html + "<a class=""btn secondary"" href=""/error-back"">Back</a>"
    html = html + "</body></html>"
    return html
end function

' Auto-advances back to "/" once the TV clears errorTitle.
function _peErrorDismissedPage() as String
    html = "<!DOCTYPE html><html><head><meta name=""viewport"" content=""width=device-width, initial-scale=1"">"
    html = html + "<meta http-equiv=""refresh"" content=""1;url=/"">"
    html = html + "<title>SelectaVue</title><style>"
    html = html + "body{background:#024c48;color:#e8f5f3;font-family:sans-serif;text-align:center;padding:24px}"
    html = html + "</style></head><body></body></html>"
    return html
end function

function _peEntryPage() as String
    safeText  = _peHtmlEscape(m.top.initialText)
    safeTitle = _peHtmlEscape(m.top.pageTitle)
    safeInstr = _peHtmlEscape(m.top.pageInstructions)
    safeSend  = _peHtmlEscape(m.top.sendLabel)

    html = "<!DOCTYPE html><html><head><meta name=""viewport"" content=""width=device-width, initial-scale=1"">"
    html = html + "<title>SelectaVue</title><style>"
    html = html + "body{background:#024c48;color:#e8f5f3;font-family:sans-serif;text-align:center;padding:24px}"
    html = html + "img.logo{max-width:220px;margin-bottom:8px}"
    html = html + "h2{color:#8fcdc1;margin:4px 0}"
    html = html + "p.instr{color:#e8f5f3;font-size:15px;margin:4px 0 20px}"
    html = html + "input{width:90%;font-size:20px;padding:12px;border-radius:6px;border:2px solid #8fcdc1;margin-top:8px}"
    html = html + "button{width:90%;font-size:20px;padding:14px;margin-top:16px;background:#8fcdc1;color:#024c48;border:none;border-radius:6px;font-weight:bold}"
    html = html + "</style></head><body>"
    html = html + "<img class=""logo"" src=""" + _peLogoDataUri() + """ alt=""SelectaVue"">"
    if safeTitle <> "" then html = html + "<h2>" + safeTitle + "</h2>"
    if safeInstr <> "" then html = html + "<p class=""instr"">" + safeInstr + "</p>"
    html = html + "<form method=""get"" action=""/submit"">"
    html = html + "<input name=""text"" value=""" + safeText + """ autofocus autocapitalize=""off"" autocorrect=""off"">"
    html = html + "<button type=""submit"">" + safeSend + "</button>"
    html = html + "</form></body></html>"
    return html
end function

' Brief confirmation, auto-advances back to "/" -- picks up the TV's next step.
function _peSentPage() as String
    html = "<!DOCTYPE html><html><head><meta name=""viewport"" content=""width=device-width, initial-scale=1"">"
    html = html + "<meta http-equiv=""refresh"" content=""1;url=/"">"
    html = html + "<title>SelectaVue</title><style>"
    html = html + "body{background:#024c48;color:#e8f5f3;font-family:sans-serif;text-align:center;padding:24px}"
    html = html + "img.logo{max-width:220px;margin-bottom:8px}"
    html = html + "h2{color:#8fcdc1}"
    html = html + "</style></head><body>"
    html = html + "<img class=""logo"" src=""" + _peLogoDataUri() + """ alt=""SelectaVue"">"
    html = html + "<h2>Sent</h2>"
    html = html + "</body></html>"
    return html
end function

' Shown once the TV is done with the flow -- set right before the server stops
' so a pending refresh from _peSentPage() lands here, not on a dead server.
function _peDonePage() as String
    safeMsg = _peHtmlEscape(m.top.doneMessage)
    html = "<!DOCTYPE html><html><head><meta name=""viewport"" content=""width=device-width, initial-scale=1"">"
    html = html + "<title>SelectaVue</title><style>"
    html = html + "body{background:#024c48;color:#e8f5f3;font-family:sans-serif;text-align:center;padding:24px}"
    html = html + "img.logo{max-width:220px;margin-bottom:8px}"
    html = html + "h2{color:#8fcdc1;margin:4px 0}"
    html = html + "p.msg{color:#e8f5f3;font-size:16px;margin:8px 0 24px}"
    html = html + "</style></head><body>"
    html = html + "<img class=""logo"" src=""" + _peLogoDataUri() + """ alt=""SelectaVue"">"
    html = html + "<h2>All set!</h2>"
    if safeMsg <> "" then html = html + "<p class=""msg"">" + safeMsg + "</p>"
    html = html + "</body></html>"
    return html
end function
