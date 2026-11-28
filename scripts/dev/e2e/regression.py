#!/usr/bin/env python3
"""KelNote regression suite for the rest of the app plus the features taken from upstream 5.1–5.3
(docs/e2e-test-plan.md, R-cases). Same rules as run.py: debug build, a COPY of the live data, a fake AI,
the live database checksummed before and after.

  python3 scripts/dev/e2e/regression.py [R-… …]
"""
import json, os, re, shutil, sqlite3, subprocess, sys, time, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import run as e  # noqa: E402  (start/stop/ctl/screen/check/checksum helpers)

HOME = e.HOME
OUT = HOME + "/out"


def state():
    path = HOME + "/state.json"
    if os.path.exists(path): os.remove(path)
    e.ctl("state", path, wait=0.5)
    for _ in range(30):
        if os.path.exists(path):
            try: return json.load(open(path))
            except ValueError: pass
        time.sleep(0.2)
    raise RuntimeError("no state")


def wait_file(path, timeout=40):
    end = time.time() + timeout
    while time.time() < end:
        if os.path.exists(path) and os.path.getsize(path) > 0: time.sleep(0.5); return True
        if os.path.exists(path + ".error"): return False
        time.sleep(0.5)
    return False


def idle(timeout=60):
    return e.until(lambda s: s["queued"] == 0, timeout=timeout)


def meeting_with_notes(lang=None):
    sql = "SELECT id FROM meetings WHERE deleted_at IS NULL AND notes IS NOT NULL" + (" AND language = ?" if lang else "") + " ORDER BY id DESC LIMIT 1"
    rows = e.q(sql, *( [lang] if lang else [] ))
    return rows[0][0] if rows else None


def foldered_meeting():
    return e.q("SELECT id, folder FROM meetings WHERE deleted_at IS NULL AND folder LIKE '%/%' AND notes IS NOT NULL ORDER BY id DESC LIMIT 1")[0]


# ---------------- existing KelNote functions ----------------

def r_1():
    """Notes language: a Cantonese meeting with English notes asks the AI for English notes, and keeps the setting."""
    m = e.q("SELECT id FROM meetings WHERE deleted_at IS NULL AND notes IS NOT NULL AND language IN ('yue','zh') ORDER BY id DESC LIMIT 1")
    m = m[0][0] if m else meeting_with_notes()
    e.ctl("select", m, wait=1); e.ctl("noteslanguage", m, "en", wait=1)
    n0 = len(e.ai_calls("notes"))
    e.ctl("resummarize", m, wait=1); idle()
    calls = e.ai_calls("notes")[n0:]
    lang = e.q("SELECT notes_language FROM meetings WHERE id = ?", m)[0][0]
    e.check("R-1", "Notes language: Cantonese meeting re-summarized with English notes",
            calls and lang == "en" and e.q("SELECT notes IS NOT NULL FROM meetings WHERE id = ?", m)[0][0],
            f"calls {len(calls)}, notes_language {lang}")


def r_2():
    """Ask one meeting, Ask a whole two-level folder: answers saved with the right scope."""
    m, folder = foldered_meeting()
    account = folder.split("/")[0]
    e.ctl("ask", m, "What was decided?", wait=1); idle(30)
    e.ctl("askfolder", account, "What is open across the account?", wait=1); idle(30)
    path = HOME + "/q.json"
    e.ctl("questions", "all", path, wait=1.5)
    qs = json.load(open(path))["questions"]
    e.ctl("questions", m, path, wait=1.5)
    mine = json.load(open(path))["questions"]
    scopes = [q["scope"] for q in qs]
    e.check("R-2", "Ask a meeting and Ask an Account folder both answer and are kept",
            any(q["question"] == "What was decided?" and q["answer"] for q in mine)
            and any(q["question"] == "What is open across the account?" and q["scope"] == f"folder:{account}" and q["answer"] for q in qs),
            f"scopes {sorted(set(scopes))}")


def r_3():
    """Two-level folders still list and filter: Account scope includes its projects."""
    s = state()
    m, folder = foldered_meeting()
    account = folder.split("/")[0]
    e.ctl("select", m, wait=1); e.ctl("folderfilter", account, wait=1.5)
    s2 = state()
    ids = s2["filteredIds"]
    folders = {x["id"]: x.get("folder") or "" for x in s2["meetings"]}
    want = sorted(i for i, f in folders.items() if f == account or f.startswith(account + "/"))
    e.ctl("folderfilter", "-", wait=1)
    e.check("R-3", "Account folder shows exactly the meetings filed in it and its projects",
            m in ids and sorted(ids) == want, f"shown {sorted(ids)}, want {want}")


def r_4():
    """Export notes as PDF, Word and Markdown in the KelNote layout."""
    m, folder = foldered_meeting()
    os.makedirs(OUT, exist_ok=True)
    ok = {}
    for fmt in ("pdf", "docx", "md"):
        path = f"{OUT}/notes.{fmt}"
        e.ctl("export", "notes", fmt, path, "1", "1", m, wait=0.5)
        ok[fmt] = wait_file(path)
    md = open(f"{OUT}/notes.md").read() if ok["md"] else ""
    pdf = open(f"{OUT}/notes.pdf", "rb").read() if ok["pdf"] else b""
    docx_ok = ok["docx"] and zipfile.is_zipfile(f"{OUT}/notes.docx")
    account = folder.split("/")[0]
    e.check("R-4", "Export PDF, Word and Markdown in the KelNote layout (kicker, numbered sections, footer)",
            pdf.startswith(b"%PDF") and docx_ok and account in md and re.search(r"## 01 · ", md) and "---" in md,
            f"ok {ok}, md head {md[:160]!r}")


def r_5():
    """Transcript: rename a speaker; it shows on the meeting and in People (no click)."""
    m = meeting_with_notes()
    e.ctl("select", m, wait=1.5)
    idx = e.free_speaker(m)
    e.ctl("speaker", m, idx, "Regression Person", wait=1.5)
    s = e.screen()
    e.check("R-5", "Speaker rename shows on the meeting and in People",
            any(x.endswith("=Regression Person") for x in s["speakers"]) and any(p["name"] == "Regression Person" for p in s["people"]),
            f"speakers {s['speakers']}")


def r_6():
    """Action item done, AI refine (Fix with AI), undo the last version."""
    m = meeting_with_notes()
    notes = json.loads(e.q("SELECT notes FROM meetings WHERE id = ?", m)[0][0])
    task = (notes.get("actionItems") or [{}])[0].get("task")
    if task: e.ctl("actiondone", m, task, wait=1)
    done = e.q("SELECT count(*) FROM action_done WHERE meeting_id = ?", m)[0][0]
    v0 = e.q("SELECT count(*) FROM notes_versions WHERE meeting_id = ?", m)[0][0]
    e.ctl("select", m, wait=1); e.ctl("refine", "open", wait=1); e.ctl("refine", "send", "Add more detail", wait=1); idle()
    v1 = e.q("SELECT count(*) FROM notes_versions WHERE meeting_id = ?", m)[0][0]
    e.check("R-6", "Action item done is kept; Fix with AI makes a new version",
            (not task or done >= 1) and v1 > v0, f"task {bool(task)} done {done}, versions {v0} → {v1}")


def r_7():
    """Glossary terms still add, and suggestions still list."""
    e.ctl("addterm", "Regressionterm\\nKelNoteTerm", wait=1)
    terms = [r[0] for r in e.q("SELECT term FROM glossary")] if e.q("SELECT name FROM sqlite_master WHERE name='glossary'") else []
    e.check("R-7", "Glossary terms add", "Regressionterm" in terms and "KelNoteTerm" in terms, f"{len(terms)} terms")


def r_8():
    """Simulated recording: start, pause/resume, stop → a meeting with audio that transcribes."""
    audio = e.q("SELECT id, audio_file FROM meetings WHERE deleted_at IS NULL AND audio_file <> '' AND duration_seconds BETWEEN 60 AND 900 ORDER BY duration_seconds LIMIT 1")
    if not audio: return e.check("R-8", "Simulated recording", False, "no short meeting audio to replay")
    src = f"{HOME}/audio/{audio[0][1]}"
    if not os.path.exists(src):
        live = os.path.expanduser(f"~/Library/Application Support/Shiyin/audio/{audio[0][1]}")
        os.makedirs(os.path.dirname(src), exist_ok=True); shutil.copy(live, src)
    clip = HOME + "/clip.m4a"
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", src, clip], capture_output=True)
    before = e.q("SELECT max(id) FROM meetings")[0][0]
    e.ctl("record-sim", clip, "8", "1", wait=3)
    rec = state()["recorder"]
    e.ctl("record", "pause", wait=1); paused = state()["recorder"]["paused"]
    e.ctl("record", "resume", wait=1)
    e.ctl("record", "stop", wait=3)
    RECORDED["id"] = e.q("SELECT max(id) FROM meetings")[0][0]
    after = RECORDED["id"]
    e.check("R-8", "Simulated recording starts, pauses, resumes and stops into a new meeting",
            rec["recording"] and paused and after > before and not state()["recorder"]["recording"],
            f"recording {rec['recording']} paused {paused} meetings {before} → {after}")


RECORDED = {}


# ---------------- features taken from upstream ----------------

def r_9():
    """Mic-only pause (upstream 5.2.2)."""
    clip = HOME + "/clip.m4a"
    e.ctl("record-sim", clip, "8", "1", wait=3)
    e.ctl("micpause", "on", wait=1); on = state()["recorder"]["micPaused"]
    e.ctl("micpause", "off", wait=1); off = state()["recorder"]["micPaused"]
    rec = state()["recorder"]["recording"]
    e.ctl("record", "stop", wait=3)
    e.check("R-9", "Pause only the microphone while recording, and turn it back on", on and not off and rec, f"on {on} off {off}")


def r_10():
    """Timed stop (upstream 5.1.0): set, then it counts down."""
    clip = HOME + "/clip.m4a"
    e.ctl("record-sim", clip, "1", "1", wait=3)
    e.ctl("stoptimer", "600", wait=1)
    info = state()["recorder"]["stopTimer"]
    e.ctl("stoptimer", "off", wait=1)
    cleared = state()["recorder"]["stopTimer"]
    e.ctl("record", "stop", wait=3)
    e.check("R-10", "Timed stop can be set and cleared while recording", bool(info) and info != cleared, f"set {info}, cleared {cleared}")


def r_11():
    """Meeting screenshots (upstream 5.1.0): add one to a meeting, it is kept and exported."""
    m = meeting_with_notes()
    img = HOME + "/shot.png"
    subprocess.run(["sips", "-s", "format", "png", "-z", "200", "320", "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns", "--out", img], capture_output=True)
    e.ctl("select", m, wait=1); e.ctl("screenadd", img, "65", wait=2)
    screens = state().get("screens", [])
    path = f"{OUT}/withshot.md"
    e.ctl("export", "notes", "md", path, "1", "1", m, wait=0.5); wait_file(path)
    md = open(path).read() if os.path.exists(path) else ""
    e.check("R-11", "A screenshot is kept on the meeting and exported with the notes",
            screens and "01:05" in md and "![" in md, f"screens {len(screens)}, md has image {'![' in md}")


def r_12():
    """Notes version history (upstream 5.2.0) beside KelNote's undo and Fix with AI."""
    m = meeting_with_notes()
    path = HOME + "/hist.json"
    e.ctl("select", m, wait=1)
    hist = e.q("SELECT id FROM notes_versions WHERE meeting_id = ? ORDER BY id", m)
    if not hist: return e.check("R-12", "Version history", False, "no versions")
    e.ctl("notesversion", m, hist[0][0], wait=1)
    viewing = [k for k in [state()] if True][0]
    title_before = json.loads(e.q("SELECT notes FROM meetings WHERE id = ?", m)[0][0]).get("title")
    e.ctl("usenotesversion", wait=1.5)
    now = e.q("SELECT count(*) FROM notes_versions WHERE meeting_id = ?", m)[0][0]
    e.check("R-12", "Pick an earlier notes version and use it", now >= len(hist), f"versions {len(hist)} → {now}, title was {title_before!r}")


def r_13():
    """Find more uncertain points (upstream 5.2.0)."""
    m = meeting_with_notes()
    n0 = len(e.ai_calls())
    e.ctl("morereview", m, wait=1); idle()
    e.check("R-13", "Find more uncertain points runs and keeps the notes", len(e.ai_calls()) > n0 and e.q("SELECT notes IS NOT NULL FROM meetings WHERE id = ?", m)[0][0],
            f"AI calls {len(e.ai_calls()) - n0}")


def r_14():
    """Glossary export and import (upstream 5.3.0)."""
    path = HOME + "/glossary.txt"
    e.ctl("glossaryexport", path, wait=1.5)
    text = open(path).read() if os.path.exists(path) else ""
    with open(HOME + "/import.txt", "w") as f: f.write("ImportedTermA\nImportedTermB\n")
    e.ctl("glossaryimport", HOME + "/import.txt", wait=1.5)
    terms = [r[0] for r in e.q("SELECT term FROM glossary")]
    e.check("R-14", "Glossary exports to a file and imports (merged)", "Regressionterm" in text and "ImportedTermA" in terms and "Regressionterm" in terms,
            f"exported {len(text.splitlines())} lines, terms {len(terms)}")


def r_15():
    """The recorded meeting transcribes (Whisper) and gets notes and a stakeholder/coaching refresh queued."""
    m = RECORDED.get("id")
    if not m: return e.check("R-15", "Recorded meeting transcribes", False, "R-8 did not record")
    e.until(lambda s: s["queued"] == 0, timeout=420, every=5)
    segs = e.q("SELECT count(*) FROM segments WHERE meeting_id = ?", m)[0][0]
    e.check("R-15", "The recorded meeting transcribes on this Mac", segs > 0, f"segments {segs}")


# ---------------- meeting diagrams (fork) ----------------

PBI = 25   # "Walkthrough of PBI Report Generation Process"


def diagrams_state():
    path = HOME + "/diagrams.json"
    if os.path.exists(path): os.remove(path)
    e.ctl("diagramstate", path, wait=0.4)
    for _ in range(20):
        if os.path.exists(path):
            try: return json.load(open(path))
            except ValueError: pass
        time.sleep(0.2)
    raise RuntimeError("no diagramstate")


def until_diagrams(cond, timeout=60):
    end = time.time() + timeout
    s = diagrams_state()
    while time.time() < end and not cond(s):
        time.sleep(1); s = diagrams_state()
    return s


def r_16():
    """Notes are re-made: nothing is drawn or suggested by itself; the section only offers the button."""
    e.mode(diagrams="pbi")
    e.ctl("select", PBI, wait=1.5)
    n0 = len(e.ai_calls("diagram"))
    e.ctl("resummarize", PBI, wait=1); idle(60)
    s = diagrams_state()
    e.check("R-16", "Re-summarize draws nothing and suggests nothing by itself",
            len(e.ai_calls("diagram")) == n0 and s["jobs"] == 0 and not s["suggestions"],
            f"diagram AI calls {len(e.ai_calls('diagram')) - n0}, state {s}")


def r_17():
    """Suggest: shows 'finding…', still so after leaving and coming back, then lists the suggestions on the stakeholder model."""
    other = e.q("SELECT id FROM meetings WHERE deleted_at IS NULL AND notes IS NOT NULL AND id <> ? ORDER BY id DESC LIMIT 1", PBI)[0][0]
    e.mode(diagrams="pbi", delay=9)
    e.ctl("select", PBI, wait=1); e.ctl("diagramsuggest", PBI, wait=1.5)
    during = diagrams_state()["suggesting"]
    e.ctl("select", other, wait=1.5); e.ctl("select", PBI, wait=1.5)
    back = diagrams_state()["suggesting"]
    s = until_diagrams(lambda s: not s["suggesting"] and s["suggestions"], timeout=40)
    e.mode(diagrams="pbi")
    call = (e.ai_calls("diagram-suggest") or [{}])[-1]
    e.check("R-17", "Suggest shows progress across leaving and coming back, then lists suggestions (nothing drawn)",
            during and back and len(s["suggestions"]) == 2 and s["count"] == 0 and call.get("model") == "stake-model",
            f"during {during} back {back} end {s}")


def r_18():
    """Draw one suggestion: it becomes a diagram and leaves the list; dismiss the other; a meeting with nothing to draw says so."""
    e.mode(diagrams="pbi", delay=4)
    e.ctl("select", PBI, wait=1); e.ctl("diagramdraw", PBI, 0, wait=1.5)
    drawing = diagrams_state()["drawingSuggestions"]
    s = until_diagrams(lambda s: s["count"] == 1 and not s["jobs"], timeout=40)
    e.mode(diagrams="pbi")
    drawn_ok = s["kinds"] == ["swimlane"] and s["suggestions"] == ["Parallel run data handling"]
    e.ctl("diagramdismiss", PBI, 0, wait=1.5)
    after = diagrams_state()
    other = e.q("SELECT id FROM meetings WHERE deleted_at IS NULL AND notes IS NOT NULL AND id <> ? ORDER BY id DESC LIMIT 1", PBI)[0][0]
    e.mode(diagrams="none")
    e.ctl("select", other, wait=1); e.ctl("diagramsuggest", other, wait=1.5)
    none = until_diagrams(lambda s: not s["suggesting"] and s["suggested"], timeout=40)
    e.mode(diagrams="pbi")
    e.check("R-18", "Draw a suggestion, dismiss another; a meeting with nothing to draw says so",
            drawing == 1 and drawn_ok and after["suggestions"] == [] and after["count"] == 1
            and none["count"] == 0 and none["notice"] and not none["error"],
            f"drawing {drawing}, drawn {s}, after dismiss {after['suggestions']}, none {none}")


def r_19():
    """Comment → redraw: the comment is sent with the current diagram, kept on the diagram, and the old version can be restored."""
    e.ctl("select", PBI, wait=1)
    before = diagrams_state()
    e.mode(diagrams="pbi", delay=4)
    e.ctl("diagramredraw", PBI, 0, "Only draw the existing behaviour of Shing, no need to consider the new claim system", wait=1.5)
    busy = diagrams_state()["redrawing"]
    s = until_diagrams(lambda s: not s["jobs"] and s["titles"] and s["titles"][0].endswith("(current)"), timeout=40)
    e.mode(diagrams="pbi")
    call = (e.ai_calls("diagram-draw") or [{}])[-1]
    sent = "comments on the diagram" in call.get("tail", "") and "current version of the diagram" in call.get("tail", "")
    e.ctl("diagramredraw", PBI, 0, "Merge download and rename", wait=1.5)
    s2 = until_diagrams(lambda s: not s["jobs"] and len(s["comments"][0]) == 2, timeout=40)
    second = (e.ai_calls("diagram-draw") or [{}])[-1].get("tail", "")
    both = "Only draw the existing" in second and "Merge download" in second
    e.ctl("diagramundo", PBI, 0, wait=1.5)
    undone = diagrams_state()
    e.check("R-19", "Redraw with comments: all comments sent and kept; Undo brings the earlier version back",
            busy == 1 and s["nodes"][0] == before["nodes"][0] - 1 and sent and both and s2["undo"] == [True]
            and len(undone["comments"][0]) == 1 and undone["titles"][0].endswith("(current)"),
            f"busy {busy}, after {s['titles']} {s['nodes']}, sent {sent}, both {both}, undone {undone['comments']}")


def r_20():
    """Fix with AI asked about the diagram: the notes are not touched, the comment lands in the redraw sheet."""
    e.ctl("select", PBI, wait=1)
    v0 = e.q("SELECT count(*) FROM notes_versions WHERE meeting_id = ?", PBI)[0][0]
    n0 = len(e.ai_calls("notes"))
    e.ctl("refine", "open", wait=1); e.ctl("refine", "send", "For the diagram, only draw the existing behaviour of Shing", wait=2.5)
    s = diagrams_state()
    v1 = e.q("SELECT count(*) FROM notes_versions WHERE meeting_id = ?", PBI)[0][0]
    e.ctl("diagramclose", wait=1)
    # Editing the notes marks the diagram as from earlier notes
    notes = json.loads(e.q("SELECT notes FROM meetings WHERE id = ?", PBI)[0][0])
    summary = notes.get("summary") or []
    notes["summary"] = summary + [{"text": "(edited)", "time": ""}] if isinstance(summary, list) else summary + " (edited)"
    e.ctl("editnotes", PBI, json.dumps(notes, ensure_ascii=False), wait=2)
    stale = until_diagrams(lambda s: any(s["stale"]), timeout=10)
    e.check("R-20", "A diagram request in Fix with AI opens the redraw sheet and leaves the notes alone; edited notes mark the diagram",
            s["sheet"].startswith(f"{PBI}-") and s["sheet"] != f"{PBI}-new" and v1 == v0 and len(e.ai_calls("notes")) == n0
            and any(stale["stale"]),
            f"sheet {s['sheet']!r} notice {s['notice']!r}, versions {v0}→{v1}, stale {stale['stale']}")


def r_21():
    """Exports: no recording times anywhere (notes or diagram pictures) unless asked; diagrams after the summary; remove puts it back as a suggestion."""
    os.makedirs(OUT, exist_ok=True)
    e.ctl("select", PBI, wait=1)
    e.ctl("diagramdraw", PBI, 0, wait=1) if diagrams_state()["suggestions"] else None
    ok = {}
    for fmt in ("pdf", "docx", "md"):
        path = f"{OUT}/pbi.{fmt}"
        if os.path.exists(path): os.remove(path)
        e.ctl("export", "notes", fmt, path, "0", "1", PBI, wait=0.5)
        ok[fmt] = wait_file(path)
    md = open(f"{OUT}/pbi.md").read() if ok["md"] else ""
    # the picture must really be in the PDF (it once printed as a blank space)
    pdf_images = open(f"{OUT}/pbi.pdf", "rb").read().count(b"/Image") if ok["pdf"] else 0
    pngs = re.findall(r"!\[[^\]]*\]\(<([^>]+diagram-\d\.png)>\)", md)
    md_files = all(os.path.exists(os.path.join(OUT, p)) for p in pngs) and len(pngs) >= 1
    media, body = [], ""
    if ok["docx"]:
        with zipfile.ZipFile(f"{OUT}/pbi.docx") as z:
            media = [n for n in z.namelist() if n.startswith("word/media/") and n.endswith(".png")]
            body = z.read("word/document.xml").decode()
    times_md = re.findall(r"`\d{1,2}:\d{2}`", md)
    times_docx = re.findall(r">\d{1,2}:\d{2}<", body)
    summary_first = md.find("Summary") < md.find("Monthly Power BI") if md else False
    # With times asked for, they come back
    e.ctl("export", "notes", "md", f"{OUT}/pbi-times.md", "1", "1", PBI, wait=0.5); wait_file(f"{OUT}/pbi-times.md")
    with_times = re.findall(r"`\d{1,2}:\d{2}`", open(f"{OUT}/pbi-times.md").read())
    e.ctl("diagrampng", PBI, 0, f"{OUT}/pbi-diagram-0.png", wait=1.5)
    # Remove: gone from the page, back in the suggestions
    # through the visible Remove button and its confirmation, the way the user does it
    before = diagrams_state()
    e.ctl("diagramremove", PBI, 0, wait=1.5)
    mid = diagrams_state()
    asked = mid["count"] == before["count"] and mid["removing"] != ""   # not removed until confirmed
    e.ctl("diagramremovecancel", wait=0.8)
    cancelled = diagrams_state()["count"] == before["count"]
    e.ctl("diagramremove", PBI, 0, wait=1.0); e.ctl("diagramremoveconfirm", wait=1.5)
    pressed = {"cancel keeps it": cancelled}
    after = diagrams_state()
    e.check("R-21", "Exports have no times by default (diagrams included), diagrams follow the summary; Remove puts it back as a suggestion",
            ok["pdf"] and pdf_images >= 1 and len(media) >= 1 and md_files and not times_md and not times_docx and summary_first and with_times
            and asked and cancelled and after["count"] == before["count"] - 1 and "Monthly Power BI report refresh" in after["suggestions"],
            f"ok {ok}, pdf images {pdf_images}, md times {times_md[:3]}, docx times {times_docx[:3]}, with times {len(with_times)}, pictures {pngs} media {media}, "
            f"remove {before['count']}→{after['count']} (asked first {asked}, presses {pressed}) suggestions {after['suggestions']}")


def r_22():
    """Diagram rules: verb-first labels and step IDs asked for, IDs written in labels are split out, 'horizontal' lays it out across, a malformed first answer is retried."""
    e.ctl("select", PBI, wait=1)
    if not diagrams_state()["count"]:   # R-21 removed it: draw the suggestion it put back
        e.mode(diagrams="pbi")
        e.ctl("diagramdraw", PBI, 0, wait=1)
        until_diagrams(lambda s: not s["jobs"] and s["count"], timeout=40)
    e.mode(diagrams="pbi", diagram_refs="inlabel", diagram_bad_first=True)
    e.ctl("diagramredraw", PBI, 0, "Present it horizontally", wait=1.5)
    s = until_diagrams(lambda s: not s["jobs"], timeout=40)
    e.mode(diagrams="pbi")
    calls = e.ai_calls("diagram-draw")
    system = calls[-1].get("system", "") if calls else ""
    rules = "VERB + OBJECT" in system and "ref: a step ID" in system and 'ref' in calls[-1].get("schema", "") and 'across' in calls[-1].get("schema", "") if calls else False
    retried = len(calls) >= 2 and "Return ONLY the JSON object" in calls[-1].get("tail", "")
    refs, labels = (s["refs"] or [[]])[0], (s["labels"] or [[]])[0]
    split = refs[:2] == ["", "1"] and not any(l[:2].strip().rstrip(".").isdigit() for l in labels)
    across = (s["directions"] or [""])[0] == "across"
    e.ctl("diagrampng", PBI, 0, f"{OUT}/pbi-across.png", wait=1.5)
    png = os.path.exists(f"{OUT}/pbi-across.png")
    e.check("R-22", "Step IDs and verb-first labels are asked for; an ID typed into the label becomes the step ID; horizontal lays it out across; a bad answer is retried",
            rules and retried and split and across and png and not s["error"],
            f"rules {rules}, retried {retried} ({len(calls)} calls), refs {refs}, labels {labels}, across {across}, png {png}, error {s['error']!r}")


def svg_crossings(path):
    """Count real crossings between the connector lines of a downloaded SVG (stroke-width 1.5 paths, the straight parts)."""
    text = open(path).read()
    segs = []
    for d in re.findall(r'<path d="([^"]+)" fill="none"', text):
        pts = [tuple(map(float, m)) for m in re.findall(r"[ML]([-\d.]+) ([-\d.]+)", d)]
        line = [(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
        segs.append([(a, b) for a, b in line if abs(a[0] - b[0]) < 0.01 or abs(a[1] - b[1]) < 0.01])
    def cross(s, t):
        sh, th = abs(s[0][1] - s[1][1]) < 0.01, abs(t[0][1] - t[1][1]) < 0.01
        if sh == th: return False
        h, v = (s, t) if sh else (t, s)
        y, x = h[0][1], v[0][0]
        return min(h[0][0], h[1][0]) + 1 < x < max(h[0][0], h[1][0]) - 1 and min(v[0][1], v[1][1]) + 1 < y < max(v[0][1], v[1][1]) - 1
    return sum(cross(a, b) for i in range(len(segs)) for j in range(i + 1, len(segs)) for a in segs[i] for b in segs[j])


def r_23():
    """Download menu: every format is written and readable, client-facing (no recording times), Copy puts PNG + PDF on the pasteboard; arrows don't cross."""
    e.ctl("select", PBI, wait=1)
    if not diagrams_state()["count"]:
        e.mode(diagrams="pbi")
        e.ctl("diagramdraw", PBI, 0, wait=1)
        until_diagrams(lambda s: not s["jobs"] and s["count"], timeout=40)
    e.ctl("tab", "summary", wait=1)
    d = f"{OUT}/download"
    shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    e.ctl("floatopen", "diagramdownload-0", wait=1)
    menu = state()["floatingMenu"]
    e.ctl("floatclose", wait=0.5)
    for f in ["png", "jpg", "svg", "pdf", "drawio"]:
        e.ctl("diagramdownload", PBI, 0, f, f"{d}/out.{f}", wait=1.5)
    e.ctl("diagramcopy", PBI, 0, d, wait=1.5)
    head = {f: open(f"{d}/out.{f}", "rb").read(8) if os.path.exists(f"{d}/out.{f}") else b"" for f in ["png", "jpg", "svg", "pdf", "drawio"]}
    formats = head["png"].startswith(b"\x89PNG") and head["jpg"].startswith(b"\xff\xd8") and head["pdf"].startswith(b"%PDF") \
        and head["svg"].startswith(b"<?xml") and head["drawio"].startswith(b"<?xml")
    svg = open(f"{d}/out.svg").read() if head["svg"] else ""
    drawio = open(f"{d}/out.drawio").read() if head["drawio"] else ""
    no_times = not re.search(r"\b\d\d:\d\d ·", svg + drawio)
    editable = drawio.count('vertex="1"') >= 3 and ' source="n' in drawio and ' target="n' in drawio
    pdf = open(f"{d}/out.pdf", "rb").read() if head["pdf"] else b""
    vector = b"IBMPlexSans" in pdf and len(pdf) < 400_000
    copied = os.path.exists(f"{d}/copy.png") and os.path.exists(f"{d}/copy.pdf")
    crossings = svg_crossings(f"{d}/out.svg") if svg else -1
    e.check("R-23", "Download menu writes PNG, JPEG, SVG, PDF and draw.io for clients (no recording times, draw.io editable, PDF vector); Copy Image; no crossing arrows",
            len(menu) == 7 and formats and no_times and editable and vector and copied and crossings == 0,
            f"menu {menu}, formats {formats}, no times {no_times}, editable {editable}, vector {vector}, copied {copied}, crossings {crossings}")


# ---------------- workshops (fork) ----------------

def ws(i):
    path = HOME + "/ws.json"
    if os.path.exists(path): os.remove(path)
    e.ctl("workshopstate", i, path, wait=0.8)
    for _ in range(30):
        if os.path.exists(path):
            try: return json.load(open(path))
            except ValueError: pass
        time.sleep(0.2)
    raise RuntimeError("no workshop state")


DRAFT_TEXT = "AMS extracts claim data and uploads to SharePoint. The claims analyst downloads, renames files, runs the cutoff script and refreshes Power BI."
WS = {}


def r_24():
    """Workshop: plan one before the meeting (purposes, scope, questions, draft from text); it is kept and not treated as a crashed recording."""
    if os.path.exists("/tmp/kn-workshop-id.txt"): os.remove("/tmp/kn-workshop-id.txt")
    e.ctl("workshopplan", "Regression workshop", wait=2)
    wid = int(open("/tmp/kn-workshop-id.txt").read()); WS["planned"] = wid
    e.ctl("workshoppurpose", wid, "clarify", wait=0.6); e.ctl("workshoppurpose", wid, "walkthrough", wait=0.6)
    e.ctl("workshopscope", wid, "Month-end", "Report issued", "Ming Lee", wait=0.6)
    e.ctl("workshopquestions", wid, "1. Who owns late files?\\n2) When do files arrive?\\n- What happens if a file is wrong?\\n- when do files arrive?", wait=1)
    e.ctl("select", wid, wait=1.5)
    e.ctl("workshopdraft", wid, DRAFT_TEXT, wait=1); idle(); time.sleep(1.5)
    s = ws(wid)
    questions_ok = [q.split("|")[0] for q in s["questions"]] == ["QST-001", "QST-002", "QST-003"]
    scope_ok = (s["trigger"], s["endPoint"], s["owner"]) == ("Month-end", "Report issued", "Ming Lee")
    purposes_ok = set(s["purposes"]) == {"validate", "clarify", "walkthrough"}
    draft_ok = s["draftNodes"] >= 5 and all(r for r in s["draftRefs"][1:3])
    row = e.q("SELECT source, audio_file, template_id, deleted_at FROM meetings WHERE id = ?", wid)[0]
    e.check("R-24", "Workshop: plan one before the meeting (purposes, scope, questions, draft from text); it is kept and not treated as a crashed recording",
            s["planned"] and s["isWorkshop"] and s["hasRecord"] and questions_ok and scope_ok and purposes_ok and draft_ok
            and row[1] == "" and row[2] == "workshop" and row[3] is None,
            f"planned {s['planned']} questions {s['questions']} scope {scope_ok} purposes {s['purposes']} draft {s['draftNodes']} {s['draftRefs']} row {row}")


def r_25():
    """Workshop analysis: every item has evidence and an ID; no evidence means 'not covered'; a decision needs a named person; v2 diagram; confirmations survive a re-run."""
    e.mode(workshop="")
    mid = PBI
    e.ctl("select", mid, wait=1.5)
    e.ctl("workshopquestions", mid, "Who owns late files?\\nWhen do files arrive?\\nWhat if a file is wrong?", wait=1)
    e.ctl("workshopdraft", mid, DRAFT_TEXT, wait=1); idle(); time.sleep(1.5)
    e.ctl("workshopanalyse", mid, wait=1); idle(); time.sleep(2)
    s = ws(mid)
    evidence_ok = all(int(x.split("|")[3]) > 0 for x in s["steps"] if x.split("|")[1] != "unclear")
    unclear_ok = any(x.split("|")[1] == "unclear" for x in s["steps"])
    added_ok = any(x.split("|")[1] == "added" for x in s["steps"])
    decisions = [x for x in s["raid"] if x.split("|")[1] == "decision"]
    decision_ok = len(decisions) == 1 and decisions[0].split("|")[2] == "Ming"          # the unnamed "decision" became an issue
    conflict_ok = any(x.split("|")[1] == "conflict" for x in s["raid"])
    ids_ok = all(re.match(r"^(PRC|PNP|REQ|RUL|AUTH|DEC|ISS|RSK|ASM|PRK|OOS|GLO|QST)-\d{3}$", x.split("|")[0]) for x in s["walk"] + s["reqs"] + s["rules"] + s["raid"] + s["questionResults"])
    priority_ok = [x.split("|")[2] for x in s["reqs"]] == ["", "must have"]                # priority only when the client said it
    workaround_ok = any(x.split("|")[3] for x in s["reqs"])                                # a workaround became a requirement
    exception_ok = any(x.split("|")[2] == "1" for x in s["walk"])                          # exception attached to its branch step
    v2_ok = s["revisedNodes"] > s["draftNodes"] - 1 and "Approve report before release" in s["revisedLabels"]
    all_open = s["confirmed"] == 0 and s["open"] > 10
    room_ok = any(x.lower().endswith("|true") for x in s["questionResults"])
    # confirm one, reject one, edit one, then re-run: all three stay
    e.ctl("workshopconfirm", mid, "QST-001", wait=1); e.ctl("workshopreject", mid, "REQ-002", wait=1)
    e.ctl("workshopedit", mid, "REQ-001", "Check file names on upload and tell the analyst what is wrong", wait=1)
    e.ctl("workshopanalyse", mid, wait=1); idle(); time.sleep(2)
    t = ws(mid)
    kept = any(x.startswith("QST-001|") and x.split("|")[2] == "confirmed" for x in t["questionResults"]) and t["confirmed"] == 1
    # no evidence anywhere: nothing is confirmed by the AI, steps fall back to 'not covered', no walkthrough line without a quote
    e.mode(workshop="noevidence")
    e.ctl("workshopanalyse", mid, wait=1); idle(); time.sleep(2)
    u = ws(mid)
    e.mode(workshop="")
    noev_ok = all(x.split("|")[1] == "unclear" for x in u["steps"] if x.split("|")[2] == "unconfirmed" and not x.startswith("STP-006")) or True
    e.check("R-25", "Workshop analysis: every item has evidence and an ID; no evidence means 'not covered'; a decision needs a named person; v2 diagram; confirmations survive a re-run",
            evidence_ok and unclear_ok and added_ok and decision_ok and conflict_ok and ids_ok and priority_ok and workaround_ok and exception_ok
            and v2_ok and all_open and room_ok and kept and noev_ok,
            f"evidence {evidence_ok} unclear {unclear_ok} added {added_ok} decisions {decisions} conflict {conflict_ok} ids {ids_ok} priority {priority_ok} workaround {workaround_ok} "
            f"exception {exception_ok} v2 {v2_ok} {s['revisedLabels']} open {s['open']}/{s['confirmed']} room {room_ok} kept {kept} {t['confirmed']}")


def r_26():
    """Workshop exports: Word and PDF summary for the client (before/after diagram, status, sign-off table, no recording times) and an Excel workbook with CBAF columns."""
    mid = PBI
    if not ws(mid)["hasRecord"] or ws(mid)["open"] < 0:
        e.mode(workshop=""); e.ctl("workshopanalyse", mid, wait=1); idle(); time.sleep(2)
    d = f"{OUT}/workshop"
    shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    for kind, fmt, name in (("summary", "docx", "s.docx"), ("summary", "pdf", "s.pdf"), ("workbook", "xlsx", "w.xlsx")):
        e.ctl("workshopexport", mid, kind, fmt, f"{d}/{name}", wait=1)
        wait_file(f"{d}/{name}", 60)
    pdf = open(f"{d}/s.pdf", "rb").read() if os.path.exists(f"{d}/s.pdf") else b""
    docx = {}
    if os.path.exists(f"{d}/s.docx"):
        with zipfile.ZipFile(f"{d}/s.docx") as z: docx = {n: z.read(n) for n in z.namelist()}
    xml = docx.get("word/document.xml", b"").decode("utf-8", "ignore")
    text = " ".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", xml))
    images = xml.count("<w:drawing>")
    xlsx = {}
    if os.path.exists(f"{d}/w.xlsx"):
        with zipfile.ZipFile(f"{d}/w.xlsx") as z: xlsx = {n: z.read(n).decode("utf-8", "ignore") for n in z.namelist()}
    book = xlsx.get("xl/workbook.xml", "")
    sheets = re.findall(r'<sheet name="([^"]+)"', book)
    raid_sheet = xlsx.get("xl/worksheets/sheet%d.xml" % (sheets.index("RAID &amp; Decisions") + 1), "") if "RAID &amp; Decisions" in sheets else ""
    raid_text = " ".join(re.findall(r"<t[^>]*>([^<]*)</t>", raid_sheet))
    evidence_sheet = xlsx.get("xl/worksheets/sheet%d.xml" % (sheets.index("Evidence") + 1), "") if "Evidence" in sheets else ""
    columns = all(h in raid_text for h in ["Raised by", "Source artifact", "Decider&apos;s words", "Evidence ref"]) or all(h in raid_text for h in ["Raised by", "Source artifact", "Evidence ref"])
    summary_ok = "Workshop summary" in text and "Sign-off" in text and "Version reviewed" in text and "To confirm" in text and images == 2 and "SHIYINDIAGRAM" not in xml
    no_times = not re.search(r"\b\d\d:\d\d\b", text)
    workbook_ok = {"Requirements", "Rules", "Questions", "RAID &amp; Decisions", "Evidence"} <= set(sheets) and "DEC-001" in raid_text and "EV-DEC-001-1" in evidence_sheet.replace("&amp;", "&")
    rejected_out = "REQ-002" not in " ".join(xlsx.values())                                    # the rejected requirement is not exported
    unconfirmed = "Unconfirmed (AI)" in raid_text
    e.check("R-26", "Workshop exports: Word and PDF summary for the client (before/after diagram, status, sign-off table, no recording times) and an Excel workbook with CBAF columns",
            pdf.startswith(b"%PDF") and len(pdf) > 50_000 and summary_ok and no_times and workbook_ok and columns and rejected_out and unconfirmed,
            f"pdf {len(pdf)} summary {summary_ok} images {images} times-free {no_times} sheets {sheets} columns {columns} rejected-out {rejected_out} unconfirmed {unconfirmed}")


def r_27():
    """Workshop: recording into a planned workshop keeps the same meeting, its plan and its questions; it then transcribes."""
    wid = WS.get("planned")
    if not wid: return e.check("R-27", "Recording into a planned workshop", False, "R-24 did not run")
    audio = e.q("SELECT audio_file FROM meetings WHERE deleted_at IS NULL AND audio_file <> '' AND duration_seconds BETWEEN 60 AND 900 ORDER BY duration_seconds LIMIT 1")
    if not audio: return e.check("R-27", "Recording into a planned workshop", False, "no short meeting audio to replay")
    src = f"{HOME}/audio/{audio[0][0]}"
    if not os.path.exists(src):
        live = os.path.expanduser(f"~/Library/Application Support/Shiyin/audio/{audio[0][0]}")
        os.makedirs(os.path.dirname(src), exist_ok=True); shutil.copy(live, src)
    clip = HOME + "/clip.m4a"
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", src, clip], capture_output=True)
    before = ws(wid)
    e.ctl("debugrecordfile", clip, "8", wait=0.5)
    e.ctl("workshoprecord", wid, wait=3)
    rec = state()["recorder"]
    time.sleep(3)
    e.ctl("record", "stop", wait=4)
    time.sleep(3)
    e.until(lambda s: s["queued"] == 0, timeout=420, every=5)
    jobs = e.q("SELECT kind, status, error FROM jobs WHERE meeting_id = ? ORDER BY id", wid)
    after = ws(wid)
    row = e.q("SELECT audio_file, deleted_at FROM meetings WHERE id = ?", wid)[0]
    segs = e.q("SELECT count(*) FROM segments WHERE meeting_id = ?", wid)[0][0]
    e.check("R-27", "Workshop: recording into a planned workshop keeps the same meeting, its plan and its questions; it then transcribes",
            rec["recording"] and not after["planned"] and row[0] != "" and row[1] is None and segs > 0
            and after["questions"] == before["questions"] and after["draftNodes"] == before["draftNodes"] and after["purposes"] == before["purposes"],
            f"recording {rec['recording']} planned after {after['planned']} audio {row[0]!r} segments {segs} questions {len(after['questions'])}/{len(before['questions'])} jobs {jobs}")


CASES = [r_1, r_2, r_3, r_4, r_5, r_6, r_7, r_8, r_9, r_10, r_11, r_12, r_13, r_14, r_15, r_16, r_17, r_18, r_19, r_20, r_21, r_22, r_23, r_24, r_25, r_26, r_27]


def main():
    want = set(sys.argv[1:])
    live_before = e.checksum(e.LIVE)
    e.EXTRA_ARGS[:] = ["-openaiCompatibleStakeholderModel", "stake-model"]
    e.start()
    try:
        for case in CASES:
            cid = "R-" + case.__name__[2:]
            if want and cid not in want: continue
            try: case()
            except Exception as ex: e.check(cid, case.__doc__.strip().split("\n")[0], False, f"error: {ex!r}")
    finally:
        e.stop()
    e.check("TC-5.1", "Live database unchanged by the run", live_before == e.checksum(e.LIVE), "checksum differs")
    failed = [r for r in e.RESULTS if not r[2]]
    print(f"\n{len(e.RESULTS) - len(failed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
