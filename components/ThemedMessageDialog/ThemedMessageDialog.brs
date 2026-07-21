' ==================== ThemedMessageDialog.brs ====================
' See ThemedMessageDialog.xml's header comment for the full rationale.

sub init()
    m.border   = m.top.findNode("tmdBorder")
    m.panel    = m.top.findNode("tmdPanel")
    m.titleBox = m.top.findNode("tmdTitleBox")
    m.titleLbl = m.top.findNode("tmdTitleLabel")
    m.msgLbl   = m.top.findNode("tmdMessageLabel")
    m.btnGroup = m.top.findNode("tmdButtonGroup")
    m.focusIndex  = 0
    m.buttonRects = []
    m.buttonRings = []
end sub

sub onShowChanged()
    if m.top.show then
        _tmdOpen()
    else
        _tmdClose()
    end if
end sub

' Margins/reserved space match the established WelcomeDialog/PhoneKeyboardDialog
' panel conventions: 32px content margin, 6px border thickness.
sub _tmdOpen()
    m.top.buttonSelected = -1
    w = m.top.dialogWidth
    h = m.top.dialogHeight

    m.border.width        = w
    m.border.height       = h
    m.border.translation  = [(1920 - w) / 2, (1080 - h) / 2]
    m.panel.width         = w - 12
    m.panel.height        = h - 12

    ' Title bar runs the full panel width (left border to right border),
    ' text centered within it.
    m.titleBox.width = w - 12
    m.titleLbl.width = w - 12
    m.titleLbl.text  = m.top.dialogTitle

    contentWidth = w - 12 - 64   ' 32px margin each side (message/buttons only)
    buttonRowY      = h - 12 - 96   ' 96px reserved for button row + bottom margin
    m.msgLbl.text      = m.top.message
    m.msgLbl.width     = contentWidth
    m.msgLbl.height    = buttonRowY - 104
    m.msgLbl.horizAlign = m.top.messageAlign

    _tmdBuildButtons(contentWidth, buttonRowY)
    m.focusIndex = 0
    _tmdRefreshFocus()

    m.border.visible = true
    m.top.visible    = true
    m.top.SetFocus(true)
end sub

sub _tmdClose()
    m.border.visible = false
    m.top.visible    = false
end sub

' Builds 1-2 buttons side by side, equal width, using the established
' border/fill/label pattern (WelcomeDialog's Next button) -- white border
' shown only for the focused button, fill/label always visible as siblings
' of the border (NOT children of it -- a hidden parent hides its whole
' subtree, which would wipe out every unfocused button entirely).
sub _tmdBuildButtons(contentWidth as Integer, y as Integer)
    m.btnGroup.removeChildren(m.btnGroup.getChildren(-1, 0))
    m.buttonRects = []
    m.buttonRings = []

    labels = m.top.buttons
    count  = labels.Count()
    if count = 0 then return

    gap    = 24
    btnW   = Int((contentWidth - (count - 1) * gap) / count)
    btnH   = 64
    x      = 32

    for i = 0 to count - 1
        border = CreateObject("roSGNode", "Rectangle")
        border.translation = [x, y]
        border.width        = btnW
        border.height        = btnH
        border.color         = "0xFFFFFFFF"
        border.visible        = false
        m.btnGroup.appendChild(border)   ' appended first -- renders behind the fill

        fill = CreateObject("roSGNode", "Rectangle")
        fill.translation = [x + 4, y + 4]
        fill.width        = btnW - 8
        fill.height        = btnH - 8
        fill.color         = "0x5A8A82FF"

        label = CreateObject("roSGNode", "Label")
        label.width      = btnW - 8
        label.height     = btnH - 8
        label.horizAlign = "center"
        label.vertAlign  = "center"
        label.font       = "font:MediumBoldSystemFont"
        label.color      = "0xE8F5F3FF"
        label.text       = UCase(labels[i])

        fill.appendChild(label)
        m.btnGroup.appendChild(fill)
        m.buttonRects.Push(border)

        x = x + btnW + gap
    end for
end sub

sub _tmdRefreshFocus()
    for i = 0 to m.buttonRects.Count() - 1
        m.buttonRects[i].visible = (i = m.focusIndex)
    end for
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    count = m.buttonRects.Count()
    if count = 0 then return true

    if key = "left" then
        if m.focusIndex > 0 then
            m.focusIndex = m.focusIndex - 1
            _tmdRefreshFocus()
        end if
        return true
    else if key = "right" then
        if m.focusIndex < count - 1 then
            m.focusIndex = m.focusIndex + 1
            _tmdRefreshFocus()
        end if
        return true
    else if key = "OK" then
        m.top.buttonSelected = m.focusIndex
        return true
    else if key = "back" then
        ' Last button is always Cancel/Back/OK-alone -- same semantic as
        ' pressing it directly.
        m.top.buttonSelected = count - 1
        return true
    end if
    return true   ' swallow everything else -- this dialog owns all input while up
end function
