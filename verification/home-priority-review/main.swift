import Foundation
var c = Calendar(identifier: .gregorian)
c.timeZone = TimeZone(secondsFromGMT: 0)!
let now = c.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12))!
func ago(_ days: Int) -> Date { c.date(byAdding: .day, value: -days, to: now)! }
func person(_ name: String, _ closeness: String, _ direction: String, _ connection: String) -> Person {
    var p = Person()
    p.name = name; p.closeness = closeness; p.directionChoice = direction; p.connectionKinds = [connection]
    return p
}
var a = person("Aaron", "Casual", "Grow closer", "Friend")
var z = person("Zoe", "Inner circle", "Grow closer", "Friend")
var m = person("Mei", "Close", "Keep it steady", "Family")
var j = Journal()
func check(_ label: String, _ expected: [String], _ growth: String?, _ date: Date = now) {
    let ranked = j.rankedSuggestions(now: date, calendar: c)
    let context = j.contextualSuggestions(excluding: Set(ranked.prefix(3).map(\.id)), ranked: ranked, now: date, calendar: c)
    let names = ranked.map(\.name)
    precondition(names == expected && context.growth?.name == growth)
    print(label, names, context.growth?.name ?? "nil", separator: " | ")
}
j.people = [z,m,a]
check("zero history", [], "Aaron")
check("zero history +7d", [], "Aaron", ago(-7))
j.moments = [Moment(personID: a.id, date: now)]
check("connected Aaron today", [], "Aaron")
j.moments = [Moment(personID: a.id, date: now, connected: false)]
check("outreach Aaron today", [], "Zoe")
j.moments = []
a.cadence = 7; a.reminderStart = ago(21)
m.cadence = 30; m.baselineConnection = ago(31)
j.people = [z,m,a]
precondition(j.lastConnection(a) == nil)
check("Aaron setup 21/7 and close family known 31/30", ["Aaron","Mei"], "Zoe")
z.cadence = 7; z.baselineConnection = ago(7)
j.people = [z,m,a]
check("add due inner-circle", ["Zoe","Aaron","Mei"], nil)
