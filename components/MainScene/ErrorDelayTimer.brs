' ==================== ErrorDelayTimer.brs ====================
' Short pause before calling retryStream() on a clean (non-stall) error,
' giving transient server drops a chance to recover before escalating
' through the retry ladder.

' ---------- Error delay timer ----------
' Short pause before calling retryStream() on a clean error,
' giving transient server drops a chance to recover.

sub startErrorDelayTimer()
    ' 1.5s pause before escalating to next retry step — long enough to let
    ' transient server hiccups settle, short enough not to frustrate the user.
    ' Old value was 4s which added 36s of dead time across a full ladder run.
    _startNamedTimer("errorDelayTimer", 1.5, false, "onErrorDelayFired")
end sub

sub onErrorDelayFired()
    m.errorDelayTimer = invalid
    ' If the user cancelled while this timer was in flight, drop it
    if m.reconnectState = "gaveup" then return
    if m.loadingChannelIndex < 0 then return
    deviceInfo = CreateObject("roDeviceInfo")
    if deviceInfo.GetConnectionType() = "none" then
        print ">>> ERROR DELAY: Network is down"
        _enterNetworkWait()
    else
        retryStream(m.savedErrorMsg)
    end if
end sub
