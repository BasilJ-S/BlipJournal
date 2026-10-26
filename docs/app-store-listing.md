# App Store listing

The copy for Blip Journal's App Store page: subtitle, keyword field, description and
screenshot plan. The positioning comes from issue #40: **a personal research tool. Your
memory lies about your days; Blip asks you in the moment.** Mood is one example survey,
not the product.

Rules for this copy:

- No diagnostic, treatment or therapy claims (README, App Store compliance checklist).
- Claim only what ships. A line that depends on unshipped work is marked with its issue
  and stays out of the live listing until that issue merges.
- No comparisons with named apps. App Review rejects them, and they date quickly.

## Name and subtitle

- **Name:** Blip Journal
- **Subtitle (30 max):** Random check-ins, your survey (29)

The subtitle names both halves of the idea, random timing and questions you write, and
avoids "mood tracker". The other candidates from issue #40 were "Study your own life,
offline" (28) and "Sample your life, privately" (27); neither says the questions are
yours. The final choice is the maintainer's.

## Keyword field (100 max)

```
experience sampling,ESM,EMA,self-experiment,quantified self,mood,private,open source,diary,offline
```

98 characters. Commas with no spaces, as Apple recommends.

- "journal", "random", "check-ins" and "survey" are left out: the App Store already
  indexes words in the name and subtitle, so repeating them wastes characters. Searches
  for "random check-in" and "private journal" should still match by combining fields;
  check in App Store Connect search once the app is live.
- "mood" stays so mood searches still find Blip.
- "diary" and "offline" fill the remaining room with terms people use for the same need.

## Description

Promotional text (170 max, 146 used; editable without a new build):

> Your memory lies about your days. Blip Journal asks you in the moment, with your own
> questions, at random times. Private, offline and open source.

Description (4000 max):

> Your memory lies about your days. Think back over a week and you recall the high
> points and the last few hours; the ordinary afternoons are gone. Blip Journal asks you
> in the moment instead, at random times, so your answers cover the whole day, not the
> parts you happen to remember.
>
> You write the questions. Ask how you feel, what you are doing, who you are with, how
> much coffee you have had, whether your focus is any good: anything you want to
> understand about your own life. Scales, single and multiple choice, yes/no and short
> text answers. Run several surveys, each with its own schedule.
>
> No network, no account, open source. Blip Journal makes no network requests, has no
> sign-up and no server: it never sends your answers anywhere. They live on your iPhone,
> encrypted at rest, behind Face ID or your passcode. The code is MIT licensed and
> public, so you can check.
>
> CSV and JSON export. Take your data to Numbers, Excel, R or Python at any time, in wide
> or long CSV, or as a complete JSON backup you can restore from.
>
> Missed prompts are counted. When a prompt expires unanswered, Blip records it as
> missed, and Insights shows your response rate. Entries you log on your own are marked
> as such. You see how complete your data is instead of guessing.
>
> HOW IT WORKS
> • Pick how many prompts a day, the hours they may arrive, the minimum gap between
>   them and how long each stays open.
> • Prompts arrive at unpredictable times inside that window, never closer together than
>   the gap you set.
> • Answer on one scrolling screen. Answers save as you go.
> • Log an entry yourself any time.
>
> SEE YOUR OWN PATTERNS
> • Any scale question over time, by hour of day and by day of week.
> • Compare a scale question across the options of any choice question, such as
>   activity or company, and open the entries behind each comparison.
> • Filter the Journal by survey, source or answer, and sort it by date or by a scale
>   answer.
>
> YOURS TO KEEP OR ERASE
> • Edit questions without losing what past answers meant: earlier wording is kept.
> • Delete one entry, permanently erase anything archived, or wipe everything from
>   Settings.
>
> Blip Journal is a tool for noticing patterns in your own days. It is not a medical
> device and does not diagnose or treat any condition.

The first five paragraphs follow the order issue #40 requires (R3): random prompts beat
memory; you write the questions; no network, no account, open source (MIT); CSV and JSON
export; missed prompts are counted.

The closing disclaimer is there because the default survey asks about feelings.

### Lines to add when the sub-issues ship

Not in the live listing yet. Add each one when its issue merges.

- #44: "Answer straight from the notification, without opening the app." (HOW IT WORKS)
- #42: "Start from a template: sleep, focus, energy, mood and more, or a blank survey."
  (after "You write the questions."; adjust the list to the templates that ship)
- #41: "Share a survey as a file, so friends or a small study can ask the same
  questions." (after the export paragraph)
- #43: "Blip reminds you to open the app before your scheduled prompts run out."
  (HOW IT WORKS). Until then prompts are scheduled at most 7 days ahead (less with many
  prompts a day), so the listing does not promise they keep arriving without opening
  the app.
- #45: HealthKit (placeholder). No copy until the scope is defined.

## Screenshots

Order for the 6.9" iPhone set. Each caption is one short line over the screenshot.

1. **"Your memory lies about your days. Blip asks you in the moment."** A prompt
   notification on the Lock Screen. Best with the quick answers from #44 visible; until
   then, the notification with the survey runner behind it.
2. **"You write the questions."** The survey editor with a non-mood survey (for example
   focus or energy). Best showing the template gallery from #42; until then, the editor.
3. **"One screen, then done."** The survey runner with a spectrum and choice chips.
4. **"See your own patterns."** Insights: a scale over time and by hour of day.
5. **"Missed prompts count."** Insights with the response rate tile, answered and missed
   counts visible.
6. **"No network. No account. Open source."** About's Privacy section ("Blip Journal
   makes no network requests and collects no data.").

Shots 1 and 2 are blocked on #44 and #42 for their best version (R4). Use sample data
with a non-mood survey in at least two shots, so mood reads as one example.
