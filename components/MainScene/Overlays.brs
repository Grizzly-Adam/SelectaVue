' ==================== Overlays.brs ====================
' Manages every visual overlay that sits on top of the main UI:
'   - Channel info banner + clock
'   - Error overlays (preview & fullscreen)
'   - Mute indicator
'   - Buffer progress bar
'   - Grid decorations (VideoClipLeft, TV frame, mute hint, channel name)
'   - Screensaver shade

' ---------- Channel info banner ----------

sub showChannelInfo(channel as Object)
    if m.channelInfoOverlay = invalid or m.channelInfoLabel = invalid then return

    channelNumber  = (m.currentChannelIndex + 1).ToStr()
    totalChannels  = m.flatChannelList.Count().ToStr()
    m.channelInfoLabel.text = channelNumber + "/" + totalChannels + " - " + channel.title
    showClock()
    m.channelInfoOverlay.visible = true

    if m.channelInfoTimer <> invalid then m.channelInfoTimer.control = "stop"

    m.channelInfoTimer = CreateObject("roSGNode", "Timer")
    m.channelInfoTimer.duration = 3
    m.channelInfoTimer.repeat   = false
    m.channelInfoTimer.ObserveField("fire", "hideChannelInfo")
    m.channelInfoTimer.control  = "start"
end sub

sub showChannelInfoPersistent(channel as Object)
    if m.channelInfoOverlay = invalid or m.channelInfoLabel = invalid then return
    if m.channelInfoTimer <> invalid then
        m.channelInfoTimer.control = "stop"
        m.channelInfoTimer = invalid
    end if
    channelNumber = (m.currentChannelIndex + 1).ToStr()
    totalChannels = m.flatChannelList.Count().ToStr()
    m.channelInfoLabel.text = channelNumber + "/" + totalChannels + " - " + channel.title
    showClock()
    m.channelInfoOverlay.visible = true
end sub

sub showChannelInfoMessage(message as String)
    if m.channelInfoOverlay = invalid or m.channelInfoLabel = invalid then return
    m.channelInfoLabel.text = message
    showClock()
    m.channelInfoOverlay.visible = true

    if m.channelInfoTimer <> invalid then m.channelInfoTimer.control = "stop"

    m.channelInfoTimer = CreateObject("roSGNode", "Timer")
    m.channelInfoTimer.duration = 2
    m.channelInfoTimer.repeat   = false
    m.channelInfoTimer.ObserveField("fire", "hideChannelInfo")
    m.channelInfoTimer.control  = "start"
end sub

sub hideChannelInfo()
    if m.channelInfoOverlay <> invalid then m.channelInfoOverlay.visible = false
    if m.clockLabel <> invalid then m.clockLabel.text = ""
end sub

sub showClock()
    if m.clockLabel = invalid then return
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    hours   = dt.GetHours()
    minutes = dt.GetMinutes()
    ampm = "AM"
    if hours >= 12 then
        ampm = "PM"
        if hours > 12 then hours = hours - 12
    end if
    if hours = 0 then hours = 12
    minStr = minutes.ToStr()
    if minutes < 10 then minStr = "0" + minStr
    m.clockLabel.text = hours.ToStr() + ":" + minStr + " " + ampm
end sub

' ---------- Error overlays ----------

sub showChannelError(errorMsg as String)
    friendlyMsg = getFriendlyError(errorMsg)

    m.lastErrorMsg          = friendlyMsg
    m.lastErrorChannelIndex = m.currentChannelIndex

    hideBufferBar()
    cancelStallTimer()

    if m.isPlayingVideo then resetFullscreenInactivityTimer() else resetGridInactivityTimer()

    if m.isPlayingVideo then
        showFullscreenError(friendlyMsg)
    else
        showPreviewError(friendlyMsg)
        showErrorOverlay(errorMsg)
    end if
end sub

sub showFullscreenError(friendlyMsg as String)
    if m.fullscreenFailContainer = invalid then return
    channel     = m.flatChannelList[m.currentChannelIndex]
    channelName = "Unknown Channel"
    if channel <> invalid and channel.title <> invalid then channelName = channel.title
    channelNum = (m.currentChannelIndex + 1).ToStr() + "/" + m.flatChannelList.Count().ToStr()
    if m.fullscreenFailChannel <> invalid then m.fullscreenFailChannel.text = channelNum + "  -  " + channelName
    if m.fullscreenFailLabel   <> invalid then m.fullscreenFailLabel.text   = friendlyMsg
    m.fullscreenFailContainer.visible = true
end sub

sub showPreviewError(friendlyMsg as String)
    if m.previewErrorContainer = invalid then return
    m.previewErrorContainer.visible = true
end sub

sub hidePreviewError()
    if m.previewErrorContainer <> invalid then m.previewErrorContainer.visible = false
end sub

sub showErrorOverlay(errorMsg as String)
    if m.errorOverlay = invalid then return

    channel     = m.flatChannelList[m.currentChannelIndex]
    channelName = "Unknown Channel"
    channelNum  = (m.currentChannelIndex + 1).ToStr() + "/" + m.flatChannelList.Count().ToStr()
    if channel <> invalid and channel.title <> invalid then channelName = channel.title

    if m.errorTitleLabel   <> invalid then m.errorTitleLabel.text   = "Channel Unavailable"
    if m.errorChannelLabel <> invalid then m.errorChannelLabel.text = channelNum + "  -  " + channelName
    if m.errorMessageLabel <> invalid then
        if m.lastErrorMsg <> "" and m.lastErrorChannelIndex = m.currentChannelIndex then
            m.errorMessageLabel.text = m.lastErrorMsg
        else
            m.errorMessageLabel.text = getFriendlyError(errorMsg)
        end if
    end if

    m.errorOverlay.visible = true
    m.errorVisible         = true
    if m.focusTrap <> invalid then m.focusTrap.SetFocus(true)
end sub

sub hideErrorOverlay()
    if m.errorOverlay <> invalid then m.errorOverlay.visible = false
    m.errorVisible = false
end sub

' ---------- Mute indicator ----------

sub showMuteIndicator()
    if m.muteIndicatorContainer = invalid or m.muteIndicatorImage = invalid then return

    m.muteIndicatorImage.uri = iif(m.previewMuted, "pkg:/images/muteon.png", "pkg:/images/muteoff.png")
    m.muteIndicatorContainer.visible = true

    if m.muteIndicatorTimer <> invalid then
        m.muteIndicatorTimer.control = "stop"
        m.muteIndicatorTimer.unobserveField("fire")
    end if

    m.muteIndicatorTimer = CreateObject("roSGNode", "Timer")
    m.muteIndicatorTimer.duration = 2
    m.muteIndicatorTimer.repeat   = false
    m.muteIndicatorTimer.ObserveField("fire", "hideMuteIndicator")
    m.muteIndicatorTimer.control  = "start"
end sub

sub hideMuteIndicator()
    if m.muteIndicatorContainer <> invalid then m.muteIndicatorContainer.visible = false
end sub

' ---------- Buffer progress bar ----------

sub onBufferingStatus()
    status = m.previewVideo.bufferingStatus
    if status = invalid then return

    pct = 0
    if status.percentage <> invalid then pct = status.percentage

    if not m.bufferVisible and pct < 100 then
        if m.bufferDelayTimer = invalid then
            m.bufferDelayTimer = CreateObject("roSGNode", "Timer")
            m.bufferDelayTimer.duration = 1.0
            m.bufferDelayTimer.repeat   = false
            m.bufferDelayTimer.ObserveField("fire", "showBufferBar")
            m.bufferDelayTimer.control  = "start"
        end if
    end if

    if m.bufferVisible then updateBufferBar(pct)

    ' Stall detection
    if pct <> m.lastBufferPct and pct < 100 then
        m.lastBufferPct = pct
        if m.stallTimer <> invalid then
            m.stallTimer.control = "stop"
            m.stallTimer.unobserveField("fire")
            m.stallTimer = invalid
        end if
        m.stallTimer = CreateObject("roSGNode", "Timer")
        m.stallTimer.duration = 5.0
        m.stallTimer.repeat   = false
        m.stallTimer.ObserveField("fire", "onBufferStall")
        m.stallTimer.control  = "start"
    end if

    if pct >= 100 then
        hideBufferBar()
        cancelStallTimer()
    end if
end sub

sub showBufferBar()
    if m.bufferDelayTimer <> invalid then
        m.bufferDelayTimer.unobserveField("fire")
        m.bufferDelayTimer = invalid
    end if

    if m.previewVideo.state <> "buffering" then return

    if m.isPlayingVideo then
        ' Fullscreen - centred near bottom
        m.bufferContainer.translation = [560, 980]
        m.bufferContainer.width       = 800
        m.bufferTrack.width           = 794
        m.bufferLabel.width           = 800
    else
        ' Grid - centred over preview area
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
    if m.bufferDelayTimer <> invalid then
        m.bufferDelayTimer.control = "stop"
        m.bufferDelayTimer.unobserveField("fire")
        m.bufferDelayTimer = invalid
    end if
    if m.bufferContainer <> invalid then m.bufferContainer.visible = false
    if m.bufferFill      <> invalid then m.bufferFill.width        = 0
    if m.bufferLabel     <> invalid then m.bufferLabel.text        = ""
    m.bufferVisible = false
end sub

' ---------- Grid decoration overlays ----------

sub showGridOverlays()
    if m.videoClipLeft             <> invalid then m.videoClipLeft.visible             = true
    if m.muteHintContainer         <> invalid then m.muteHintContainer.visible         = true
    if m.tvOverlay                 <> invalid then m.tvOverlay.visible                 = true
    if m.previewChannelNameContainer <> invalid then m.previewChannelNameContainer.visible = true
    if m.lastErrorMsg <> "" and m.lastErrorChannelIndex = m.currentChannelIndex then
        showPreviewError(m.lastErrorMsg)
    end if
    m.playlistPanelActive = false
    m.channelList.SetFocus(true)
end sub

sub hideGridOverlays()
    if m.videoClipLeft             <> invalid then m.videoClipLeft.visible             = false
    if m.muteHintContainer         <> invalid then m.muteHintContainer.visible         = false
    if m.tvOverlay                 <> invalid then m.tvOverlay.visible                 = false
    if m.previewChannelNameContainer <> invalid then m.previewChannelNameContainer.visible = false
    hidePreviewError()
end sub

sub hideOverlay()
    m.channelOverlay.visible = false
    m.overlayVisible         = false
    m.channelOverlayList.setFocus(false)
    m.top.setFocus(true)
    if m.overlayInactivityTimer <> invalid then
        m.overlayInactivityTimer.control = "stop"
        m.overlayInactivityTimer.unobserveField("fire")
        m.overlayInactivityTimer = invalid
    end if
end sub

sub updatePreviewHint()
    if m.previewHintLabel = invalid then return
    m.previewHintLabel.text = iif(m.previewMuted, "Press RIGHT to unmute", "Press RIGHT to mute")
end sub

' ---------- Inline ternary helper (BrightScript lacks one) ----------
function iif(condition as Boolean, trueVal as Dynamic, falseVal as Dynamic) as Dynamic
    if condition then return trueVal
    return falseVal
end function
