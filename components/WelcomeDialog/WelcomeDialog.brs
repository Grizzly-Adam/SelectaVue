' ==================== WelcomeDialog.brs ====================
' First-run welcome dialog. The two "SelectaVue" mentions render bold/
' bright-white inline with normal text -- no native rich-text support on
' Label, so each segment is its own Label at a hardcoded x (tune directly
' if spacing looks off; text-width measurement isn't available on this
' thread).

sub init()
    m.border       = m.top.findNode("wdBorder")
    m.textArea     = m.top.findNode("wdTextArea")
    m.nextBtn      = m.top.findNode("wdNextBtn")
    m.nextBtnLabel = m.top.findNode("wdNextBtnLabel")

    _wdBuildContent()
end sub

' One line made of adjacent segments (e.g. normal + bold + normal). Each
' segment gives its own x position directly -- tune these numbers by hand
' if the spacing looks off, no formula involved.
sub _wdAddInlineRow(y as Integer, segments as Object)
    if m.textArea = invalid then return
    for each seg in segments
        lbl = CreateObject("roSGNode", "Label")
        lbl.translation = [seg.x, y]
        lbl.width       = 1634 - seg.x
        lbl.height      = 44
        lbl.vertAlign   = "center"
        lbl.text        = seg.text
        if seg.bold then
            lbl.font  = "font:MediumBoldSystemFont"
            lbl.color = "0xFFFFFFFF"   ' bright white -- stands out from the rest of the paragraph
        else
            lbl.font  = "font:MediumSystemFont"
            lbl.color = "0xE8F5F3FF"
        end if
        m.textArea.appendChild(lbl)
    end for
end sub

' A full-width paragraph line, wraps if it runs long. Centered per Adam's request.
sub _wdAddWrappedRow(y as Integer, text as String, height as Integer, color = "0xE8F5F3FF" as String)
    if m.textArea = invalid then return
    lbl = CreateObject("roSGNode", "Label")
    lbl.translation = [0, y]
    lbl.width       = 1634
    lbl.height      = height
    lbl.wrap        = true
    lbl.horizAlign  = "center"
    lbl.font        = "font:MediumSystemFont"
    lbl.color       = color
    lbl.text        = text
    m.textArea.appendChild(lbl)
end sub

sub _wdBuildContent()
    _wdAddInlineRow(0, [
        { text: "Thank you for choosing ", bold: false, x: 350 },
        { text: "SelectaVue", bold: true, x: 740 },
        { text: ", the TV of the future!", bold: false, x: 927 }
    ])
    _wdAddInlineRow(60, [
        { text: "SelectaVue", bold: true, x: 346 },
        { text: " plays live TV from M3U playlists that you provide.", bold: false, x: 532 }
    ])
    _wdAddWrappedRow(150, "Add any IPTV playlist you already have access to, and watch it right here.", 70)
    _wdAddWrappedRow(200, "To get started, you'll add your first playlist next.", 70)
    _wdAddWrappedRow(250, "If you don't have one handy, try one of these free channel lists:", 70)
    _wdAddWrappedRow(320, "United States: https://iptv-org.github.io/iptv/countries/us.m3u", 40, "0x8fcdc1FF")
    _wdAddWrappedRow(380, "Canada: https://iptv-org.github.io/iptv/countries/ca.m3u", 40, "0x8fcdc1FF")
    _wdAddWrappedRow(440, "Australia: https://iptv-org.github.io/iptv/countries/au.m3u", 40, "0x8fcdc1FF")
    _wdAddWrappedRow(500, "United Kingdom: https://iptv-org.github.io/iptv/countries/uk.m3u", 40, "0x8fcdc1FF")
end sub

sub onShowChanged()
    if m.top.show then
        if m.border <> invalid then m.border.visible = true
        m.top.visible = true
        m.top.SetFocus(true)
    else
        if m.border <> invalid then m.border.visible = false
        m.top.visible = false
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "OK" or key = "back" then
        m.top.dismissed = true
        return true
    end if
    return true
end function
