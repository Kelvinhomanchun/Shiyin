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
| R-16 | Diagrams | Re-making the notes draws and suggests nothing by itself; the Diagrams section only offers Suggest Diagrams and Describe a Diagram |
| R-17 | Diagrams | Suggest says "Finding…" until done, also after leaving the meeting and coming back; suggestions come from the stakeholder model |
| R-18 | Diagrams | Draw This turns a suggestion into a diagram and takes it off the list; Not needed drops one; a meeting with nothing to draw says so and offers Describe a Diagram |
| R-19 | Diagrams | Comment and Redraw sends the current diagram plus every comment, keeps the comments on the card, and Restore previous version brings the old one back |
| R-20 | Diagrams | Fix with AI asking about a diagram leaves the notes alone and opens the redraw sheet with the comment; editing the notes marks a diagram as drawn from earlier notes |
| R-21 | Exports | Notes exports (Markdown, Word, PDF) and diagram pictures carry no recording times unless "Include recording times" is on; diagrams follow the summary; removing a diagram puts its suggestion back |
| R-22 | Diagrams | The drawing rules ask for verb + object step labels and step IDs (1, 2a, 2b…); an ID the AI types into the label becomes the step ID; "horizontal" lays the diagram out left to right; a malformed first answer is asked again |
| R-23 | Diagrams | The Download menu writes PNG, JPEG, SVG, PDF and draw.io files for clients (no recording times; draw.io boxes and connectors stay editable; PDF is vector with the fonts embedded); Copy Image puts PNG + PDF on the pasteboard; the downloaded diagram has no crossing arrows |

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

## Last run with user-driven diagrams (2026-11-27)

Nothing is drawn automatically any more: suggest → draw → comment → redraw → restore, plus Describe a Diagram.
R-16 to R-21 were rewritten for this; see the table. Exports drop recording times by default.
Checked by eye at text size 4 and 960 pt, light and dark: the empty section, the suggestion cards, a drawn and
redrawn swimlane with its comment list, and the redraw sheet, in Chinese and English.

## Last run with diagram rules and PDF fix (2026-11-27)

`run.py` 19 of 19 and `regression.py` 23 of 23 passed (new R-22); live database unchanged.
Fixed: PDF exports printed the diagram as a blank space (the image had not been decoded when the page was printed); R-21 now
checks that the PDF really holds an image. Remove is a visible button on each diagram, with a confirmation.
Checked by eye: the left-to-right swimlane with step IDs, and the PDF page with the diagram.


## Last run with arrow routing and diagram downloads (2026-11-27)

Arrows: parallel steps in one lane share a column, channels between columns are ordered so lines don't cross, a gateway's
exits get their own ports, loop-backs pick the side with fewer crossings (top in left-to-right flowcharts), lines
blocked by a box run beside it instead of round the whole diagram, and two lines into one box swap ports if they cross.
Checked by eye: the PBI swimlane left-to-right and top-down, and a claims flowchart with two decisions and a loop-back
in both directions. New Download menu (R-23); the draw.io file was opened in draw.io and matches the app.

`run.py` 19 of 19 and `regression.py` 24 of 24 passed (new R-23); live database unchanged.
