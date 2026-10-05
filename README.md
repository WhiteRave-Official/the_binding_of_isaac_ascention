# The Binding Of Isaac - Ascention

Adds Geburah, Arclight, Golden Eye, Empress's Tiara, a Revelation rework, and
custom Mini Isaac combat.

## Installation (Windows)

1. Install Repentance+ and REPENTOGON.
2. Subscribe to Ascention in Steam Workshop.
3. Download `Ascention Native Setup.exe` from
   https://github.com/WhiteRave-Official/the_binding_of_isaac_ascention/releases.
4. Close Isaac and run the downloaded setup.
5. Launch Isaac through REPENTOGON.

Workshop cannot distribute executables or DLLs. Run the setup again after an
Ascention update. It embeds `zhlAscention.dll`,
checks the REPENTOGON runtime SHA-256 before writing, verifies the DLL after
installation, and refuses to replace an unknown DLL. If it reports an
unsupported REPENTOGON build, wait for an updated Ascention installer. Do not
force-install a DLL compiled for another build.

The Windows installer is unsigned and may trigger antivirus warnings. Its
source is `AscentionNativeSetup.cs` in the source repository.
