#!/usr/bin/env python3
"""End-to-end test fake AI (docs/e2e-test-plan.md). Answers every KelNote job kind, records requests.
POST /__mode {"key": value} switches behaviour:
  stakeholder_thin_first: first stakeholder answer has 1 portrait section, the retry is full
  stakeholder_thin_always: every stakeholder answer has 1 section (an incremental update)
  coaching_variant: "A" (default) or "B" (B leaves out "Restates what you heard")
  speaker_name: {"speaker": 1, "name": "..."}  suggest this speaker name
  delay: seconds before each answer
  diagrams: "pbi" (default, the PBI walkthrough: a swimlane and a flowchart), "none" (no diagram needed), "big" (over budget)
Log: one JSON line per request with kind and the start of the prompt."""
import json, sys, time, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
LOG = sys.argv[1]; PORT = int(sys.argv[2]); MODE = {}; LOCK = threading.Lock(); COUNT = {"stake": 0}

def ev(mid, t="01:00", q="quote"): return [{"meetingId": mid, "time": t, "quote": q}]
def pt(text, mid): return {"text": text, "evidence": ev(mid)}

def notes():
    return {"title": "E2E notes", "summary": [{"text": "E2E summary.", "time": "00:05"}], "decisions": [], "actionItems": [],
            "openQuestions": [], "topics": [{"title": "t", "start": "00:00", "points": [{"text": "p", "time": "00:05"}]}],
            "custom": [], "reviewItems": [], "people": []}

def stakeholder(mid, full):
    portrait = {"mandate": [pt("Owns the area", mid)], "measuredOn": [], "agenda": [], "pressures": [], "personalWin": "",
                "decisionStyle": [], "workingStyle": [], "redLines": [], "trustedVoices": []}
    if full:
        portrait.update({"measuredOn": [pt("Measured on delivery", mid)], "agenda": [pt("Agenda", mid)], "pressures": [pt("Pressure", mid)],
                         "personalWin": "Wants credit", "decisionStyle": [pt("Evidence", mid)], "workingStyle": [pt("Direct", mid)],
                         "redLines": [pt("Vague claims", mid)], "trustedVoices": ["Kelvin"]})
    return {"summary": "E2E stakeholder %d" % COUNT["stake"], "portrait": portrait, "changes": [], "role": "Role", "organization": "Org",
            "power": "high", "powerReason": "r", "interest": "high", "attitude": "supporter", "attitudeTrend": "stable",
            "decisionRole": "influencer", "confidence": "medium", "personality": [pt("p", mid)], "motivations": [pt("m", mid)],
            "needs": ["n"], "topics": [], "readings": [], "commitments": [], "relationships": [],
            "nextMeeting": {"objective": "o", "talkingPoints": [], "questions": [], "avoid": []}, "projects": [],
            "workingWithMe": {"relationship": "r", "trust": "high", "expectations": [], "communication": [], "buildTrust": [],
                              "watchOuts": [], "interactions": []}, "advice": [], "openQuestions": []}

def coaching(mid):
    f = lambda t: {"title": t, "detail": "d", "trend": "same", "kinds": ["client"], "evidence": ev(mid)}
    tp = {"score": 3.0, "trend": "same", "text": "t", "evidence": ev(mid)}
    strengths = ["Restates what you heard", "Keeps follow-ups", "Clear groupings"]
    if MODE.get("coaching_variant") == "B": strengths = ["Brand new A", "Brand new B", "Brand new C"]
    return {"summary": ["E2E coaching " + MODE.get("coaching_variant", "A") + " " + str(time.time())],
            "strengths": [f(t) for t in strengths], "weaknesses": [f("Long briefings"), f("Fillers")],
            "trust": {"credibility": tp, "reliability": tp, "intimacy": tp, "selfOrientation": tp}, "byKind": [],
            "plan": {"focus": "Shorter briefings", "skill": "concision", "kind": "interview", "why": "w",
                     "techniques": ["a", "b", "c"], "goodExample": None}, "changes": ["x"]}

def node(i, label, detail="", shape="step", lane="", focal=False, time="00:00"):
    return {"id": i, "label": label, "detail": detail, "shape": shape, "lane": lane, "focal": focal, "time": time}

def edge(a, b, label="", dashed=False): return {"from": a, "to": b, "label": label, "dashed": dashed}

def diagrams():
    m = MODE.get("diagrams", "pbi")
    if m == "none": return {"diagrams": []}
    if m == "big":
        return {"diagrams": [{"kind": "flowchart", "title": "Too many", "caption": "c",
                              "nodes": [node("n%d" % i, "Step %d" % i, focal=True) for i in range(14)],
                              "edges": [edge("n%d" % i, "n%d" % (i + 1)) for i in range(13)] + [edge("n1", "zz")]}]}
    swim = {"kind": "swimlane", "title": "Monthly Power BI report refresh", "caption": "How the claim reports are produced each month today.",
            "nodes": [node("n1", "Extract claim data", "Claim owners + exposure files", "data", "AMS team", time="18:16"),
                      node("n2", "Upload to SharePoint", "Around the 10th, 5-7 years of data", "step", "AMS team", time="02:32"),
                      node("n3", "Download and rename files", "Sheet names Power BI expects", "step", "Claims analyst", time="10:35"),
                      node("n4", "Run VBA cutoff script", "Removes data after month-end", "step", "Claims analyst", True, "11:43"),
                      node("n5", "Refresh Power BI", "Adds local mapping tables", "system", "Power BI", time="04:40"),
                      node("n6", "Export operational reports", "Zero reserve, recovery, FTE", "step", "Power BI", time="06:46")],
            "edges": [edge("n1", "n2"), edge("n2", "n3", "Monthly"), edge("n3", "n4"), edge("n4", "n5"), edge("n5", "n6")]}
    flow = {"kind": "flowchart", "title": "Parallel run data handling", "caption": "Records from both claim systems are appended during the six-month parallel run.",
            "nodes": [node("a", "Month-end extract", "", "start", time="13:48"),
                      node("b", "Claim in new system?", "", "decision", time="13:48"),
                      node("c", "New system extract", "Same field structure", "data", time="14:21"),
                      node("d", "Smart Claim extract", "Existing file layout", "data", time="14:21"),
                      node("e", "Append at table level", "No report rebuild", "step", focal=True, time="14:44"),
                      node("f", "Refresh Power BI", "", "end", time="14:44")],
            "edges": [edge("a", "b"), edge("b", "c", "Yes"), edge("b", "d", "No"), edge("c", "e"), edge("d", "e"), edge("e", "f")]}
    return {"diagrams": [swim, flow]}

def diagram_suggestions():
    if MODE.get("diagrams") == "none": return {"suggestions": []}
    return {"suggestions": [
        {"kind": "swimlane", "title": "Monthly Power BI report refresh", "why": "Shows who does each step and where the files change hands.",
         "focus": "Topics: current report generation", "time": "02:32"},
        {"kind": "flowchart", "title": "Parallel run data handling", "why": "The branch between the two claim systems is easier to follow as a picture.",
         "focus": "Topics: parallel run", "time": "13:48"}]}

def diagram_draw(prompt):
    d = diagrams()["diagrams"]
    pick = d[1] if ("Parallel run" in prompt and "Monthly Power BI" not in prompt) else d[0]
    if "The user asked for this diagram" in prompt:
        pick = dict(d[0], title="Shing's monthly steps", kind="steps", edges=[])
    pick = json.loads(json.dumps(pick))
    pick["direction"] = "down"
    # step IDs in reading order (the second answer writes them into the label, as some models do)
    k = 0
    for n in pick["nodes"]:
        if n["shape"] in ("step", "decision"):
            k += 1; n["ref"] = str(k)
            if MODE.get("diagram_refs") == "inlabel": n["label"], n["ref"] = f"{k}. {n['label']}", ""
        else: n["ref"] = ""
    if "comments on the diagram" in prompt and "horizontal" in prompt.lower():
        pick["direction"] = "across"
    if MODE.get("diagram_bad_first") and not COUNT.get("bad_sent"):
        COUNT["bad_sent"] = 1
        return {"diagram": {"title": "broken"}}
    if "comments on the diagram" in prompt and "only draw" in prompt.lower():
        # the comment asks for the current behaviour only: drop the last step, mark it in the title
        pick["nodes"] = pick["nodes"][:-1]
        pick["edges"] = [e for e in pick["edges"] if e["to"] in {n["id"] for n in pick["nodes"]}]
        pick["title"] = pick["title"] + " (current)"
    return {"diagram": pick}

def workshop_draft():
    d = {"kind": "swimlane", "title": "Monthly claims report", "caption": "How the monthly claims report is produced.", "direction": "down",
         "nodes": [node("s1", "Start of month", "", "start"), node("s2", "Extract claim data", "", "step", "AMS team"),
                   node("s3", "Upload files to SharePoint", "", "step", "AMS team"), node("s4", "Rename downloaded files", "", "step", "Claims analyst"),
                   node("s5", "Run cutoff script", "", "step", "Claims analyst"), node("s6", "Refresh Power BI", "", "step", "Claims analyst"),
                   node("s7", "Report issued", "", "end", "Claims analyst")],
         "edges": [edge("s1", "s2"), edge("s2", "s3"), edge("s3", "s4"), edge("s4", "s5"), edge("s5", "s6"), edge("s6", "s7")]}
    k = 0
    for n in d["nodes"]:
        if n["shape"] == "step": k += 1; n["ref"] = str(k)
        else: n["ref"] = ""
    return {"diagram": d}

def workshop_analysis(prompt):
    import re
    def e(speaker, time, quote): return [{"speaker": speaker, "time": time, "quote": quote}]
    nodes = re.findall(r"^- node (\S+) \| ref (\S+) \| (\w+) \| (.*?)(?: \| lane:.*)?$", prompt, re.M)
    steps = []
    steps_nodes = [n for n in nodes if n[2] in ("step", "decision")]
    verdicts = ["confirmed", "changed", "notDone", "disputed", "unclear", "confirmed"]
    for i, (nid, ref, shape, label) in enumerate(steps_nodes):
        v = verdicts[i % len(verdicts)]
        if MODE.get("workshop") == "noevidence": ev = []
        elif v == "unclear" and i == 4: ev = []
        else: ev = e("Shing", "0%d:%02d" % (i, 10), "We do it like this at step %d" % (i + 1))
        steps.append({"nodeId": nid, "ref": ref, "verdict": v, "note": "Client said: " + v if ev else "", "newLabel": "Check and rename downloaded files" if v == "changed" else "",
                      "newLane": "", "afterRef": "", "evidence": ev})
    if steps_nodes:
        steps.append({"nodeId": "", "ref": "", "verdict": "added", "note": "A reviewer signs off before the report goes out", "newLabel": "Approve report before release",
                      "newLane": "Claims analyst", "afterRef": steps_nodes[min(3, len(steps_nodes) - 1)][1], "evidence": e("Ming", "05:10", "Someone from finance has to approve it first")})
    questions = []
    for i, (qid, text) in enumerate(re.findall(r"^- (QST-\d+): (.*?)(?: \(about step.*)?$", prompt, re.M)):
        state = ["answered", "partial", "notCovered"][min(i, 2)]
        questions.append({"qid": qid, "text": text, "stepRef": "", "state": state, "answer": "About the 10th of the month" if state != "notCovered" else "",
                          "raisedInRoom": False, "owner": "", "due": "", "evidence": e("Shing", "03:%02d" % (i * 10), "Around the tenth") if state != "notCovered" else []})
    questions.append({"qid": "", "text": "Who approves late files?", "stepRef": "", "state": "notCovered", "answer": "", "raisedInRoom": True,
                      "owner": "Ming", "due": "2026-12-05", "evidence": e("Kelvin", "07:00", "Who signs off when the files are late?")})
    walk = [
        {"ref": "1", "label": "Receive claim files", "actor": "Claims analyst", "systems": "Email, SharePoint", "timing": "10th of each month", "branchFrom": "", "frequency": "", "handoffNeeds": "File names as agreed", "draftNodeId": "", "evidence": e("Shing", "02:00", "I get them around the tenth")},
        {"ref": "2", "label": "Rename downloaded files", "actor": "Claims analyst", "systems": "Excel", "timing": "30 minutes", "branchFrom": "", "frequency": "", "handoffNeeds": "", "draftNodeId": "", "evidence": e("Shing", "03:00", "I rename them by hand")},
        {"ref": "2a", "label": "Chase late files", "actor": "Claims analyst", "systems": "", "timing": "", "branchFrom": "1", "frequency": "about 1 in 10", "handoffNeeds": "", "draftNodeId": "", "evidence": e("Shing", "04:00", "About one month in ten they are late")},
        {"ref": "3", "label": "Refresh Power BI", "actor": "Claims analyst", "systems": "Power BI", "timing": "1 hour", "branchFrom": "", "frequency": "", "handoffNeeds": "", "draftNodeId": "", "evidence": e("Shing", "06:00", "Then I refresh the report")}]
    if MODE.get("workshop") == "noevidence": walk[0]["evidence"] = []
    pains = [{"text": "Renaming files by hand causes mistakes", "stepRef": "2", "workaround": "A side spreadsheet that lists the sheet names Power BI expects", "impact": "2 hours a month", "evidence": e("Shing", "03:30", "I keep a spreadsheet of the names")},
             {"text": "Nobody knows who owns late files", "stepRef": "1", "workaround": "", "impact": "", "evidence": []}]
    reqs = [{"text": "Check file names automatically on upload", "kind": "functional", "priority": "", "stepRef": "2", "fromPainIndex": 0, "evidence": e("Shing", "03:30", "I keep a spreadsheet of the names")},
            {"text": "Report refresh must finish within an hour", "kind": "nonFunctional", "priority": "must have", "stepRef": "3", "fromPainIndex": -1, "evidence": e("Ming", "08:00", "It must be done within the hour, that is a must")}]
    rules = [{"text": "Files after month-end are excluded", "isAuthority": False, "stepRef": "", "evidence": e("Shing", "09:00", "Anything after month end is cut off")},
             {"text": "Only the finance manager can approve the release", "isAuthority": True, "stepRef": "", "evidence": e("Ming", "05:20", "Only the finance manager approves")}]
    raid = [{"kind": "decision", "text": "Use SharePoint as the single drop location", "decidedBy": "Ming", "owner": "", "due": "", "evidence": e("Ming", "10:00", "Let's use SharePoint only")},
            {"kind": "decision", "text": "Move reporting to monthly week 2", "decidedBy": "", "owner": "", "due": "", "evidence": e("Shing", "10:30", "Maybe we could move it")},
            {"kind": "conflict", "text": "Shing says files arrive on the 10th; Ming says the 5th", "decidedBy": "", "owner": "", "due": "", "evidence": e("Ming", "02:10", "No, the fifth")},
            {"kind": "risk", "text": "Late files delay the board pack", "decidedBy": "", "owner": "Ming", "due": "", "evidence": e("Ming", "11:00", "The board pack slips if files are late")}]
    note = lambda t, d="": {"text": t, "detail": d, "evidence": e("Ming", "12:00", t)}
    return {"steps": steps if MODE.get("workshop") != "nodraft" else [], "questions": questions, "walkthrough": walk, "pains": pains, "requirements": reqs,
            "rules": rules, "raid": raid, "parking": [note("Archive old reports")], "outOfScope": [note("Claims system replacement")],
            "glossary": [note("AMS", "The claims administration system")],
            "readBack": {"done": True, "result": "agreed", "time": "13:00", "quote": "Yes, that is how it works"}}

def first_meeting(prompt):
    import re
    m = re.search(r"[Mm]eeting (\d+)", prompt)
    return int(m.group(1)) if m else 1

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, obj):
        data = json.dumps(obj).encode()
        self.send_response(200); self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))) or b"{}")
        if self.path == "/__mode":
            MODE.clear(); MODE.update(body); COUNT.pop("bad_sent", None); return self.reply(MODE)
        system = body["messages"][0]["content"]; prompt = body["messages"][-1]["content"]
        schema = json.dumps(body.get("response_format", {}))
        mid = first_meeting(prompt)
        if prompt.startswith("Target person:") or '"portrait"' in schema:
            with LOCK:
                COUNT["stake"] += 1
                retry = "IMPORTANT: Return the COMPLETE" in prompt
                full = not MODE.get("stakeholder_thin_always") and (retry or not MODE.get("stakeholder_thin_first"))
            kind, out = "stakeholder" + ("-retry" if retry else ""), stakeholder(mid, full)
        elif "executive coach" in system or prompt.startswith("The user:"): kind, out = "coaching", coaching(mid)
        elif '"readBack"' in schema: kind, out = "workshop-analysis", workshop_analysis(prompt)
        elif prompt.startswith("Process description"): kind, out = "workshop-draft", workshop_draft()
        elif '"suggestions"' in schema: kind, out = "diagram-suggest", diagram_suggestions()
        elif '"diagram"' in schema: kind, out = "diagram-draw", diagram_draw(prompt)
        elif '"speakerNames"' in schema:
            s = MODE.get("speaker_name"); kind = "speakerNames"
            out = {"speakerNames": [dict(s, reason="said so", time="00:01")] if s else []}
        elif '"corrections"' in schema: kind, out = "corrections", {"corrections": []}
        elif '"lines"' in schema: kind, out = "clean", {"lines": []}
        elif '"keywords"' in schema: kind, out = "keywords", {"keywords": ["e2e"]}
        elif '"citations"' in schema: kind, out = "answer", {"answer": "a", "found": True, "citations": []}
        else: kind, out = "notes", notes()
        with open(LOG, "a") as f: f.write(json.dumps({"kind": kind, "model": body.get("model", ""), "system": system[:6000], "schema": schema[:4000], "prompt": prompt[:4000], "tail": prompt[-3000:]}, ensure_ascii=False) + "\n")
        if MODE.get("delay"): time.sleep(float(MODE["delay"]))
        self.reply({"choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": json.dumps(out, ensure_ascii=False)}}]})

ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
