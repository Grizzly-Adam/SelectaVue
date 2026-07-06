' ==================== ErrorDelayTimer.brs ====================
' Short pause before calling retryStream() on a clean (non-stall) error,
' giving transient server drops a chance to recover before escalating
' through the retry ladder.

' ---------- Error delay timer ----------
' Short pause before calling retryStream() on a clean error,
' giving transient server drops a chance to recover.

sub startErrorDelayTimer()
    _startNamedTimer("errorDelayTimer", 4.0, false, "onErrorDelayFired")
end sub

sub onErrorDelayFired()
    m.errorDelayTimer = invalid
    deviceInfo = CreateObject("roDeviceInfo")
    if deviceInfo.GetConnectionType() = "none" then
        print ">>> ERROR DELAY: Network is down"
        _enterNetworkWait()
    else
        retryStream(m.savedErrorMsg)
    end if
end sub
