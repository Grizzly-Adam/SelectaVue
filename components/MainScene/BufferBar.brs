' ==================== BufferBar.brs ====================
' Buffer progress bar display, stall detection, slow-buffer step-down,
'  and the bufferingStatus observer.

' ---------- Buffer progress bar + stall/slow-buffer detection ----------

sub onBufferingStatus()
    status = m.previewVideo.bufferingStatus
    if status = invalid then return
    pct = 0
    if status.percentage <> invalid then pct = status.percentage
    underrun = "?"
    if status.isUnderrun <> invalid then underrun = status.isUnderrun.ToStr()
    print ">>> BUFFER: "; pct; "% (t="; _loadElapsedMs(); "ms, isUnderrun="; underrun; ")"

    if not m.bufferVisible and pct < 100 then
        if m.bufferDelayTimer = invalid then
            _startNamedTimer("bufferDelayTimer", 1.0, false, "showBufferBar")
        end if
    end if

    if m.bufferVisible then updateBufferBar(pct)

    ' Hard stall detection — reset 20s timer when buffer moves
    if pct <> m.lastBufferPct and pct < 100 then
        m.lastBufferPct = pct
        _startNamedTimer("stallTimer", 20.0, false, "onBufferStall")
    end if

    ' Soft step-down — sustained low buffer.
    ' Avoid creating roDateTime objects when not needed (called at high frequency).
    if pct > 0 and pct < 50 and m.previewVideo.state = "buffering" then
        if m.slowBufferStartTime = invalid then
            m.slowBufferStartTime = CreateObject("roDateTime")
        else
            now     = CreateObject("roDateTime")   ' only created when timer is running
            elapsed = now.AsSeconds() - m.slowBufferStartTime.AsSeconds()
            if elapsed >= 15 then
                m.slowBufferStartTime = CreateObject("roDateTime")
                _softStepDown()
            end if
        end if
    else
        if pct >= 50 then m.slowBufferStartTime = invalid
    end if

    if pct >= 100 then
        hideBufferBar()
        cancelStallTimer()
        cancelChannelLoadBufferTimer()
        m.slowBufferStartTime = invalid
    end if
end sub

sub _softStepDown()
    if m.softStepCount >= 4 then return
    bandwidths = [3000000, 2000000, 1500000, 1000000]
    bw = bandwidths[m.softStepCount]
    m.softStepCount = m.softStepCount + 1
    print ">>> SOFT STEP-DOWN "; m.softStepCount; ": maxBandwidth = "; bw; " (t="; _loadElapsedMs(); "ms)"
    ' Store the cap — it will be applied on the next content node creation
    ' Do NOT reassign m.previewVideo.content to itself — that triggers
    ' SceneGraph observers and restarts the video node unexpectedly
    m.softStepBandwidth = bw
end sub

sub showBufferBar()
    _cancelNamedTimer("bufferDelayTimer")
    ' Don't show (or re-show) the buffer bar while the retry dialog is up --
    ' retries keep the video node buffering in the background the whole
    ' time, which would otherwise pop the bar right back up a second later
    ' via the delay timer below, on top of (or behind) the reconnect overlay.
    if m.reconnectOverlay <> invalid and m.reconnectOverlay.visible then return
    ' Show whenever the channel isn't fully playing yet, rather than
    ' requiring the video node to already be in "buffering" state
    ' specifically — the 3s channel-load timer can fire before the video
    ' even reaches that state, and we still want to show 0% at that point.
    if m.previewVideo.state = "playing" then return
    if m.isPlayingVideo then
        ' Sits above the channel bar's background (which now starts at
        ' y=820) so the two never overlap while both are visible.
        m.bufferContainer.translation = [560, 760]
        m.bufferContainer.width       = 800
        m.bufferTrack.width           = 794
        m.bufferLabel.width           = 800
    else
        m.bufferContainer.translation = [1467, 252]
        m.bufferContainer.width       = 283
        m.bufferTrack.width           = 277
        m.bufferLabel.width           = 283
    end if
    m.bufferContainer.visible = true
    m.bufferVisible           = true
    status = m.previewVideo.bufferingStatus
    if status <> invalid and status.percentage <> invalid then
        updateBufferBar(status.percentage)
    else
        updateBufferBar(0)
    end if
end sub

sub updateBufferBar(pct as Integer)
    if m.bufferFill = invalid or m.bufferLabel = invalid then return
    trackWidth = m.bufferTrack.width
    fillWidth  = Int(trackWidth * pct / 100)
    if fillWidth < 0 then fillWidth = 0
    if fillWidth > trackWidth then fillWidth = trackWidth
    m.bufferFill.width = fillWidth
    m.bufferLabel.text = pct.ToStr() + "%"
end sub

sub hideBufferBar()
    _cancelNamedTimer("bufferDelayTimer")
    if m.bufferContainer <> invalid then m.bufferContainer.visible = false
    if m.bufferFill      <> invalid then m.bufferFill.width        = 0
    if m.bufferLabel     <> invalid then m.bufferLabel.text        = ""
    m.bufferVisible = false
end sub
