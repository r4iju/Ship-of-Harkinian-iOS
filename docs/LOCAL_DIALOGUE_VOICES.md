# Local dialogue voice packs

Apple builds can play an offline voice pack alongside the original game audio.
Keep ROM-derived transcripts, generated speech, reference recordings, and model
outputs under ignored `local-branding/`. Do not commit or publish them. Local
installations must still bundle the user-owned `oot.o2r` archive as instructed in
`AGENTS.md`; the voice pack does not replace the game archive.

Configure the pack in ignored `local-branding/branding.cmake`:

```cmake
set(SOH_LOCAL_VOICE_PACK "${CMAKE_SOURCE_DIR}/local-branding/dialogue-voices")
```

The directory contains a `manifest.json` and WAV recordings. CMake bundles these
files in `Resources/dialogue-voices` for macOS, iOS, and tvOS. Reconfigure after
generating or changing a pack, rebuild, and install the resulting app. A fresh
app data container must work without downloading or importing recordings.

The manifest format is:

```json
{
  "version": 1,
  "language": "eng",
  "clips": [
    {
      "text_id": 4096,
      "text": "The exact dialogue page to match.",
      "voice": "companion",
      "file": "companion-page.wav"
    }
  ]
}
```

`text_id` is the numeric message ID. `text` is one decoded dialogue page, not a
whole multi-page message. Lookup ignores presentation punctuation and whitespace
and compares case-insensitively. It uses both message ID and decoded page text,
so changed dialogue and player-name substitutions do not accidentally receive
an unrelated recording. File names must be local basenames. Unsupported packs,
missing clips, and unmatched pages retain the original text.

Settings → General → Accessibility → Recorded Dialogue Voices enables playback. Settings
→ Audio → Dialogue Voice Volume controls its level relative to Master Volume.
Advancing, closing, leaving a scene, or exiting the game stops the current clip.
Pausing the game or putting the app in the background suspends playback. Text to
Speech remains available for uncovered pages and menus; recorded pages suppress
the duplicate synthesized dialogue.

The initial local prototype covers Navi and the Great Deku Tree in the opening:
message IDs `1000`, `1098`, `1099`, `109A`, `109D`, `109E`, and `109F` (hexadecimal).
It is not full-game voice coverage. Voice casting, pronunciation, dynamic names
and numbers, speaker ambiguity, and the remainder of the corpus still need
review. Additional Navi wake-up messages `1095` and `1096` are not recorded in
this first pack; `1095` contains the player-selected name. The local generation environment must pass its Metal/MLX preflight
before producing fresh clips. Preserve reference recordings to keep each voice
consistent during regeneration.

For verification, enable local CVar `gSettings.DialogueVoiceDebug` to log pack
loading, clip starts, playback progress, stops, and uncovered pages. Logs can
contain game text and should remain local and ignored. Verify actual gameplay
page transitions and interruption behavior, not only successful WAV generation.
