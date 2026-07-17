' ==================== IconHelpers.brs ====================
' Icon selection, category matching, and logo load callbacks.
' Split from Utils.brs to stay within Roku's per-file compile limit.
' Long keyword chains are split into multiple if-blocks to avoid
' Roku's per-expression token limit (compile error &hae).

function _bestIconUrl(channel as Object) as String
    logoUrl = _channelLogoUrl(channel)
    if logoUrl <> "" then return logoUrl
    return _categoryIconUrl(channel)
end function

function _categoryIconUrl(channel as Object) as String
    group = ""
    if channel <> invalid and channel.group <> invalid then
        group = _stripGroupPrefixes(channel.group)
    end if
    title = ""
    if channel <> invalid then
        base = iif(channel.baseTitle <> invalid and channel.baseTitle <> "", channel.baseTitle, channel.title)
        if base <> invalid then title = LCase(base)
    end if
    icon = _matchCategoryKeywords(group)
    if icon = "" then icon = _matchCategoryKeywords(title)
    if icon = "" then icon = "pkg:/images/icon_general.svg"
    return icon
end function

function _stripGroupPrefixes(group as String) as String
    g = group
    while Len(g) > 0 and (Left(g,1) = " " or Left(g,1) = Chr(9))
        g = Mid(g, 2)
    end while
    pipeIdx = g.InStr("|")
    if pipeIdx > 0 and pipeIdx <= 6 then
        g = Mid(g, pipeIdx + 1)
        while Len(g) > 0 and (Left(g,1) = " " or Left(g,1) = "|")
            g = Mid(g, 2)
        end while
    end if
    if Left(g, 1) = "[" then
        closeIdx = g.InStr("]")
        if closeIdx > 0 and closeIdx <= 7 then
            g = Mid(g, closeIdx + 1)
            while Len(g) > 0 and Left(g,1) = " "
                g = Mid(g, 2)
            end while
        end if
    end if
    if Left(g, 1) = "(" then
        closeIdx = g.InStr(")")
        if closeIdx > 0 and closeIdx <= 7 then
            g = Mid(g, closeIdx + 1)
            while Len(g) > 0 and Left(g,1) = " "
                g = Mid(g, 2)
            end while
        end if
    end if
    colonIdx = g.InStr(":")
    if colonIdx > 0 and colonIdx <= 5 then
        g = Mid(g, colonIdx + 1)
        while Len(g) > 0 and Left(g,1) = " "
            g = Mid(g, 2)
        end while
    end if
    dashIdx = g.InStr(" - ")
    if dashIdx > 0 and dashIdx <= 5 then
        g = Mid(g, dashIdx + 3)
    end if
    return LCase(g)
end function

' Keyword matching — each category uses separate if-blocks to stay
' within Roku's per-expression token limit.
function _matchCategoryKeywords(s as String) as String
    if s = "" or s = invalid then return ""

    ' Anime (check before cartoons)
    if s.InStr("anime") >= 0 then return "pkg:/images/icon_anime.svg"
    if s.InStr("manga") >= 0 then return "pkg:/images/icon_anime.svg"
    if s.InStr("crunchyroll") >= 0 then return "pkg:/images/icon_anime.svg"
    if s.InStr("funimation") >= 0 then return "pkg:/images/icon_anime.svg"

    ' Cartoons / Animation — kids takes priority if also present
    if s.InStr("cartoon") >= 0 or s.InStr("animation") >= 0 or s.InStr("animated") >= 0 or s.InStr("toon") >= 0 then
        if s.InStr("kid") >= 0 or s.InStr("child") >= 0 or s.InStr("junior") >= 0 or s.InStr("jr") >= 0 then
            return "pkg:/images/icon_kids.svg"
        end if
        if s.InStr("infantil") >= 0 or s.InStr("kinder") >= 0 then
            return "pkg:/images/icon_kids.svg"
        end if
        return "pkg:/images/icon_cartoons.svg"
    end if
    if s.InStr("desenho") >= 0 or s.InStr("dessin") >= 0 then
        return "pkg:/images/icon_cartoons.svg"
    end if

    ' Kids / Children / Family
    if s.InStr("kid") >= 0 or s.InStr("child") >= 0 or s.InStr("family") >= 0 then
        return "pkg:/images/icon_kids.svg"
    end if
    if s.InStr("junior") >= 0 or s.InStr("youth") >= 0 or s.InStr("baby") >= 0 then
        return "pkg:/images/icon_kids.svg"
    end if
    if s.InStr("infant") >= 0 or s.InStr("nickelodeon") >= 0 then
        return "pkg:/images/icon_kids.svg"
    end if
    if s.InStr("disney jr") >= 0 or s.InStr("boomerang") >= 0 then
        return "pkg:/images/icon_kids.svg"
    end if
    if s.InStr("playhouse") >= 0 or s.InStr("sprout") >= 0 then
        return "pkg:/images/icon_kids.svg"
    end if
    if s.InStr("kinder") >= 0 or s.InStr("enfant") >= 0 then
        return "pkg:/images/icon_kids.svg"
    end if
    if s.InStr("jeunesse") >= 0 or s.InStr("bambini") >= 0 or s.InStr("infantil") >= 0 then
        return "pkg:/images/icon_kids.svg"
    end if

    ' Sitcoms (before comedy)
    if s.InStr("sitcom") >= 0 then return "pkg:/images/icon_sitcoms.svg"

    ' Comedy
    if s.InStr("comedy") >= 0 or s.InStr("humor") >= 0 or s.InStr("humour") >= 0 then
        return "pkg:/images/icon_comedy.svg"
    end if
    if s.InStr("funny") >= 0 or s.InStr("laugh") >= 0 then
        return "pkg:/images/icon_comedy.svg"
    end if
    if s.InStr("comedi") >= 0 or s.InStr("comedie") >= 0 then
        return "pkg:/images/icon_comedy.svg"
    end if

    ' Sports
    if s.InStr("sport") >= 0 or s.InStr("football") >= 0 or s.InStr("soccer") >= 0 then
        return "pkg:/images/icon_sports.svg"
    end if
    if s.InStr("cricket") >= 0 or s.InStr("basketball") >= 0 or s.InStr("baseball") >= 0 then
        return "pkg:/images/icon_sports.svg"
    end if
    if s.InStr("hockey") >= 0 or s.InStr("tennis") >= 0 or s.InStr("golf") >= 0 then
        return "pkg:/images/icon_sports.svg"
    end if
    if s.InStr("nfl") >= 0 or s.InStr("nba") >= 0 or s.InStr("mlb") >= 0 or s.InStr("nhl") >= 0 or s.InStr("mls") >= 0 then
        return "pkg:/images/icon_sports.svg"
    end if
    if s.InStr("espn") >= 0 or s.InStr("eurosport") >= 0 or s.InStr("motorsport") >= 0 then
        return "pkg:/images/icon_sports.svg"
    end if
    if s.InStr("racing") >= 0 or s.InStr("formula") >= 0 or s.InStr("olympic") >= 0 then
        return "pkg:/images/icon_sports.svg"
    end if
    if s.InStr("deport") >= 0 or s.InStr("futbol") >= 0 or s.InStr("fútbol") >= 0 then
        return "pkg:/images/icon_sports.svg"
    end if
    if s.InStr("calcio") >= 0 or s.InStr("rugby") >= 0 or s.InStr("wrestling") >= 0 then
        return "pkg:/images/icon_sports.svg"
    end if
    if s.InStr("boxing") >= 0 or s.InStr("ufc") >= 0 or s.InStr("atletico") >= 0 then
        return "pkg:/images/icon_sports.svg"
    end if

    ' Weather
    if s.InStr("weather") >= 0 or s.InStr("meteo") >= 0 or s.InStr("météo") >= 0 then
        return "pkg:/images/icon_weather.svg"
    end if
    if s.InStr("forecast") >= 0 or s.InStr("climate") >= 0 then
        return "pkg:/images/icon_weather.svg"
    end if
    if s.InStr("wetter") >= 0 or s.InStr("tiempo") >= 0 then
        return "pkg:/images/icon_weather.svg"
    end if

    ' Educational / Documentary
    if s.InStr("edu") >= 0 or s.InStr("learn") >= 0 or s.InStr("school") >= 0 then
        return "pkg:/images/icon_educational.svg"
    end if
    if s.InStr("document") >= 0 or s.InStr("science") >= 0 or s.InStr("history") >= 0 then
        return "pkg:/images/icon_educational.svg"
    end if
    if s.InStr("discovery") >= 0 or s.InStr("national geo") >= 0 or s.InStr("natgeo") >= 0 then
        return "pkg:/images/icon_educational.svg"
    end if
    if s.InStr("knowledge") >= 0 or s.InStr("nature") >= 0 then
        return "pkg:/images/icon_educational.svg"
    end if
    if s.InStr("bbc four") >= 0 or s.InStr("curiosity") >= 0 or s.InStr("smithsonian") >= 0 then
        return "pkg:/images/icon_educational.svg"
    end if
    if s.InStr("historia") >= 0 or s.InStr("ciencia") >= 0 then
        return "pkg:/images/icon_educational.svg"
    end if

    ' News / Network
    if s.InStr("news") >= 0 or s.InStr("network") >= 0 or s.InStr("broadcast") >= 0 then
        return "pkg:/images/icon_network.svg"
    end if
    if s.InStr("noticias") >= 0 or s.InStr("nachrichten") >= 0 or s.InStr("actualit") >= 0 then
        return "pkg:/images/icon_network.svg"
    end if
    if s.InStr("cnn") >= 0 or s.InStr("msnbc") >= 0 or s.InStr("al jazeera") >= 0 then
        return "pkg:/images/icon_network.svg"
    end if
    if s.InStr("bbc news") >= 0 or s.InStr("sky news") >= 0 or s.InStr("fox news") >= 0 then
        return "pkg:/images/icon_network.svg"
    end if
    if s.InStr("abc news") >= 0 or s.InStr("nbc news") >= 0 or s.InStr("headline") >= 0 then
        return "pkg:/images/icon_network.svg"
    end if

    ' Movies
    if s.InStr("movie") >= 0 or s.InStr("film") >= 0 or s.InStr("cinema") >= 0 then
        return "pkg:/images/icon_movies.svg"
    end if
    if s.InStr("cine") >= 0 or s.InStr("hbo") >= 0 or s.InStr("showtime") >= 0 then
        return "pkg:/images/icon_movies.svg"
    end if
    if s.InStr("starz") >= 0 or s.InStr("epix") >= 0 or s.InStr("amc") >= 0 then
        return "pkg:/images/icon_movies.svg"
    end if
    if s.InStr("tcm") >= 0 or s.InStr("pelicula") >= 0 or s.InStr("filme") >= 0 then
        return "pkg:/images/icon_movies.svg"
    end if

    ' Music
    if s.InStr("music") >= 0 or s.InStr("mtv") >= 0 or s.InStr("vh1") >= 0 then
        return "pkg:/images/icon_music.svg"
    end if
    if s.InStr("radio") >= 0 or s.InStr("hits") >= 0 or s.InStr("jazz") >= 0 then
        return "pkg:/images/icon_music.svg"
    end if
    if s.InStr("rock music") >= 0 or s.InStr("rock radio") >= 0 then
        return "pkg:/images/icon_music.svg"
    end if
    if s.InStr("country music") >= 0 or s.InStr("hip hop") >= 0 or s.InStr("hiphop") >= 0 then
        return "pkg:/images/icon_music.svg"
    end if
    if s.InStr("classical music") >= 0 or s.InStr("classical radio") >= 0 then
        return "pkg:/images/icon_music.svg"
    end if
    if s.InStr("musica") >= 0 or s.InStr("musique") >= 0 or s.InStr("musik") >= 0 then
        return "pkg:/images/icon_music.svg"
    end if

    ' Drama / Series
    if s.InStr("drama") >= 0 or s.InStr("serie") >= 0 or s.InStr("telenovela") >= 0 then
        return "pkg:/images/icon_drama.svg"
    end if
    if s.InStr("novela") >= 0 or s.InStr("soap") >= 0 or s.InStr("thriller") >= 0 then
        return "pkg:/images/icon_drama.svg"
    end if
    if s.InStr("mystery") >= 0 or s.InStr("crime") >= 0 or s.InStr("lifetime") >= 0 then
        return "pkg:/images/icon_drama.svg"
    end if
    if s.InStr("hallmark") >= 0 or s.InStr("bravo") >= 0 or s.InStr("entertainment") >= 0 then
        return "pkg:/images/icon_drama.svg"
    end if

    ' Religious / Faith
    if s.InStr("church") >= 0 or s.InStr("faith") >= 0 or s.InStr("religio") >= 0 then
        return "pkg:/images/icon_religious.svg"
    end if
    if s.InStr("gospel") >= 0 or s.InStr("christian") >= 0 or s.InStr("catholic") >= 0 then
        return "pkg:/images/icon_religious.svg"
    end if
    if s.InStr("worship") >= 0 or s.InStr("prayer") >= 0 or s.InStr("spiritual") >= 0 then
        return "pkg:/images/icon_religious.svg"
    end if
    if s.InStr("ministry") >= 0 or s.InStr("bible") >= 0 or s.InStr("islamic") >= 0 then
        return "pkg:/images/icon_religious.svg"
    end if
    if s.InStr("muslim") >= 0 or s.InStr("hindu") >= 0 or s.InStr("jewish") >= 0 then
        return "pkg:/images/icon_religious.svg"
    end if
    if s.InStr("mosque") >= 0 then return "pkg:/images/icon_religious.svg"

    return ""
end function

sub onChannelBarLogoStatus()
    if m.channelBarLogo = invalid then return
    if m.channelBarLogo.loadStatus <> "failed" then return
    if Left(m.channelBarLogo.uri, 4) = "pkg:" then return
    channel = m.channelBarLogoChannel
    if channel = invalid then return
    current = _currentChannel()
    if current <> invalid and channel.url <> invalid and channel.url <> current.url then
        print ">>> ICON: channelBarLogo stale — ignoring"
        return
    end if
    fallback = _categoryIconUrl(channel)
    print ">>> ICON: channelBarLogo failed, falling back to "; fallback
    m.channelBarLogo.uri     = fallback
    m.channelBarLogo.visible = true
end sub

sub onPreviewLogoStatus()
    if m.previewChannelLogo = invalid then return
    if m.previewChannelLogo.loadStatus <> "failed" then return
    if Left(m.previewChannelLogo.uri, 4) = "pkg:" then return
    channel = m.previewChannelLogoChannel
    if channel = invalid then return
    current = _currentChannel()
    if current <> invalid and channel.url <> invalid and channel.url <> current.url then
        print ">>> ICON: previewChannelLogo stale — ignoring"
        return
    end if
    fallback = _categoryIconUrl(channel)
    print ">>> ICON: previewChannelLogo failed, falling back to "; fallback
    m.previewChannelLogo.uri     = fallback
    m.previewChannelLogo.visible = true
end sub
