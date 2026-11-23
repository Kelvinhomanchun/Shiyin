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
