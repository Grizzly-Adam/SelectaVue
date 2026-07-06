' ==================== BackgroundTexture.brs ====================
' Builds the grid background texture shown behind the grid UI: a stretched
' reflection sweep + a stretched vignette shadow. Originally also had a
' tiled metal-flake layer (small Poster grid — SceneGraph has no native
' tile/repeat fill mode) but that was removed after review; the technique
' is still there in git history / images/flake_tile.png if it's wanted
' again later.

sub _buildGridBackgroundTexture()
    if m.gridBackgroundTexture = invalid then return

    ' Reflection and shadow — single stretched layers, not tiled (they're
    ' continuous gradients, not repeating patterns).
    reflection = m.gridBackgroundTexture.CreateChild("Poster")
    reflection.uri             = "pkg:/images/bg_reflection.png"
    reflection.translation     = [0, 0]
    reflection.width           = 1920
    reflection.height          = 1080
    reflection.loadDisplayMode = "scaleToFill"

    shadow = m.gridBackgroundTexture.CreateChild("Poster")
    shadow.uri             = "pkg:/images/bg_shadow.png"
    shadow.translation     = [0, 0]
    shadow.width           = 1920
    shadow.height          = 1080
    shadow.loadDisplayMode = "scaleToFill"
end sub
