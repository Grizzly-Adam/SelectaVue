' ==================== PlaylistAddDialog.brs ====================
' Two-step "add new playlist" dialog flow (name, then URL), plus the
' private dialog helpers shared between this file and PlaylistEditDialogs.brs.

' ---------- Add new playlist (two-step dialog) ----------
' Entry point for the whole add-playlist flow -- used both for the in-app
' "Add Playlist" panel item and for the very-first-run case (m.playlists
' empty), which MainScene.brs's init() reaches this same way. The welcome
' screen is step 0 of every add-playlist flow (it primes the user and lists
' starter URLs), falling through into the normal name-entry step.

sub showPlaylistManager()
    if m.top.dialog <> invalid then
        m.top.dialog.close = true
        m.top.dialog = invalid
    end if
    m.tempPlaylistName = invalid
    if m.welcomeDialog <> invalid then
        m.welcomeDialog.show = true
    else
        _showNameStep()
    end if
end sub

sub onWelcomeDialogDismissed()
    if m.welcomeDialog <> invalid then m.welcomeDialog.show = false
    ' Go straight to the name step, not back through showPlaylistManager() --
    ' that would just show the welcome dialog again.
    _showNameStep()
end sub

sub _showNameStep()
    _showPhoneKeyboardDialog("Step 1/2: Enter playlist name", "Enter name (ex: My list)", "", "Next", "onPlaylistNameEntered", true)
end sub

sub onPlaylistNameEntered()
    buttonSelected = m.phoneKeyboardDialog.buttonSelected
    print ">>> PLAYLISTADD: onPlaylistNameEntered fired, buttonSelected="; buttonSelected
    if buttonSelected = -1 then return   ' -1 is the reset default, never a real press
    if buttonSelected = 0 then
        name = m.phoneKeyboardDialog.text
        if name = "" or name = invalid then
            _showKeyboardErrorDialog("Name Required", "Playlist name cannot be empty", false, "onSimpleErrorPhoneAction")
            return
        end if
        m.tempPlaylistName = name
        _closePhoneKeyboardDialog(false)
        _delayedCall("showUrlDialog", 0.3)
    else
        _closePhoneKeyboardDialog()
        m.tempPlaylistName = invalid
        _returnToPlaylistPanel()
    end if
end sub

sub showUrlDialog()
    if m.tempPlaylistName = invalid then
        _returnToPlaylistPanel()
        return
    end if
    _showPhoneKeyboardDialog("Step 2/2: Enter playlist URL", "Enter url (ex: https://www.mysite.com/mylist.m3u)", "", "Add", "onPlaylistUrlEntered", false, true)
end sub

sub onPlaylistUrlEntered()
    buttonSelected = m.phoneKeyboardDialog.buttonSelected
    if buttonSelected = -1 then return
    if buttonSelected = 0 then
        url = m.phoneKeyboardDialog.text
        if url = "" or url = invalid then
            _showKeyboardErrorDialog("URL Required", "Playlist URL cannot be empty", true, "onUrlStepErrorPhoneAction")
            return
        end if
        if Left(LCase(url), 7) <> "http://" and Left(LCase(url), 8) <> "https://" then
            ' Default to http:// rather than https:// when the scheme is
            ' left off -- safer for making sure the link actually works,
            ' since a source that's only served over plain http would
            ' otherwise fail outright under a forced https:// guess.
            url = "http://" + url
        end if
        _closePhoneKeyboardDialog()
        if m.tempPlaylistName <> invalid then
            savePlaylist(m.tempPlaylistName, url)
            m.currentPlaylist = m.playlists.Count() - 1   ' the playlist we just pushed
            ' Capture whatever's currently playing BEFORE the switch, same as
            ' every other playlist-switch path (onPlaylistSelected(), reloads,
            ' Favorites/Hidden view rebuilds) -- without this, the new
            ' playlist's load has nothing to resync/pin the playing channel
            ' against, and "now playing" tracking silently goes stale even
            ' though playback itself is unaffected.
            _captureCurrentlyPlayingChannel()
            loadPlaylist(url)
        end if
        m.tempPlaylistName = invalid
        _returnToPlaylistPanel()
    else if buttonSelected = 2 then
        _goBackToNameStep()
    else
        _closePhoneKeyboardDialog()
        m.tempPlaylistName = invalid
        _returnToPlaylistPanel()
    end if
end sub

' Back to step 1 -- pre-fill with whatever name they'd already entered so
' they can just adjust it, not retype from scratch. Same server-continuity
' fix as the step1->step2 transition: don't stop the phone server here, or
' the phone loses its connection. Shared by the on-screen/remote BACK key
' and the phone's mirrored-error Back button.
sub _goBackToNameStep()
    prevName = m.tempPlaylistName
    if prevName = invalid then prevName = ""
    _closePhoneKeyboardDialog(false)
    _showPhoneKeyboardDialog("Step 1/2: Enter playlist name", "Enter name (ex: My list)", prevName, "Next", "onPlaylistNameEntered", true)
end sub

' Phone-side handler for the URL-empty error specifically -- the only one
' that offers Back, since step 2 has a previous step to return to.
sub onUrlStepErrorPhoneAction()
    if m.phoneKeyboardDialog = invalid then return
    action = m.phoneKeyboardDialog.phoneErrorAction
    if action = "" then return
    m.phoneKeyboardDialog.unobserveField("phoneErrorAction")
    _closeThemedMessageDialog()
    m.phoneKeyboardDialog.callFunc("clearPhoneError")
    m.phoneKeyboardDialog.SetFocus(true)
    if action = "back" then _goBackToNameStep()
end sub

' ---------- Private helpers ----------

' Fires AppDialogComplete exactly once, only if this dialog sequence was
' the very-first-run one (see m.isFirstRunSetupDialog in MainScene.brs's
' init()) — not when showPlaylistManager() is reached later from the
' in-app "add playlist" menu. Called at every exit point of the flow below
' (success, cancel, or error) since the beacon measures time spent in the
' dialog, not whether it succeeded.
sub _completeFirstRunSetupDialogIfNeeded()
    if m.isFirstRunSetupDialog then
        m.top.signalBeacon("AppDialogComplete")
        m.isFirstRunSetupDialog = false
    end if
end sub

' Unobserve and close the current dialog in one call.
sub _closeDialog()
    if m.top.dialog <> invalid then
        m.top.dialog.unobserveField("buttonSelected")
        m.top.dialog.close = true
    end if
end sub

' ---------- Custom text-entry dialog (replaces StandardKeyboardDialog) ----------
' Same calling convention as _showKeyboardDialog() on purpose: buttonSelected=0
' means the confirm/save action, =1 means cancel -- existing callbacks
' (onPlaylistNameEntered, onPlaylistUrlEntered, onEditNameComplete,
' onEditUrlComplete) only need to swap which node they read from and which
' close helper they call, not their branching logic. saveLabel replaces the
' old two-item buttons array (["Next","Cancel"] etc.) since Cancel is now
' implicit -- every one of the 4 existing call sites already used exactly
' that pattern (confirm label + "Cancel").
function _showPhoneKeyboardDialog(title as String, message as String, initialText as String, saveLabel as String, buttonCallback = "" as String, autoCapFirst = false as Boolean, backMeansStepBack = false as Boolean) as Object
    dialog = m.phoneKeyboardDialog
    if dialog = invalid then return invalid
    dialog.dialogTitle        = title
    dialog.instructions       = message
    dialog.saveLabel          = saveLabel
    dialog.text               = initialText
    dialog.autoCapFirst       = autoCapFirst
    dialog.backMeansStepBack  = backMeansStepBack
    if buttonCallback <> "" then dialog.observeField("buttonSelected", buttonCallback)
    dialog.show = true
    return dialog
end function

' stopServer=true (default) actually stops the phone-entry server -- use this
' for a real close (final save, or cancel out of the flow entirely). Pass
' false when transitioning to another step of the SAME flow (e.g. name entry
' -> URL entry, or BACK from URL -> name) -- the server's Task thread does
' not restart just by setting control="RUN" again once it has already
' returned, so it must be left running across those transitions or the phone
' loses its connection (confirmed via device log: server stopped, never
' restarted, phone got "site can't be reached").
sub _closePhoneKeyboardDialog(stopServer = true as Boolean)
    if m.phoneKeyboardDialog <> invalid then
        m.phoneKeyboardDialog.unobserveField("buttonSelected")
        m.phoneKeyboardDialog.show = false
        if stopServer then
            ' Show a friendly landing page on the phone before stopping --
            ' the sent-confirmation page auto-refreshes ~1s after
            ' submission, so give it that long (plus margin) to land on
            ' this instead of hitting a dead server (was showing as a 404).
            m.phoneKeyboardDialog.callFunc("showPhoneDone")
            _delayedCall("_stopPhoneEntryServerDelayed", 2.0)
        end if
    end if
end sub

' Guards against stopping a server that a NEW flow already restarted in the
' meantime (e.g. the user reopened Add Playlist within the delay window).
sub _stopPhoneEntryServerDelayed()
    if m.phoneKeyboardDialog <> invalid and not m.phoneKeyboardDialog.show then
        m.phoneKeyboardDialog.stopPhoneEntry = true
    end if
end sub

' ---------- Validation error dialogs (mirrored onto the phone too) ----------
' Shows a themed popup on the TV AND mirrors it onto the phone page (OK, and
' Back if showBack) so the user can dismiss from whichever device is handy
' without switching to the remote. Either side dismissing closes both.
' phoneActionCallback is invoked (via observeField, same convention as
' buttonSelected) when the PHONE'S button is pressed -- it's responsible for
' closing the Roku popup too and reacting to Back where applicable, since
' what "Back" means differs per call site (only step 2's URL-empty error
' offers it, going back to step 1).
sub _showKeyboardErrorDialog(title as String, message as String, showBack as Boolean, phoneActionCallback as String)
    _showThemedMessageDialog(title, message, ["OK"], "_onKeyboardErrorRokuOk", 700, 360)
    if m.phoneKeyboardDialog <> invalid then
        m.phoneKeyboardDialog.callFunc("showPhoneError", title, message, showBack)
        m.phoneKeyboardDialog.observeField("phoneErrorAction", phoneActionCallback)
    end if
end sub

' Roku-side OK also needs to clear the phone's mirrored error, so the phone
' doesn't keep showing a stale error after being dismissed from the remote.
sub _onKeyboardErrorRokuOk()
    if m.themedMessageDialog.buttonSelected = -1 then return   ' -1 is the reset default, never a real press
    _closeThemedMessageDialog()
    if m.phoneKeyboardDialog <> invalid then
        m.phoneKeyboardDialog.unobserveField("phoneErrorAction")
        m.phoneKeyboardDialog.callFunc("clearPhoneError")
        m.phoneKeyboardDialog.SetFocus(true)
    end if
end sub

' Phone-side handler for errors that only ever offer OK (name-empty on
' either Add Playlist or Edit Name, URL-empty on Edit URL) -- just closes
' both sides, same as the Roku OK press.
sub onSimpleErrorPhoneAction()
    if m.phoneKeyboardDialog = invalid then return
    action = m.phoneKeyboardDialog.phoneErrorAction
    if action = "" then return
    m.phoneKeyboardDialog.unobserveField("phoneErrorAction")
    _closeThemedMessageDialog()
    m.phoneKeyboardDialog.callFunc("clearPhoneError")
    m.phoneKeyboardDialog.SetFocus(true)
end sub

' Return focus to the playlist side panel — always done together.
sub _returnToPlaylistPanel()
    _completeFirstRunSetupDialogIfNeeded()
    m.playlistList.setFocus(true)
    m.playlistPanelActive = true
end sub

' Show a simple error dialog, then return to the playlist panel on dismiss.
sub _showPlaylistError(message as String)
    m.pendingErrorMessage = message
    _delayedCall("onShowPlaylistError", 0.3)
end sub

sub onShowPlaylistError()
    _cancelNamedTimer("optionTimer")
    message = "An error occurred."
    if m.pendingErrorMessage <> invalid then
        message = m.pendingErrorMessage
        m.pendingErrorMessage = invalid
    end if
    _showSimpleDialog("Error", message, ["OK"], "onPlaylistErrorClosed")
end sub

sub onPlaylistErrorClosed()
    _closeDialog()
    _returnToPlaylistPanel()
end sub

' Creates a one-shot timer that fires callbackName after delaySec seconds.
sub _delayedCall(callbackName as String, delaySec as Float)
    _startNamedTimer("optionTimer", delaySec, false, callbackName)
end sub

sub _clearOptionTimer()
    _cancelNamedTimer("optionTimer")
end sub
