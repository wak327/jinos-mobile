"""Exercise store.py against a throwaway Evolution Data Server.

Never run this against your real address book. tests/run.sh starts a
private session bus and points EDS at temporary folders.
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from jinos_contacts import store as _store  # noqa: E402,F401  (loads the EDS bindings)
from gi.repository import EBookContacts, GLib  # noqa: E402

from jinos_contacts.store import Entry, Person, Store  # noqa: E402

assert os.environ.get("JINOS_TEST_SANDBOX") == "1", "run through tests/run.sh, not directly"

store = Store()
assert store.all() == [], "expected a fresh, empty address book"

changes = []
store.watch(lambda: changes.append(1))

ada = store.save(Person(
    name="Ada Lovelace",
    phones=[Entry("CELL", "+44 20 7946 0018"), Entry("WORK", "020 7946 0999")],
    emails=[Entry("HOME", "ada@example.org")],
    note="Analytical Engine",
))
assert ada.uid
assert [(p.kind, p.value) for p in ada.phones] == [("CELL", "+44 20 7946 0018"), ("WORK", "020 7946 0999")], (ada.phones, ada.contact.to_string(getattr(EBookContacts.VCardFormat, '30')))
assert [(e.kind, e.value) for e in ada.emails] == [("HOME", "ada@example.org")]
assert ada.note == "Analytical Engine"

store.save(Person(name="", phones=[Entry("CELL", "555 0100")]))
people = store.all()
assert [p.display_name for p in people] == ["555 0100", "Ada Lovelace"], [p.display_name for p in people]

# Edit: rename, drop a number, change a kind. Fields we don't edit must survive.
ada.name = "Augusta Ada King"
ada.phones = [Entry("HOME", "+44 20 7946 0018")]
ada.contact.set_property("nickname", "Ada")
ada = store.save(ada)
assert ada.name == "Augusta Ada King"
assert [(p.kind, p.value) for p in ada.phones] == [("HOME", "+44 20 7946 0018")]
assert ada.contact.get_property("nickname") == "Ada", "unedited field was lost"

# Search by name, by digits typed without spaces, and by email.
assert ada.matches("augusta") and ada.matches("2079460018") and ada.matches("example.org")
assert not ada.matches("zzz")

store.delete(ada)
assert [p.display_name for p in store.all()] == ["555 0100"]

# Let the change notifications arrive.
loop_context = GLib.MainContext.default()
for _ in range(50):
    loop_context.iteration(False)
    if len(changes) >= 3:
        break
    GLib.usleep(20000)
assert len(changes) >= 3, f"expected change notifications, got {len(changes)}"

print("store test: PASS")
