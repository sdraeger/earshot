cask "earshot" do
  version "1.0.0"
  sha256 "PLACEHOLDER"

  url "https://github.com/pasrom/meeting-transcriber/releases/download/v#{version}/Earshot-#{version}.dmg"
  name "Earshot"
  desc "Auto-transcribe and summarize meetings"
  homepage "https://github.com/pasrom/meeting-transcriber"

  depends_on macos: :sonoma

  conflicts_with cask: "earshot@beta"

  app "Earshot.app"

  zap trash: [
    "~/Library/Application Support/Earshot",
    "~/.meeting-transcriber",
  ]
end
