# jinOS mobile (Debian-based, discontinued)

The earlier, Debian-based jinOS for phones and Intel laptops: Plasma Mobile
with jinOS Home, built with mkosi. It is no longer developed; the
from-scratch jinOS is at <https://github.com/wak327/jinos>.

- `image/`: image build (start with `image/README.md`)
- `apps/`: jinOS apps; `shell/`: home screen plugins
- `blueprint.md`, `designs/`, `research/`: early design documents

Development images use the login `jin` / `1234`. Do not expose one to a network
without changing it.

The plugins in `shell/` are GPL-2.0-or-later, as declared in their
`metadata.json`. No licence has been chosen yet for the rest.
