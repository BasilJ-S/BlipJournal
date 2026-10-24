# Onboarding

`WelcomeView` is a one-screen introduction shown the first time the app is unlocked. It
says what the app does and that nothing leaves the phone, then offers **Enable
notifications** or **Not now**. Without it the app's core feature, random prompts, only
switched on if someone found Settings → Notifications.

- `RootView` presents it as a full-screen cover while `@AppStorage("hasSeenWelcome")` is
  false. Either button sets the flag, so it never shows again, including after
  Delete all data.
- A stored flag rather than the notification status: the coordinator reports
  `.notDetermined` until its first refresh finishes, so a status check would flash the
  screen on every launch.
- Enable asks the coordinator for permission, then refreshes it and the app model, the
  same sequence as `NotificationSettingsView`. Granting or refusing both finish the screen.
- The cover lives inside `RootView`, so it only appears once unlocked, and relocking
  before a choice tears it down and shows it again after the next unlock.
- No logic lives here worth a test; the flag is a single `UserDefaults` bool, already
  declared in the privacy manifest.
