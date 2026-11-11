# App Review notes

Reply to the Guideline 2.1 "Information Needed" request. The block below goes in the
Notes field of App Review Information (4000 characters max); the screen recording is
attached there or in the Resolution Center reply.

## Notes field

```
SCREEN RECORDING
Attached: recorded on a physical iPhone running the latest iOS, starting from app launch. It shows unlocking, the welcome, enabling notifications, adding a template survey, answering a prompt from a notification, logging an entry manually, the Journal, Insights, editing a survey, export, and Delete all data.

1. PURPOSE AND AUDIENCE
Blip Journal is a personal self-tracking tool based on experience sampling. Instead of asking people to recall their day at bedtime (when memory favours the high points and the last few hours), it sends short check-ins at random times within a daily window and asks questions the user writes. It is for individuals who want to understand their own days: mood, focus, energy, phone use, social time or anything else they choose. Answers take under 30 seconds, missed prompts are counted so the response rate is honest, and built-in charts show patterns. It is not a medical device and makes no diagnostic or treatment claims.

2. SETUP AND ACCESS
No account, login or sign-up exists, so no demo credentials are needed. No sample files are needed.
- Launch: the app asks for Face ID or the device passcode (it protects private answers).
- Welcome: tap Enable notifications and allow; then add a template (e.g. Focus & energy) or Skip.
- To see a prompt without waiting for a random time: Settings > Notifications > "Send a test prompt in 15 seconds", then leave the app and tap the banner. For a survey whose first question is yes/no or a short scale, the answer can also be picked by long-pressing the notification.
- Log an entry any time: Journal > New entry.
- Journal: tap an entry for details, and Delete entry there removes it. Filter and sort from the toolbar.
- Insights: charts over time, by hour, by weekday, by option, and the response rate.
- Surveys: Settings > Surveys to edit questions and the sampling schedule, or + to add a blank or template survey. Surveys can also be imported or shared as .blipsurvey files.
- Export: Settings > Export (CSV or JSON backup). Restore: Settings > Restore from backup.
- Erase: Settings > Delete all data erases every survey and answer on the device.

Account deletion: not applicable, the app has no accounts.
User-generated content: answers are private to the device and never shown to other users; there is no social feed, so reporting and blocking do not apply.
Paid content: none. The app is free, with no in-app purchases, subscriptions or ads.

3. EXTERNAL SERVICES
None. The app makes no network requests, has no server, no analytics, no advertising, no third-party SDKs that send data, and no AI services. Data is stored locally in SQLite (via the open-source GRDB.swift library, bundled) protected by iOS Data Protection. Apple frameworks used: UserNotifications (local notifications only), LocalAuthentication (Face ID/passcode), Swift Charts. The only link out is "View source repository" in About, which opens the public GitHub page in the browser.

4. REGIONAL DIFFERENCES
None. The app works identically in all regions. It is in English only.

5. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. The app is a general-purpose personal journal, not a medical, financial or other regulated service, and it contains no protected third-party content. Bundled fonts are under the SIL Open Font License; GRDB.swift is MIT licensed. The app's own source is MIT licensed and public.
```

## Recording shot list

Record on a physical iPhone on the latest iOS with Control Center screen recording,
starting from the Home Screen. Do a full reinstall first so the welcome shows. Keep it
to about two to three minutes.

1. Tap the app icon. Unlock with Face ID or passcode.
2. Welcome: Enable notifications, allow. Add a template (Focus & energy).
3. Settings > Notifications > Send a test prompt in 15 seconds. Go to the Home Screen.
4. When the banner arrives, long-press it and pick an answer (quick answer), or tap it
   and answer in the survey runner.
5. Journal > New entry: answer the mood survey manually.
6. Journal: open an entry, then delete it. Show Filter and sort.
7. Insights: scroll the charts and the response rate tile.
8. Settings > Surveys: open a survey, edit a question, show the Sampling schedule.
9. Settings > Export: export a CSV to Files.
10. Settings > Delete all data: confirm, show the empty Journal.

If quick answers are not in the build, drop that part of step 4 and the matching line
in the notes.
