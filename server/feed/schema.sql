-- Per day and app version: update checks, and distinct installs among them.
CREATE TABLE IF NOT EXISTS daily (
  day TEXT NOT NULL,
  version TEXT NOT NULL,
  checks INTEGER NOT NULL DEFAULT 0,
  installs INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, version)
);
-- Who was already counted today: a salted hash only (never the IP), deleted after two days.
CREATE TABLE IF NOT EXISTS seen (
  day TEXT NOT NULL,
  visitor TEXT NOT NULL,
  PRIMARY KEY (day, visitor)
);
-- Downloads of each dmg per day (site button, Homebrew and Sparkle updates all come through here).
CREATE TABLE IF NOT EXISTS downloads (
  day TEXT NOT NULL,
  file TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, file)
);
