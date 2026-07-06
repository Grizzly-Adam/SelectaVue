' ==================== SessionRefreshTimer.brs ====================
' Session-token stream refresh: fires 2s after each patched play, re-running
' the ManifestPatcher so segment URLs never expire mid-playback. See
' ManifestPatcher/ for the patching logic itself.

sub startSessionRefreshTimer()
    _startNamedTimer("sessionRefreshTimer", 2.0, false, "onSessionRefreshFired")
end sub

sub cancelSessionRefreshTimer()
    _cancelNamedTimer("sessionRefreshTimer")
end sub

sub onSessionRefreshFired()
    m.sessionRefreshTimer = invalid
    if not m.sessionTokenStream then return
    state = m.previewVideo.state
    ' For direct MP4 clips: allow swap on playing, buffering, or finished
    ' For HLS live: only swap while playing (buffering reset is unrecoverable)
    allowSwap = (state = "playing")
    if not allowSwap then
        print ">>> SESSION REFRESH: Deferring swap (state="; state; ") -- restarting timer"
        startSessionRefreshTimer()
        return
    end if
    channel = invalid
    if m.flatChannelList <> invalid and m.loadingChannelIndex >= 0 and m.loadingChannelIndex < m.flatChannelList.Count() then
        channel = m.flatChannelList[m.loadingChannelIndex]
    end if
    if m.sessionRefreshUrl = invalid or m.sessionRefreshUrl = "" then return
    ' sessionSlot is already set to the NEXT slot by onManifestPatched after each play.
    ' Just patch using it directly -- no toggle here.
    print ">>> SESSION REFRESH: Re-patching to slot "; m.manifestPatcher.sessionSlot; " (state="; state; ")"
    if m.manifestPatcher <> invalid then
        headers = _resolveHeaders(channel)
        m.manifestPatcher.url       = m.sessionRefreshUrl
        m.manifestPatcher.userAgent = headers.ua
        m.manifestPatcher.referrer  = headers.ref
        m.manifestPatcher.control   = "RUN"
    end if
end sub
