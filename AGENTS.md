# Local game builds

For this fork, Emanuel explicitly requires local Apple app builds to include
the user-owned game data in the app bundle. Do not leave local installations
dependent on a separate ROM import or Apple TV HTTP upload, even when upstream
documentation describes that flow. Bundle the extracted `oot.o2r` runtime
archive, using `SOH_LOCAL_GAME_ARCHIVE` in ignored
`local-branding/branding.cmake`. Raw ROM extraction is a runtime asset step,
not a C/C++ compilation input.

Preserve source ROMs and cloud originals. Keep ROMs, extracted game archives,
licensed artwork, signing materials, and built apps out of Git and public
artifacts. Verify a fresh app data container can launch using bundled data.
Local name and icon overrides also belong in ignored `local-branding/`.
