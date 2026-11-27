#!/usr/bin/env python3
"""KelNote end-to-end tests (docs/e2e-test-plan.md). Runs the debug build on a COPY of the live data with a fake AI.

  python3 scripts/dev/e2e/run.py [case-id …]

Never writes to the live database: it is only read (sqlite3 -readonly .backup) and checksummed before and after.
Each check reads what the screen holds right now (debug `screen`), without forcing a reload, so a screen that only
updates after a click fails the case."""
import hashlib, json, os, shutil, sqlite3, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
LIVE = os.path.expanduser("~/Library/Application Support/Shiyin/shiyin.sqlite")
HOME = "/tmp/kn-e2e"
APP = os.path.expanduser("~/Library/Caches/ShiyinBuild/app/Shiyin.app/Contents/MacOS/Shiyin")
CTL = os.path.expanduser("~/Library/Caches/ShiyinBuild/shiyinctl")
PORT = 18790
AILOG = HOME + "/ai.jsonl"
RESULTS = []
EXTRA_ARGS = []   # more launch arguments (regression.py sets a separate stakeholder model)


def sh(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


def ctl(*args, wait=0.6):
    sh(CTL, *[str(a) for a in args])
    time.sleep(wait)


def screen():
    path = HOME + "/screen.json"
    if os.path.exists(path): os.remove(path)
    ctl("screen", path, wait=0.4)
    for _ in range(20):
        if os.path.exists(path):
            try: return json.load(open(path))
            except ValueError: pass
        time.sleep(0.2)
    raise RuntimeError("debug app did not answer `screen`")


def until(cond, timeout=40, every=1.0):
    """Wait for the screen to satisfy cond (the app updates by itself); returns the last screen."""
    end = time.time() + timeout
    s = screen()
    while time.time() < end:
        if cond(s): return s
        time.sleep(every)
        s = screen()
    return s


def db():
    return sqlite3.connect(f"file:{HOME}/shiyin.sqlite?mode=ro", uri=True)


def q(sql, *args):
    with db() as c: return c.execute(sql, args).fetchall()


def ai_calls(kind=None):
    if not os.path.exists(AILOG): return []
    rows = [json.loads(l) for l in open(AILOG) if l.strip()]
    return [r for r in rows if kind is None or r["kind"].startswith(kind)]


def mode(**kw):
    import urllib.request
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/__mode", data=json.dumps(kw).encode(), method="POST")
    urllib.request.urlopen(req).read()


def check(case, title, ok, detail=""):
    RESULTS.append((case, title, bool(ok), detail))
    print(f"{'PASS' if ok else 'FAIL'}  {case}  {title}" + ("" if ok else f"\n      → {detail}"), flush=True)


def checksum(path):
    h = hashlib.sha256()
    tmp = "/tmp/kn-e2e-live-check.sqlite"
    sh("sqlite3", "-readonly", path, f".backup {tmp}")
    with sqlite3.connect(tmp) as c:
        for table in ("people", "speakers", "meetings", "stakeholder_profiles", "coaching", "jobs"):
            for row in c.execute(f"SELECT * FROM {table} ORDER BY 1"):
                h.update(repr(row).encode())
    os.remove(tmp)
    return h.hexdigest()


def start():
    stop()
    shutil.rmtree(HOME, ignore_errors=True); os.makedirs(HOME)
    sh("sqlite3", "-readonly", LIVE, f".backup {HOME}/shiyin.sqlite")
    # The copy must not inherit queued work from the live app
    with sqlite3.connect(HOME + "/shiyin.sqlite") as c:
        c.execute("UPDATE jobs SET status = 'done' WHERE status IN ('queued', 'running')")
        c.execute("UPDATE coaching SET useful = '[]', rejected = '[]'")   # start from no marks (copy only)
    global FAKE, PROC
    FAKE = subprocess.Popen([sys.executable, "-I", HERE + "/fake_ai.py", AILOG, str(PORT)])
    launch()


def launch():
    global PROC
    env = dict(os.environ, SHIYIN_HOME=HOME)
    PROC = subprocess.Popen([APP, "-autoSummarize", "NO", "-stakeholderAnalysis", "YES", "-AppleLanguages", "(en)",
                             "-recordingIsland", "NO", *EXTRA_ARGS], env=env, stdout=open(HOME + "/app.log", "w"), stderr=subprocess.STDOUT)
    time.sleep(7)
    ctl("llmurl", "openaiCompatible", f"http://127.0.0.1:{PORT}/v1")
    ctl("setkey", "openaiCompatible", "fake")
    ctl("settle", "0")


def restart():
    PROC.terminate(); PROC.wait(10); time.sleep(1); launch()


def stop():
    sh("pkill", "-f", "ShiyinBuild/app/Shiyin.app/Contents/MacOS/Shiyin")
    sh("pkill", "-f", "e2e/fake_ai.py")
    time.sleep(1)


def me_id():
    return screen()["myIds"][0]


def meeting_with(person, exclude_me=True):
    rows = q("SELECT s.meeting_id FROM speakers s JOIN meetings m ON m.id = s.meeting_id "
             "WHERE s.person_id = ? AND m.deleted_at IS NULL ORDER BY m.meeting_date DESC, m.id DESC LIMIT 1", person)
    return rows[0][0]


def other_person():
    me = me_id()
    rows = q("SELECT person_id, count(*) n FROM speakers WHERE person_id IS NOT NULL AND person_id != ? "
             "GROUP BY person_id ORDER BY n DESC LIMIT 1", me)
    return rows[0][0]


def free_speaker(meeting):
    """A speaker in this meeting not linked to anyone (or any speaker but me)."""
    me = me_id()
    rows = q("SELECT idx, person_id FROM speakers WHERE meeting_id = ? ORDER BY person_id IS NOT NULL, idx", meeting)
    for idx, pid in rows:
        if pid != me: return idx
    return rows[0][0]


# ---------------- cases ----------------

def tc_1_1():
    s = screen()
    n = q("SELECT count(*) FROM people")[0][0]
    check("TC-1.1", "People lists every person", len(s["people"]) == n and len(s["myIds"]) == 1,
          f"screen {len(s['people'])}, db {n}, first {s['people'][0] if s['people'] else None}")


def tc_1_2():
    m = q("SELECT id FROM meetings WHERE deleted_at IS NULL ORDER BY id DESC LIMIT 1")[0][0]
    idx = free_speaker(m)
    ctl("select", m, wait=1.5)
    ctl("speaker", m, idx, "Quinn Newperson", wait=1.5)
    s = until(lambda s: any(p["name"] == "Quinn Newperson" for p in s["people"]), timeout=6)
    check("TC-1.2", "Renamed speaker appears in People without a click",
          any(p["name"] == "Quinn Newperson" for p in s["people"]), f"people: {[p['name'] for p in s['people']][:40]}")


def tc_1_3():
    pid = next((p["id"] for p in screen()["people"] if p["name"] == "Quinn Newperson"), None)
    if pid is None: return check("TC-1.3", "Rename a person from People", False, "TC-1.2 person missing")
    ctl("renameperson", pid, "Quinn Renamed", wait=1.5)
    s = screen()
    on_page = any("Quinn Renamed" in x for x in s["speakers"])
    check("TC-1.3", "Renamed person shows in People and on the open meeting",
          any(p["name"] == "Quinn Renamed" for p in s["people"]) and on_page, f"speakers on page {s['speakers']}")


def tc_2_1():
    # (a) What voiceprint matching does during transcription: the database links a speaker to a person in the background.
    #     Done here straight on the COPY's database, then a background job finishes; People must show it with no click.
    m = q("SELECT id FROM meetings WHERE deleted_at IS NULL ORDER BY id DESC LIMIT 1 OFFSET 1")[0][0]
    idx = free_speaker(m)
    ctl("peoplemode"); ctl("openperson", me_id(), wait=1)
    with sqlite3.connect(HOME + "/shiyin.sqlite") as c:
        c.execute("INSERT INTO people (name, created_at) VALUES ('Rowan Background', '2026-11-26T00:00:00Z')")
        pid = c.execute("SELECT id FROM people WHERE name = 'Rowan Background'").fetchone()[0]
        c.execute("UPDATE speakers SET name = 'Rowan Background', name_source = 'voiceprint', person_id = ? WHERE meeting_id = ? AND idx = ?",
                  (pid, m, idx))
    ctl("stakeholdermeeting", m, wait=0.5)
    s = until(lambda s: any(p["name"] == "Rowan Background" and p["meetings"] >= 1 for p in s["people"]), timeout=40)
    check("TC-2.1a", "A person a background job links shows in People when the job ends",
          any(p["name"] == "Rowan Background" and p["meetings"] >= 1 for p in s["people"]),
          f"queued {s['queued']}, people {[p['name'] for p in s['people']]}")
    # (b) Speaker naming suggests a name; accepting the suggestion makes the person show up with no click.
    m2, idx2 = q("SELECT s.meeting_id, s.idx FROM speakers s JOIN meetings m ON m.id = s.meeting_id "
                 "WHERE s.name_source = 'default' AND m.deleted_at IS NULL ORDER BY m.id DESC LIMIT 1")[0]
    mode(speaker_name={"speaker": idx2, "name": "Sage Suggested"})
    ctl("namespeakers", m2, wait=0.5)
    until(lambda s: s["queued"] == 0, timeout=30)
    mode()
    suggested = q("SELECT suggested_name FROM speakers WHERE meeting_id = ? AND idx = ?", m2, idx2)
    ctl("select", m2, wait=1.5)
    ctl("applysuggestion", m2, idx2, wait=1.5)
    s = until(lambda s: any(p["name"] == "Sage Suggested" for p in s["people"]), timeout=6)
    check("TC-2.1b", "Accepting a suggested speaker name shows the person in People with no click",
          any(p["name"] == "Sage Suggested" for p in s["people"]), f"suggestion in db {suggested}")


def tc_2_2():
    me = me_id()
    ctl("peoplemode"); ctl("openperson", me, wait=2); ctl("coachingtab", "overview")
    before = screen()
    m = meeting_with(me)
    ctl("resummarize", m, wait=1)
    s = until(lambda s: s["coachingUpdated"] != before["coachingUpdated"] and not s["coachingRunning"], timeout=60)
    ran = len(ai_calls("coaching"))
    check("TC-2.2", "My coaching refreshes itself after a meeting's notes finish (page open)",
          s["coachingUpdated"] != before["coachingUpdated"] and not s["coachingRunning"],
          f"updated {before['coachingUpdated']} → {s['coachingUpdated']}, running {s['coachingRunning']}, coaching AI calls {ran}")


def tc_2_3():
    pid = other_person()
    ctl("peoplemode"); ctl("openperson", pid, wait=2)
    before = screen()
    ctl("stakeholdermeeting", meeting_with(pid), wait=0.5)
    s = until(lambda s: s["stakeholderUpdated"] != before["stakeholderUpdated"] and s["queued"] == 0, timeout=40)
    check("TC-2.3", "An automatic stakeholder update shows on the open person page",
          s["stakeholderPerson"] == pid and s["stakeholderUpdated"] != before["stakeholderUpdated"],
          f"person {s['stakeholderPerson']} updated {before['stakeholderUpdated']} → {s['stakeholderUpdated']}")


def tc_2_4():
    pid = other_person()
    mode(delay=6)
    ctl("peoplemode"); ctl("openperson", pid, wait=1.5)
    before = screen()
    ctl("stakeholder", pid, wait=1)
    ctl("openperson", me_id(), wait=1.5); ctl("openperson", pid, wait=1.5)
    mid = screen()
    s = until(lambda s: s["stakeholderUpdated"] != before["stakeholderUpdated"] and pid not in s["analyzing"], timeout=40)
    mode()
    check("TC-2.4", "Analyze keeps showing 'Analyzing…' after leaving and coming back, then shows the result",
          pid in mid["analyzing"] and s["stakeholderUpdated"] != before["stakeholderUpdated"] and pid not in s["analyzing"],
          f"while running analyzing={mid['analyzing']}, after updated={s['stakeholderUpdated'] != before['stakeholderUpdated']}, analyzing={s['analyzing']}")


def tc_2_5():
    me = me_id()
    mode(delay=6)
    ctl("peoplemode"); ctl("openperson", me, wait=1.5)
    before = screen()
    ctl("coachingrefresh", me, wait=1)
    ctl("openperson", other_person(), wait=1.5); ctl("openperson", me, wait=1.5)
    mid = screen()
    s = until(lambda s: s["coachingUpdated"] != before["coachingUpdated"] and not s["coachingRunning"], timeout=40)
    mode()
    check("TC-2.5", "Coaching Refresh keeps showing 'Updating…' after leaving and coming back, then shows the result",
          mid["coachingRunning"] and s["coachingUpdated"] != before["coachingUpdated"] and not s["coachingRunning"],
          f"while running running={mid['coachingRunning']}, after running={s['coachingRunning']}")


USEFUL = {}


def tc_3_1():
    me = me_id()
    ctl("peoplemode"); ctl("openperson", me, wait=1.5)
    USEFUL["title"] = screen()["strengths"][0]
    ctl("peoplemode"); ctl("openperson", me, wait=1.5); ctl("coachingtab", "findings")
    ctl("coachinguseful", me, USEFUL["title"], wait=1)
    ctl("coachingtab", "trends"); ctl("openperson", other_person(), wait=1.5); ctl("openperson", me, wait=1.5); ctl("coachingtab", "findings")
    s = screen()
    check("TC-3.1", "Useful stays marked after leaving and coming back", USEFUL["title"] in s["useful"], f"useful {s['useful']}")


def tc_3_2():
    me = me_id()
    mode(coaching_variant="B")
    before = screen()
    ctl("coachingrefresh", me, wait=1)
    s = until(lambda s: s["coachingUpdated"] != before["coachingUpdated"] and not s["coachingRunning"], timeout=40)
    mode()
    prompt = ai_calls("coaching")[-1]["prompt"] if ai_calls("coaching") else ""
    check("TC-3.2", "A useful point the AI leaves out is kept; the AI is told about it",
          USEFUL["title"] in s["strengths"] and "Brand new A" in s["strengths"] and "marked as useful" in prompt,
          f"strengths {s['strengths']}")


def tc_3_3():
    me = me_id()
    ctl("coachinguseful", me, USEFUL["title"], wait=1)
    s = screen()
    check("TC-3.3", "Clicking Useful again removes the mark", USEFUL["title"] not in s["useful"], f"useful {s['useful']}")


def tc_3_4():
    me = me_id()
    target = "Long briefings"
    ctl("coachingreject", me, target, wait=1)
    s1 = screen()
    before = s1["coachingUpdated"]
    ctl("coachingrefresh", me, wait=1)
    s = until(lambda s: s["coachingUpdated"] != before and not s["coachingRunning"], timeout=40)
    prompt = ai_calls("coaching")[-1]["prompt"]
    check("TC-3.4", "Not right removes the point, it stays gone after Refresh, the AI is told",
          target not in s1["weaknesses"] and target not in s["weaknesses"] and "marked as wrong" in prompt and target in prompt,
          f"after reject {s1['weaknesses']}, after refresh {s['weaknesses']}")


def tc_3_5():
    me = me_id()
    ctl("peoplemode"); ctl("openperson", me, wait=1.5); ctl("coachingtab", "findings")
    m = meeting_with(me)
    ctl("personcite", m, "01:00", wait=2)
    s = screen()
    ctl("peoplemode"); ctl("openperson", me, wait=1.5)
    back = screen()
    check("TC-3.5", "A quote opens its meeting; going back keeps the tab",
          s["mode"] == "meetings" and s["selection"] == m and back["coachingTab"] == "findings",
          f"after click mode={s['mode']} selection={s['selection']} (want {m}); back tab={back['coachingTab']}")


def tc_3_6():
    me = me_id()
    ctl("coachinguseful", me, "Brand new A", wait=1)
    before = screen()
    restart()
    ctl("peoplemode"); ctl("openperson", me, wait=2)
    s = screen()
    check("TC-3.6", "After restarting, Useful marks and coaching are still there",
          "Brand new A" in s["useful"] and s["coachingUpdated"] == before["coachingUpdated"] and s["coachingMeetings"] == before["coachingMeetings"],
          f"useful {s['useful']}, updated {before['coachingUpdated']} vs {s['coachingUpdated']}")


def tc_4_1():
    pid = other_person()
    mode(stakeholder_thin_first=True)
    n0 = len(ai_calls("stakeholder"))
    ctl("peoplemode"); ctl("openperson", pid, wait=1.5)
    before = screen()
    ctl("stakeholder", pid, wait=1)
    s = until(lambda s: s["stakeholderUpdated"] != before["stakeholderUpdated"] and pid not in s["analyzing"], timeout=40)
    mode()
    calls = [c["kind"] for c in ai_calls("stakeholder")[n0:]]
    check("TC-4.1", "A thin portrait is asked for again and the fuller one kept",
          "stakeholder-retry" in calls and s["portraitFilled"] >= 7, f"calls {calls}, filled {s['portraitFilled']}")


def tc_4_2():
    pid = other_person()
    mode(stakeholder_thin_always=True)
    before = screen()
    ctl("stakeholdermeeting", meeting_with(pid), wait=0.5)
    s = until(lambda s: s["stakeholderUpdated"] != before["stakeholderUpdated"] and s["queued"] == 0, timeout=40)
    mode()
    check("TC-4.2", "An automatic update that leaves sections out keeps the earlier ones",
          s["stakeholderUpdated"] != before["stakeholderUpdated"] and s["portraitFilled"] >= before["portraitFilled"],
          f"filled {before['portraitFilled']} → {s['portraitFilled']}")


def tc_4_3():
    pid = other_person()
    ctl("peoplemode"); ctl("openperson", pid, wait=1.5)
    path = HOME + "/other.png"
    ctl("snapshot", path, "light", "person", wait=4)
    s = screen()
    # The person page for someone else must load a stakeholder record and not the coaching tabs
    check("TC-4.3", "Other people still get the stakeholder page", s["stakeholderPerson"] == pid and os.path.exists(path),
          f"stakeholderPerson {s['stakeholderPerson']} (want {pid})")


CASES = [tc_1_1, tc_1_2, tc_1_3, tc_2_1, tc_2_2, tc_2_3, tc_2_4, tc_2_5, tc_3_1, tc_3_2, tc_3_3, tc_3_4, tc_3_5, tc_3_6,
         tc_4_1, tc_4_2, tc_4_3]


def main():
    want = set(sys.argv[1:])
    live_before = checksum(LIVE)
    start()
    ctl("peoplemode")
    try:
        for case in CASES:
            cid = case.__name__.replace("tc_", "TC-").replace("_", ".")
            if want and not any(w.startswith(cid) or cid.startswith(w) for w in want): continue
            try: case()
            except Exception as e: check(cid, case.__name__, False, f"error: {e!r}")
    finally:
        stop()
    live_after = checksum(LIVE)
    check("TC-5.1", "Live database unchanged by the run", live_before == live_after, "checksum differs")
    failed = [r for r in RESULTS if not r[2]]
    print(f"\n{len(RESULTS) - len(failed)} passed, {len(failed)} failed")
    json.dump([{"id": c, "title": t, "pass": ok, "detail": d} for c, t, ok, d in RESULTS], open(HOME + "-results.json", "w"), indent=1)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
