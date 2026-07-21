' ==================== ThemedMenuDialog.brs ====================
' See ThemedMenuDialog.xml's header comment for the full rationale.

sub init()
    m.border    = m.top.findNode("tmnBorder")
    m.panel     = m.top.findNode("tmnPanel")
    m.titleBox  = m.top.findNode("tmnTitleBox")
    m.titleLbl  = m.top.findNode("tmnTitleLabel")
    m.btnGroup  = m.top.findNode("tmnButtonGroup")
    m.focusIndex  = 0
    m.buttonRects = []
end sub

sub onShowChanged()
    if m.top.show then
        _tmnOpen()
    else
        _tmnClose()
    end if
end sub

' Margins match ThemedMessageDialog: 32px content margin, 6px border
' thickness, 80px title bar. Panel height is derived from the button count
' -- 104px from the top to the first button row, 64px per button + 16px gap
' between, 24px bottom margin.
sub _tmnOpen()
    m.top.buttonSelected = -1
    labels = m.top.buttons
    count  = labels.Count()

    rowH = 64
    gap  = 16
    h    = 12 + 104 + count * rowH + (count - 1) * gap + 24
    if count = 0 then h = 12 + 104 + 24
    w = m.top.dialogWidth

    m.border.width       = w
    m.border.height      = h
    m.border.translation = [(1920 - w) / 2, (1080 - h) / 2]
    m.panel.width        = w - 12
    m.panel.height       = h - 12

    ' Title bar runs the full panel width (left border to right border),
    ' text centered within it.
    m.titleBox.width = w - 12
    m.titleLbl.width = w - 12
    m.titleLbl.text  = m.top.dialogTitle

    contentWidth = w - 12 - 64   ' 32px margin each side (buttons only)
    _tmnBuildButtons(contentWidth, rowH, gap)
    m.focusIndex = 0
    _tmnRefreshFocus()

    m.border.visible = true
    m.top.visible    = true
    m.top.SetFocus(true)
end sub

sub _tmnClose()
    m.border.visible = false
    m.top.visible    = false
end sub

' Builds one full-width button per row, stacked vertically, using the
' established border/fill/label pattern (WelcomeDialog's Next button) --
' white border shown only for the focused row, fill/label always visible
' as siblings of the border (NOT children of it -- a hidden parent hides
' its whole subtree, which would wipe out every unfocused button entirely).
sub _tmnBuildButtons(contentWidth as Integer, rowH as Integer, gap as Integer)
    m.btnGroup.removeChildren(m.btnGroup.getChildren(-1, 0))
    m.buttonRects = []

    labels = m.top.buttons
    y = 104
    for i = 0 to labels.Count() - 1
        border = CreateObject("roSGNode", "Rectangle")
        border.translation = [32, y]
        border.width         = contentWidth
        border.height         = rowH
        border.color          = "0xFFFFFFFF"
        border.visible         = false
        m.btnGroup.appendChild(border)   ' appended first -- renders behind the fill

        fill = CreateObject("roSGNode", "Rectangle")
        fill.translation = [32 + 4, y + 4]
        fill.width         = contentWidth - 8
        fill.height         = rowH - 8
        fill.color          = "0x5A8A82FF"

        label = CreateObject("roSGNode", "Label")
        label.width      = contentWidth - 8
        label.height     = rowH - 8
        label.horizAlign = "center"
        label.vertAlign  = "center"
        label.font       = "font:MediumBoldSystemFont"
        label.color      = "0xE8F5F3FF"
        label.text       = UCase(labels[i])

        fill.appendChild(label)
        m.btnGroup.appendChild(fill)
        m.buttonRects.Push(border)

        y = y + rowH + gap
    end for
end sub

sub _tmnRefreshFocus()
    for i = 0 to m.buttonRects.Count() - 1
        m.buttonRects[i].visible = (i = m.focusIndex)
    end for
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    count = m.buttonRects.Count()
    if count = 0 then return true

    if key = "up" then
        if m.focusIndex > 0 then
            m.focusIndex = m.focusIndex - 1
            _tmnRefreshFocus()
        end if
        return true
    else if key = "down" then
        if m.focusIndex < count - 1 then
            m.focusIndex = m.focusIndex + 1
            _tmnRefreshFocus()
        end if
        return true
    else if key = "OK" then
        m.top.buttonSelected = m.focusIndex
        return true
    else if key = "back" then
        ' Last row is always Cancel -- same semantic as selecting it directly.
        m.top.buttonSelected = count - 1
        return true
    end if
    return true   ' swallow everything else -- this dialog owns all input while up
end function
