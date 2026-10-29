# Background schedule agent

The sandboxed command-line target embeds its own processed Info.plist into the Mach-O `__TEXT,__info_plist` section, with a bundle identifier distinct from the GUI. Debug dylib support is disabled for this tool. This is required for sandbox initialization; see [Apple’s ServiceManagement packaging example](https://developer.apple.com/forums/thread/802443).

The app embeds `MAAScheduleAgent` in `Contents/MacOS` and its fixed launchd plist in `Contents/Library/LaunchAgents`. Registration uses `SMAppService.agent(plistName:)`; the app never installs files directly into a user's Library/LaunchAgents directory.

The helper runs once at load and every 60 seconds while the user is logged in. It reads the published schedule, claims one occurrence in the shared ledger, writes a data-only inbox envelope, and opens only the application bundle containing that helper. It does not link MaaCore or invoke adb, a shell, or user scripts. The GUI validates the envelope after Core/resource initialization and dispatches it through the foreground scheduling handoff.

Both targets must be signed by the same developer team, with the macOS App Group entitlement `$(TeamIdentifierPrefix)com.hguandl.MeoAsstMac.Schedule`. The runtime derives the group name from the actual code-signing team and verifies that the signed entitlement includes it. Unsigned/ad-hoc builds remain unable to enable the background service and do not substitute a manually constructed filesystem path. Configure the signing team for **both** app and helper when building a signed package.

See [Apple's macOS App Group naming requirements](https://developer.apple.com/documentation/xcode/accessing-app-group-containers) and [ServiceManagement packaging](https://developer.apple.com/documentation/ServiceManagement/updating-your-app-package-installer-to-use-the-new-service-management-api).

The GUI's default is off. It displays the actual registration/approval status, and disabling unregisters the service before changing the saved preference. First delivery is limited to logged-in sessions, approximately 0–60 seconds of polling delay plus GUI initialization. A five-minute catch-up window applies after wake; shutdown, logged-out execution, and waking a sleeping machine on time are unsupported.

Local tests compile the exact shared sources. Signed installation, actual App Group access, system approval, exit-triggered launch, sleep/login, relocation and upgrade behavior still require a developer-signed validation package. An unsigned helper refusing to run is a signing-boundary check, not proof of working background scheduling.
