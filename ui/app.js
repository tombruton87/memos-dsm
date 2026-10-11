// Memos's tabs on the chassis window: Users, Attachments and Phones.
(function (P) {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function mmUrl(st) { return ((st.app || {}).url || "").replace(/\/$/, ""); }
  function touched(id) { ["input", "change"].forEach(function (e) { $(id).addEventListener(e, function () { $(id).dataset.touched = "1"; }); }); }
  function quiet(id, v) { if (!$(id).dataset.touched) $(id).value = v == null ? "" : v; }
  function people(a) { return (a.users || []).filter(function (u) { return u.user !== a.pkg_admin; }); }
  function links(st) { document.querySelectorAll(".mm-link").forEach(function (x) { x.href = mmUrl(st) || "#"; }); }
  function n(v, one, many) { return v + " " + (v === 1 ? one : many); }

  // ---------------------------------------------------------------- Users
  P.register("users", {
    render: function (st) {
      var a = st.app || {}, list = a.users || [], mine = people(a), t = $("us-tiles"), tb = $("users"); links(st);
      $("us-noapi").hidden = a.api !== false || !a.up;
      P.clear(t); P.tile(t, String(mine.length), mine.length === 1 ? "person" : "people");
      var adm = mine.filter(function (u) { return u.role === "ADMIN"; }).length; P.tile(t, String(adm), adm === 1 ? "administrator" : "administrators"); P.tile(t, String(a.memos || 0), "memos");
      var s = $("us-signups"), b = $("us-signups-btn"); P.clear(s); P.clear(b);
      if (a.signups != null) { s.appendChild(a.signups ? P.chip("on: anyone can make an account", "warn") : P.chip("off: only administrators add people", "ok"));
        b.appendChild(P.btn(a.signups ? "Turn off" : "Turn on", "", function () { P.act("signups", { on: a.signups ? 0 : 1 }, a.signups ? null : "Let anyone who can reach Memos make an account?"); })); }
      $("us-access").textContent = a.access === "INSTANCE_ACCESS_MODE_PUBLIC" ? "Visitors who aren't signed in can read memos marked Public (set in Memos → Settings → System)."
        : a.access ? "Visitors who aren't signed in see only the sign-in page (Memos → Settings → System changes that)." : "";
      var sig = JSON.stringify(list) + "|" + P.busy + "|" + P.role + "|" + a.api; if (tb.dataset.sig === sig) return; tb.dataset.sig = sig; P.clear(tb);
      if (!list.length) { var r0 = P.el("tr"), c0 = P.cell("Nobody yet — your account is made when Memos first answers.", "empty"); c0.colSpan = 5; r0.appendChild(c0); tb.appendChild(r0); }
      list.forEach(function (u) {
        var pkg = u.user === a.pkg_admin, me = u.user === a.admin_user, who = P.el("div"), acts = P.el("span", null, "row");
        who.appendChild(P.el("b", u.user));
        var sub = pkg ? "the package's own administrator" : me ? "you" + (u.name ? " · " + u.name : "") : u.name || "";
        if (u.state === "ARCHIVED") sub = (sub ? sub + " · " : "") + "archived in Memos (can't sign in)";
        if (sub) who.appendChild(P.el("div", sub, "muted small"));
        if (!pkg && a.api !== false) {
          acts.appendChild(P.btn("New password", "", function () { P.act("userpw", { user: u.user }, "Make a new password for " + u.user + "? The old one stops working."); }));
          if (!me) acts.appendChild(u.role === "ADMIN" ? P.btn("Member only", "", function () { P.act("setadmin", { user: u.user, role: "user" }); })
            : P.btn("Make admin", "", function () { P.act("setadmin", { user: u.user, role: "admin" }, "Make " + u.user + " an administrator? They can change Memos's settings."); }));
          if (!me) acts.appendChild(P.btn("Remove", "danger", function () { P.act("userdel", { user: u.user }, "Remove " + u.user + "? Their memos and attached files go too. There is no undo (except a backup)."); }));
        }
        var tr = P.row(tb, [P.cell(who), u.role === "ADMIN" ? P.chip("administrator", "ok") : P.chip("member", ""), P.cell(String(u.memos || 0), "n"), u.last_memo ? P.ago(u.last_memo) : "–", P.cell(acts, "n")]);
        if (pkg || u.state === "ARCHIVED") tr.className = "muted-row";
      });
    }
  });
  P.register("overview", { tiles: function (t, st) { var a = st.app || {}; P.tile(t, String(a.memos || 0), "memos"); P.tile(t, String(people(a).length), people(a).length === 1 ? "person" : "people"); } });
  P.register("secretNote", function (s) { return "Use it to sign in to Memos, then keep it in a password manager (it can be changed in Memos → Settings → My Account)."; });
  $("nu-add").onclick = function () { P.act("useradd", { user: $("nu-name").value.trim(), role: $("nu-role").value }).then(function () { $("nu-name").value = ""; }); };

  // ---------------------------------------------------------------- Attachments
  var WHERE = { LOCAL: "In the memos shared folder, in attachments/ — as ordinary files, included in this package's backups.",
                DATABASE: "Inside Memos's database. They're backed up, but the database grows with every file; Memos → Settings → Storage → Local file system keeps new files in the shared folder instead.",
                S3: "In an S3 bucket elsewhere — not on this Synology, and not in this package's backups." };
  touched("at-limit");
  P.register("attachments", {
    render: function (st) {
      var a = st.app || {}, at = a.attachments || {}, by = at.by_storage || [], f = at.folder || {}, t = $("at-tiles"), s = a.storage;
      var total = by.reduce(function (m, x) { return m + (x.n || 0); }, 0), bytes = by.reduce(function (m, x) { return m + (x.bytes || 0); }, 0);
      $("at-dir").textContent = (at.dir || "attachments") + "/";
      P.clear(t); P.tile(t, String(total), total === 1 ? "attached file" : "attached files"); P.tile(t, P.bytes(bytes), "their size");
      P.tile(t, P.mb(f.mb || 0), "in " + (at.dir || "attachments") + "/"); P.tile(t, P.mb((st.disk || {}).free_mb), "free on the volume");
      var w = $("at-where"); P.clear(w);
      if (s) { w.appendChild(s.type === "LOCAL" ? P.chip("shared folder", "ok") : P.chip(s.type === "DATABASE" ? "database" : "S3" + (s.name ? ": " + s.name : ""), "warn")); w.appendChild(P.el("span", " " + (WHERE[s.type] || s.type))); }
      else w.textContent = "Memos isn't answering the package right now.";
      if (s && s.type === "LOCAL" && s.template && !/^assets\//.test(s.template)) w.appendChild(P.el("div", "Memos's file path template (" + s.template + ") doesn't start with assets/, so new files land inside the data volume instead of the shared folder. Memos → Settings → Storage → Filepath template: assets/{timestamp}_{uuid}_{filename} puts them back.", "note warn"));
      var other = by.filter(function (x) { return x.storage !== "LOCAL"; }), notes = [];
      other.forEach(function (x) { notes.push(n(x.n, "file is", "files are") + " kept " + (x.storage === "DATABASE" ? "in the database" : x.storage === "S3" ? "in S3" : "as links elsewhere") + "."); });
      if (at.unattached) notes.push(n(at.unattached, "uploaded file isn't", "uploaded files aren't") + " attached to any memo.");
      if (f.at) notes.push("The folder holds " + n(f.files || 0, "file", "files") + " (counted " + P.ago(f.at) + ").");
      $("at-other").textContent = notes.join(" ");
      if (s) quiet("at-limit", String(s.limit_mb || 30));
      var tb = $("at-people"); P.clear(tb);
      var list = (a.users || []).filter(function (u) { return u.files; });
      if (!list.length) { var r0 = P.el("tr"), c0 = P.cell("No files attached yet.", "empty"); c0.colSpan = 3; r0.appendChild(c0); tb.appendChild(r0); }
      list.forEach(function (u) { P.row(tb, [P.cell(P.el("b", u.user)), P.cell(String(u.files), "n"), P.cell(P.bytes(u.bytes), "n")]); });
    }
  });
  $("at-limit-save").onclick = function () { P.act("uploadlimit", { mb: $("at-limit").value }).then(function () { $("at-limit").dataset.touched = ""; }); };

  // ---------------------------------------------------------------- Phones
  P.register("phones", {
    render: function (st) {
      var a = st.app || {}, url = a.url || "";
      if (a.qr && $("ph-qr").dataset.qr !== a.qr) { $("ph-qr").src = "data:image/png;base64," + a.qr; $("ph-qr").dataset.qr = a.qr; }
      $("ph-url").textContent = url;
      var home = /^https?:\/\/(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.)/.test(url);
      $("ph-reach").textContent = (home ? "An address on your own network: it works at home. For anywhere else, give Memos an address reachable from outside on the Site address tab. " : "")
        + (/^http:/.test(url) ? "Over plain HTTP the home-screen icon is a shortcut that opens the browser; from an HTTPS address (DSM's reverse proxy, Site address tab) it installs as a full app." : "");
    }
  });

  // ---------------------------------------------------------------- Storage
  P.register("storage", { render: function (app, st, box) {
    P.clear(box); var c = P.el("div", null, "card"); c.appendChild(P.el("h2", "Memos's data")); var tbl = P.el("table"), tb = P.el("tbody"); tbl.appendChild(tb); c.appendChild(tbl);
    [["Database (memos_prod.db), in the data volume", app.database], ["Picture previews (made again when needed)", app.caches], ["Attached files, in the shared folder's attachments/", app.attachments]].forEach(function (p) { P.kv(tb, p[0], P.mb(p[1] || 0), true); });
    box.appendChild(c);
  } });
})(window.Panel);
