' ==================== Timers.brs ====================
' All inactivity timers and the buffer-stall retry loop.
'
' Timers managed here:
'   gridInactivityTimer       - auto-fullscreen or screensaver after 45s on grid
'   fullscreenInactivityTimer - screensaver shade after 45s fullscreen with error
'   overlayInactivityTimer    - auto-dismiss quick-menu overlay after 10s
'   optionsDialogTimer        - auto-close video options dialog after 30s
'   stallTimer                - detect stuck buffer and retry with lower bitrate

' ---------- Grid inactivity ----------

sub resetGridInactivityTimer()
    if m.isPlayingVideo then return
    if m.gridInactivityTimer <> invalid then
        m.gridInactivityTimer.control = "stop"
        m.gridInactivityTimer.unobserveField("fire")
    end if
    if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = false
    m.gridInactivityTimer = CreateObject("roSGNode", "Timer")
    m.gridInactivityTimer.duration = 45.0
    m.gridInactivityTimer.repeat   = false
    m.gridInactivityTimer.ObserveField("fire", "onGridInactivity")
    m.gridInactivityTimer.control  = "start"
end sub

sub onGridInactivity()
    m.gridInactivityTimer = invalid
    if m.errorVisible then
        if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = true
        return
    end if
    if m.isPlayingVideo then return

    if m.previewVideo.state = "playing" then
        ' Resize preview to fullscreen without reloading the stream
        m.top.backgroundURI = ""
        m.top.backgroundColor = "0x024c48FF"
        m.previewVideo.trickplaybarvisibilityauto = false
        m.previewVideo.translation = [0, 0]
        m.previewVideo.width       = 1920
        m.previewVideo.height      = 1080
        m.channelList.visible      = false
        m.sidePanel.visible        = false
        hideGridOverlays()
        m.isPlayingVideo = true
        m.suppressNextVideoOptionsMenu = true
        startOverlayOkSuppressionTimer()
        m.top.setFocus(true)
        saveLastState()
    else
        if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = true
    end if
end sub

' ---------- Fullscreen inactivity ----------

sub resetFullscreenInactivityTimer()
    if m.fullscreenInactivityTimer <> invalid then
        m.fullscreenInactivityTimer.control = "stop"
        m.fullscreenInactivityTimer.unobserveField("fire")
    end if
    if m.screensaverOverlay <> invalid then m.screensaverOverlay.visible = false
    m.fullscreenInactivityTimer = CreateObject("roSGNode", "Timer")
    m.fullscreenInactivityTimer.duration = 45.0
    m.fullscreenInactivityTimer.repeat   = false
    m.fullscreenInactivityTimer.ObserveField("fire", "onFullscreenInactivity")
    m.fullscreenInactivityTimer.control  = "start"
end sub

sub onFullscreenInactivity()
    m.fullscreenInactivityTimer = invalid
    if m.screensaverOverlay = invalid then return
    ' Only shade when the fullscreen error banner is visible
    if m.fullscreenFailContainer <> invalid and m.fullscreenFailContainer.visible then
        m.screensaverOverlay.visible = true
    end if
end sub

' ---------- Overlay (quick-menu) inactivity ----------

sub resetOverlayInactivityTimer()
    if m.overlayInactivityTimer <> invalid then
        m.overlayInactivityTimer.control = "stop"
        m.overlayInactivityTimer.unobserveField("fire")
    end if
    m.overlayInactivityTimer = CreateObject("roSGNode", "Timer")
    m.overlayInactivityTimer.duration = 10.0
    m.overlayInactivityTimer.repeat   = false
    m.overlayInactivityTimer.ObserveField("fire", "onOverlayInactivity")
    m.overlayInactivityTimer.control  = "start"
end sub

sub onOverlayInactivity()
    m.overlayInactivityTimer = invalid
    if m.overlayVisible then
        hideOverlay()
        if m.isPlayingVideo then
            m.top.setFocus(true)
            resetFullscreenInactivityTimer()
        end if
    end if
end sub

' ---------- Options dialog auto-close ----------

sub resetOptionsDialogTimer()
    if m.optionsDialogTimer <> invalid then
        m.optionsDialogTimer.control = "stop"
        m.optionsDialogTimer.unobserveField("fire")
    end if
    m.optionsDialogTimer = CreateObject("roSGNode", "Timer")
    m.optionsDialogTimer.duration = 30.0
    m.optionsDialogTimer.repeat   = false
    m.optionsDialogTimer.ObserveField("fire", "onOptionsDialogTimeout")
    m.optionsDialogTimer.control  = "start"
end sub

sub onOptionsDialogTimeout()
    m.optionsDialogTimer = invalid
    if m.top.dialog <> invalid then m.top.dialog.close = true
end sub

' ---------- Buffer stall detection & retry ----------

sub cancelStallTimer()
    if m.stallTimer <> invalid then
        m.stallTimer.control = "stop"
        m.stallTimer.unobserveField("fire")
        m.stallTimer = invalid
    end if
end sub

sub onBufferStall()
    m.stallTimer = invalid
    if m.previewVideo.state <> "buffering" then return

    pct    = 0
    status = m.previewVideo.bufferingStatus
    if status <> invalid and status.percentage <> invalid then pct = status.percentage
    if pct >= 100 then return

    print ">>> STALL: Buffer stalled at "; pct; "%, retry count = "; m.stallRetryCount

    content = m.previewVideo.content
    if content = invalid then return

    if m.stallRetryCount = 0 then
        print ">>> STALL: Retrying with MaxBandwidth 2.5 Mbps"
        m.previewVideo.maxBandwidth = 2500000
        m.stallRetryCount = 1
    else if m.stallRetryCount = 1 then
        print ">>> STALL: Retrying with MaxBandwidth 1 Mbps"
        m.previewVideo.maxBandwidth = 1000000
        m.stallRetryCount = 2
    else
        print ">>> STALL: All retries exhausted, showing error"
        hideBufferBar()
        showChannelError("Stream stalled and could not recover. The channel may require more bandwidth than is available.")
        if m.isPlayingVideo then resetFullscreenInactivityTimer() else resetGridInactivityTimer()
        return
    end if

    ' Force reload with the new bandwidth cap
    m.lastBufferPct         = -1
    m.previewVideo.content  = invalid
    m.previewVideo.content  = content
    m.previewVideo.control  = "play"
end sub

' ---------- OK-suppression timer (prevents options menu after channel switch) ----------

sub startOverlayOkSuppressionTimer()
    if m.overlayOkSuppressTimer <> invalid then
        m.overlayOkSuppressTimer.control = "stop"
        m.overlayOkSuppressTimer.unobserveField("fire")
        m.overlayOkSuppressTimer = invalid
    end if
    m.overlayOkSuppressTimer = CreateObject("roSGNode", "Timer")
    m.overlayOkSuppressTimer.duration = 0.5
    m.overlayOkSuppressTimer.repeat   = false
    m.overlayOkSuppressTimer.observeField("fire", "clearOverlayOkSuppression")
    m.overlayOkSuppressTimer.control  = "start"
end sub

sub clearOverlayOkSuppression()
    if m.overlayOkSuppressTimer <> invalid then
        m.overlayOkSuppressTimer.control = "stop"
        m.overlayOkSuppressTimer.unobserveField("fire")
        m.overlayOkSuppressTimer = invalid
    end if
    m.suppressNextVideoOptionsMenu = false
end sub
