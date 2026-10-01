---
name: Damla
description: The marketing site for Damla, a macOS notch app, drawn as an ebru tray of dark water that the visitor marbles.
colors:
  ink: "#0a0d12"
  ink-2: "#0e131a"
  ink-3: "#151c26"
  water-night: "#111a27"
  notch-black: "#000000"
  water-blue: "#cce3ff"
  pale-white: "#f3f6fa"
  sea-blue: "#8fb3e6"
  deep-blue: "#3a5a8a"
  abyss-blue: "#162236"
  bone: "#ece9e2"
  cover-coral: "#f4a18b"
  waiting-amber: "#ffcc5c"
  text: "#eceff4"
  mute: "#a4adbb"
  faint: "#737e8f"
  line: "rgba(230, 236, 245, .12)"
typography:
  display:
    fontFamily: "Nunito, ui-rounded, SF Pro Rounded, system-ui, sans-serif"
    fontSize: "clamp(2.9rem, 6.4vw, 6rem)"
    fontWeight: 900
    lineHeight: 0.98
    letterSpacing: "-0.03em"
  headline:
    fontFamily: "Nunito, ui-rounded, SF Pro Rounded, system-ui, sans-serif"
    fontSize: "clamp(2.2rem, 4.2vw, 4rem)"
    fontWeight: 850
    lineHeight: 0.98
    letterSpacing: "-0.03em"
  title:
    fontFamily: "Nunito, ui-rounded, SF Pro Rounded, system-ui, sans-serif"
    fontSize: "1.35rem"
    fontWeight: 850
    lineHeight: 1.15
    letterSpacing: "-0.015em"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, Nunito Sans, system-ui, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, Nunito Sans, system-ui, sans-serif"
    fontSize: "0.85rem"
    fontWeight: 400
    lineHeight: 1.4
  command:
    fontFamily: "JetBrains Mono, ui-monospace, SF Mono, monospace"
    fontSize: "0.82rem"
    fontWeight: 400
rounded:
  sheet: "2px"
  kbd: "6px"
  chip: "10px"
  slip: "12px"
  control: "14px"
  pill: "999px"
spacing:
  gutter: "clamp(16px, 4vw, 56px)"
  section: "clamp(96px, 16vh, 180px)"
  column-gap: "clamp(24px, 4vw, 72px)"
  measure: "44ch"
  container: "1320px"
  container-wide: "1480px"
components:
  button-primary:
    backgroundColor: "{colors.pale-white}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0 24px"
    height: "54px"
  button-primary-hover:
    backgroundColor: "#ffffff"
    textColor: "{colors.ink}"
  button-quiet:
    backgroundColor: "transparent"
    textColor: "{colors.bone}"
    rounded: "{rounded.control}"
    padding: "0 18px"
    height: "46px"
  button-quiet-hover:
    backgroundColor: "rgba(237, 231, 220, .08)"
  command-field:
    backgroundColor: "rgba(10, 13, 18, .86)"
    textColor: "{colors.bone}"
    typography: "{typography.command}"
    rounded: "{rounded.control}"
    padding: "6px 6px 6px 16px"
  copy-chip:
    backgroundColor: "rgba(237, 231, 220, .08)"
    textColor: "{colors.bone}"
    rounded: "{rounded.chip}"
    padding: "0 12px"
    height: "36px"
  copy-chip-done:
    backgroundColor: "{colors.water-blue}"
    textColor: "{colors.ink}"
  notch-nav:
    backgroundColor: "{colors.notch-black}"
    textColor: "#ffffff"
    rounded: "0 0 14px 14px"
    height: "32px"
    width: "196px"
  slip-note:
    backgroundColor: "rgba(10, 13, 18, .6)"
    textColor: "{colors.text}"
    rounded: "{rounded.slip}"
    padding: "12px 14px"
---

# Design System: Damla

## Overview

**Creative North Star: "The Ebru Tray"**

Damla means drop, and the site is a tray of dark water. The ground is near-black cool ink, the same black as the notch it hangs from. Pigment lands on it only in two ways: once, when the page opens and a drop falls from the notch and is pulled into a tulip, and afterwards only when the visitor clicks. A drag combs what is there, and scrolling pulls slow tines through it. Everything else holds still. Calm water is the default state, and pigment is an event.

The pigments are Damla's own in-app colours, not a generic marbling palette. The agents' pale water blue leads, white is the default accent, bone is the paper, and the demo cover's coral is used sparingly. Amber means one thing, as it does in the app: something is waiting. The product appears as a faithful replica of the live panel, drawn at the app's native point size in the system font and scaled as one piece, so the page shows the real thing rather than an illustration of it.

The page reads as a sequence, developer first: the tray (headline about coding agents), a pinned stage where the panel melts out of the notch and turns its pages (agents, notifications, now playing, shelf, Mirror), a book of pulled ebru sheets for everything else, a quiet privacy statement, and a finale that installs in one line beside the visitor's own marbling pulled as a print. Liquid Glass lens effects were tried on this surface and rejected; so were automatic pours, a mint accent, and "demo data" disclaimers.

**Key Characteristics:**
- Near-black cool ink ground; calm until the visitor touches it.
- Tonal blue pigments with bone paper and a sparing coral.
- Rounded heavy display (Nunito 850–900) over the Mac's own system text.
- The product appears as an exact-scale replica of the live panel, never a mockup.
- Pulled paper sheets with bone edges, slightly rotated, carry secondary features.
- The site nav is a black notch at the top centre.

## Colors

A cool, near-monochrome night palette of ink and water blues, lit by white and bone, with coral and amber held back for specific jobs.

### Primary
- **Agent Water Blue** (`water-blue`): the agents' colour from the app (Theme.agent) and the site's lead accent. Focus rings, text selection, caret, the copied state of the copy chip, the third line of the privacy statement, the mascot at rest, the first pigment of every sequence.
- **Default White** (`pale-white`): the app's default accent is white, so the site's is too. The primary button, active tab and pressed segment backgrounds, and a pigment in the tray.

### Secondary
- **Cover Coral** (`cover-coral`): the tint of the demo track's cover. It drives the panel's cover-tinted gradient, the progress bar, the Allow button, a selected answer chip, and the focus dial's arc. In the water it appears as one ring among blues, never as a field.
- **Waiting Amber** (`waiting-amber`): Theme.amber. Reserved for waiting state: the waiting agent, its status text, the mascot's waiting phase, and the tab dot that marks a pending request.

### Tertiary
- **Sea Blue** (`sea-blue`), **Deep Blue** (`deep-blue`), **Abyss Blue** (`abyss-blue`): the tonal ramp that the ebru pigments step through, from surface highlight to the dark underlayer. Used in the tray and in the sheet pattern colour sets.
- **Bone** (`bone`): the paper. The held edge of every pulled sheet, the finale print, command text, quiet button text and border, keycaps.

### Neutral
- **Ink** (`ink`): page ground, hero and book backgrounds, text on light fills.
- **Ink 2** (`ink-2`): the privacy section, one step up so the section reads as a change of place without a border-heavy frame.
- **Ink 3** (`ink-3`): canvas background inside sheets before pigment renders.
- **Water Night** (`water-night`): the tray's ground colour on the canvas.
- **Notch Black** (`notch-black`): the notch nav and the panel replica; true black, like the hardware.
- **Text** (`text`), **Mute** (`mute`), **Faint** (`faint`): primary copy, secondary copy and ledes, hints and fine print.
- **Line** (`line`): hairline dividers between sections and definition rows.

### Named Rules
**The Own Colours Rule.** Every accent on the page is a colour the app itself uses. Water blue, white, coral from the cover, amber for waiting. Nothing is imported from a generic marbling or SaaS palette, and there is no mint.

**The Amber Means Waiting Rule.** Amber is never decorative. If it is on screen, something is waiting for the user.

**The Calm Water Rule.** Backgrounds stay calm. The ground is dark tonal blues combed into slow ribbons; bright pigment covers a small share of any viewport and arrives only from the opening drop or a visitor's click.

## Typography

**Display Font:** Nunito (with ui-rounded, SF Pro Rounded, system-ui)
**Body Font:** -apple-system / SF Pro Text on the Mac (with Nunito Sans, system-ui)
**Label/Mono Font:** JetBrains Mono (with ui-monospace, SF Mono), for commands only

**Character:** A soft, heavy rounded display that echoes the droplet, set against the Mac's own text face so body copy reads like the operating system the product lives in.

### Hierarchy
- **Display** (Nunito 900, clamp(2.9rem, 6.4vw, 6rem), 0.98): the hero headline only, max 12ch. The privacy statement uses the same weight at clamp(2.8rem, 7.4vw, 6rem), line-height 1, as three stepped lines.
- **Headline** (Nunito 850, clamp(2.2rem, 4.2vw, 4rem), 0.98): chapter and finale headings. The book heading runs larger (up to 4.6rem, -0.035em).
- **Title** (Nunito 850, 1.35rem, 1.15): sheet titles and small section heads.
- **Body** (system 400, 1.0625rem, 1.55; 1rem under 720px): ledes and descriptions in mute, held to 44–46ch.
- **Label** (system 400, 0.85rem): fine print, install requirements, the version line.
- **Command** (JetBrains Mono, 0.82rem, bone): the Homebrew command and inline code.

### Named Rules
**The Mono Is For Commands Rule.** JetBrains Mono appears only where the visitor would type or copy something. It is never a stylistic label face.

**The Replica Follows The App Rule.** Inside the panel replica and the sheet vignettes, type is the Mac system font at the app's own point sizes (for example 16.5px track titles, 12.5px buttons). The replica never adopts the site's display or body scale.

## Layout

Full-bleed sections with a fluid side gutter (`gutter`) and content capped at 1320px (1480px for the hero and chapters). Section breathing room is tall and fluid (`section`). Text columns are held to 44–46ch.

- **Hero:** a full-viewport tray; headline bottom-left and install block bottom-right in a 7fr / 5fr grid, aligned to the bottom edge, with a gradient from ink at the base so copy sits on calm water. A one-line hint sits bottom-centre until the visitor first touches the water, and is hidden on touch devices.
- **Stage:** a tall scroll track with a pinned full-viewport stage, five chapters: agents (list, approval, question), notifications (card, reply, page), now playing, shelf, Mirror. The panel replica sits top-centre under the notch; each chapter is a 5fr / 2.2fr / 4.4fr grid pinned to the bottom (lead left, points right), crossfading with a blur.
- **Book:** a 12-column grid where each sheet takes a different span, aspect ratio, rotation and vertical offset, so the page reads like sheets laid out to dry rather than a card grid.
- **Privacy and finale:** two-column 5fr / 6fr and 6fr / 5fr splits.
- **Breakpoints:** 1100px (chapters go to two columns), 900px (all splits stack, install block aligns left), 720px (single column; sheets alternate 92% / 84% widths, left and right).

## Elevation & Depth

Depth comes from tone and the physical metaphor more than from shadow. Sections step between ink and ink-2; pinned copy sits on gradients of ink rather than boxes. Shadows are soft, long, negative-spread drops that read as paper or hardware lifting off water, never as UI chrome.

### Shadow Vocabulary
- **Pulled sheet** (`box-shadow: 0 0 0 clamp(6px, .75vw, 11px) #ece9e2, 0 34px 50px -30px rgba(0,0,0,.95)`): the bone held edge and the drop beneath every book sheet.
- **Finale print** (`box-shadow: 0 40px 70px -30px rgba(0,0,0,.9), 0 2px 0 rgba(255,255,255,.4) inset`): the larger pulled print.
- **Primary button** (`box-shadow: 0 10px 24px -12px rgba(0,0,0,.7)`, deepening on hover to `0 16px 30px -14px rgba(0,0,0,.8)`).
- **Panel** (`0 calc(22px * open) calc(44px * open) -14px rgba(0,0,0,.7)`): grows with how far the panel has opened.

### Named Rules
**The No Lens Rule.** No Liquid Glass lens, refraction or frosted-glass cards on the site, and no backdrop blur at all: the command field sits on near-opaque ink. Nothing blends with the moving water (the grain is a plain low-opacity layer).

**The No Overlap Rule.** The panel replica is scaled from the room the tallest chapter leaves (`stage.measure()`); on very short windows the fine print steps aside (`body.tight`). Chapter copy never sits on the panel, and the opening drop lands in the free water above the hero copy.

**The Bounded Water Rule.** The ebru runs off the main thread (module worker + OffscreenCanvas, `engine.js`), stops entirely while off screen, combs once per frame with the scroll distance clamped, and stays inside a vertex budget (26k) and a 1.5× / 3 MP canvas.

## Shapes

Two families that never mix. Site controls are softly rounded rectangles (14px for buttons and the command field, 10px for the copy chip, 12px for slips, 6px for keycaps) and full pills for toggles. Paper is nearly square-cornered (2–3px) and set at a slight rotation (about ±0.6 to ±1.8 degrees), straightening on hover. The notch and panel follow the hardware: flat top, rounded bottom corners (14px closed, 28px open for the nav; 12px to 22px for the panel), with inverted 10px fillets where they meet the top edge.

## Components

### Buttons
Quiet and solid, like a Mac control.
- **Shape:** gently rounded (`rounded.control`).
- **Primary:** white fill (`pale-white`) with ink text, 54px tall, system font at 650. An arrow or download icon in 1.8px stroke leads.
- **Hover / Focus:** hover goes to pure white and lifts 1px with a deeper shadow; focus is a 2px water-blue outline, 3px offset.
- **Quiet:** transparent with a bone hairline border (rgba bone at .28), 46px tall; hover adds a faint bone wash.

### Command Field
- **Style:** the Homebrew command in JetBrains Mono on translucent ink, 1px `line` border, 14px radius, horizontally scrollable without a visible scrollbar.
- **Copy chip:** bone text on a faint bone wash; on success it fills with water blue and the text goes ink.

### Navigation
The nav is a black notch fixed at top centre, 196px wide and 32px tall, in the system font. Its right side shows live status that follows the stage (brand wordmark, amber waiting count, unread bell and count, playing bars, file count). Opened, it springs to 480px wide with a two-column menu in Nunito 800 and a TR/EN segmented pill.

### Slip Notes
Privacy reassurances attached to each chapter: a dashed 1px border in a palette pigment (water blue, coral or amber) at 55%, translucent ink fill, 12px radius, 0.9rem text. They state a fact; they are not callouts.

### Panel Replica (signature)
The live app panel rebuilt in HTML at native size (384 × 218pt, page pill 336 × 36) with the app's system font, SF-style 1.6px line icons, glass-free translucent white controls, and the cover-tinted gradient. It is scaled as one piece with a single transform and never re-typeset at site sizes. Its pages are interactive: the track can change, the approval can be answered, the mixer moves. When the app changes, the replica follows the app.

### Pulled Sheet (signature)
The "everything else" section is a book of ten pulled ebru sheets at varied sizes. Each sheet is a live canvas marbled in a named traditional pattern (somaki, kumlu, gelgit, lale, hatip, battal, bülbül yuvası, taraklı, neftli, şal) using tonal blue, bone and occasional coral colour sets, held in a bone edge, rotated slightly, darkened with a light ink veil, and carrying its feature's real UI drawn at app size and scaled like the panel. The pattern name sits in faint italic under the description.

### Droplet Mascot
The app's drop with a face. Water blue at work, a paler blue when idle, amber and waving when waiting, a smile and spark when done. It hops, sways and blinks only in those states, and goes still under Reduce Motion.

## Do's and Don'ts

### Do:
- **Do** keep the ground near-black cool ink (`ink`, `ink-2`, `ink-3`) and let pigment arrive only from the opening drop or a visitor's click; a drag combs, scrolling pulls slow tines.
- **Do** lead with water blue (`water-blue`) and white (`pale-white`); keep coral to cover-tinted details and a single ring in the water.
- **Do** use amber (`waiting-amber`) only for waiting state.
- **Do** draw product UI at the app's native point size in the system font and scale it as one piece, matching the live app.
- **Do** give every sheet a bone held edge, a slight rotation and its feature's real UI.
- **Do** keep JetBrains Mono for commands and code only.
- **Do** honour Reduce Motion: drops land at once, combs and loops stop, the page stays fully readable.

### Don't:
- **Don't** pour colour into the water automatically, on a timer, or on page changes.
- **Don't** label the replica or its content as "demo data".
- **Don't** use a Liquid Glass lens, refraction or frosted-glass cards.
- **Don't** introduce a mint or teal site accent.
- **Don't** make backgrounds busy: no bright full-field pigment, no constant motion behind copy.
- **Don't** set the panel replica in Nunito or at the site's body sizes.
