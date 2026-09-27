# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

Recorded for the design surfaces Impeccable works on (the marketing site in `docs/`). The product itself is a native macOS app (Swift/SwiftUI/AppKit, macOS 26+, universal binary), which none of the ios/android values describe.

## Stack

- App: Swift 6 package, built with `build.sh`, released with `release.sh` (Developer ID, notarization, Sparkle appcast, GitHub Release, Homebrew tap).
- Website: plain static HTML/CSS/JS in `docs/`, served by GitHub Pages from `main /docs`. No build step. Chosen by the owner on 2026-09-28.

## Users

Mac users with a notched MacBook (and external displays, where Damla draws its own notch) who want the notch to be useful. A strong subgroup is developers running AI coding agents (Claude Code, Codex CLI) in the background who want to see status and approve commands without switching windows. The owner is a Turkish solo developer; the audience is global.

## Product Purpose

Damla turns the MacBook notch into a small Liquid Glass hub. Hovering the notch melts a panel out of it with whatever is needed right now (now playing, sound, files, clipboard, focus, AI agents) and it slips back when the pointer leaves. Success on the website: a visitor understands this in seconds and installs it (Homebrew cask or DMG).

## Positioning

- The notch as a living surface: the panel grows out of the notch itself, and on displays without a notch Damla draws one.
- A droplet mascot that acts out what an AI agent is doing (hops while working, turns amber and waves when waiting, smiles when done).
- Claude Code and Codex CLI permission requests answered from the notch (Allow / Deny / Always allow), with context and usage limits shown.
- No account, no server, no tracking.

## Operating Context

Hover the notch, click the droplet in the menu bar, or press ⌃⌥Space to open; move away, click, or Esc to close. First launch plays a short tour inside the notch. Permissions are all optional and asked where they come up.

## Capabilities and Constraints

Confirmed features (from README): now playing from any app with cover-tinted panel, synced lyrics, smart handoff between players, multiple players side by side, video from Chromium browsers docked under the notch; AI agent sessions and approvals for Claude Code and Codex CLI; file shelf with Quick Look, AirDrop, image convert/compress, PDF merge; sound output switching, AirPods battery, per-app volume; next meeting countdown with one-click join; mic mute; Mirror camera; Shortcuts; low battery warnings; local dev servers; volume/brightness HUDs; clipboard history; focus timer; full-screen aware; cleaning mode; English and Turkish UI.

Constraints: macOS 26 or later. ChatGPT app permission requests cannot be answered from the notch (shown as waiting only). Signed and notarized, auto-updates via Sparkle.

Install: `brew install --cask erkamyigitaydin/tap/damla` or the DMG at https://github.com/erkamyigitaydin/Damla/releases/latest.

## Brand Commitments

- Name: Damla (Turkish for "drop"). The droplet is the brand: app icon is a pale mint water drop on a deep teal rounded square; the mascot is a drop with a face.
- Tagline in use: "Your notch, finally doing something."
- Voice: plain, friendly, concrete, a little playful; no hype. README tone is the reference.
- Bilingual: English and Turkish.

## Evidence on Hand

- Screenshots made with demo data: `docs/screenshots/home.png`, `closed.png`, `agents.png`, `approval.png`, `files.png`.
- App icon source: `Resources/MakeIcon.swift`; mascot drawing: `Sources/Damla/Mascot.swift`.
- No testimonials, user counts, press, or ratings exist. Do not invent them. The app is free, with its source public on GitHub; the repo has no LICENSE file, so do not call it open source. No pricing.
- The README screenshots in `docs/screenshots/` predate 0.7–0.8 and no longer match the UI; current feature truth is `dist/notes-*.md`. Fresh reference captures of the live panel (demo data) were taken 2026-09-28 with the `--debug` hooks.

## Product Principles

1. The notch is the stage: everything starts from and returns to it.
2. Glanceable first, actionable second: show state, then offer one tap.
3. Stay out of the way: nothing appears unless it matters now.
4. Private by construction: local only, every permission optional.
5. Personality in small, precise details (the droplet), never noise.

## Accessibility & Inclusion

The app honors Reduce Motion (mascot and loops go still). The website must do the same and remain fully readable without animation.
