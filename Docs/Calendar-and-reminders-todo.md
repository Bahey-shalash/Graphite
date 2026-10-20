# Apple Calendar and Reminders integration: TODO

Created: 2026-10-18.

Status: not started. Graphite does not use EventKit yet, and `App/Info.plist` asks for no calendar or reminders access.

## Request

Native integration with Apple Calendar and Reminders through EventKit, on iPadOS, iOS and macOS. The vault stays authoritative: events and reminders are read from and written to the system stores, and what ends up in a note is ordinary Markdown that Obsidian reads unchanged.

## Scope

- [ ] Permissions: ask only when the user first uses a calendar or reminders feature, never at launch. Full access for reading (`NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`); consider write-only calendar access where Graphite only adds events. Every feature explains itself and stays usable when access is denied.
- [ ] Calendar view for daily notes, the gap noted in `Obsidian-mobile-gaps.md` ("no Calendar view"): a month view that opens or creates the daily note for a day and marks the days that have one.
- [ ] Today's events in the daily note: a command that inserts the day's events as a Markdown list (time, title, optional link to a meeting note), and a template variable for daily-note templates.
- [ ] Meeting and lecture notes from an event: create a note named from the event, with date, time, location and attendees as properties, in a folder the user chooses per calendar.
- [ ] Lecture recording context: when a recording starts during a calendar event, offer the event's title and course as the recording's name and destination (OBJECTIVE.md asks for meaningful names and course context).
- [ ] Tasks to Reminders: a task with a due date (`- [ ] … 📅 2026-10-20`, the Tasks plugin syntax Obsidian users already write) can be sent to a Reminders list; completing it on either side completes it on the other. Which tasks sync is the user's choice, never all tasks by default.
- [ ] Reminders into notes: show or import a Reminders list as Markdown tasks.
- [ ] Changes made in Calendar or Reminders while Graphite is closed are picked up on the next launch (`EKEventStoreChanged`, and a check on activation).
- [ ] `Architecture.md`, `Coverage.md` and the gaps list updated once each part is built and tested.

## Storage rules

- Markdown stays the only representation of the user's tasks and notes. The link between a task and its reminder must survive without a Graphite database: either a visible, Obsidian-compatible marker in the task line, or a lookup that can be rebuilt from the vault and the Reminders store. An index that is lost may only cost the link, never content.
- Graphite never deletes an event or reminder it did not create, and never deletes one without the user asking.
- Events are not copied into the vault unless the user inserts them.

## Open questions

- How should a task remember its reminder: an inline marker (for example a Tasks-style field or a block ID), or matching on text and date? A marker is reliable but adds text to the note.
- Which Obsidian plugin conventions to follow: the Tasks plugin's emoji fields, Dataview inline fields, or both?
- Should the calendar view live in the sidebar, a tab, or both, given the screen-space rule of keeping chrome to a minimum?
- macOS: same features, or Calendar only?
