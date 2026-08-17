"""Widget renaming -- part of explain's own preview fixture, not real code.

Brand-new file, implementing the ADDED "Widget renaming" requirement -- demonstrates explain's
"new file" diff badge.
"""


def rename_widget(db, widget_id, new_name):
    if not new_name:
        raise ValueError("new_name must be non-empty")
    widget = db.widgets.get(widget_id)
    widget.name = new_name
    db.widgets.save(widget)
