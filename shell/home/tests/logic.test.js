// Unit tests for contents/ui/logic.js. Run: node --test tests/*.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

// logic.js is a QML JavaScript library; drop the QML-only pragma and load it.
const source = fs.readFileSync(path.join(__dirname, "../contents/ui/logic.js"), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
// Same realm as the tests, so deepStrictEqual compares like with like.
const names = [...source.matchAll(/^function (\w+)/gm)].map(m => m[1]).concat(["DOCK_SIZE"]);
const L = new Function(source + "\nreturn {" + names.join(", ") + "};")();

test("appId strips the kicker prefix", () => {
    assert.equal(L.appId("applications:org.jinos.Contacts.desktop"), "org.jinos.Contacts.desktop");
    assert.equal(L.appId("org.gnome.Console.desktop"), "org.gnome.Console.desktop");
    assert.equal(L.appId(undefined), "");
});

test("installed keeps order and drops missing apps", () => {
    const apps = { "a.desktop": {}, "c.desktop": {} };
    assert.deepEqual(L.installed(["c.desktop", "b.desktop", "a.desktop"], apps), ["c.desktop", "a.desktop"]);
    assert.deepEqual(L.installed(undefined, apps), []);
});

test("add appends once and respects the dock size", () => {
    assert.deepEqual(L.add(["a"], "b", 0), ["a", "b"]);
    assert.deepEqual(L.add(["a", "b"], "a", 0), ["a", "b"]);
    assert.deepEqual(L.add(["a", "b", "c", "d"], "e", L.DOCK_SIZE), ["a", "b", "c", "d"]);
    const original = ["a"];
    L.add(original, "b", 0);
    assert.deepEqual(original, ["a"], "add must not modify its input");
});

test("remove drops the id", () => {
    assert.deepEqual(L.remove(["a", "b", "a"], "a"), ["b"]);
    assert.deepEqual(L.remove(undefined, "a"), []);
});

test("seen times survive bad JSON", () => {
    assert.deepEqual(L.parseSeen("not json"), {});
    assert.deepEqual(L.parseSeen("null"), {});
    const json = L.markSeen("garbage", "x.desktop", new Date("2026-10-03T10:00:00Z"));
    assert.equal(L.parseSeen(json)["x.desktop"], "2026-10-03T10:00:00.000Z");
});

test("unread counts only notifications after the app was opened", () => {
    const notices = [
        { created: new Date("2026-10-03T10:05:00Z") },
        { created: new Date("2026-10-03T09:55:00Z") },
    ];
    assert.equal(L.unread(notices, undefined), 2);
    assert.equal(L.unread(notices, "2026-10-03T10:00:00Z"), 1);
    assert.equal(L.unread(notices, "2026-10-03T11:00:00Z"), 0);
    assert.equal(L.unread(undefined, undefined), 0);
});

test("plain removes HTML and entities", () => {
    assert.equal(L.plain('<?xml version="1.0"?><html>Missed &amp; <b>call</b></html>'), "Missed & call");
    assert.equal(L.plain(undefined), "");
});

test("groupNotices groups by desktop entry and skips anonymous ones", () => {
    const map = L.groupNotices([
        { desktopEntry: "org.jinos.Contacts", created: 1, summary: "Ada", body: "<b>Missed</b>" },
        { desktopEntry: "", created: 2, summary: "x", body: "" },
        { desktopEntry: "org.jinos.Contacts", created: 3, summary: "Alan", body: "" },
    ]);
    assert.deepEqual(Object.keys(map), ["org.jinos.Contacts.desktop"]);
    assert.equal(map["org.jinos.Contacts.desktop"].length, 2);
    assert.equal(map["org.jinos.Contacts.desktop"][0].body, "Missed");
});

test("matches is case-insensitive and empty matches everything", () => {
    assert.equal(L.matches("Contacts", "CON"), true);
    assert.equal(L.matches("Contacts", "  "), true);
    assert.equal(L.matches("Settings", "con"), false);
});

test("shortName drops a trailing generic name", () => {
    assert.equal(L.shortName("Chromium Web Browser", "Web Browser"), "Chromium");
    assert.equal(L.shortName("Firefox web browser", "Web Browser"), "Firefox");
    assert.equal(L.shortName("Web Browser", "Web Browser"), "Web Browser");
    assert.equal(L.shortName("Contacts", "Address Book"), "Contacts");
    assert.equal(L.shortName("Console", ""), "Console");
    assert.equal(L.shortName(undefined, undefined), "");
});
