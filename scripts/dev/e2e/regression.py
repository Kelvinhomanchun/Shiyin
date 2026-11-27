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
    """After notes are re-made, a diagram is drawn automatically on the stakeholder model and shows with no click."""
    e.mode(diagrams="pbi")
    e.ctl("select", PBI, wait=1.5)
    n0 = len(e.ai_calls("diagrams"))
    e.ctl("resummarize", PBI, wait=1)
    s = until_diagrams(lambda s: s["count"] == 2 and not s["drawing"], timeout=90)
    calls = e.ai_calls("diagrams")[n0:]
    e.check("R-16", "Re-summarize draws the diagrams by itself, on the stakeholder model, and the notes page shows them",
            s["selection"] == PBI and s["kinds"] == ["swimlane", "flowchart"] and calls and calls[-1]["model"] == "stake-model"
            and s["model"] == "stake-model" and not s["stale"],
            f"state {s}, calls {[c['model'] for c in calls]}")


def r_17():
    """Redraw: it says drawing while it runs, still says so after leaving the meeting and coming back, then shows the result."""
    other = e.q("SELECT id FROM meetings WHERE deleted_at IS NULL AND notes IS NOT NULL AND id <> ? ORDER BY id DESC LIMIT 1", PBI)[0][0]
    e.mode(diagrams="pbi", delay=6)
    e.ctl("select", PBI, wait=1)
    e.ctl("drawdiagrams", PBI, wait=1.5)
    during = diagrams_state()["drawing"]
    e.ctl("select", other, wait=1.5); e.ctl("select", PBI, wait=1.5)
    back = diagrams_state()["drawing"]
    s = until_diagrams(lambda s: not s["drawing"], timeout=40)
    e.mode(diagrams="pbi")
    e.check("R-17", "Redraw shows 'drawing' until done, also after leaving and coming back",
            during and back and s["count"] == 2 and not s["error"], f"during {during} back {back} end {s}")


def r_18():
    """A meeting with no process: a redraw returns nothing, the page says so and shows no diagram section."""
    other = e.q("SELECT id FROM meetings WHERE deleted_at IS NULL AND notes IS NOT NULL AND id <> ? ORDER BY id DESC LIMIT 1", PBI)[0][0]
    e.mode(diagrams="none")
    e.ctl("select", other, wait=1)
    e.ctl("drawdiagrams", other, wait=1.5)
    s = until_diagrams(lambda s: not s["drawing"] and s["notice"], timeout=40)
    e.mode(diagrams="pbi")
    e.check("R-18", "No process → no diagram; the page says it needs none", s["count"] in (0, -1) and s["notice"] and not s["error"], f"{s}")


def r_19():
    """Too big an answer is cut to the rules (9 nodes, 2 focal, edges to real nodes only)."""
    e.mode(diagrams="big")
    e.ctl("select", PBI, wait=1); e.ctl("drawdiagrams", PBI, wait=1.5)
    s = until_diagrams(lambda s: not s["drawing"] and s["titles"] == ["Too many"], timeout=40)
    row = e.q("SELECT diagrams FROM meeting_diagrams WHERE meeting_id = ?", PBI)[0][0]
    d = json.loads(row)["diagrams"][0]
    focal = sum(1 for n in d["nodes"] if n["focal"])
    ids = {n["id"] for n in d["nodes"]}
    e.mode(diagrams="pbi")
    e.ctl("drawdiagrams", PBI, wait=1.5); until_diagrams(lambda s: not s["drawing"] and s["count"] == 2, timeout=40)
    e.check("R-19", "An over-budget answer is cut to 9 nodes, 2 focal, edges between kept nodes",
            len(d["nodes"]) == 9 and focal == 2 and all(x["from"] in ids and x["to"] in ids for x in d["edges"]),
            f"nodes {len(d['nodes'])} focal {focal} edges {len(d['edges'])}")


def r_20():
    """Editing the notes keeps the diagrams but marks them as drawn from the earlier notes."""
    e.ctl("select", PBI, wait=1)
    notes = json.loads(e.q("SELECT notes FROM meetings WHERE id = ?", PBI)[0][0])
    summary = notes.get("summary") or []
    notes["summary"] = summary + ["(edited)"] if isinstance(summary, list) else summary + " (edited)"
    e.ctl("editnotes", PBI, json.dumps(notes, ensure_ascii=False), wait=2)
    s = until_diagrams(lambda s: s["stale"], timeout=10)
    e.check("R-20", "After editing the notes, the diagrams stay and say they are from the earlier notes", s["count"] == 2 and s["stale"], f"{s}")


def r_21():
    """PDF, Word and Markdown exports carry the diagrams as pictures after the summary."""
    os.makedirs(OUT, exist_ok=True)
    ok = {}
    for fmt in ("pdf", "docx", "md"):
        path = f"{OUT}/pbi.{fmt}"
        if os.path.exists(path): os.remove(path)
        e.ctl("export", "notes", fmt, path, "1", "1", PBI, wait=0.5)
        ok[fmt] = wait_file(path)
    md = open(f"{OUT}/pbi.md").read() if ok["md"] else ""
    pngs = re.findall(r"!\[[^\]]*\]\(<([^>]+diagram-\d\.png)>\)", md)
    md_files = all(os.path.exists(os.path.join(OUT, p)) for p in pngs) and len(pngs) == 2
    media = []
    if ok["docx"]:
        with zipfile.ZipFile(f"{OUT}/pbi.docx") as z:
            media = [n for n in z.namelist() if n.startswith("word/media/") and n.endswith(".png")]
            body = z.read("word/document.xml").decode()
    pdf = open(f"{OUT}/pbi.pdf", "rb").read() if ok["pdf"] else b""
    pdf_text = subprocess.run(["/usr/bin/strings", f"{OUT}/pbi.pdf"], capture_output=True, text=True).stdout if ok["pdf"] else ""
    no_marker = "SHIYINDIAGRAM" not in md and ok["docx"] and "SHIYINDIAGRAM" not in body and "SHIYINDIAGRAM" not in pdf_text
    summary_first = md.find("Summary") < md.find("Monthly Power BI report refresh") if md else False
    e.check("R-21", "PDF, Word and Markdown exports include both diagrams after the summary",
            pdf.startswith(b"%PDF") and len(media) >= 2 and md_files and no_marker and summary_first and b"/Image" in pdf,
            f"ok {ok}, md pictures {pngs}, docx media {media}, markers gone {no_marker}, order {summary_first}")
    for k in (0, 1):
        e.ctl("diagrampng", PBI, k, f"{OUT}/pbi-diagram-{k}.png", wait=1.5)


CASES = [r_1, r_2, r_3, r_4, r_5, r_6, r_7, r_8, r_9, r_10, r_11, r_12, r_13, r_14, r_15, r_16, r_17, r_18, r_19, r_20, r_21]


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
