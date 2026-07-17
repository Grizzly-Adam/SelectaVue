sub Main(args as Dynamic)
    reg = CreateObject("roRegistrySection", "profile")
    if reg.Exists("primaryfeed") then
        url = reg.Read("primaryfeed")
    else
        url = "https://www.m3u.cl/lista/CO.m3u"
    end if

    ' Resolve launch deep link args before CreateScene so init() can
    ' read them synchronously — avoids the render-thread observer race
    ' that caused deep links to be missed on launch.
    launchArgs = invalid
    if args <> invalid and type(args) = "roAssociativeArray" and args.Count() > 0 then
        launchArgs = args
        print ">>> DEEPLINK: Main(args)="; FormatJson(args)
    else
        appInfo = CreateObject("roAppInfo")
        if appInfo <> invalid then
            fallback = appInfo.GetArgs()
            if fallback <> invalid and type(fallback) = "roAssociativeArray" and fallback.Count() > 0 then
                launchArgs = fallback
                print ">>> DEEPLINK: GetArgs()="; FormatJson(fallback)
            end if
        end if
    end if

    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)
    ' Required to receive roInputEvent at all — the ECP /input command (used
    ' to deep link into an already-running app) has nothing to deliver to
    ' without a dedicated roInput object on this same port. supports_input_launch=1
    ' in the manifest alone isn't enough; this is the other half of it.
    m.input = CreateObject("roInput")
    m.input.SetMessagePort(m.port)
    m.global = screen.getGlobalNode()
    _setupMemoryMonitor()
    ' Set deepLinkArgs BEFORE CreateScene so init() reads it synchronously.
    ' Runtime deep links (roInputEvent) use the observer path instead.
    m.global.addFields({ feedurl: url, deepLinkArgs: launchArgs })
    scene = screen.CreateScene("MainScene")
    screen.show()

    while true
        msg = wait(0, m.port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent" then
            if msg.isScreenClosed() then return
        else if msgType = "roInputEvent" then
            if msg.IsInput() then
                info = msg.GetInfo()
                if info <> invalid then
                    print ">>> DEEPLINK: Runtime input: "; FormatJson(info)
                    m.global.deepLinkArgs = info
                end if
            end if
        else if msgType = "roAppMemoryNotificationEvent" then
            _onMemoryWarning(msg)
        else if msgType = "roDeviceInfoEvent" then
            _onLowGeneralMemory(msg)
        end if
    end while
end sub

' Subscribes to low-memory notifications on the same port the main loop
' already pumps — roAppMemoryMonitor (cgroup-based, more granular: 80/85/
' 90/95% thresholds) where supported, falling back to roDeviceInfo's
' coarser low/normal general-memory-level event on models that don't
' support cgroup memory limits. Mirrors Roku's own reference pattern for
' this exact fallback.
sub _setupMemoryMonitor()
    m.memMonitor = CreateObject("roAppMemoryMonitor")
    if m.memMonitor <> invalid then m.memMonitor.SetMessagePort(m.port)
    if m.memMonitor <> invalid and m.memMonitor.EnableMemoryWarningEvent(true) then
        print ">>> MEMORY: Using roAppMemoryMonitor (cgroup thresholds)"
    else
        print ">>> MEMORY: roAppMemoryMonitor unavailable on this model — falling back to roDeviceInfo"
        m.memMonitor = CreateObject("roDeviceInfo")
        if m.memMonitor <> invalid then
            m.memMonitor.SetMessagePort(m.port)
            m.memMonitor.EnableLowGeneralMemoryEvent(true)
        end if
    end if
end sub

' roAppMemoryNotificationEvent — fires as usage crosses 80/85/90/95% of the
' per-app limit (either direction, throttled by the OS). Logs current
' usage/available/limit for correlating against proxy and retry-ladder
' activity during testing, and forwards a lightweight signal to the scene
' via m.global so MainScene can react (e.g. trim non-essential state) —
' see onMemoryPressure in MainScene.brs.
sub _onMemoryWarning(msg as Object)
    percent = invalid
    info = msg.GetInfo()
    if info <> invalid then percent = info.Lookup("MemoryUsagePercent")
    limitPercent = invalid
    availableKb  = invalid
    limits       = invalid
    if m.memMonitor <> invalid and type(m.memMonitor) = "roAppMemoryMonitor" then
        limitPercent = m.memMonitor.GetMemoryLimitPercent()
        availableKb  = m.memMonitor.GetChannelAvailableMemory()
        limits       = m.memMonitor.GetChannelMemoryLimit()
    end if
    print ">>> MEMORY WARNING: usagePercent="; percent; " limitPercent="; limitPercent; " availableKb="; availableKb; " limits="; FormatJson(limits)
    m.global.addFields({ memoryPressure: { source: "cgroup", percent: percent, limitPercent: limitPercent, availableKb: availableKb } })
end sub

' roDeviceInfoEvent from the roDeviceInfo fallback path (EnableLowGeneralMemoryEvent) —
' coarser signal for models without cgroup-based memory limits.
sub _onLowGeneralMemory(msg as Object)
    if not msg.isStatusMessage() then return
    level = msg.GetInfo().Lookup("generalMemoryLevel")
    print ">>> MEMORY WARNING: generalMemoryLevel="; level
    m.global.addFields({ memoryPressure: { source: "generalMemoryLevel", level: level } })
end sub
