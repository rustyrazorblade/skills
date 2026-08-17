## Purpose

A tiny widget-management capability, invented purely as a preview fixture for `explain`'s
OpenSpec-aware rendering — not a real spec for a real system.

## Requirements

### Requirement: Widget deletion
The system SHALL allow deleting a widget by id.

#### Scenario: Delete succeeds
- **WHEN** a delete request is submitted for an existing widget id
- **THEN** the widget is removed

### Requirement: Widget export
The system SHALL allow exporting a widget's data as JSON.

#### Scenario: Export succeeds
- **WHEN** an export request is submitted for an existing widget id
- **THEN** a JSON representation of the widget is returned
