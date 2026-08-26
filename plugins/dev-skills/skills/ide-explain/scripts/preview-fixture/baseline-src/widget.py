"""Widget domain model -- part of explain's own preview fixture, not real code."""


class Widget:
    def __init__(self, widget_id, name):
        self.id = widget_id
        self.name = name

    def delete(self, db):
        """Delete this widget by id."""
        db.widgets.remove(self.id)
