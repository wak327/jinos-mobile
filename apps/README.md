# jinOS apps

The home screen lives in `../shell/home` (jinOS Home, a Plasma Mobile plugin).

Python + GTK4/libadwaita apps built into the jinOS image, styled with
`jinos_ui` (see `jinos_ui/README.md`).

Each app has its own folder with an `install.sh` that installs it into a
root directory. The image build mounts this folder (`BuildSources=` in
`../image/mkosi.conf`) and `../image/scripts/postinst.chroot` runs every
app's installer, so a new app needs no image changes.

Desktop files must include `X-Purism-FormFactor=Workstation;Mobile;`,
or Phosh hides the app behind "Show All Apps".

| App | Folder | Status |
|---|---|---|
| jinos_ui | `jinos_ui/` | Done: shared look and helpers, used by both apps |
| About Phone | `about/` | Done: device info and hardware detection, Device / Hardware tabs; verified in the VM |
| Contacts | `contacts/` | Done: A-Z list, search, add, edit, delete on Evolution Data Server, Call/Message/Email quick actions; verified in the VM |
| Gallery | | Next |
| Settings | | Planned |
| Dialer, SMS | | GNOME Calls and Chatty for now (see `../image/README.md`) |
| Camera | | Planned; phone only |
| Welcome | | Planned |

## About Phone

    python3 -m jinos_about.probes    # run the hardware checks in a terminal (from about/)

Checks use only the Python standard library, no GTK, so they can grow
into the `hwtest` tool from the blueprint.

## Contacts

Stores contacts in Evolution Data Server, the GNOME address book, so
GNOME Calls, Chatty and later jinOS's own dialer and SMS apps can show
names. Call, message and email buttons open `tel:`, `sms:` and `mailto:`
links; until an app handles them, Contacts says so.

    contacts/tests/run.sh    # storage tests against a private, throwaway EDS

The test starts its own session bus and data folders, so it never touches
a real address book. On a host without the EDS Python bindings, set
`GI_TYPELIB_PATH` to typelibs copied from a jinOS image.

The window opens at once with "Loading Contacts"; the address book connects
in the background (`Store.open`), because starting the service can take
tens of seconds the first time.

## Testing an app without a VM

    tests/run-headless.sh about
    tests/run-headless.sh contacts --seed    # with three sample contacts

Runs the app with GTK's Broadway backend: open http://127.0.0.1:8085 in a
browser. It gets its own session bus and temporary folders, so Contacts
uses a throwaway address book. Good for layout and navigation. Typing does
not reach the app this way, and buttons on pages pushed after the first
one stopped responding in testing; test those in the VM.
