' ==================== Utils.brs ====================
' Pure helper functions with no side-effects.
' Safe to call from any other module.

function isValidUrl(url as String) as Boolean
    if url = "" then return false
    httpReg = CreateObject("roRegex", "^https?://", "i")
    if not httpReg.isMatch(url) then return false
    urlReg = CreateObject("roRegex", "^https?://[^\s/$.?#].[^\s]*$", "i")
    return urlReg.isMatch(url)
end function

function getFriendlyError(errorMsg as String) as String
    if errorMsg = invalid or errorMsg = "" then
        return "The stream could not be loaded. The channel may be offline or the URL may be invalid."
    end if

    msg = LCase(errorMsg)

    if msg.InStr("404") >= 0 or msg.InStr("not found") >= 0 then
        return "Stream not found (404). The channel URL may be incorrect or the stream has moved."
    else if msg.InStr("403") >= 0 or msg.InStr("forbidden") >= 0 then
        return "Access denied (403). This stream may be geo-restricted or require authentication."
    else if msg.InStr("401") >= 0 or msg.InStr("unauthorized") >= 0 then
        return "Unauthorized (401). This stream requires a login or subscription."
    else if msg.InStr("500") >= 0 or msg.InStr("server error") >= 0 then
        return "Server error (500). The streaming server is having problems. Try again later."
    else if msg.InStr("timeout") >= 0 or msg.InStr("timed out") >= 0 then
        return "Connection timed out. The stream is taking too long to respond. Check your network."
    else if msg.InStr("network") >= 0 or msg.InStr("connect") >= 0 then
        return "Network error. Check your internet connection and try again."
    else if msg.InStr("drm") >= 0 or msg.InStr("license") >= 0 then
        return "DRM / copy protection error. This stream uses a protection scheme that is not supported."
    else if msg.InStr("format") >= 0 or msg.InStr("codec") >= 0 or msg.InStr("unsupported") >= 0 then
        return "Unsupported format. This stream uses a codec or container that cannot be played."
    else if msg.InStr("empty") >= 0 or msg.InStr("no data") >= 0 then
        return "Empty stream. The channel URL returned no playable content."
    else if msg.InStr("ssl") >= 0 or msg.InStr("certificate") >= 0 then
        return "SSL / certificate error. There was a problem with the stream's security certificate."
    else if msg.InStr("dns") >= 0 or msg.InStr("resolve") >= 0 then
        return "DNS error. The stream's server address could not be found. Check your network."
    end if

    return "Playback error: " + errorMsg
end function

function getLanguageName(code as String) as String
    languages = {
        "es": "Spanish",   "spa": "Spanish",   "spanish": "Spanish",
        "en": "English",   "eng": "English",   "english": "English",
        "pt": "Portugues", "por": "Portugues", "portuguese": "Portugues",
        "fr": "French",    "fra": "French",    "fre": "French",    "french": "French",
        "de": "German",    "deu": "German",    "ger": "German",    "german": "German",
        "it": "Italian",   "ita": "Italian",   "italian": "Italian",
        "ja": "Japanese",  "jpn": "Japanese",  "japanese": "Japanese",
        "ko": "Korean",    "kor": "Korean",    "korean": "Korean",
        "zh": "Chinese",   "chi": "Chinese",   "zho": "Chinese",   "chinese": "Chinese",
        "ru": "Russian",   "rus": "Russian",   "russian": "Russian",
        "ar": "Arab",      "ara": "Arab",      "arabic": "Arab",
        "und": "Unknown",  "mul": "Multiple"
    }
    lowerCode = LCase(code)
    if languages.DoesExist(lowerCode) then return languages[lowerCode]
    return code
end function

function toStr(value as Dynamic) as String
    if value = invalid then return "N/A"
    if type(value) = "String" or type(value) = "roString" then return value
    if type(value) = "Integer" or type(value) = "roInt" then return value.ToStr()
    if type(value) = "Float" or type(value) = "roFloat" then return Str(value)
    return type(value)
end function
