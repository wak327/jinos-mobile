"""Contacts: the people you call and message, stored in the GNOME address book."""

import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, GObject, Gtk  # noqa: E402

import jinos_ui  # noqa: E402

from .store import EMAIL_KINDS, PHONE_KINDS, Entry, Person, Store  # noqa: E402

APP_ID = "org.jinos.Contacts"


def _scrolled(child):
    clamp = Adw.Clamp(maximum_size=600, child=child, margin_top=6, margin_bottom=24,
                      margin_start=12, margin_end=12)
    return Gtk.ScrolledWindow(child=clamp, hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)


def _header():
    # Phones close apps from the task switcher, not a window button.
    return Adw.HeaderBar(show_end_title_buttons=False)


class ListPage(Adw.NavigationPage):
    def __init__(self, window):
        super().__init__(title="Contacts", tag="list")
        self.window = window
        self.people = []

        search_button = Gtk.ToggleButton(icon_name="system-search-symbolic", tooltip_text="Search")
        add = Gtk.Button(icon_name="list-add-symbolic", tooltip_text="Add contact")
        add.connect("clicked", lambda _b: window.edit(None))
        header = _header()
        header.pack_start(search_button)
        header.pack_end(add)

        self.search = Gtk.SearchEntry(placeholder_text="Search name, number or email", hexpand=True)
        self.search.connect("search-changed", lambda _e: self._refilter())
        self.search_bar = Gtk.SearchBar(child=Adw.Clamp(maximum_size=600, child=self.search))
        self.search_bar.connect_entry(self.search)
        search_button.bind_property("active", self.search_bar, "search-mode-enabled",
                                    GObject.BindingFlags.BIDIRECTIONAL)

        # A plain list with letter headers, like the contacts app on most phones.
        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, valign=Gtk.Align.START)
        self.list.add_css_class("navigation-sidebar")
        self.list.set_filter_func(lambda row: row.person.matches(self.search.get_text()))
        self.list.set_header_func(self._letter_header)
        self.list.connect("row-activated", lambda _l, row: window.show_person(row.person))

        add_first = Gtk.Button(label="Add Contact", halign=Gtk.Align.CENTER)
        add_first.add_css_class("pill")
        add_first.add_css_class("suggested-action")
        add_first.connect("clicked", lambda _b: window.edit(None))
        self.empty = Adw.StatusPage(icon_name="avatar-default-symbolic", title="No Contacts",
                                    description="Add the people you call and message.", child=add_first)
        self.no_results = Adw.StatusPage(icon_name="system-search-symbolic", title="No Matches")

        loading = Adw.StatusPage(title="Loading Contacts", child=Adw.Spinner(width_request=32, height_request=32))
        self.error = Adw.StatusPage(icon_name="dialog-error-symbolic", title="Address Book Unavailable")

        self.stack = Gtk.Stack()
        self.stack.add_named(loading, "loading")
        self.stack.add_named(self.error, "error")
        self.stack.add_named(self.empty, "empty")
        self.stack.add_named(self.no_results, "no-results")
        self.stack.add_named(_scrolled(self.list), "list")

        toolbar = Adw.ToolbarView(content=self.stack)
        toolbar.add_top_bar(header)
        toolbar.add_top_bar(self.search_bar)
        self.set_child(toolbar)

    def _letter_header(self, row, before):
        if self.search.get_text():
            row.set_header(None)
            return
        letter = row.person.display_name[:1].upper()
        if not letter.isalpha():
            letter = "#"
        previous = before.person.display_name[:1].upper() if before else None
        if previous is not None and not previous.isalpha():
            previous = "#"
        row.set_header(jinos_ui.SectionHeader(letter, top=4 if before is None else 14)
                       if letter != previous else None)

    def show_error(self, message):
        self.error.set_description(GLib.markup_escape_text(message))
        self.stack.set_visible_child_name("error")

    def _refilter(self):
        self.list.invalidate_filter()
        self.list.invalidate_headers()
        self._update_stack()

    def _update_stack(self):
        text = self.search.get_text()
        if not self.people:
            self.stack.set_visible_child_name("empty")
        elif text and not any(p.matches(text) for p in self.people):
            self.stack.set_visible_child_name("no-results")
        else:
            self.stack.set_visible_child_name("list")

    def show(self, people):
        self.people = people
        self.list.remove_all()
        for person in people:
            row = Adw.ActionRow(title=GLib.markup_escape_text(person.display_name), activatable=True)
            if person.name and person.phones:
                row.set_subtitle(GLib.markup_escape_text(person.phones[0].value))
            row.add_prefix(jinos_ui.avatar(person.display_name, 44, bool(person.name)))
            row.person = person
            self.list.append(row)
        self._update_stack()


class PersonPage(Adw.NavigationPage):
    def __init__(self, window, person):
        super().__init__(title=person.display_name, tag="person")
        self.window = window
        self.person = person

        edit = Gtk.Button(label="Edit")
        edit.connect("clicked", lambda _b: window.edit(person))
        header = _header()
        header.pack_end(edit)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Avatar, name and quick actions, centred, like phone contact apps.
        top = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin_top=12, margin_bottom=8)
        top.append(jinos_ui.avatar(person.display_name, 96, bool(person.name)))
        name = Gtk.Label(label=person.display_name, wrap=True, justify=Gtk.Justification.CENTER)
        name.add_css_class("jinos-name")
        top.append(name)
        box.append(top)

        actions = Gtk.Box(spacing=28, halign=Gtk.Align.CENTER, margin_top=8, margin_bottom=8)
        if person.phones:
            number = person.phones[0].value
            actions.append(jinos_ui.ActionButton("call-start-symbolic", "Call",
                                                 lambda: window.open_uri(f"tel:{number}")))
            actions.append(jinos_ui.ActionButton("mail-send-symbolic", "Message",
                                                 lambda: window.open_uri(f"sms:{number}")))
        if person.emails:
            address = person.emails[0].value
            actions.append(jinos_ui.ActionButton("mail-unread-symbolic", "Email",
                                                 lambda: window.open_uri(f"mailto:{address}")))
        if actions.get_first_child() is not None:
            box.append(actions)

        if person.phones:
            group = Adw.PreferencesGroup(title="Phone", margin_top=12)
            for entry in person.phones:
                row = Adw.ActionRow(title=GLib.markup_escape_text(entry.value), subtitle=PHONE_KINDS[entry.kind])
                row.set_title_selectable(True)
                row.add_suffix(self._action_button("mail-send-symbolic", "Send Message", f"sms:{entry.value}"))
                row.add_suffix(self._action_button("call-start-symbolic", "Call", f"tel:{entry.value}"))
                group.add(row)
            box.append(group)

        if person.emails:
            group = Adw.PreferencesGroup(title="Email", margin_top=12)
            for entry in person.emails:
                row = Adw.ActionRow(title=GLib.markup_escape_text(entry.value), subtitle=EMAIL_KINDS[entry.kind])
                row.set_title_selectable(True)
                row.add_suffix(self._action_button("mail-unread-symbolic", "Send Email", f"mailto:{entry.value}"))
                group.add(row)
            box.append(group)

        if person.note:
            group = Adw.PreferencesGroup(title="Note", margin_top=12)
            note = Adw.ActionRow(title=GLib.markup_escape_text(person.note))
            note.set_title_lines(0)
            note.set_title_selectable(True)
            group.add(note)
            box.append(group)

        delete = Gtk.Button(label="Delete Contact", halign=Gtk.Align.CENTER, margin_top=24)
        delete.add_css_class("pill")
        delete.add_css_class("destructive-action")
        delete.connect("clicked", lambda _b: window.confirm_delete(person))
        box.append(delete)

        toolbar = Adw.ToolbarView(content=_scrolled(box))
        toolbar.add_top_bar(header)
        self.set_child(toolbar)

    def _action_button(self, icon, label, uri):
        button = Gtk.Button(icon_name=icon, tooltip_text=label, valign=Gtk.Align.CENTER)
        button.add_css_class("flat")
        button.update_property([Gtk.AccessibleProperty.LABEL], [label])
        button.connect("clicked", lambda _b: self.window.open_uri(uri))
        return button


class EntryList:
    """Editable rows for phone numbers or emails, each with a kind and a remove button."""

    def __init__(self, title, add_label, kinds, entries, purpose):
        self.kinds = list(kinds)
        self.labels = list(kinds.values())
        self.purpose = purpose
        self.group = Adw.PreferencesGroup(title=title)
        self.rows = []
        self.add_row = Adw.ButtonRow(title=add_label, start_icon_name="list-add-symbolic")
        self.add_row.connect("activated", lambda _r: self.append(Entry(self.kinds[0], ""), focus=True))
        self.group.add(self.add_row)
        for entry in entries:
            self.append(entry)

    def append(self, entry, focus=False):
        row = Adw.EntryRow(title=self.labels[self.kinds.index(entry.kind)], text=entry.value,
                           input_purpose=self.purpose)
        kind = Gtk.DropDown.new_from_strings(self.labels)
        kind.set_selected(self.kinds.index(entry.kind))
        kind.set_valign(Gtk.Align.CENTER)
        kind.add_css_class("flat")
        kind.connect("notify::selected", lambda d, _p: row.set_title(self.labels[d.get_selected()]))
        remove = Gtk.Button(icon_name="user-trash-symbolic", tooltip_text="Remove", valign=Gtk.Align.CENTER)
        remove.add_css_class("flat")
        remove.connect("clicked", lambda _b: self._remove(row))
        row.add_suffix(kind)
        row.add_suffix(remove)
        row.kind = kind
        # Keep the "Add" button last.
        self.group.remove(self.add_row)
        self.group.add(row)
        self.group.add(self.add_row)
        self.rows.append(row)
        if focus:
            row.grab_focus()

    def _remove(self, row):
        self.group.remove(row)
        self.rows.remove(row)

    def entries(self):
        return [Entry(self.kinds[r.kind.get_selected()], r.get_text().strip())
                for r in self.rows if r.get_text().strip()]


class EditPage(Adw.NavigationPage):
    def __init__(self, window, person):
        new = person is None
        person = person or Person(name="", phones=[Entry("CELL", "")])
        super().__init__(title="New Contact" if new else "Edit Contact", tag="edit")
        self.window = window
        self.person = person

        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", lambda _b: window.nav.pop())
        save = Gtk.Button(label="Save")
        save.add_css_class("suggested-action")
        save.connect("clicked", lambda _b: self.save())
        header = Adw.HeaderBar(show_back_button=False, show_end_title_buttons=False)
        header.pack_start(cancel)
        header.pack_end(save)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        names = Adw.PreferencesGroup()
        self.name = Adw.EntryRow(title="Name", text=person.name)
        self.name.connect("entry-activated", lambda _r: self.save())
        names.add(self.name)
        box.append(names)

        self.phones = EntryList("Phone", "Add Phone Number", PHONE_KINDS, person.phones, Gtk.InputPurpose.PHONE)
        box.append(self.phones.group)
        self.emails = EntryList("Email", "Add Email", EMAIL_KINDS, person.emails, Gtk.InputPurpose.EMAIL)
        box.append(self.emails.group)

        notes = Adw.PreferencesGroup(title="Note")
        self.note = Adw.EntryRow(title="Note", text=person.note)
        notes.add(self.note)
        box.append(notes)

        toolbar = Adw.ToolbarView(content=_scrolled(box))
        toolbar.add_top_bar(header)
        self.set_child(toolbar)
        self.connect("shown", lambda _p: self.name.grab_focus())

    def save(self):
        person = Person(
            name=self.name.get_text().strip(),
            phones=self.phones.entries(),
            emails=self.emails.entries(),
            note=self.note.get_text().strip(),
            uid=self.person.uid,
            contact=self.person.contact,
        )
        if not (person.name or person.phones or person.emails):
            self.window.toast("Add a name, number or email first")
            return
        try:
            saved = self.window.store.save(person)
        except GLib.Error as error:
            self.window.toast(f"Could not save: {error.message}")
            return
        self.window.saved(saved)


class Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Contacts", default_width=360, default_height=720)
        self.store = None
        self.nav = Adw.NavigationView()
        self.list_page = ListPage(self)
        self.nav.add(self.list_page)
        self.toasts = Adw.ToastOverlay(child=self.nav)
        self.set_content(self.toasts)
        # Show the window straight away; the address book connects in the background.
        Store.open(self._connected)

    def _connected(self, store, error):
        if error is not None:
            self.list_page.show_error(error.message)
            return
        self.store = store
        self.reload()
        store.watch(self.reload)

    def edit(self, person):
        if self.store is not None:
            self.nav.push(EditPage(self, person))

    def reload(self):
        if self.store is None:
            return
        try:
            self.list_page.show(self.store.all())
        except GLib.Error as error:
            self.toast(f"Could not read contacts: {error.message}")

    def show_person(self, person):
        self.nav.push(PersonPage(self, person))

    def saved(self, person):
        # Replace the edit page (and an outdated person page) with the saved contact.
        self.nav.pop_to_tag("list")
        self.reload()
        self.show_person(person)
        self.toast("Contact saved")

    def confirm_delete(self, person):
        dialog = Adw.AlertDialog(
            heading=f"Delete {person.display_name}?",
            body="This removes the contact from this phone.",
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("delete", "Delete")
        dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_close_response("cancel")
        dialog.connect("response", lambda _d, response: response == "delete" and self.delete(person))
        dialog.present(self)

    def delete(self, person):
        try:
            self.store.delete(person)
        except GLib.Error as error:
            self.toast(f"Could not delete: {error.message}")
            return
        self.nav.pop_to_tag("list")
        self.reload()
        self.toast(f"Deleted {person.display_name}")

    def open_uri(self, uri):
        scheme = uri.split(":", 1)[0]
        what = {"tel": "make calls", "sms": "send messages", "mailto": "send email"}[scheme]

        def done(launcher, result):
            try:
                launcher.launch_finish(result)
            except GLib.Error:
                self.toast(f"Could not open the app to {what}")

        # Without this check GTK shows its own "No Apps Found" dialog pointing at an app store.
        if Gio.AppInfo.get_default_for_uri_scheme(scheme) is None:
            self.toast(f"No app can {what} yet")
            return
        Gtk.UriLauncher.new(uri).launch(self, None, done)

    def toast(self, text):
        self.toasts.add_toast(Adw.Toast(title=GLib.markup_escape_text(text), timeout=3))


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_startup(self):
        Adw.Application.do_startup(self)
        jinos_ui.init()

    def do_activate(self):
        window = self.get_active_window() or Window(self)
        window.present()


def main():
    return App().run(sys.argv)
