"""Contacts storage on Evolution Data Server, the GNOME address book.

Calls and Chatty read the same address book, so contacts saved here show
up by name there. No GTK in this module.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import gi

gi.require_version("EDataServer", "1.2")
gi.require_version("EBook", "1.2")
gi.require_version("EBookContacts", "1.2")
from gi.repository import EBook, EBookContacts, EDataServer, GLib  # noqa: E402

Field = EBookContacts.ContactField

# vCard TYPE value -> label, in the order the editor offers them.
PHONE_KINDS = {"CELL": "Mobile", "HOME": "Home", "WORK": "Work", "VOICE": "Other"}
EMAIL_KINDS = {"HOME": "Home", "WORK": "Work", "OTHER": "Other"}


@dataclass
class Entry:
    kind: str  # vCard TYPE value, a key of PHONE_KINDS or EMAIL_KINDS
    value: str


@dataclass
class Person:
    name: str
    phones: list[Entry] = field(default_factory=list)
    emails: list[Entry] = field(default_factory=list)
    note: str = ""
    uid: str | None = None
    # The EDS contact this was read from, so saving keeps fields we don't edit (photo, address...).
    contact: EBookContacts.Contact | None = field(default=None, repr=False, compare=False)

    @property
    def display_name(self) -> str:
        if self.name:
            return self.name
        if self.phones:
            return self.phones[0].value
        if self.emails:
            return self.emails[0].value
        return "No Name"

    def matches(self, text: str) -> bool:
        text = text.casefold().strip()
        if not text:
            return True
        digits = "".join(c for c in text if c.isdigit())
        if text in self.display_name.casefold():
            return True
        if any(text in e.value.casefold() for e in self.emails):
            return True
        return bool(digits) and any(digits in _digits(p.value) for p in self.phones)


def _digits(number: str) -> str:
    return "".join(c for c in number if c.isdigit())


def _entries(contact, field_id, kinds: dict[str, str], fallback: str) -> list[Entry]:
    entries = []
    for attr in contact.get_attributes(field_id):
        value = (attr.get_value() or "").strip()
        if not value:
            continue
        types = [t.upper() for t in (attr.get_param("TYPE") or [])]
        kind = next((k for k in kinds if k in types), fallback)
        entries.append(Entry(kind, value))
    return entries


def person_from_contact(contact) -> Person:
    return Person(
        name=(contact.get_property("full-name") or "").strip(),
        phones=_entries(contact, Field.TEL, PHONE_KINDS, "VOICE"),
        emails=_entries(contact, Field.EMAIL, EMAIL_KINDS, "OTHER"),
        note=(contact.get_property("note") or "").strip(),
        uid=contact.get_property("id"),
        contact=contact,
    )


def _replace(contact, attr_name: str, entries: list[Entry]) -> None:
    contact.remove_attributes(None, attr_name)
    for entry in entries:
        if not entry.value.strip():
            continue
        attr = EBookContacts.VCardAttribute.new(None, attr_name)
        attr.add_param_with_value(EBookContacts.VCardAttributeParam.new("TYPE"), entry.kind)
        attr.add_value(entry.value.strip())
        contact.append_attribute(attr)


def contact_from_person(person: Person):
    contact = person.contact.duplicate() if person.contact else EBookContacts.Contact.new()
    # Contact.set() takes a C pointer Python can't pass; use the GObject properties.
    contact.set_property("full-name", person.name.strip() or None)
    contact.set_property("file-as", person.name.strip() or None)
    _replace(contact, "TEL", person.phones)
    _replace(contact, "EMAIL", person.emails)
    contact.set_property("note", person.note.strip() or None)
    return contact


def _builtin_source():
    return EDataServer.SourceRegistry.new_sync(None).ref_builtin_address_book()


class Store:
    """The user's built-in address book. Calls block briefly; the book is local."""

    _QUERY = EBookContacts.BookQuery.any_field_contains("").to_string()
    _FLAGS = EBookContacts.BookOperationFlags.NONE

    def __init__(self, client=None, wait_seconds: int = 30):
        """Use an already connected client, or connect now (blocking; tests only)."""
        if client is None:
            client = EBook.BookClient.connect_sync(_builtin_source(), wait_seconds, None)
        self.client = client
        self._view = None

    @classmethod
    def open(cls, callback, wait_seconds: int = 30):
        """Connect without blocking the UI; calls callback(store, error) when done.

        Starting the address book service can take tens of seconds the first
        time, so apps must show their window first and fill it in later.
        """
        def done(_source, result, *_args):
            try:
                client = EBook.BookClient.connect_finish(result)
            except GLib.Error as error:
                callback(None, error)
                return
            callback(cls(client), None)

        EBook.BookClient.connect(_builtin_source(), wait_seconds, None, done)

    def all(self) -> list[Person]:
        _ok, contacts = self.client.get_contacts_sync(self._QUERY, None)
        people = [person_from_contact(c) for c in contacts]
        return sorted(people, key=lambda p: p.display_name.casefold())

    def get(self, uid: str) -> Person:
        _ok, contact = self.client.get_contact_sync(uid, None)
        return person_from_contact(contact)

    def save(self, person: Person) -> Person:
        """Add or update; returns the person as stored."""
        contact = contact_from_person(person)
        if person.uid:
            self.client.modify_contact_sync(contact, self._FLAGS, None)
            uid = person.uid
        else:
            _ok, uid = self.client.add_contact_sync(contact, self._FLAGS, None)
        return self.get(uid)

    def delete(self, person: Person) -> None:
        self.client.remove_contact_by_uid_sync(person.uid, self._FLAGS, None)

    def watch(self, callback) -> None:
        """Call callback() whenever any app changes the address book."""
        _ok, self._view = self.client.get_view_sync(self._QUERY, None)
        for signal in ("objects-added", "objects-modified", "objects-removed"):
            self._view.connect(signal, lambda *_args: callback())
        self._view.start()
