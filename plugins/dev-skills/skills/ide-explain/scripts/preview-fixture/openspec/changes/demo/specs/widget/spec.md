## ADDED Requirements

### Requirement: Widget renaming
The system SHALL allow renaming a widget.

#### Scenario: Rename succeeds
- **WHEN** a rename request is submitted with a new, non-empty name
- **THEN** the widget's name is updated

## MODIFIED Requirements

### Requirement: Widget deletion
The system SHALL allow deleting a widget by id, and SHALL cascade-delete any attachments it owns.

#### Scenario: Delete succeeds
- **WHEN** a delete request is submitted for an existing widget id
- **THEN** the widget and all of its attachments are removed

## REMOVED Requirements

### Requirement: Widget export
**Reason**: Replaced by the new bulk-export system, which covers single-widget export as a
special case.
**Migration**: Use the bulk-export endpoint with a single widget id in its filter.
