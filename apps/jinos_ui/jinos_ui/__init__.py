"""The jinOS look for GTK4/libadwaita apps.

Call jinos_ui.init() once at startup (Adw.Application.do_startup). Apps then
use ordinary libadwaita layout (header bars, boxed-list cards, view switcher
tabs) plus the few helpers here: SectionHeader, ActionButton, avatar().

The accent colour defaults to DEFAULT_ACCENT and can be overridden in
~/.config/jinos/ui.ini:

    [style]
    accent = #3584e4
"""

import configparser
import os

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GLib, Gtk  # noqa: E402

from .widgets import ActionButton, SectionHeader, avatar  # noqa: E402,F401

DEFAULT_ACCENT = "#3584e4"

_STYLE = os.path.join(os.path.dirname(__file__), "style.css")
_initialised = False


def accent() -> str:
    path = os.path.join(GLib.get_user_config_dir(), "jinos", "ui.ini")
    config = configparser.ConfigParser()
    config.read(path)
    value = config.get("style", "accent", fallback=DEFAULT_ACCENT).strip()
    return value if Gdk.RGBA().parse(value) else DEFAULT_ACCENT


def init() -> None:
    """Apply the jinOS look to this process. Safe to call more than once."""
    global _initialised
    if _initialised:
        return
    _initialised = True

    # Follow the system's light or dark setting, like any phone app.
    Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.DEFAULT)

    # The same icons in every shell: under Plasma GTK would otherwise use
    # Breeze, which lacks several of the icons GTK apps ask for.
    settings = Gtk.Settings.get_default()
    if settings is not None:
        settings.props.gtk_icon_theme_name = "Adwaita"

    display = Gdk.Display.get_default()
    base = Gtk.CssProvider()
    base.load_from_path(_STYLE)
    Gtk.StyleContext.add_provider_for_display(display, base, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    colour = accent()
    accent_css = Gtk.CssProvider()
    # Set the derived accent text colour too, with libadwaita's own formula;
    # otherwise it keeps following the system accent (orange on Ubuntu).
    accent_css.load_from_string(
        f":root {{ --accent-bg-color: {colour}; --accent-fg-color: #ffffff;"
        " --accent-color: oklab(from var(--accent-bg-color) var(--standalone-color-oklab)); }"
    )
    Gtk.StyleContext.add_provider_for_display(display, accent_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
