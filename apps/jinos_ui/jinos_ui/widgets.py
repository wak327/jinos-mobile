"""Small helpers on top of libadwaita."""

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk  # noqa: E402


class SectionHeader(Gtk.Label):
    """Small grey label above a group of rows, or a letter in an A-Z list."""

    def __init__(self, text, top=18):
        super().__init__(label=text, xalign=0, margin_start=14, margin_end=14, margin_top=top, margin_bottom=6)
        self.add_css_class("jinos-section")


class ActionButton(Gtk.Box):
    """Round icon button with a label underneath, for quick actions like Call."""

    def __init__(self, icon, label, callback):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=6, halign=Gtk.Align.CENTER)
        self.add_css_class("jinos-action")
        self.button = Gtk.Button(icon_name=icon, tooltip_text=label, halign=Gtk.Align.CENTER)
        self.button.update_property([Gtk.AccessibleProperty.LABEL], [label])
        self.button.connect("clicked", lambda _b: callback())
        self.append(self.button)
        self.append(Gtk.Label(label=label))


def avatar(name, size=48, initials=True):
    """A round avatar with initials (libadwaita's own)."""
    return Adw.Avatar(size=size, text=name, show_initials=initials)
