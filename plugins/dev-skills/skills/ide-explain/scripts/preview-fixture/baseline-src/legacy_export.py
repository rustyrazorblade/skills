"""Legacy single-widget export -- part of explain's own preview fixture, not real code.

Superseded by the bulk-export system; removed as part of the in-flight "demo" change (this file
exists only in the baseline commit -- the "after" state deletes it, to demonstrate explain's
deleted-file diff rendering).
"""


def export_widget(db, widget_id):
    widget = db.widgets.get(widget_id)
    return {"id": widget.id, "name": widget.name}
