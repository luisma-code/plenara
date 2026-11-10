#!/usr/bin/env python3
"""Exclusive production faults, with source restoration even on interruption."""
from pathlib import Path
import json, os, signal, subprocess, sys, time

stopping = False
child = None
def stop(signum, frame):
    global stopping
    stopping = True
for sig in (signal.SIGINT, signal.SIGTERM): signal.signal(sig, stop)

def run(command):
    global child
    child = subprocess.Popen(command, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    while child.poll() is None:
        if stopping:
            os.killpg(child.pid, signal.SIGTERM)
            try: child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL); child.wait()
            raise InterruptedError("Calibration interrupted; source restored")
        time.sleep(.2)
    return child.wait()

mode = sys.argv[1]
faults = {
 "unit": [
  ("Models.swift", "[personID] + (additionalPersonIDs ?? [])", "[personID]"),
  ("JournalStore.swift", "try old.write(to: beforeWorkflowUpdate,", 'try Data("broken recovery".utf8).write(to: beforeWorkflowUpdate,'),
  ("JournalStore.swift", "candidate.people[i].cadence = cadence", "candidate.people[i].cadence = 3"),
  ("JournalStore.swift", "if id != nil { j.pendingContact = nil }", "if id != nil { /* deliberately retain handled draft */ }"),
  ("JournalStore.swift", "j.people[i].notes[n].followUp = followUp;", "j.people[i].notes[n].followUp = nil;"),
 ],
 "picker": [("SocialEvents.swift", '.safeAreaInset(edge: .bottom) {\n                    ActionButton(title: "Done", icon: "checkmark") { dismiss() }.accessibilityIdentifier("event-people-done").padding(16).background(Theme.paper)\n                }', '.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("event-people-done") } }')],
 "handoff": [("PlenaraApp.swift", "offerContact(draft) }\n        }", "/* return offer deliberately disconnected */ }\n        }")],
}
tests = {
 "unit": ["PlenaraTests/WorkflowTests"],
 "picker": ["PlenaraUITests/WorkflowUITests/testAttendeeSearchKeepsDoneReachable"],
 "handoff": ["PlenaraUITests/WorkflowUITests/testHomeReachOutReturnConfirmationAndNoDuplicateOnReopen"],
}
expected = {
 "unit": ["testFiveGuestEventIsOneRecordAndRecomputesEveryHistory", "testBuild1007UpgradeKeepsImportsAndRecoveryBytes", "testRhythmSetupRequiresChoiceAndUndoPreservesOtherEdits", "testHandoffSurvivesReopenAndRequiresExactlyOneConfirmedSave", "testThreadsResolveAndPostponeWithoutChangingMemoryOrConnection"],
 "picker": ["Searching must keep Done reachable"],
 "handoff": ["Returning from a selected route must offer confirmation"],
}
faults["refinements"] = [
    ("WorkflowModels.swift", "date: date, channel: channel", "date: Date(), channel: channel"),
    ("RhythmSetup.swift", "[3, 7, 14, 21, 30, 60, 90, cadence]", "[3, 7, 14, 21, 30, 60, 90]"),
    ("JournalStore.swift", '        guard !changes.isEmpty else { errorMessage = "These people already have this rhythm. Nothing was changed."; return false }\n        guard update({ $0 = candidate }) else { return false }\n        rhythmUndo = RhythmReceipt(changes: changes)', '        guard update({ $0 = candidate }) else { return false }\n        if !changes.isEmpty { rhythmUndo = RhythmReceipt(changes: changes) }'),
] + faults["handoff"]
tests["refinements"] = ["PlenaraTests/WorkflowTests", "PlenaraUITests/WorkflowUITests/testOptionalCustomRhythmSetupPreservesUnknownHistoryAndUndo", "PlenaraUITests/WorkflowUITests/testHomeReachOutReturnConfirmationAndNoDuplicateOnReopen"]
expected["refinements"] = ["testOvernightDraftUsesOriginalDateForEitherConfirmedOutcome", "testUnchangedRhythmDoesNotPretendToReplaceEarlierUndo", "The picker must name a custom rhythm", "Returning from a selected route must offer confirmation"]
faults["geometry"] = [("ReconnectionSection.swift", '.frame(minHeight: 44).accessibilityIdentifier("suggestions-expand")', '.frame(height: 43).accessibilityIdentifier("suggestions-expand")'), ("Theme.swift", "configuration.label.frame(minWidth: 44, minHeight: 44)", "configuration.label.frame(minWidth: 44, minHeight: 43)")]
tests["geometry"] = ["PlenaraUITests/PlenaraUITests/testRankedHomeDarkAndLargeText"]
expected["geometry"] = ["Touch targets must be at least 44 points"]
originals = {}
try:
    for filename, good, bad in faults[mode]:
        p = Path("ios/Plenara") / filename
        if p not in originals: originals[p] = p.read_bytes()
        text = p.read_text(); assert text.count(good) == 1, (filename, good)
        p.write_text(text.replace(good, bad, 1))
    Path(".tmp/native-tests.log").unlink(missing_ok=True)
    code = run(["bash", "tool/test-native.sh"] + ["-only-testing:" + t for t in tests[mode]])
    log = Path(".tmp/native-tests.log").read_text()
    evidence = Path("verification/workflows")
    (evidence / ("red-" + mode + ".log")).write_text(log)
    assert code != 0, "Broken production behavior unexpectedly passed"
    for message in expected[mode]:
        assert any(message in line and ("error:" in line or " failed (" in line) for line in log.splitlines()), "Missing intended failure: " + message
    (evidence / ("calibration-" + mode + ".json")).write_text(json.dumps({"mode": mode, "faults": faults[mode], "rejected": True, "expectedFailures": expected[mode]}, indent=2) + "\n")
finally:
    for p, data in originals.items(): p.write_bytes(data)
    print("Restored all source bytes; rebuild the candidate before delivery.", flush=True)
