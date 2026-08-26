"""Widget domain model -- part of explain's own preview fixture, not real code."""


class Widget:
    def __init__(self, widget_id, name):
        self.id = widget_id
        self.name = name

    def delete(self, db):
        """Delete this widget by id, cascade-deleting any attachments it owns."""
        db.attachments.remove_all(widget_id=self.id)
        db.widgets.remove(self.id)
