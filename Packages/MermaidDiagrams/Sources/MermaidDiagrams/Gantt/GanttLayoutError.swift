/// Why a Gantt chart was not laid out.
public enum GanttLayoutError: Error, Equatable, Sendable {
    /// The chart has a statement that is not drawn yet: drawn without it, it would look complete and be wrong.
    case statementNotDrawn(GanttStatementNotDrawn)
    /// A start date is written in a form neither `dateFormat` nor the date forms read here read, by its text. Mermaid
    /// then asks JavaScript's date parser, which reads more forms than are read here.
    case unreadableDate(String)
    /// Every day for 10,000 days after a task's end is excluded, by the task's text: Mermaid's error.
    case noDayLeftAfterExclusions(task: String)
    /// Moving tasks' ends past excluded days would step through more days than the limit.
    case tooManyScheduledDays(limit: Int)
}
