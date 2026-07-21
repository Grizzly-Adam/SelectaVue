# SelectaVue IPTV Player

SelectaVue manages and plays M3U playlists with a clean, fast interface built for easy and intuitive navigation across multiple playlists.

## 🎯 Features

- **Multiple M3U playlists** — Save and quickly switch between multiple playlist URLs
- **Channel grid** — Browse channels organized by category with section headers
- **Preview** — A small window in the top right corner of the channel grid allows you to preview channels before launching in full screen
- **Channelbar** - A channelbar with playlist name, channel name, and option buttons is available in full-screen mode
- **Quick menu** — Press ← while watching to browse all channels without pausing video
- **Favorites** - Easily add channels as favorites by pressing * on channel list or selecting the "⭐" button from channelbar
- **Closed captioning** — Turn closed captioning on/off (when available) from the channelbar "CC" button, or using Roku's built in * menu
- **Reload/Jump to live** — Press → or select the LIVE button from the channelbar to reload the stream, or jump to live if stream was paused
- **Channel information** - Display channel stream details by selecting the "ℹ️" button from the channelbar
- **Hide channel** - Hide/unhide unwanted channels by clicking the channelbar "👁" button
- **Special views** - Switch from standard grid view to Favorites or Hidden channels view
- **Page up/down** — Use Fast Forward / Rewind to page up/down on the channel grid and in the quick menu
- **Channel surf** — Switch channels by pressing up/down while in fullscreen
- **Multi-format** — HLS, MP4, DASH, TS, and more; format auto-detected from stream URL
- **Smart buffering** — Loading progress bar shown during buffering; automatic multi-step retry with progressively lower bitrate; proactive bandwidth step-down when buffer is sluggish
- **Manifest patching** — Automatically fixes common HLS manifest problems (missing bitrate info, flat manifests, LL-HLS markers) that cause streams to fail on Roku but work in VLC
- **Per-stream headers** — Reads `#EXTVLCOPT` User-Agent and Referrer overrides from M3U playlists so streams that require specific headers play correctly
- **Error reporting** — Friendly error messages with channel name and description of the problem
- **Phone/QR text entry** — Scan a QR code to input playlist names and URLs from your phone instead of the remote

## 📥 Installation

Visit https://developer.roku.com/dev/docs/developer-setup for sideloading instructions

## 🎮 Controls

### Playlist list

| Button             | Action                                                     |
| ------------------ | ---------------------------------------------------------- |
| **↑↓**             | Browse playlists                                           |
| **→**              | Switch to channel grid                                     |
| **OK**             | Select playlist                                            |
| **✱**              | Playlist menu (Show hidden channels, edit/delete playlist) |

### Channel grid

| Button              | Action                                              |
| ------------------- | --------------------------------------------------- |
| **↑↓**              | Browse channels                                     |
| **←**               | Switch to playlist list                             |
| **→**               | Go fullscreen with the previewing channel           |
| **OK** (once)       | Load selected channel in preview window             |
| **OK** (twice)      | Go fullscreen with the previewing channel           |
| **⏪ Rewind**       | Page up                                             |
| **⏩ Fast Forward** | Page down                                           |
| **✱**               | Add/remove selected channel as favorite             |
| **Instant Replay**  | Jump to previously viewed channel, does not start   |

> **Tip:** Channels with multiple categories will appear in each of their categories.

### Fullscreen playback

| Button              | Action                                              |
| ------------------- | --------------------------------------------------- |
| **OK**              | Open channelbar                                |
| **Play/Pause**      | Pause or resume video                               |
| **↑**               | Channel surf to previous channel                    |
| **↓**               | Channel surf to next channel                        |
| **←**               | Show quick menu (video continues playing)           |
| **→**               | Reload the current channel                          |
| **Instant Replay**  | Jump to previous channel                            |
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


### Channelbar (press OK while in fullscreen)

| Button                | Action                                             |
| --------------------- | -------------------------------------------------- |
| **←→**                | Select channelbar buttons                          |
| **Back**              | Close the channelbar                               |
| ⭐ **Favorites**      | Add/remove channel from favorites list             |
| **Closed captioning** | Toggles closed captioning on and off               |
| ℹ️ **Channel info**   | Display information about the current channel      |
| 🎬 **Live**           | Reload/jump to live video                          |
| 👁 **Show/hide**       | Shows/hides the current playing channel            |


## 📺 Playlists

Use your own M3U playlist or your IPTV provider's URL, see **Playlist resources** below

**Supported formats:**
- HTTP/HTTPS URLs
- M3U format with EXTINF labels
- Channel groups via `group-title` (semicolon-separated for multiple categories)

### Included free channel lists (not available in the Roku Channel Store version)

- 🇺🇸 United States
- 🇨🇦 Canada
- 🇦🇺 Australia
- 🇬🇧 United Kingdom

### Add a custom playlist
1. Select **➕ Add List** in the playlist list
2. Enter a name for your playlist — either with the on-screen keyboard, or by scanning the QR code with your phone
3. Enter the URL of your M3U playlist the same way
4. Your list will appear in the menu immediately

**Playlist resources:**
- [IPTV-ORG](https://github.com/iptv-org/iptv) — Global collection
- [IPTV-ORG](https://iptv-org.github.io/iptv/countries/au.m3u) — Australia playlist
- [IPTV-ORG](https://iptv-org.github.io/iptv/countries/ca.m3u) — Canada playlist
- [IPTV-ORG](https://iptv-org.github.io/iptv/countries/uk.m3u) — United Kingdom playlist
- [IPTV-ORG](https://iptv-org.github.io/iptv/countries/us.m3u) — United States playlist

## 🔧 Troubleshooting

**The app closes on startup:**
- Check your internet connection
- Try a smaller playlist first

**Black Screen**
- Press **↑** or **↓**  to surf to another channel
- Press the back button to move to grid view and verify that your playlist has loaded

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

- **Current version:** 1.6.1
- **Last updated:** July 21, 2026


## 📄 Legal

- [Privacy Policy](PRIVACY_POLICY.md)
- [Terms of Service](TERMS_OF_SERVICE.md)

## 📧 Contact

- Email: grizzsoft@gmail.com
- GitHub: https://github.com/Grizzly-Adam/SelectaVue
