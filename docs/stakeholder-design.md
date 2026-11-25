# Stakeholder analysis — design (fork)

Goal: help a consultant walk into the next meeting knowing *who decides, what each person needs, where they stand, and what their words really mean* — and act on it.

## 1. Consulting frame

The first version answered "what is this person like". A consultant needs "what do I do about this person". The redesign adds the standard stakeholder-management tools, all grounded in meeting evidence:

| Concept | Why it matters | Source |
|---|---|---|
| **Power × Interest grid** (Mendelow) | Tells you the engagement strategy: *Manage closely / Keep satisfied / Keep informed / Monitor*. | AI, from evidence + user context |
| **Attitude** (champion · supporter · neutral · skeptic · blocker) | Power says how much they matter; attitude says which way they push. Together they flag risk (high power + skeptic). | AI, per stance in meetings |
| **Attitude trend** (improving · stable · declining) | A supporter cooling off is an early warning. | AI, comparing meetings over time |
| **Decision role** (decision maker · influencer · gatekeeper · expert · user · other) | Buying-centre view: who signs, who shapes, who can block access. | AI, or user context |
| **What they need from me / us** | Converts motivations into deliverables. | AI |
| **Commitments** (what they promised, what was promised to them) | Trust is built on follow-through; this is what to check next time. | AI, from action items + transcript |
| **Next-meeting playbook**: objective, talking points, questions to ask, things to avoid | The "so what" — immediately actionable. | AI |
| **Key relationships** (who they defer to / align with / clash with) | Political map: lets you work through allies. | AI, from interactions in excerpts |

**User context is ground truth.** The AI only sees transcripts, so it guesses titles and authority. The user can set a **role/title**, **organisation**, and a free-text **"What I know"** note (reporting line, history, what they're measured on). These are passed as facts and override inference. The page labels them "You" vs "Inferred".

## 2. UX principles

1. **Answer first, evidence on demand.** Top of the page is a compact *profile card*: role, organisation, quadrant, attitude + trend, one-line summary. Evidence is collapsed under each point ("3 sources ▸").
2. **Action over description.** "Next meeting" playbook sits directly under the card, before the descriptive sections.
3. **Visual, not just text.** A small Power × Interest grid with a dot shows the quadrant at a glance. A **Stakeholder map** (all people on one grid, coloured by attitude) answers "who matters most" across the account; it filters by folder.
4. **Honest confidence.** Each profile shows *confidence* (low / medium / high) based on how much the person spoke and in how many meetings, plus "Based on N meetings, updated date". Low-confidence profiles show a hint to add context.
5. **Editable where the AI is weakest.** Role/organisation/notes are inline-editable on the card; saving re-analyses that person.
6. **Calm visual language.** Follow the app: Songti headings, celadon links, muted secondary text, capsule badges. Attitude colours: champion/supporter green, neutral grey, skeptic orange, blocker red.

## 3. Page layout (person page)

```
[Avatar] Sandy                                   [Edit context] [Re-analyze]
Technical / delivery lead · HKJC   (You / Inferred)
┌ Profile card ───────────────────────────────────────────────┐
│ Manage closely  ● Power High  ● Interest High   [mini grid] │
│ Attitude: Skeptic ↘ declining   Decision role: Influencer   │
│ Confidence: High · 3 meetings · updated 2026-11-23          │
│ "Direct, ground-truth oriented lead who …"                  │
└─────────────────────────────────────────────────────────────┘
Next meeting
  Objective · Talking points · Questions to ask · Avoid
What they need from us        Commitments (they ↔ us)
Reading between the lines     (quote → meaning, cited)
Topics & stance               Personality & style · Motivations
Key relationships             Not clear yet
— Action items · Meetings (existing sections)
```

The **Stakeholder map** opens from the People header ("Map") as a window: a 2×2 grid, one dot per analysed person (initials, attitude colour), folder filter, click a dot to open the person.

## 4. Data

`stakeholder_profiles` gains `user_role`, `user_org`, `user_notes` (user context, kept across re-analysis). Profile JSON gains: `organization`, `quadrant`, `attitude`, `attitudeTrend`, `decisionRole`, `confidence`, `needs[]`, `commitments[] {who, text, meetingId, time}`, `relationships[] {person, relation, note}`, `nextMeeting {objective, talkingPoints[], questions[], avoid[]}`. Old profiles decode with defaults; they are re-analysed after install.

## 5. Version 3: a profile of the person, not a diary of meetings (2026-11-25)

**Problem.** The summary narrated meeting events ("In Meeting 22 he…"). It read like notes from several meetings, not a briefing on a person. Open questions mixed in app housekeeping (duplicate folder names). Meetings were cited by internal number.

**What a consultant wants to know before meeting someone** draws on chief-of-staff stakeholder maps (*owns · measured on · this quarter · how they like to work · trusts*), key-account management (*strategic priorities, personal wins, risk posture, decision triggers*), Miller Heiman's *personal win*, Social Styles (*how they decide*) and Maister/Sobel (*the client's agenda*). The new **portrait** has these fields:

| Field | Question it answers |
|---|---|
| mandate | What do they own and answer for? |
| measuredOn | How is their success judged (outcomes, metrics, deadlines)? |
| agenda | What are they trying to get done right now? |
| pressures | What pressure are they under, and what risks worry them? |
| personalWin | What would success do for them personally? (always marked as inferred) |
| decisionStyle | What evidence they trust, speed, consensus or directive, risk appetite |
| workingStyle | Direct or diplomatic, detail or big picture, pace, humour, feedback |
| redLines | What triggers push-back |
| trustedVoices | Whose opinion they rely on |

The existing *personality* (enduring traits and values) and *motivations* (deeper drivers) stay, and move into the same tab.

**Other changes.**
- **Summary:** 3–4 sentences that stay true across meetings (who they are, what they're driving toward, how they operate, what it means for you). No meeting narration.
- **What changed:** 0–5 items comparing this update with the previous profile, each citing the meeting by date. Shown on the card, so after a meeting you can see at a glance what the update changed. On a full re-analysis, the earlier profile is sent only for this comparison.
- **Meetings by date and title:** the prompt labels meetings `[Meeting id=N] date · title` and forbids ids in text. Any "Meeting N" left in the answer is replaced with `date “title”`.
- **Open questions** are about the person only, never about the app or the data.
- **Person page tabs:** **Who they are** (portrait, then character and drivers) → Plan → Read them (readings and what to find out) → Interests → Network → Record.
- **Freshness:** the attendee row and hover cards redraw when an analysis finishes (an observed revision counter).
- **Automatic analysis waits:** it runs one minute after the notes settle, not after every edit.
- **Renamed folders:** project entries are renamed with the folder and merged. On startup and after each analysis, entries for folders that no longer exist are dropped.
