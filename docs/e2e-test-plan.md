# KelNote end-to-end test plan (People, stakeholders, My coaching)

Build the debug app (`scripts/build-app.sh --debug`), then run `python3 scripts/dev/e2e/run.py [TC-…]`. It never touches your live data or the installed app:

- It copies `shiyin.sqlite` to `/tmp/kn-e2e/` and runs the **debug build** against the copy (`SHIYIN_HOME`).
- Every AI call goes to a local fake server (`scripts/dev/e2e/fake_ai.py`), never a real provider.
- Each case is a check on what the **screen state** shows (the debug app's own `peopleOverview`, `coaching`,
  `stakeholder` and selection), read *without* forcing a reload. A case passes only if the screen updates by
  itself, the way you would see it.

The defect class that leaked twice (People not refreshed, Useful not saved) is: *something changes in the
background or on another page, and the open screen still shows the old value until you click*. Every
background job in the TC-2 group is checked for that.

| ID | Area | Steps | Expected |
|---|---|---|---|
| TC-1.1 | People | Open the app on the copy | People lists every person in the database, "me" first |
| TC-1.2 | People | Rename a speaker in a meeting to a new name | The new person appears in People with no click |
| TC-1.3 | People | Rename a person from People | The new name shows in People and on the meeting |
| TC-2.1a | Background → People | A speaker is linked to a new person in the background (as voiceprint matching does), then a job ends | People shows them with no click |
| TC-2.1b | Background → People | Speaker naming suggests a name; I accept it | People shows the person with no click |
| TC-2.2 | Background → coaching | A meeting's notes finish while my page is open | My coaching numbers and "Updated…" refresh by themselves |
| TC-2.3 | Background → stakeholder | An automatic stakeholder update runs for the person whose page is open | The page shows the new analysis with no click |
| TC-2.4 | Background → stakeholder | Analyze is pressed, then I leave the page and come back | It still says "Analyzing…" until done, then shows the result |
| TC-2.5 | Background → coaching | Refresh is pressed, then I leave my page and come back | It still says "Updating…" until done, then shows the result |
| TC-3.1 | Coaching | Mark a finding Useful, leave the tab, come back | Still "Marked useful" |
| TC-3.2 | Coaching | Refresh where the AI leaves the useful point out | The useful point is kept |
| TC-3.3 | Coaching | Click Useful again | The mark is removed |
| TC-3.4 | Coaching | Mark a finding Not right, then Refresh | It is gone, and stays gone; the AI is told not to repeat it |
| TC-3.5 | Coaching | Click a quote | That meeting opens; going back keeps the tab |
| TC-3.6 | Coaching | Restart the app | Useful marks, tab content and coaching are all still there |
| TC-4.1 | Stakeholder | The AI returns a thin portrait (1 of 9 sections) | KelNote asks again and keeps the fuller answer |
| TC-4.2 | Stakeholder | An automatic update leaves sections out | Earlier sections are kept |
| TC-4.3 | Stakeholder | Other people's pages | Still show the stakeholder analysis, not coaching |
| TC-5.1 | Safety | After the whole run | The live database is unchanged (same checksum as before) |
</content>
</invoke>

## Last run (2026-11-26)

19 of 19 passed on a copy of the live data; the live database checksum was unchanged.

The suite was checked against the bug it is meant to catch: with the People refresh after jobs switched off
(`refreshPeopleIfChanged()` in `AppModel.reload()`), TC-1.2, TC-2.1a and TC-2.1b fail. A green run therefore means that
class of defect is not present.
