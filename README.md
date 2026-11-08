# PresetEQ
iOS equalizer for audio files you open in the app. Loads EasyEffects (.json) and AutoEQ / Equalizer APO (.txt) presets.

## Get the IPA (no Mac needed)
1. Create a GitHub repo and push this folder.
2. Actions tab > "Build unsigned IPA" > Run workflow.
3. Download the PresetEQ-ipa artifact, then sideload it with AltStore, Sideloadly or TrollStore (they sign it with your Apple ID).

## With a Mac
brew install xcodegen && xcodegen generate && open PresetEQ.xcodeproj, set your Team under Signing, Run.

## Notes
- iOS cannot apply EQ system-wide; only audio played inside this app.
- Put preset files in the app's folder in the Files app, or use the import button.
