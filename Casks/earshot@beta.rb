cask "earshot@beta" do
  version "1.0.0-rc.1"
  sha256 "PLACEHOLDER"

  url "https://github.com/pasrom/meeting-transcriber/releases/download/v#{version}/Earshot-#{version}.dmg"
  name "Earshot (Beta)"
  desc "Auto-transcribe and summarize meetings (pre-release)"
  homepage "https://github.com/pasrom/meeting-transcriber"

  depends_on macos: :sonoma

  conflicts_with cask: "earshot"

  app "Earshot.app"

  zap trash: [
    "~/Library/Application Support/Earshot",
    "~/.meeting-transcriber",
  ]
end
