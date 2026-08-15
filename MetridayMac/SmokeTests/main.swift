import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let date = Date(timeIntervalSince1970: 1_786_729_600)
let seeded = MarkdownCodec.seed(for: date)
let markdown = MarkdownCodec.serialize(seeded)
let parsed = MarkdownCodec.parse(markdown, date: date)

expect(parsed.tasks.count == 3, "Markdown should keep all tasks")
expect(parsed.tasks[0].title == "GeneZip rebuttal experiment", "Task title should round-trip")
expect(parsed.tasks[0].timeRange == "14:00 - 16:00", "Time range should round-trip")
expect(parsed.tasks[0].tags == ["research", "important"], "Tags should round-trip")
expect(parsed.tasks[2].timeRange == nil, "Unscheduled task should remain unscheduled")
expect(TimeFormat.parseRange("09:30-10:15")?.start == 570, "ASCII time range should parse")
expect(TimeFormat.parseRange("14:00–16:00")?.end == 960, "En dash time range should parse")
expect(TimeFormat.parseRange("16:00–14:00") == nil, "Reverse range should be rejected")

let rules = [
    WebRule(domain: "youtube.com"),
    WebRule(domain: "studio.youtube.com", isAllowed: true)
]
expect(DomainRuleMatcher.shouldBlock(host: "www.youtube.com", rules: rules), "Subdomains should be blocked")
expect(!DomainRuleMatcher.shouldBlock(host: "studio.youtube.com", rules: rules), "Allowlist should win")
expect(!DomainRuleMatcher.shouldBlock(host: "example.com", rules: rules), "Unlisted domain should pass")

Task { @MainActor in
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MetridaySmoke-\(UUID().uuidString)")
    let store = MarkdownStore(date: date, rootDirectory: tempRoot)
    guard let draftID = store.tasks.first(where: { $0.title == "Draft response" })?.id else {
        expect(false, "Seed should include Draft response")
        return
    }

    store.schedule(id: draftID, start: 11 * 60, end: 12 * 60)
    expect(store.task(draftID)?.timeRange == "11:00 - 12:00", "Scheduling should update the Markdown model")
    expect(store.markdown.contains("11:00 - 12:00 Draft response"), "Scheduling should rewrite Markdown text")

    store.move(id: draftID, start: 13 * 60 + 30)
    expect(store.task(draftID)?.timeRange == "13:30 - 14:30", "Moving should preserve duration and rewrite time")

    store.resize(id: draftID, end: 15 * 60)
    expect(store.task(draftID)?.timeRange == "13:30 - 15:00", "Resizing should rewrite the end time")

    store.resizeStart(id: draftID, start: 14 * 60)
    expect(store.task(draftID)?.timeRange == "14:00 - 15:00", "Resizing should rewrite the start time")

    store.unschedule(id: draftID)
    expect(store.task(draftID) != nil, "Removing time should preserve the task")
    expect(store.task(draftID)?.timeRange == nil, "Removing time should clear only the range")

    let newTaskID = UUID()
    expect(store.addTask(title: "Fresh draggable task", id: newTaskID) == newTaskID, "New editor task should be committed with its drag identity")
    store.schedule(id: newTaskID, start: 10 * 60, end: 11 * 60)
    expect(store.task(newTaskID)?.timeRange == "10:00 - 11:00", "A newly committed task should be immediately schedulable")
    expect(store.markdown.contains("10:00 - 11:00 Fresh draggable task"), "New task drag should persist its Time Block in Markdown")

    let rawBeforeFreeEdit = store.markdown
    let freelyEdited = "Custom first line\n1. Editable ordered item\n" + rawBeforeFreeEdit
    store.updateRawMarkdown(freelyEdited)
    expect(store.markdown == freelyEdited, "The native editor must preserve arbitrary Markdown exactly")
    expect(store.task(newTaskID)?.title == "Fresh draggable task", "Task identity should survive inserting ordinary lines above it")
    store.move(id: newTaskID, start: 12 * 60)
    expect(store.markdown.hasPrefix("Custom first line\n1. Editable ordered item\n"), "Calendar edits must not rewrite unrelated Markdown lines")
    expect(store.markdown.contains("12:00 - 13:00 Fresh draggable task"), "Calendar edits should replace only the matching task line")

    store.updateRawMarkdown("# An entirely free-form note\n\nParagraph text\n")
    expect(store.markdown == "# An entirely free-form note\n\nParagraph text\n", "A document without task lines must remain valid Markdown")
    expect(store.tasks.isEmpty, "Calendar should simply be empty when the Markdown has no tasks")

    let originalMarkdown = store.markdown
    let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: date)!
    expect(store.load(date: nextDate), "Selecting a missing date should create its daily Markdown")
    expect(store.fileURL.lastPathComponent != "", "The selected date should have a concrete Markdown file")
    expect(store.markdown.contains("## Focus"), "A new day should start with an editable Markdown template")
    expect(store.tasks.isEmpty, "A newly created day must not copy tasks from another date")

    _ = store.addTask(title: "Task on next day")
    expect(store.markdown.contains("Task on next day"), "The newly created daily Markdown should be editable")
    expect(!store.load(date: date), "Returning to an existing date should open instead of recreate it")
    expect(store.markdown == originalMarkdown, "Switching dates must preserve each day's Markdown independently")

    try? FileManager.default.removeItem(at: tempRoot)
    print("Metriday smoke tests passed")
    exit(0)
}

RunLoop.main.run()
