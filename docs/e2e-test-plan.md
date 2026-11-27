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

## Regression suite (existing functions + upstream 5.1–5.3 features)

`python3 scripts/dev/e2e/regression.py [R-…]` — same safety rules (debug build, data copy, fake AI, live checksum).

| ID | Area | Expected |
|---|---|---|
| R-1 | Notes language | A Cantonese meeting re-summarizes with English notes; the setting is kept |
| R-2 | Ask | Asking one meeting and asking an Account folder both answer and are saved with the right scope |
| R-3 | Folders | An Account folder lists exactly its own meetings and its projects' meetings |
| R-4 | Export | PDF, Word and Markdown come out in the KelNote layout (kicker with Account › Project, numbered sections, footer) |
| R-5 | Speakers | A rename shows on the meeting and in People |
| R-6 | Notes | An action item marked done is kept; Fix with AI makes a new version |
| R-7 | Glossary | Terms add |
| R-8 | Recording | A (simulated) recording starts, pauses, resumes and stops into a new meeting |
| R-9 | New: mic pause | Pause only the microphone while recording, then turn it back on |
| R-10 | New: timed stop | A stop time can be set and cleared while recording |
| R-11 | New: screenshots | A screenshot stays on the meeting and is exported with the notes |
| R-12 | New: version history | An earlier notes version can be picked and used |
| R-13 | New: find more | "Find more uncertain points" runs and keeps the notes |
| R-14 | New: glossary file | The glossary exports to a file and imports (merged) |
| R-15 | Transcription | The recorded meeting transcribes on this Mac |
| R-16 | New: diagrams | Re-summarizing the PBI walkthrough draws a swimlane and a flowchart by itself, on the stakeholder model; the notes page shows them with no click |
| R-17 | New: diagrams | Redraw says "Drawing…" until done, also after leaving the meeting and coming back |
| R-18 | New: diagrams | A meeting with no process gets no diagram; the page says it needs none |
| R-19 | New: diagrams | An over-budget answer is cut to the rules (9 nodes, 2 focal, edges only between kept nodes) |
| R-20 | New: diagrams | Editing the notes keeps the diagrams and marks them as drawn from earlier notes |
| R-21 | New: diagrams | PDF, Word and Markdown exports carry both diagrams as pictures after the summary |

## Last run (2026-11-26)

19 of 19 passed on a copy of the live data; the live database checksum was unchanged.

The suite was checked against the bug it is meant to catch: with the People refresh after jobs switched off
(`refreshPeopleIfChanged()` in `AppModel.reload()`), TC-1.2, TC-2.1a and TC-2.1b fail. A green run therefore means that
class of defect is not present.

## Last run with upstream features (2026-11-27)

`run.py` 19 of 19 and `regression.py` 16 of 16 passed on the merged build; live database unchanged.
Screens checked by eye at text size 4 and 960 pt: notes toolbar (version history, undo, Fix with AI, Edit), transcript
search, My coaching, recording bar. The recording bar pushed Stop off-screen with the microphone paused; fixed.

## Last run with meeting diagrams (2026-11-27)

`run.py` 19 of 19 and `regression.py` 22 of 22 passed; live database unchanged.
Checked by eye: both PBI diagrams as exported PNGs, the notes page at text size 4 and 960 pt in light and dark,
and the PDF page. Fixes made from that review: the Yes/No exits of a decision no longer jog sideways; at large text
sizes a wide diagram shrinks to the column (down to 0.75×) instead of scrolling both ways; in the PDF a tall diagram
is capped near 3/4 of a page so its section heading is not left alone on the page before.
