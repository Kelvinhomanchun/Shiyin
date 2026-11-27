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
            MODE.clear(); MODE.update(body); return self.reply(MODE)
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
        elif '"diagrams"' in schema: kind, out = "diagrams", diagrams()
        elif '"speakerNames"' in schema:
            s = MODE.get("speaker_name"); kind = "speakerNames"
            out = {"speakerNames": [dict(s, reason="said so", time="00:01")] if s else []}
        elif '"corrections"' in schema: kind, out = "corrections", {"corrections": []}
        elif '"lines"' in schema: kind, out = "clean", {"lines": []}
        elif '"keywords"' in schema: kind, out = "keywords", {"keywords": ["e2e"]}
        elif '"citations"' in schema: kind, out = "answer", {"answer": "a", "found": True, "citations": []}
        else: kind, out = "notes", notes()
        with open(LOG, "a") as f: f.write(json.dumps({"kind": kind, "model": body.get("model", ""), "system": system[:300], "prompt": prompt[:4000]}, ensure_ascii=False) + "\n")
        if MODE.get("delay"): time.sleep(float(MODE["delay"]))
        self.reply({"choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": json.dumps(out, ensure_ascii=False)}}]})

ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
