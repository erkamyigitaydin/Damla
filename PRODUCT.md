# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

Recorded for the design surfaces Impeccable works on (the marketing site in `docs/`). The product itself is a native macOS app (Swift/SwiftUI/AppKit, macOS 26+, universal binary), which none of the ios/android values describe.

## Stack

- App: Swift 6 package, built with `build.sh`, released with `release.sh` (Developer ID, notarization, Sparkle appcast, GitHub Release, Homebrew tap).
- Website: plain static HTML/CSS/JS in `docs/`, served at https://damla.erkamaydin.com by the Cloudflare Worker in `server/feed` (static assets plus /appcast.xml, /latest.json, /download/*). No build step. The ebru runs in a module worker on an OffscreenCanvas (`docs/assets/engine.js`), with an on-page fallback.

## Users

Mac users with a notched MacBook (and external displays, where Damla draws its own notch) who want the notch to be useful. A strong subgroup is developers running AI coding agents (Claude Code, Codex CLI) in the background who want to see status and approve commands without switching windows. The owner is a Turkish solo developer; the audience is global.

## Product Purpose

Damla turns the MacBook notch into a small Liquid Glass hub, led on the website by the developer use: Claude Code and Codex sessions, approvals and questions answered from the notch. Hovering the notch melts a panel out of it with whatever is needed right now (now playing, sound, files, clipboard, focus, AI agents) and it slips back when the pointer leaves. Success on the website: a visitor understands this in seconds and installs it (Homebrew cask or DMG).

## Positioning

- The notch as a living surface: the panel grows out of the notch itself, and on displays without a notch Damla draws one.
- A droplet mascot that acts out what an AI agent is doing (hops while working, turns amber and waves when waiting, smiles when done).
- Claude Code and Codex CLI permission requests answered from the notch (Allow / Deny / Always allow), with context and usage limits shown.
- No account, no server, no tracking.

## Operating Context

Hover the notch, click the droplet in the menu bar, or press ⌃⌥Space to open; move away, click, or Esc to close. First launch plays a short tour inside the notch. Permissions are all optional and asked where they come up.

## Capabilities and Constraints

Confirmed features (README and dist/notes-*.md, up to 0.8.2): notifications from other apps as a card dropping from the notch (click to reply or use its buttons, Open, ✕) and a Notifications page stacked per app, memory only; Mirror's panel-wide viewfinder that saves wide Polaroids (cream border, orange date stamp, handwritten date, optional); pages reordered by drag in Settings › General › Pages; all permissions on one tour step; now playing from any app with cover-tinted panel, synced lyrics, smart handoff between players, multiple players side by side, video from Chromium browsers docked under the notch; AI agent sessions and approvals for Claude Code and Codex CLI; file shelf with Quick Look, AirDrop, image convert/compress, PDF merge; sound output switching, AirPods battery, per-app volume; next meeting countdown with one-click join; mic mute; Mirror camera; Shortcuts; low battery warnings; local dev servers; volume/brightness HUDs; clipboard history; focus timer; full-screen aware; cleaning mode; English and Turkish UI.

Constraints: macOS 26 or later. ChatGPT app permission requests cannot be answered from the notch (shown as waiting only). Signed and notarized, auto-updates via Sparkle.

Install: `brew install --cask erkamyigitaydin/tap/damla` or the DMG at https://damla.erkamaydin.com/download/latest. The GitHub repository is going private: the site must not link to GitHub. Contact is mailto:erkamyigitaydin@gmail.com?subject=Damla.

## Brand Commitments

- Name: Damla (Turkish for "drop"). The droplet is the brand, and since 2026-10-01 the mascot is the logo: the app icon is a graphite screen with the black notch at its top and the mascot (a drop with a face, at rest) just melted out of it (`Resources/MakeIcon.swift`). The old mint-drop-on-teal icon is retired.
- Tagline in use: "Your notch, finally doing something."
- Voice: plain, friendly, concrete, a little playful; no hype. README tone is the reference.
- Bilingual: English and Turkish.

## Evidence on Hand

- Screenshots made with demo data: `docs/screenshots/home.png`, `closed.png`, `agents.png`, `approval.png`, `files.png`.
- App icon source: `Resources/MakeIcon.swift`; mascot drawing: `Sources/Damla/Mascot.swift` (100 × 100 box geometry, shared with the site's MASCOT in `docs/assets/site.js`). Site icons (favicon-64, apple-touch-icon, icon-256) come from MakeIcon's output.
- No testimonials, user counts, press, or ratings exist. Do not invent them. The app is free; do not call it open source. No pricing.
- The README screenshots in `docs/screenshots/` predate 0.7–0.8 and no longer match the UI; current feature truth is `dist/notes-*.md`. Fresh reference captures of the live panel (demo data) were taken 2026-09-28 with the `--debug` hooks.

## Product Principles

1. The notch is the stage: everything starts from and returns to it.
2. Glanceable first, actionable second: show state, then offer one tap.
3. Stay out of the way: nothing appears unless it matters now.
4. Private by construction: local only, every permission optional.
5. Personality in small, precise details (the droplet), never noise.

## Accessibility & Inclusion

The app honors Reduce Motion (mascot and loops go still). The website must do the same and remain fully readable without animation.
