# Widget capability — design notes

Not a real doc — part of explain's own preview fixture, referenced via `--doc` to demonstrate a
plain markdown node (no OpenSpec delta headers, no badge, just rendered content).

Widgets are the toy domain used throughout this fixture: a `Widget` has an id and a name, can be
deleted (cascade-deleting its attachments as of the in-flight "demo" change), can be renamed, and
used to support a single-widget export that's being replaced by a bulk-export system.
