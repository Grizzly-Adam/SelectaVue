sub init()
	m.top.functionName = "getContent"
end sub

sub getContent()
	feedurl = m.global.feedurl

	m.port = CreateObject("roMessagePort")
	searchRequest = CreateObject("roUrlTransfer")
	searchRequest.setURL(feedurl)
	searchRequest.SetPort(m.port)
	searchRequest.EnableEncodings(true)
	httpsReg = CreateObject("roRegex", "^https:", "")
	if httpsReg.isMatch(feedurl)
		searchRequest.SetCertificatesFile("common:/certs/ca-bundle.crt")
		searchRequest.AddHeader("X-Roku-Reserved-Dev-Id", "")
		searchRequest.InitClientCertificates()
	end if

	if searchRequest.AsyncGetToString()
		event = wait(60000, m.port)
		if type(event) = "roUrlEvent"
			responseCode = event.GetResponseCode()
			if responseCode = 200
				text = event.GetString()
				if text = "" or text = invalid then
					print ">>> PLAYLIST ERROR: Response was empty or invalid"
					print ">>> PLAYLIST ERROR: URL = "; feedurl
					m.top.content = CreateObject("roSGNode", "ContentNode")
					return
				end if
			else
				print ">>> PLAYLIST ERROR: HTTP error code "; responseCode; " for URL: "; feedurl
				if responseCode = 401 then print ">>> PLAYLIST ERROR: Unauthorized"
				if responseCode = 403 then print ">>> PLAYLIST ERROR: Forbidden"
				if responseCode = 404 then print ">>> PLAYLIST ERROR: Not found"
				if responseCode = 500 then print ">>> PLAYLIST ERROR: Server error"
				if responseCode = 0   then print ">>> PLAYLIST ERROR: No response"
				m.top.content = CreateObject("roSGNode", "ContentNode")
				return
			end if
		else
			print ">>> PLAYLIST ERROR: Request timed out after 60 seconds for URL: "; feedurl
			m.top.content = CreateObject("roSGNode", "ContentNode")
			return
		end if
	else
		print ">>> PLAYLIST ERROR: Failed to start HTTP request for URL: "; feedurl
		m.top.content = CreateObject("roSGNode", "ContentNode")
		return
	end if

	reHasGroups = CreateObject("roRegex", "group-title=" + chr(34) + "?([^" + chr(34) + "]*)" + chr(34) + "?,", "")
	hasGroups   = reHasGroups.isMatch(text)
	print ">>> PLAYLIST: Has groups = "; hasGroups

	reLineSplit = CreateObject("roRegex", "(?>\r\n|[\r\n])", "")
	reExtinf    = CreateObject("roRegex", "(?i)^#EXTINF:\s*(\d+|-1|-0).*,\s*(.*)$", "")
	reSemicolon = CreateObject("roRegex", ";", "")
	rePath      = CreateObject("roRegex", "^([^#].*)$", "")
	reVlcUA     = CreateObject("roRegex", "(?i)^#EXTVLCOPT:http-user-agent=(.*)$", "")
	reVlcRef    = CreateObject("roRegex", "(?i)^#EXTVLCOPT:http-referrer=(.*)$", "")
	reVlcCookie = CreateObject("roRegex", "(?i)^#EXTVLCOPT:http-cookie=(.*)$", "")
	reTvgId     = CreateObject("roRegex", "(?i)tvg-id=" + chr(34) + "([^" + chr(34) + "]*)" + chr(34), "")
	reTvgLogo   = CreateObject("roRegex", "(?i)tvg-logo=" + chr(34) + "([^" + chr(34) + "]*)" + chr(34), "")

	inExtinf         = false
	groupNames       = []
	channelCount     = 0
	pendingUserAgent = ""
	pendingReferrer  = ""
	pendingCookie    = ""
	pendingTvgId     = ""
	pendingLogo      = ""

	' Collected during parsing; each entry is {url, title, description,
	' group} — group is "" for ungrouped channels, or one of possibly
	' several group names for a channel tagged under multiple categories
	' (each membership becomes its own entry, sharing the same url/title).
	' Sorted and assembled into the final tree by the shared
	' buildSortedChannelTree() (see components/Shared/PlaylistSort.brs).
	allItems = []

	for each line in reLineSplit.Split(text)
		if inExtinf
			' Collect #EXTVLCOPT lines between #EXTINF and the URL
			maUA = reVlcUA.Match(line)
			if maUA.Count() = 2
				pendingUserAgent = _stripLeadingColons(maUA[1].Trim())
				continue for
			end if
			maRef = reVlcRef.Match(line)
			if maRef.Count() = 2
				pendingReferrer = _stripLeadingColons(maRef[1].Trim())
				continue for
			end if
			maCookie = reVlcCookie.Match(line)
			if maCookie.Count() = 2
				pendingCookie = _stripLeadingColons(maCookie[1].Trim())
				continue for
			end if

			maPath = rePath.Match(line)
			if maPath.Count() = 2
				url  = maPath[1]
				desc = invalid
				if pendingUserAgent <> "" or pendingReferrer <> "" or pendingCookie <> "" or pendingLogo <> "" or pendingTvgId <> "" then
					desc = "UA:" + pendingUserAgent + "||REF:" + pendingReferrer + "||COOKIE:" + pendingCookie + "||TVGID:" + pendingTvgId + "||LOGO:" + pendingLogo
				end if
				if hasGroups and groupNames.Count() > 0
					for each gName in groupNames
						allItems.Push({ url: url, title: title, description: desc, group: gName })
					end for
				else
					allItems.Push({ url: url, title: title, description: desc, group: "" })
				end if
				channelCount     = channelCount + 1
				inExtinf         = false
				groupNames       = []
				pendingUserAgent = ""
				pendingReferrer  = ""
				pendingCookie    = ""
				pendingTvgId     = ""
				pendingLogo      = ""
			end if
		end if

		maExtinf = reExtinf.Match(line)
		if maExtinf.Count() = 3
			groupNames       = []
			pendingUserAgent = ""
			pendingReferrer  = ""
			pendingCookie    = ""
			if hasGroups
				maGroup = reHasGroups.Match(line)
				if maGroup.Count() >= 2 then
					rawGroup = maGroup[1]
					if rawGroup = "" or rawGroup = invalid then
						groupNames.Push("Other")
					else
						parts = reSemicolon.Split(rawGroup)
						for each part in parts
							trimmed = part.Trim()
							if trimmed <> "" then groupNames.Push(trimmed)
						end for
						if groupNames.Count() = 0 then groupNames.Push("Other")
					end if
				else
					groupNames.Push("Other")
				end if
			end if
			length = maExtinf[1].ToInt()
			if length < 0 then length = 0
			title = maExtinf[2]
			if title = "" or title = invalid then title = "Unknown Channel"
			pendingTvgId = ""
			pendingLogo  = ""
			maTvgId = reTvgId.Match(line)
			if maTvgId.Count() = 2 then pendingTvgId = maTvgId[1].Trim()
			maTvgLogo = reTvgLogo.Match(line)
			if maTvgLogo.Count() = 2 then pendingLogo = maTvgLogo[1].Trim()
			inExtinf = true
		end if
	end for

	print ">>> PLAYLIST: Total channels loaded: "; channelCount
	if channelCount = 0 then
		print ">>> PLAYLIST WARNING: No channels found. Check M3U format for URL: "; feedurl
	end if

	m.top.content = buildSortedChannelTree(allItems)
end sub

' Strips any leading colons and spaces from a string.
' Some M3U sources write "#EXTVLCOPT:http-referrer=:https://..." with an
' accidental colon after the equals sign. This cleans it up at parse time
' so the value stored in description is always the bare URL/string.
function _stripLeadingColons(s as String) as String
	if s = "" or s = invalid then return ""
	i = 1
	while i <= Len(s)
		c = Mid(s, i, 1)
		if c = ":" or c = " " then
			i = i + 1
		else
			exit while
		end if
	end while
	return Mid(s, i)
end function
