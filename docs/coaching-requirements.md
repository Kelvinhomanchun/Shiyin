# My coaching (我的表現): functional requirements, draft 2 for confirmation

Status: **draft 2, not built.** Revised after your review on 2026-11-25:

1. No coaching for a single meeting. Coaching is **overall**, based on all your past meetings.
2. Every finding shows a **trend**: improving, no change, or getting worse.
3. It lives on **your own page in People** (Kelvin). Other people's pages keep their stakeholder analysis.
4. It **refreshes automatically after each meeting**, and has a **manual refresh** button.

## 1. What the function is

Today, opening Kelvin in People shows "This is you, no analysis", followed by your action items and meetings. The new function replaces that line with a coaching analysis of **you**, built from every meeting where your voice is identified.

It answers three questions:

1. **What are my strengths and weaknesses in meetings?** Recurring patterns across all meetings, each with evidence.
2. **Am I getting better, staying the same or getting worse?** A trend for every number and every pattern.
3. **What should I work on next, and how?** A short, concrete plan.

What the research means for the design:

| Research finding | Design decision |
|---|---|
| Long monologues go with people switching off; back-and-forth goes with good outcomes; more questions is not always better (Gong, 326K calls). | Measure talk share, longest stretch, back-and-forth and questions, each with a direction that counts as "better" for each type of meeting (section 4). |
| Vendors' "ideal" numbers have no published method. | Trends compare **you with your earlier self**, per type of meeting. The targets are defaults you can change. |
| Consistency separates top performers from the rest. | Show how much each number varies, and flag when it swings from meeting to meeting. |
| Trust = (credibility + reliability + intimacy) ÷ self-orientation. Self-orientation weighs most; intimacy is the most under-trained part. | The overall coaching reads your behaviour through these four parts, with a trend for each. |
| Feedback changes behaviour when it covers 1–3 points, is tied to a goal, and comes with a concrete plan. | At most 3 strengths, 3 weaknesses and 1 focus at a time, each with "what to do next". |
| AI judges *whether* a behaviour happened better than *how well*. | Every finding quotes the transcript and links to the moment. You can mark a finding wrong. |

## 2. Scope

**In scope:** your own behaviour in recorded meetings where your voice is identified.

**Out of scope:**
- Coaching for a single meeting.
- Rating other people's soft skills.
- Comparing you with colleagues.
- Voice tone or video.
- Sharing coaching outside the app.

## 3. Functional requirements

### A. Which meetings count

- **FR-A1.** "Me" is the person whose voice you enrolled. If you haven't enrolled, it's the person in the most meetings, as the People analysis already does.
- **FR-A2.** A meeting counts when you spoke for at least 60 seconds and at least one other identified speaker took part.
- **FR-A3.** Each meeting gets a type:
  - **Interview**: the meeting uses the Interview template.
  - **One-to-one**: the meeting uses the One-on-one template, or has exactly one other speaker and isn't an interview.
  - **Client**: a participant's organisation differs from yours. Your organisation comes from your People page.
  - **Internal**: everything else.
  - You can change a meeting's type on the meeting page. The coaching then refreshes.
- **FR-A4.** A meeting with doubtful speaker labels (KelNote already flags these) is left out until the labels are fixed. The page says how many meetings were left out.

### B. Behaviour numbers (no AI; calculated from the transcript timing)

- **FR-B1.** For each counted meeting, calculate:
  - **Talk share:** your speaking time ÷ everyone's speaking time.
  - **Longest stretch:** your longest run of speech before someone else speaks.
  - **Back-and-forth:** speaker changes per 5 minutes.
  - **Questions:** your questions per 30 minutes. A question is a sentence ending in ? or ？, or ending in a Cantonese or Mandarin question particle (嗎, 呢, 咩, 未).
  - **Room given:** the longest time someone else spoke without you cutting in.
  - **Jump-in gap:** the median pause before you speak after someone else stops.
  - **Fillers and restarts:** fillers (誒, 嗯, um, uh) and repeated words ("我我我") per 100 of your words.
- **FR-B2.** The numbers are recalculated whenever a meeting's transcript or speaker labels change.

### C. Trend (improving, no change, getting worse)

- **FR-C1.** For each number and each type of meeting, compare your **recent meetings** (the last 5 of that type) with your **earlier meetings** (the 5 before them).
- **FR-C2.** The trend is:
  - **Improving**: the recent median moved toward the target by more than the trend threshold (FR-C4);
  - **Getting worse**: it moved away from the target by more than the threshold;
  - **No change**: otherwise.
  - Where the target is a range (such as talk share 30–50%), getting into or closer to the range counts as improving.
- **FR-C3.** With fewer than 3 recent and 3 earlier meetings of a type, the trend shows "not enough meetings yet" and says how many more are needed.
- **FR-C4.** Threshold: the change must be bigger than half the normal spread of that number, so one unusual meeting doesn't flip the trend. The middle half of your meetings of that type sets the normal spread.
- **FR-C5.** A trend chart per number: one dot per meeting, the target band shaded, and the earlier and recent medians marked. Clicking a dot opens that meeting at the moment the number came from, for example the longest stretch.
- **FR-C6.** The AI findings in section D also carry a trend, judged by comparing evidence from your earlier and recent meetings.

### D. Overall coaching (AI, across all meetings)

- **FR-D1.** The AI reads, from every counted meeting:
  - the meeting's date, type and title;
  - your lines with the lines just before and after them;
  - the numbers from section B and the trends from section C;
  - your role and organisation from your People page.
- **FR-D2.** It writes:
  - **Summary:** 3–4 sentences on how you come across in meetings, and how that has changed.
  - **Strengths (up to 3):** the behaviour, why it works, which types of meeting it shows in, its trend, and 2–3 examples with a quote and a time.
  - **Weaknesses (up to 3):** the behaviour, its effect on other people, which types of meeting, its trend, and 2–3 examples.
  - **Trust reading:** for credibility, reliability, intimacy and self-orientation, one line each with evidence and a trend. Where there's no evidence, it says so.
  - **By type of meeting:** one line each on how you behave in client, internal, interview and one-to-one meetings.
  - **Improvement plan:**
    - **One recommended focus**, taken from the weaknesses;
    - **3 concrete techniques** for it, for example "open interviews with a 2-minute overview, then ask 'walk me through…'";
    - **one example from your own meetings** of what doing it well looks like;
    - **the number that will show progress**.
  - **What changed since the last refresh:** new strengths, resolved weaknesses, trends that moved.
- **FR-D3.** Every example must have a quote and a time from a real meeting. Findings without evidence are dropped, the same check the People analysis uses.
- **FR-D4.** Under each finding: **Useful** / **Not right**. "Not right" hides the finding, and the reason you give is sent with future refreshes so the AI doesn't repeat it.
- **FR-D5.** It's written in the language you've set for notes.

### E. Where it appears: your People page

- **FR-E1.** On your own page in People (the one marked "me"), the line "This is you, no analysis" is replaced by the coaching, in tabs like the stakeholder pages:
  1. **Overview**: summary, focus and plan, the headline trends, and what changed.
  2. **Strengths & weaknesses**: each finding with its trend badge and examples.
  3. **Trends**: the charts from FR-C5, filterable by type of meeting and date range.
  4. **Trust**: the four-part trust reading.
  5. **Record**: your action items and meetings, as the page shows today.
- **FR-E2.** Trend badges use the same style as the rest of the app: ↑ improving, → no change, ↓ getting worse, or "not enough meetings yet".
- **FR-E3.** The page header shows "Based on N meetings, updated <date>", plus the number of meetings left out (FR-A4).
- **FR-E4.** Other people's pages are unchanged.

### F. Refresh

- **FR-F1.** **Automatic:** after the notes of a counted meeting are done, the numbers update at once. The AI coaching is queued in the background, using the same delay and queue as the People analysis, so it doesn't compete with recording or notes.
- **FR-F2.** An automatic refresh adds the new meeting to the existing coaching. It doesn't rewrite everything, so findings stay stable.
- **FR-F3.** **Manual:** a **Refresh** button on your page re-reads all meetings and rebuilds the coaching from scratch. It is greyed out while a refresh is running.
- **FR-F4.** While a refresh runs, the page shows "Updating…" and keeps showing the previous coaching until the new one is ready.
- **FR-F5.** If a refresh fails, the page keeps the previous coaching and shows the error with a **Try again** button.

### G. Privacy

- **FR-G1.** Everything stays on this Mac, except the text sent to your chosen AI provider, as for notes and People today.
- **FR-G2.** The coaching isn't available to the MCP read tools or exports unless you switch that on.
- **FR-G3.** You can clear the coaching from your page's menu.

## 4. Default targets (what counts as "better")

You can change these on the Trends tab.

| Number | Client | Internal | Interview | One-to-one |
|---|---|---|---|---|
| Talk share | 30–50% | 35–60% | 30–45% | 40–60% |
| Longest stretch | under 2 min | under 3 min | under 2 min | under 2.5 min |
| Back-and-forth | higher is better | higher is better | higher is better | higher is better |
| Questions per 30 min | 8–20 | no target | 8–20 | 6–15 |
| Room given | longer is better | no target | longer is better | longer is better |
| Fillers and restarts | lower is better | lower is better | lower is better | lower is better |

These are starting points drawn from the research. The trends measure movement relative to them, not pass or fail.

## 5. Delivery phases

| Phase | Requirements | AI used |
|---|---|---|
| **1. Numbers and trends** | A, B, C1–C5, E (Overview with numbers only, Trends, Record), F1, F3 | No |
| **2. Overall coaching** | C6, D, E (all tabs), F2, F4, F5, G | Yes |

## 6. Questions for you

1. **Default targets (section 4):** do they fit your role? For example, should your internal meetings, where you lead, allow a higher talk share?
2. **Trend window:** last 5 meetings of a type against the 5 before. Or would you prefer by time, such as the last 30 days against the 30 before?
3. **Trust reading:** keep it as its own tab?
4. **Name:** "My coaching" (我的表現), or something else?
