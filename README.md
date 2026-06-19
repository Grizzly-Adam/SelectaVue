# SelectaVue IPTV Player

SelectaVue manages and plays M3U playlists with a clean, fast interface built for easy and intuitive navigation across multiple playlists.

## 🎯 Features

- **Multiple M3U playlists** — Save and quickly switch between multiple playlist URLs
- **Channel grid** — Browse channels organized by category with section headers
- **Category jumping** — Use Fast Forward / Rewind to jump between categories instantly
- **Preview** — Preview channels before launching in full screen
- **Quick menu** — Press ← while watching to browse all channels without pausing video
- **Channel surf** — Switch channels up/down while in fullscreen
- **Mute toggle** — Press → to mute or unmute preview and fullscreen audio; mute icon appears on screen
- **Audio options** — Change the audio track or language during playback
- **Subtitles** — Turn subtitles on/off when available
- **Full screen** — 1920×1080 video without letterboxing
- **Multi-format** — HLS, MP4, MKV, AVI and more than 20 formats supported
- **Smart buffering** — Loading progress bar shown during buffering in both grid and fullscreen; automatic retry with lower bitrate if stream stalls
- **Error reporting** — Friendly error messages with channel name and description of the problem
- **Clock** — Current time displayed alongside channel info

## 📥 Installation

https://developer.roku.com/dev/docs/developer-setup

## 🎮 Controls

### Playlist menu

| Button             | Action                                              |
| ------------------ | --------------------------------------------------- |
| **↑↓**             | Browse playlists                                    |
| **→**              | Switch to channel grid                              |
| **OK**             | Select playlist                                     |
| *              | Edit playlist                                       |

### Channel menu

| Button              | Action                                              |
| ------------------- | --------------------------------------------------- |
| **↑↓**              | Browse channels                                     |
| **←**               | Switch to playlist menu                             |
| **→**               | Mute / unmute preview audio                         |
| **OK** (once)       | Load selected channel in preview window             |
| **OK** (twice)      | Go fullscreen with the previewing channel           |
| **⏪ Rewind**       | Page up                                             |
| **⏩ Fast Forward** | Page down                                           |
| **Instant Replay**  | Reload current preview channel                      |

> **Tip:** Channels with multiple categories will appear in each of their categories.

### Fullscreen playback

| Button              | Action                                              |
| ------------------- | --------------------------------------------------- |
| **OK**              | Open options menu (audio, subtitles, info)          |
| **Play/Pause**      | Pause or resume video                               |
| **↑**               | Channel surf to previous channel                    |
| **↓**               | Channel surf to next channel                        |
| **⏪ Rewind**       | Page up                                             |
| **⏩ Fast Forward** | Page down                                           |
| **←**               | Show quick menu (video continues playing)           |
| **→**               | Mute / unmute audio                                 |
| **Instant Replay**  | Reload the current channel                          |
| **Back**            | Return to grid (video continues in preview)         |

> **Tip:** Channels are cyclical — the last one connects back to the first.

> **Tip:** If the video freezes, press **Instant Replay** to reload the channel.

### Quick menu (press ← while in fullscreen)

| Button              | Action                                              |
| ------------------- | --------------------------------------------------- |
| **↑↓**              | Browse channels                                     |
| **⏪ Rewind**       | Page up                                             |
| **⏩ Fast Forward** | Page down                                           |
| **OK**              | Switch to selected channel                          |
| **← or →**          | Close quick menu                                    |

### Options menu (press OK while in fullscreen)

- 🔊 **Change Audio** — Select the audio track or language
- 💬 **Subtitles** — Turn subtitles on or off
- ℹ️ **Channel Info** — Display information about the current channel
- ❌ **Close** — Close the options menu

## 📺 Playlists

Use your own M3U playlist or your IPTV provider's URL.

**Supported formats:**
- HTTP/HTTPS URLs
- M3U format with EXTINF labels
- Channel groups via `group-title` (semicolon-separated for multiple categories)

### Included free channel lists

- 🇺🇸 United States
- 🇨🇦 Canada
- 🇦🇺 Australia
- 🇬🇧 United Kingdom
- 🇯🇵 Japan
- 🇰🇷 Korea

### Add a custom playlist
1. Select **➕ Add List** in the playlist menu
2. Enter a name for your list
3. Enter the URL of your M3U playlist (must start with http:// or https://)
4. Your list will appear in the menu immediately

**Playlist resources:**
- [M3U.cl](https://m3u.cl/) — Listings by country
- [IPTV-ORG](https://github.com/iptv-org/iptv) — Global collection

## 🔧 Troubleshooting

**The app closes on startup:**
- Check your internet connection
- Try a smaller playlist first

**The playlist is not loading:**
- Verify the URL is accessible from a browser
- Make sure the format is valid M3U
- Try the default demo playlist

**No audio tracks appear:**
- Wait a few seconds after the channel starts playing
- Not all channels have multiple audio tracks
- Press OK to see available options

**A channel shows an error:**
- Channels go on and offline; some may be temporarily unavailable
- The app will automatically retry with a lower bitrate before showing an error
- Use ↑↓ to switch to another channel

**Debug (telnet log):**
```bash
telnet YOUR_ROKU_IP 8085
```

## 📋 Version

- **Current version:** 1.1.2
- **Last updated:** Jun 19, 2026

## 📄 Legal

- [Privacy Policy](PRIVACY_POLICY.md)
- [Terms of Service](TERMS_OF_SERVICE.md)

## 📧 Contact

- Email: grizzsoft@gmail.com
- GitHub: https://github.com/Grizzly-Adam/SelectaVue
