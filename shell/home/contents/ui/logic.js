// Plain logic for jinOS Home, kept free of QML so it can be unit-tested
// with node (see ../../tests/logic.test.js).
.pragma library

var DOCK_SIZE = 4;

// Kicker reports apps as "applications:foo.desktop" or "foo.desktop".
function appId(favoriteId) {
    return (favoriteId || "").replace(/^applications:/, "");
}

// Keep the configured order, drop apps that are not installed.
function installed(ids, apps) {
    return (ids || []).filter(function (id) { return apps[id] !== undefined; });
}

function contains(list, id) {
    return (list || []).indexOf(id) >= 0;
}

// Returns a new list with id appended, or the same list if it is already
// there or the list is full (max > 0).
function add(list, id, max) {
    list = (list || []).slice();
    if (contains(list, id) || (max > 0 && list.length >= max)) {
        return list;
    }
    list.push(id);
    return list;
}

function remove(list, id) {
    return (list || []).filter(function (x) { return x !== id; });
}

function parseSeen(json) {
    try {
        var value = JSON.parse(json || "{}");
        return value && typeof value === "object" ? value : {};
    } catch (e) {
        return {};
    }
}

function markSeen(json, id, now) {
    var seen = parseSeen(json);
    seen[id] = now.toISOString();
    return JSON.stringify(seen);
}

// Notifications for an app that arrived after it was last opened from Home.
function unread(notices, seenIso) {
    var since = seenIso ? new Date(seenIso).getTime() : 0;
    return (notices || []).filter(function (n) {
        return new Date(n.created).getTime() > since;
    }).length;
}

// Notification bodies arrive as HTML; badges and previews want plain text.
function plain(text) {
    return (text || "")
        .replace(/<[^>]*>/g, " ")
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
        .replace(/&amp;/g, "&")
        .replace(/\s+/g, " ")
        .trim();
}

// [{desktopEntry, created, summary, body}] -> { "id.desktop": [{created, summary, body}] }
function groupNotices(items) {
    var map = {};
    (items || []).forEach(function (n) {
        if (!n || !n.desktopEntry) {
            return;
        }
        var key = n.desktopEntry + ".desktop";
        (map[key] = map[key] || []).push({
            created: n.created,
            summary: plain(n.summary),
            body: plain(n.body)
        });
    });
    return map;
}

// "Example Web Browser" with generic name "Web Browser" -> "Example": phones
// label icons with the short name. Names that are only the generic name stay.
function shortName(name, genericName) {
    name = name || "";
    var suffix = " " + (genericName || "");
    if (genericName && name.length > suffix.length
            && name.slice(-suffix.length).toLowerCase() === suffix.toLowerCase()) {
        return name.slice(0, -suffix.length).trim();
    }
    return name;
}

// Case-insensitive match on the app name, for the drawer's search.
function matches(name, query) {
    query = (query || "").trim().toLowerCase();
    return query === "" || (name || "").toLowerCase().indexOf(query) >= 0;
}
