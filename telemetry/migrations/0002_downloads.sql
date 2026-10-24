-- Website downloads, counted by the site Worker's /download link. One counter per day and version:
-- no IP address, user agent, referrer or cookie is ever stored.
CREATE TABLE downloads (
    day TEXT NOT NULL,                 -- UTC date, YYYY-MM-DD
    version TEXT NOT NULL,             -- app version of the DMG served
    count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (day, version)
);
