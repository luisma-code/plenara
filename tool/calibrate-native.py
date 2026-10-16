#!/usr/bin/env python3
"""Exclusive broken-candidate control. Restores sources even when the run fails.
Never run alongside a build, install, or another verification job.
"""
from pathlib import Path
import subprocess,re,json
paths=[Path('ios/Plenara')/p for p in ['Models.swift','JournalStore.swift','ContactsImport.swift','PlenaraApp.swift','Notifications.swift']]
original={p:p.read_bytes() for p in paths}

def replace(name,before,after,count=1):
 p=Path('ios/Plenara')/name;s=p.read_text();assert before in s,(name,before);p.write_text(s.replace(before,after,count))

try:
 replace('JournalStore.swift','e.dateEncodingStrategy = .deferredToDate','e.dateEncodingStrategy = .iso8601')
 replace('JournalStore.swift','d.dateDecodingStrategy = .deferredToDate','d.dateDecodingStrategy = .iso8601')
 replace('JournalStore.swift','if FileManager.default.fileExists(atPath: self.file.path) {','if false {')
 replace('JournalStore.swift','    @discardableResult private func persist(_ input: Journal) -> Bool {','    @discardableResult private func persist(_ input: Journal) -> Bool {\n        journal = input')
 replace('Models.swift',' && $0.connected','')
 replace('Models.swift','var reminders: [DatedReminder] = []','if true { return [] }; var reminders: [DatedReminder] = []')
 replace('Models.swift','max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0)','0')
 replace('Models.swift','guard p.cadence > 0, !p.paused,','guard false, p.cadence > 0, !p.paused,')
 replace('Notifications.swift','guard p.notifications else { return [] }','// BROKEN CONTROL: ignore notification opt-in')
 replace('Notifications.swift','try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))','_ = trigger // BROKEN CONTROL: skip the OS scheduling call')
 replace('PlenaraApp.swift','            .navigationDestination(for: UUID.self) { PersonDetail(id: $0) }\n        }\n        .safeAreaInset','            .navigationDestination(for: UUID.self) { PersonDetail(id: $0) }\n        .safeAreaInset')
 replace('PlenaraApp.swift','        .sheet(isPresented: $settings)','        }\n        .sheet(isPresented: $settings)')
 replace('ContactsImport.swift','let existingID = forceNew ? nil : (id ?? existing(c, in: journal.people)?.id)','let existingID: UUID? = nil')
 # Reproduce the former direct bridge: native dismissal plus binding dismissal
 # tears down the import review. The host in the restored source owns this boundary.
 p=Path('ios/Plenara/ContactsImport.swift');s=p.read_text();a=s.index('struct ContactPicker:');b=s.index('\nenum ContactImport',a)
 broken='''struct ContactPicker: UIViewControllerRepresentable {
    var selected: ([Person]) -> Void
    var cancelled: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected, cancelled: cancelled) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController(); vc.delegate = context.coordinator; return vc
    }
    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) { }
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let selected: ([Person]) -> Void
        let cancelled: () -> Void
        init(selected: @escaping ([Person]) -> Void, cancelled: @escaping () -> Void) { self.selected = selected; self.cancelled = cancelled }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { cancelled() }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) { selected(contacts.map(ContactImport.person)) }
    }
}
'''
 p.write_text(s[:a]+broken+s[b:])
 run=subprocess.run(['bash','tool/test-native.sh'],text=True,capture_output=True)
 log=Path('.tmp/native-tests.log').read_text() if Path('.tmp/native-tests.log').exists() else ''
 Path('.tmp/native-broken-control.log').write_text(log)
 expected=json.loads(Path('verification/native-calibration.json').read_text())['failedTests']
 failed=set(re.findall(r"Test Case '-\[[^ ]+ (test\w+)\]' failed",log))
 assert run.returncode != 0, 'Known-broken candidate unexpectedly passed'
 missing=set(expected)-failed
 assert not missing, 'Checks did not reject the broken candidate: '+', '.join(sorted(missing))+'\n'+run.stdout+run.stderr
 result={'brokenCandidateRejected':True,'failedTests':sorted(failed),'sourceRestoredAfterRun':True}
 Path('.tmp/native-calibration.json').write_text(json.dumps(result,indent=2)+'\n')
 print('All '+str(len(failed))+' native checks rejected the known-broken candidate.')
finally:
 for p,content in original.items():p.write_bytes(content)
 print('Restored original native sources. Rebuild before delivery.')
