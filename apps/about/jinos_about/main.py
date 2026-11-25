"""About Phone: what this device is, and which hardware jinOS can see."""

import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GLib, Gtk  # noqa: E402

import jinos_ui  # noqa: E402

from . import probes  # noqa: E402

APP_ID = "org.jinos.About"

STATUS_STYLE = {
    probes.Status.DETECTED: ("object-select-symbolic", "success", "Detected"),
    probes.Status.NOT_FOUND: ("window-close-symbolic", "dim-label", "Not found"),
    probes.Status.UNKNOWN: ("dialog-question-symbolic", "warning", "Unknown"),
}


class Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="About Phone", default_width=360, default_height=720)
        self.report_text = ""

        refresh = Gtk.Button(icon_name="view-refresh-symbolic", tooltip_text="Check again")
        refresh.connect("clicked", lambda _b: self.refresh())
        copy = Gtk.Button(icon_name="edit-copy-symbolic", tooltip_text="Copy report")
        copy.connect("clicked", lambda _b: self.copy_report())
        header = Adw.HeaderBar(show_end_title_buttons=False)
        header.pack_start(refresh)
        header.pack_end(copy)

        self.device = Adw.PreferencesGroup()
        device_page = Adw.PreferencesPage()
        device_page.add(self.device)

        self.hardware = Adw.PreferencesGroup(
            description="Detected means the system found it, not that every feature works yet.")
        hardware_page = Adw.PreferencesPage()
        hardware_page.add(self.hardware)

        self.stack = Adw.ViewStack()
        self.stack.add_titled_with_icon(device_page, "device", "Device", "phone-symbolic")
        self.stack.add_titled_with_icon(hardware_page, "hardware", "Hardware", "preferences-system-symbolic")

        # Tabs at the bottom, within thumb reach.
        tabs = Adw.ViewSwitcherBar(stack=self.stack, reveal=True)

        self.toasts = Adw.ToastOverlay(child=self.stack)
        toolbar = Adw.ToolbarView(content=self.toasts)
        toolbar.add_top_bar(header)
        toolbar.add_bottom_bar(tabs)
        self.set_content(toolbar)

        self.device_rows = []
        self.hardware_rows = []
        self.refresh()

    def refresh(self):
        info = probes.device_info()
        results = probes.run_all()
        self.report_text = probes.report(info, results)

        for row in self.device_rows:
            self.device.remove(row)
        self.device_rows = []
        for key, value in info.items():
            row = Adw.ActionRow(title=key, subtitle=GLib.markup_escape_text(value))
            row.add_css_class("property")
            row.set_subtitle_selectable(True)
            self.device.add(row)
            self.device_rows.append(row)

        for row in self.hardware_rows:
            self.hardware.remove(row)
        self.hardware_rows = []
        for probe in results:
            row = self._probe_row(probe)
            self.hardware.add(row)
            self.hardware_rows.append(row)

    def _probe_row(self, probe):
        icon_name, css_class, label = STATUS_STYLE[probe.status]
        row = Adw.ActionRow(title=probe.name, subtitle=GLib.markup_escape_text(probe.detail))
        row.add_prefix(Gtk.Image(icon_name=probe.icon))
        status = Gtk.Image(icon_name=icon_name, tooltip_text=label)
        status.add_css_class(css_class)
        status.update_property([Gtk.AccessibleProperty.LABEL], [label])
        row.add_suffix(status)
        return row

    def copy_report(self):
        self.get_clipboard().set_content(Gdk.ContentProvider.new_for_value(self.report_text))
        self.toasts.add_toast(Adw.Toast(title="Report copied", timeout=2))


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)

    def do_startup(self):
        Adw.Application.do_startup(self)
        jinos_ui.init()

    def do_activate(self):
        window = self.get_active_window() or Window(self)
        window.present()


def main():
    return App().run(sys.argv)
