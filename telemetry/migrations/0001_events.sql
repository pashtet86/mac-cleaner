-- Anonymous DevSpace usage events. No IP address, user agent, host name, user name or path is ever stored.
CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    install_id TEXT NOT NULL,          -- random UUID made on the Mac after the user opted in
    event TEXT NOT NULL,               -- first_launch | app_open | cleanup
    day TEXT NOT NULL,                 -- UTC date, YYYY-MM-DD
    app_version TEXT NOT NULL,
    os_version TEXT NOT NULL,
    arch TEXT NOT NULL,                -- arm64 | x86_64
    section TEXT,                      -- cleanup only
    bytes_cleaned INTEGER,             -- cleanup only
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- One first_launch per install and one app_open per install per day; repeats are ignored.
CREATE UNIQUE INDEX events_once_per_day ON events (install_id, event, day) WHERE event IN ('first_launch', 'app_open');
CREATE INDEX events_by_day ON events (event, day);
CREATE INDEX events_by_install ON events (install_id, day);
