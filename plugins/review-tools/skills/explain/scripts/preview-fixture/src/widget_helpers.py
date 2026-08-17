"""Small helpers -- part of explain's own preview fixture. Referenced via --code (a plain code
node, not a diff) to demonstrate that node kind alongside the diff/markdown ones."""


def format_widget_label(widget):
    return f"{widget.name} (#{widget.id})"
