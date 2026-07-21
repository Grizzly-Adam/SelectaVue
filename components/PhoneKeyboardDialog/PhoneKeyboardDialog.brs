' ==================== PhoneKeyboardDialog.brs ====================
' Custom full-screen text-entry dialog (see PhoneKeyboardDialog.xml's header
' comment for the full rationale and public interface). Replaces
' StandardKeyboardDialog for playlist name/URL entry.
'
' Two independently-navigable key blocks:
'   main      - letters/numbers/symbols/cursor/space/actions (left)
'   shortcut  - the "easy keys" http://, .com, etc. (right)
' m.focusBlock tracks which one currently has the on-screen highlight.
' Left/right at a block's edge crosses over to the other block, clamping
' the row index to whatever the target block actually has.

sub init()
    m.shade      = m.top.findNode("pkdShade")
    m.border     = m.top.findNode("pkdBorder")
    m.titleLbl   = m.top.findNode("pkdTitleLabel")
    m.instrLbl   = m.top.findNode("pkdInstructionsLabel")
    m.qrCode     = m.top.findNode("pkdQrCode")
    m.textLbl    = m.top.findNode("pkdTextLabel")
    m.keyGrid    = m.top.findNode("pkdKeyGrid")
    m.shortcutGrid = m.top.findNode("pkdShortcutGrid")
    m.phoneServer = m.top.findNode("pkdPhoneServer")

    print ">>> PHONEKBD INIT: shade="; m.shade <> invalid; " border="; m.border <> invalid; " titleLbl="; m.titleLbl <> invalid; " instrLbl="; m.instrLbl <> invalid; " qrCode="; m.qrCode <> invalid; " textLbl="; m.textLbl <> invalid; " keyGrid="; m.keyGrid <> invalid; " shortcutGrid="; m.shortcutGrid <> invalid; " phoneServer="; m.phoneServer <> invalid

    m.capsOn      = false
    m.shiftPending = false
    m.cursorPos   = 0
    m.focusBlock  = "main"
    m.focusRow    = 0
    m.focusCol    = 0
    m.focusDesiredX = 0   ' x-position anchor for up/down nav -- set once grids are built below

    m.mainRows     = _pkdMainKeyRows()
    m.shortcutRows = _pkdShortcutKeyRows()
    m.mainNodes     = []
    m.shortcutNodes = []

    m.mainFocusRing     = _pkdCreateFocusRing(m.keyGrid)
    m.shortcutFocusRing = _pkdCreateFocusRing(m.shortcutGrid)

    if m.keyGrid <> invalid then m.mainNodes = _pkdBuildKeyGrid(m.keyGrid, m.mainRows, 96, 8, 64, 10)
    if m.shortcutGrid <> invalid then m.shortcutNodes = _pkdBuildKeyGrid(m.shortcutGrid, m.shortcutRows, 220, 10, 64, 10)

    if m.mainNodes.Count() > 0 then m.focusDesiredX = _pkdKeyCenterX(m.mainNodes, m.focusRow, m.focusCol)
    _pkdRefreshFocusVisuals()
end sub

' White outline behind the focused key, sized to match it. Created once per
' block, repositioned/resized as focus moves. Appended first so it renders
' behind the key rects.
function _pkdCreateFocusRing(container as Object) as Object
    if container = invalid then return invalid
    ring = CreateObject("roSGNode", "Rectangle")
    ring.color   = "0xFFFFFFFF"
    ring.visible = false
    container.appendChild(ring)
    return ring
end function

' ---------- Grid construction ----------
' Shared builder for both blocks. unitW/gapX size a key at w=1; wpx on a key
' def overrides with an exact pixel width for rows that don't divide evenly.
function _pkdBuildKeyGrid(container as Object, rows as Object, unitW as Integer, gapX as Integer, keyH as Integer, gapY as Integer) as Object
    keyNodes = []
    for r = 0 to rows.Count() - 1
        row = rows[r]
        rowNodes = []
        x = 0
        for c = 0 to row.Count() - 1
            keyDef = row[c]
            if keyDef.wpx <> invalid then
                keyW = keyDef.wpx
            else
                w = 1
                if keyDef.w <> invalid then w = keyDef.w
                keyW = w * unitW + (w - 1) * gapX
            end if

            rect = CreateObject("roSGNode", "Rectangle")
            rect.id          = "pkdKey_" + r.ToStr() + "_" + c.ToStr()
            rect.translation = [x, r * (keyH + gapY)]
            rect.width       = keyW
            rect.height      = keyH
            rect.color       = _pkdKeyBaseColor(keyDef)

            label = CreateObject("roSGNode", "Label")
            label.width      = keyW
            label.height     = keyH
            label.horizAlign = "center"
            label.vertAlign  = "center"
            label.font       = "font:MediumBoldSystemFont"
            label.color      = "0xE8F5F3FF"
            label.text       = _pkdKeyDisplayLabel(keyDef)
            rect.appendChild(label)

            container.appendChild(rect)
            rowNodes.Push({ rect: rect })
            x = x + keyW + gapX
        end for
        keyNodes.Push(rowNodes)
    end for
    return keyNodes
end function

function _pkdKeyDisplayLabel(keyDef as Object) as String
    if keyDef.action = "save" then return UCase(m.top.saveLabel)
    if keyDef.isLetter = true then return _pkdLetterDisplay(keyDef)
    return keyDef.label
end function

function _pkdLetterDisplay(keyDef as Object) as String
    if _pkdEffectiveUpper() then return UCase(keyDef.insert)
    return keyDef.insert
end function

' Caps (persistent) and Shift (one-shot) combine like a real keyboard: both
' off or both on -> lowercase; exactly one on -> uppercase (pressing Shift
' while Caps is active types lowercase, matching standard behavior).
function _pkdEffectiveUpper() as Boolean
    if m.capsOn and not m.shiftPending then return true
    if (not m.capsOn) and m.shiftPending then return true
    return false
end function

' Non-typing (action) keys get a distinct color from regular character keys
' -- caps, shift, backspace, cursor left/right, clear, cancel, save/next.
' Space stays the normal color -- Adam explicitly excluded it.
function _pkdKeyBaseColor(keyDef as Object) as String
    if keyDef.action = "caps" or keyDef.action = "shift" or keyDef.action = "backspace" or keyDef.action = "cursorLeft" or keyDef.action = "cursorRight" or keyDef.action = "clear" or keyDef.action = "cancel" or keyDef.action = "save" or keyDef.action = "back" then
        return "0x5A8A82FF"
    end if
    return "0x3D5C56FF"
end function

' Re-colors focus highlight across both blocks and refreshes letter case.
sub _pkdRefreshFocusVisuals()
    _pkdRefreshBlockVisuals(m.mainRows, m.mainNodes, "main", m.mainFocusRing)
    _pkdRefreshBlockVisuals(m.shortcutRows, m.shortcutNodes, "shortcut", m.shortcutFocusRing)
end sub

sub _pkdRefreshBlockVisuals(rows as Object, nodes as Object, blockName as String, ring as Object)
    if nodes.Count() = 0 then return
    isFocusedBlock = (blockName = m.focusBlock)
    ringThickness = 4
    for r = 0 to rows.Count() - 1
        for c = 0 to rows[r].Count() - 1
            rect = nodes[r][c].rect
            keyDef = rows[r][c]
            if isFocusedBlock and r = m.focusRow and c = m.focusCol then
                rect.color = "0x8fcdc1FF"
                if ring <> invalid then
                    rt = rect.translation
                    ring.translation = [rt[0] - ringThickness, rt[1] - ringThickness]
                    ring.width       = rect.width  + 2 * ringThickness
                    ring.height      = rect.height + 2 * ringThickness
                    ring.visible     = true
                end if
            else
                rect.color = _pkdKeyBaseColor(keyDef)
            end if
            if keyDef.isLetter = true then
                lbl = rect.getChild(0)
                if lbl <> invalid then lbl.text = _pkdLetterDisplay(keyDef)
            end if
        end for
    end for
    if not isFocusedBlock and ring <> invalid then ring.visible = false
end sub

' ---------- Open / close ----------

sub onShowChanged()
    if m.top.show then
        _pkdOpen()
    else
        _pkdCloseInternal()
    end if
end sub

' Lets a caller update the instructions line (e.g. a validation error) while
' the dialog is already open, without closing/reopening it. _pkdOpen() sets
' the label too on initial show; this covers every change after that.
sub onInstructionsChanged()
    if m.instrLbl <> invalid then m.instrLbl.text = m.top.instructions
    _pkdSyncServerPageFields()
end sub

sub _pkdOpen()
    m.top.buttonSelected = -1
    m.capsOn      = false
    m.focusBlock  = "main"
    m.focusRow    = 2   ' row A S D F G H J K L [ ]
    m.focusCol    = 5   ' H -- middle of the keyboard, per Adam's request
    m.cursorPos   = Len(m.top.text)
    if m.mainNodes.Count() > 0 then m.focusDesiredX = _pkdKeyCenterX(m.mainNodes, m.focusRow, m.focusCol)

    ' Auto-capitalize the first letter typed into an empty field (playlist
    ' names only -- Adam explicitly does not want this for URLs). Reuses
    ' the one-shot shiftPending mechanism, which already reverts itself
    ' after the next inserted letter.
    m.shiftPending = (m.top.autoCapFirst = true and m.top.text = "")

    ' Refresh the SAVE key's label -- saveLabel can differ per call
    ' (Save/Next/Add) and the grid was built once at init().
    if m.mainNodes.Count() > 0 then
        lastRow = m.mainRows.Count() - 1
        for c = 0 to m.mainRows[lastRow].Count() - 1
            keyDef = m.mainRows[lastRow][c]
            if keyDef.action = "save" then
                m.mainNodes[lastRow][c].rect.getChild(0).text = m.top.saveLabel
            end if
        end for
    end if

    if m.titleLbl <> invalid then m.titleLbl.text = m.top.dialogTitle
    if m.instrLbl <> invalid then m.instrLbl.text = m.top.instructions
    _pkdRefreshTextDisplay()
    _pkdRefreshFocusVisuals()

    if m.shade  <> invalid then m.shade.visible  = true
    if m.border <> invalid then m.border.visible = true
    m.top.visible = true
    m.top.SetFocus(true)

    _pkdStartServer()
end sub

sub _pkdCloseInternal()
    if m.shade  <> invalid then m.shade.visible  = false
    if m.border <> invalid then m.border.visible = false
    m.top.visible = false
end sub

' Separate trigger for actually stopping the phone server -- transitioning
' between steps of the same flow must NOT stop it (a Task's function can't
' be restarted just by setting control="RUN" again once it has returned).
sub onStopPhoneEntryChanged()
    if m.top.stopPhoneEntry then _pkdStopServer()
end sub

' ---------- Phone-entry server + QR ----------

sub _pkdStartServer()
    if m.phoneServer = invalid then return
    m.phoneServer.unobserveField("status")
    m.phoneServer.unobserveField("submittedText")
    m.phoneServer.unobserveField("errorAction")
    m.phoneServer.observeField("status", "onPhoneServerStatus")
    m.phoneServer.observeField("submittedText", "onPhoneServerSubmittedText")
    m.phoneServer.observeField("errorAction", "onPhoneServerErrorAction")
    m.phoneServer.stopServer   = false
    m.phoneServer.doneMessage  = ""
    m.phoneServer.errorTitle   = ""
    _pkdSyncServerPageFields()
    m.phoneServer.control      = "RUN"
end sub

' Keeps the phone page's title/instructions/label/text in sync with the TV.
' Called on open, on every step transition, and on any live instructions change.
sub _pkdSyncServerPageFields()
    if m.phoneServer = invalid then return
    m.phoneServer.pageTitle        = m.top.dialogTitle
    m.phoneServer.pageInstructions = m.top.instructions
    m.phoneServer.sendLabel        = m.top.saveLabel
    m.phoneServer.initialText      = m.top.text
end sub

sub _pkdStopServer()
    if m.phoneServer = invalid then return
    m.phoneServer.stopServer = true
end sub

' Mirrors a validation error onto the phone page (OK, + Back if showBack).
function showPhoneError(title as String, message as String, showBack as Boolean) as Void
    if m.phoneServer = invalid then return
    m.phoneServer.errorTitle    = title
    m.phoneServer.errorMessage  = message
    m.phoneServer.errorShowBack = showBack
end function

function clearPhoneError() as Void
    if m.phoneServer = invalid then return
    m.phoneServer.errorTitle = ""
end function

' Shows the phone's "All set!" landing page, right before the server stops.
function showPhoneDone() as Void
    if m.phoneServer = invalid then return
    m.phoneServer.doneMessage = "You can close this page and return to your TV. Thank you for choosing SelectaVue, the TV of the future!"
end function

' Forwards the phone's error-dismiss choice to our own observable field.
sub onPhoneServerErrorAction()
    m.top.phoneErrorAction = m.phoneServer.errorAction
end sub

sub onPhoneServerStatus()
    status = m.phoneServer.status
    print ">>> PHONEKBD: server status="; status
    if Left(status, 6) = "ready:" then
        serverUrl = Mid(status, 7)
        if m.qrCode <> invalid then m.qrCode.text = serverUrl
    end if
end sub

' Phone submit = type + confirm in one action: sync text, then act as SAVE.
sub onPhoneServerSubmittedText()
    newText = m.phoneServer.submittedText
    ' Same auto-cap-first-letter rule as the remote keyboard, applied to
    ' whatever the phone just sent, since phone-typed text bypasses
    ' _pkdActivateKey() entirely.
    if m.top.autoCapFirst = true and m.top.text = "" and newText <> "" then
        newText = UCase(Left(newText, 1)) + Mid(newText, 2)
    end if
    m.top.text  = newText
    m.cursorPos = Len(newText)
    _pkdRefreshTextDisplay()
    m.top.buttonSelected = 0
end sub

' ---------- Text display (with cursor marker) ----------

sub _pkdRefreshTextDisplay()
    if m.textLbl = invalid then return
    t = m.top.text
    if m.cursorPos < 0 then m.cursorPos = 0
    if m.cursorPos > Len(t) then m.cursorPos = Len(t)
    m.textLbl.text = Left(t, m.cursorPos) + "|" + Mid(t, m.cursorPos + 1)
end sub

' ---------- Key activation ----------

sub _pkdActivateKey(keyDef as Object)
    if keyDef.insert <> invalid then
        chars = keyDef.insert
        if Len(chars) = 1 and _pkdEffectiveUpper() then chars = UCase(chars)
        if m.shiftPending then
            m.shiftPending = false
            _pkdRefreshFocusVisuals()
        end if
        t = m.top.text
        m.top.text  = Left(t, m.cursorPos) + chars + Mid(t, m.cursorPos + 1)
        m.cursorPos = m.cursorPos + Len(chars)
        _pkdRefreshTextDisplay()
    else if keyDef.action = "backspace" then
        t = m.top.text
        if m.cursorPos > 0 then
            m.top.text  = Left(t, m.cursorPos - 1) + Mid(t, m.cursorPos + 1)
            m.cursorPos = m.cursorPos - 1
            _pkdRefreshTextDisplay()
        end if
    else if keyDef.action = "space" then
        t = m.top.text
        m.top.text  = Left(t, m.cursorPos) + " " + Mid(t, m.cursorPos + 1)
        m.cursorPos = m.cursorPos + 1
        _pkdRefreshTextDisplay()
    else if keyDef.action = "cursorLeft" then
        if m.cursorPos > 0 then
            m.cursorPos = m.cursorPos - 1
            _pkdRefreshTextDisplay()
        end if
    else if keyDef.action = "cursorRight" then
        if m.cursorPos < Len(m.top.text) then
            m.cursorPos = m.cursorPos + 1
            _pkdRefreshTextDisplay()
        end if
    else if keyDef.action = "caps" then
        m.capsOn = not m.capsOn
        _pkdRefreshFocusVisuals()
    else if keyDef.action = "shift" then
        m.shiftPending = true
        _pkdRefreshFocusVisuals()
    else if keyDef.action = "clear" then
        m.top.text  = ""
        m.cursorPos = 0
        _pkdRefreshTextDisplay()
    else if keyDef.action = "save" then
        print ">>> PHONEKBD: SAVE activated, setting buttonSelected=0 (text="; m.top.text; ")"
        m.top.buttonSelected = 0
    else if keyDef.action = "cancel" then
        print ">>> PHONEKBD: CANCEL activated, setting buttonSelected=1"
        m.top.buttonSelected = 1
    else if keyDef.action = "back" then
        print ">>> PHONEKBD: BACK activated, setting buttonSelected=2"
        m.top.buttonSelected = 2
    end if
    ' Keep the phone page's text box showing whatever's now current, so
    ' switching back to the phone after typing some on the remote (or vice
    ' versa) doesn't show stale text if the page happens to reload.
    _pkdSyncServerPageFields()
end sub

' ---------- Remote input ----------

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    curRows = m.mainRows
    curNodes = m.mainNodes
    if m.focusBlock = "shortcut" then
        curRows  = m.shortcutRows
        curNodes = m.shortcutNodes
    end if
    lastRow = curRows.Count() - 1

    if key = "up" then
        if m.focusRow > 0 then
            m.focusRow = m.focusRow - 1
            ' Keyed by screen x-position, not raw column index -- rows have
            ' different key widths (CAPS/SHIFT/SPACE span multiple units),
            ' so matching index alone zig-zags the highlight sideways.
            m.focusCol = _pkdClosestColByX(curNodes, m.focusRow, m.focusDesiredX)
            _pkdRefreshFocusVisuals()
        end if
        return true
    else if key = "down" then
        if m.focusRow < lastRow then
            m.focusRow = m.focusRow + 1
            m.focusCol = _pkdClosestColByX(curNodes, m.focusRow, m.focusDesiredX)
            _pkdRefreshFocusVisuals()
        end if
        return true
    else if key = "left" then
        if m.focusCol > 0 then
            m.focusCol = m.focusCol - 1
            m.focusDesiredX = _pkdKeyCenterX(curNodes, m.focusRow, m.focusCol)
            _pkdRefreshFocusVisuals()
        else if m.focusBlock = "shortcut" then
            m.focusBlock = "main"
            m.focusRow = _pkdMin(m.focusRow, m.mainRows.Count() - 1)
            m.focusCol = m.mainRows[m.focusRow].Count() - 1
            m.focusDesiredX = _pkdKeyCenterX(m.mainNodes, m.focusRow, m.focusCol)
            _pkdRefreshFocusVisuals()
        end if
        return true
    else if key = "right" then
        if m.focusCol < curRows[m.focusRow].Count() - 1 then
            m.focusCol = m.focusCol + 1
            m.focusDesiredX = _pkdKeyCenterX(curNodes, m.focusRow, m.focusCol)
            _pkdRefreshFocusVisuals()
        else if m.focusBlock = "main" and m.shortcutNodes.Count() > 0 then
            m.focusBlock = "shortcut"
            m.focusRow = _pkdMin(m.focusRow, m.shortcutRows.Count() - 1)
            m.focusCol = 0
            m.focusDesiredX = _pkdKeyCenterX(m.shortcutNodes, m.focusRow, m.focusCol)
            _pkdRefreshFocusVisuals()
        end if
        return true
    else if key = "OK" then
        keyDef = curRows[m.focusRow][m.focusCol]
        print ">>> PHONEKBD: OK on block="; m.focusBlock; " row="; m.focusRow; " col="; m.focusCol; " action="; keyDef.action; " insert="; keyDef.insert
        _pkdActivateKey(keyDef)
        return true
    else if key = "back" then
        if m.top.backMeansStepBack then
            m.top.buttonSelected = 2   ' same as the on-screen BACK key
        else
            m.top.buttonSelected = 1   ' no previous step here -- Cancel
        end if
        return true
    end if
    return true   ' swallow everything else -- this dialog owns all input while up
end function

function _pkdMin(a as Integer, b as Integer) as Integer
    if a < b then return a
    return b
end function

' Center x-position (pixels) of a built key rect -- used to keep vertical
' navigation visually aligned by screen position instead of column index.
function _pkdKeyCenterX(nodes as Object, row as Integer, col as Integer) as Integer
    rect = nodes[row][col].rect
    return rect.translation[0] + rect.width / 2
end function

' Column in targetRow whose key sits directly above/below x. Checks real
' horizontal containment first -- nearest-center alone fails for a much
' wider key like the spacebar, where a narrow neighbor's center can be
' numerically closer to x even though x actually falls inside the wide
' key's span and doesn't touch the narrow one at all. Falls back to
' nearest-center only when no key's span actually contains x (the small
' gap between two keys).
function _pkdClosestColByX(nodes as Object, targetRow as Integer, x as Integer) as Integer
    for c = 0 to nodes[targetRow].Count() - 1
        rect = nodes[targetRow][c].rect
        left  = rect.translation[0]
        right = left + rect.width
        if x >= left and x < right then return c
    end for

    bestCol  = 0
    bestDist = -1
    for c = 0 to nodes[targetRow].Count() - 1
        dist = Abs(_pkdKeyCenterX(nodes, targetRow, c) - x)
        if bestDist = -1 or dist < bestDist then
            bestDist = dist
            bestCol  = c
        end if
    end for
    return bestCol
end function
