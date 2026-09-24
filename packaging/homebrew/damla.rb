# Homebrew cask for Damla. release.sh fills in the version and the dmg's sha256 and pushes it to the tap
# repository erkamyigitaydin/homebrew-tap, so `brew install --cask erkamyigitaydin/tap/damla` works.
cask "damla" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/erkamyigitaydin/Damla/releases/download/v#{version}/Damla-#{version}.dmg"
  name "Damla"
  desc "Notch companion for now playing, sound, files, clipboard, focus and agents"
  homepage "https://github.com/erkamyigitaydin/Damla"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :tahoe

  app "Damla.app"

  zap trash: [
    "~/Library/Application Support/Damla",
    "~/Library/Caches/app.local.damla",
    "~/Library/HTTPStorages/app.local.damla",
    "~/Library/Preferences/app.local.damla.plist",
  ]
end
