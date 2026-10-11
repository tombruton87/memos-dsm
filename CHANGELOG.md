# Changelog

## 1.0.0 — 2026-10-11

First release. Memos 0.31 in Container Manager:
- your account is made at the first start as Memos's administrator, with the
  password shown once;
- sign-ups start off: only an administrator adds people;
- attached files are ordinary files in the memos shared folder, in
  `attachments/`;
- a package administrator handles the window's work through Memos's own API.

The DSM window adds:
- **Users:** everyone's memo count and last memo; add people, new passwords
  (shown once), administrator on or off, remove; sign-ups on or off.
- **Attachments:** how many files there are and how much room they take, by
  person; where new files go; the biggest file allowed.
- **Phones:** a QR code of the address, and how to put Memos on the home
  screen.

Also included: backups that copy the database consistently (`sqlite3
.backup`) together with `attachments/`, restore, updates and removal.
