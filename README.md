<p align="center">
  <img src="docs/screenshots/home.png" width="600" alt="Damla's panel opened from the MacBook notch, playing a song">
</p>

<h1 align="center">Damla</h1>

<p align="center">
  <b>Your notch, finally doing something.</b><br>
  Music, sound, files, clipboard, focus and your AI coding agents, one glance away at the top of your screen.
</p>

<p align="center">
  <a href="https://github.com/erkamyigitaydin/Damla/releases/latest"><img src="https://img.shields.io/github/v/release/erkamyigitaydin/Damla?label=download&color=f28b6d" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-3d4a9e" alt="macOS 26 or later">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-555" alt="Universal binary">
</p>

---

The notch sits there all day doing nothing. Damla turns it into a small Liquid Glass hub: hover over it and a panel melts out of the notch with whatever you need right now, then slips back when you move away. No external monitor gets left out either. On displays without a notch, Damla draws one into the menu bar.

No account, no server, no tracking. Everything stays on your Mac.

## Install

```sh
brew install --cask erkamyigitaydin/tap/damla
```

Or grab the `.dmg` from the [latest release](https://github.com/erkamyigitaydin/Damla/releases/latest) and drag Damla to Applications. It's signed and notarized by Apple, so it opens without warnings, and it keeps itself up to date.

## What it does

### Now playing, from anything

<p align="center">
  <img src="docs/screenshots/closed.png" width="550" alt="The closed notch showing album art, an equalizer and an agent waiting for approval">
</p>

Apple Music, Spotify, Podcasts, YouTube in the browser: if it's playing, Damla shows it. Cover art, progress, play/pause, skip, and a heart for your Apple Music favorites. No setup, no log-ins.

- **Lyrics that scroll with the song.** Tap the lyrics button and the panel stretches down into an Apple Music-style lyrics view. Tap any line to jump there.
- **Smart handoff.** Start a video and your music pauses (or ducks). Stop the video and the music picks up where it left off.
- **Every player, side by side.** Several apps playing? Switch between them in one tap.
- **Watch the video in the notch.** Playing a video in Chrome, Brave, Edge or Vivaldi? One tap and it keeps playing under the notch, even with the browser in the background: pause it, make it bigger, or jump back to its tab. A one-time setup card walks you through the permissions it needs.
- **Colors from the cover.** The whole panel picks up the tint of the album you're listening to.

### Your AI agents, at a glance

<p align="center">
  <img src="docs/screenshots/agents.png" width="550" alt="The agents page showing one Claude Code session waiting for approval and one working">
</p>

Running Claude Code or Codex in the background? Damla shows every session: which project is working, which one needs you, and how long it's been waiting. A little droplet mascot lives in the notch and reacts: it bounces while an agent works, waves when one needs you, and smiles when it's done. Click a session to bring the app it runs in (Terminal, your editor or the Claude app) to the front. For Claude Code you also see how full each session's context is and, on Pro and Max plans, how much of your five-hour and weekly limits you've used, with a heads-up in the notch at 80 % and 95 %.

### Approve commands without switching apps

<p align="center">
  <img src="docs/screenshots/approval.png" width="550" alt="A Claude Code permission request shown in the notch with Allow and Deny buttons">
</p>

When Claude Code or the Codex CLI asks for permission, the question drops out of the notch with the exact command (or, for a Codex patch, the files it touches). Hit **Allow** or **Deny** (or ⌃⌥↩ / ⌃⌥⌫), or **Always allow** to save the rule Claude Code suggests. When Claude Code asks you to pick between options, you can answer that from the notch too. If you're already looking at the terminal, Damla stays out of the way. The ChatGPT app's own permission requests can only be answered in its window; Damla shows them as waiting so you don't miss them.

### A shelf for your files

<p align="center">
  <img src="docs/screenshots/files.png" width="550" alt="The file shelf holding images and a PDF">
</p>

Start dragging a file anywhere and the notch opens into a drop zone. Park files there, preview them with **Space** (Quick Look), drag them out into another app, or AirDrop them. New screenshots land on the shelf by themselves. Right-click an image to save it as PNG, JPEG or HEIC, shrink it or compress it, or merge the PDFs on the shelf into one; the result is a new file next to the original. Damla only remembers where your files are; it never moves or changes them.

### And more

- **Sound, your way.** Switch outputs, see your AirPods' battery (each bud and the case) when they connect and right in the output list, and set the volume of each app separately.
- **Swipe between pages.** With the panel open, swipe left or right with two fingers on the trackpad.
- **Your next meeting** counts down in the notch from ten minutes before, and one click joins the Zoom, Meet, Teams, Webex or FaceTime call (off until you turn it on).
- **Microphone in use?** The notch shows it during calls, and a tap mutes it for every app at once.
- **Mirror** shows your camera before a call. The camera runs only while that page is open.
- **Shortcuts** from the Shortcuts app, pinned as one-tap buttons.
- **Low battery warnings** for your mouse, keyboard, trackpad and AirPods.
- **Local servers** on the Agents page: every dev server and database running on your Mac, one click to open or stop.
- **Beautiful volume and brightness indicators** that replace the system ones.
- **Clipboard history** with search and pinning (off until you turn it on).
- **Focus timer** for 25/45/50 minute sessions, with the countdown right in the notch.
- **Full-screen aware.** The notch hides with the menu bar in full-screen apps and comes back when you reach for it.
- **Cleaning mode** locks the keyboard for 60 seconds so you can wipe it without typing gibberish.
- **English and Turkish** interface.

## Getting started

- **Open:** hover over the notch, click the droplet in the menu bar, or press **⌃⌥Space**.
- **Close:** move the pointer away, click the notch, or press **Esc**.
- **Keep it open:** the pin button.
- **Settings:** the gear button, the menu bar icon or **⌘,**.

On first launch a short tour plays right inside the notch, one feature at a time, and asks for the few permissions Damla can use where they come up. Every one of them is optional:

| Permission | What it unlocks |
|---|---|
| Automation (Music, Spotify) | Controlling Apple Music and Spotify in the background, and their volume |
| Accessibility | Damla's own volume/brightness indicators and Cleaning mode |
| System audio recording | Per-app volume in the mixer. Nothing is recorded or sent anywhere |
| Calendars | Your next meeting in the notch, once you turn it on |
| Camera | The Mirror page, only while it's open |

### Connecting your agents

Open the tour from the menu bar (**Tour…**) and, at the **Agents** step, click **Connect Claude Code** or **Connect Codex**. Or connect them any time in **Settings → Agents**.

Damla keeps your existing `~/.claude/settings.json` and `~/.codex/hooks.json` and leaves a backup of every file it changes. For Claude Code it also sets a status line (model, context and five-hour use); if you already have one, yours keeps running and Damla only reads the data passing through. In Codex, approve the new hooks once with `/hooks`. While the notch is asking, Codex holds back its own prompt; switch to the session's app and the prompt shows up there right away. The hooks only record status (phase, tool name, timing). Your prompts, conversations and command output are never read.

## Privacy

- No account, no server, no analytics.
- Your shelf, clipboard history and timer live in `~/Library/Application Support/Damla/`.
- Now-playing info is read locally from macOS.
- Video in the notch captures only the browser's own picture-in-picture window, on your Mac; nothing is recorded or sent.
- Only two things ever touch the network: lyrics, if you turn them on (title, artist, album and duration go to [lrclib.net](https://lrclib.net)), and the daily update check.

## Building from source

You need Swift 6 and the Xcode Command Line Tools.

```sh
zsh build.sh                                  # builds and signs ../Damla.app, then runs the self-test
../Damla.app/Contents/MacOS/Damla --self-test # automated checks
../Damla.app/Contents/MacOS/Damla --diagnose  # displays, battery, volume, brightness and audio outputs
```

<details>
<summary>More for developers</summary>

- **Code map:** `Layout.swift` is the single source of truth for shapes and window sizes. `PanelController.swift` runs one window per display. `MediaSessionStore` keeps the media logic free of AppKit so it can be tested.
- **Localization:** keys are the Turkish source strings; the English text lives in `Resources/en.lproj/Localizable.strings`.
- **Automation:** launched with `--debug`, the app listens for `app.local.damla.debug` distributed notifications (`open`, `tab-agents`, `media-showcase`, `files:<paths>`…). With `DAMLA_SUPPORT_DIR` set, a debug run keeps its data in that folder. The screenshots above were made this way with demo data.
- **Hooks from the command line:** `python3 scripts/install-agent-hooks.py --binary <path to Damla binary> [--approvals] --apply` does what connecting in Damla does (without `--apply` it only prints the plan). Tests: `PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-agent-hooks.py`.
- **Releasing:**
  1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` and commit.
  2. Write the release notes to `dist/notes-<version>.md`.
  3. Run `zsh release.sh`. It builds a universal binary, signs it with Developer ID, notarizes it, signs the update for Sparkle, updates `appcast.xml`, publishes the GitHub Release and updates the Homebrew tap.

</details>

## Thanks

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3, bundled in `Vendor/MediaRemoteAdapter`): now-playing info on modern macOS.
- [Sparkle](https://sparkle-project.org): updates.
- [LRCLIB](https://lrclib.net): lyrics.
