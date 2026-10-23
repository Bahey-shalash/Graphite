/// A run of tasks written one after the other under sections of one name, which Pele draws under one band, as
/// Mermaid does: two sections of one name in a row make one band, and a section without tasks makes none.
struct UserJourneySectionRun: Equatable {
    let firstTaskIndex: Int
    let taskCount: Int
    /// The sections' heading, or nil for the tasks written before the first section, which have no band.
    let heading: DiagramLabel?

    /// The runs of `diagram`'s tasks, in order.
    static func runs(of diagram: UserJourneyDiagram) -> [UserJourneySectionRun] {
        var runs: [UserJourneySectionRun] = []
        for (index, task) in diagram.tasks.enumerated() {
            let heading = task.sectionIndex.map { section in diagram.sections[section] }
            if let last = runs.last, last.heading == heading {
                runs[runs.count - 1] = UserJourneySectionRun(firstTaskIndex: last.firstTaskIndex, taskCount: last.taskCount + 1, heading: heading)
            } else {
                runs.append(UserJourneySectionRun(firstTaskIndex: index, taskCount: 1, heading: heading))
            }
        }
        return runs
    }
}
