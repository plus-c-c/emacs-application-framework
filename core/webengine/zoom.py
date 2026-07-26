#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sqlite3


class ZoomSizeDb(object):
    def __init__(self, dbpath):
        import sqlite3

        if not os.path.exists(os.path.dirname(dbpath)):
            os.makedirs(os.path.dirname(dbpath))

        self._conn = sqlite3.connect(dbpath)
        self._conn.execute("""
        CREATE TABLE IF NOT EXISTS ZoomSize
        (Host TEXT PRIMARY KEY, ZoomScale REAL)
        """)

    def add_entry(self, host, zoom_scale):
        result = self._conn.execute("""
        SELECT Host, ZoomScale FROM ZoomSize
        WHERE Host=?
        """, (host,))
        if len(list(result))>0:
            self._conn.execute("""
            UPDATE ZoomSize SET ZoomScale=?
            WHERE Host=?
            """, (zoom_scale, host))
        else:
            self._conn.execute("""
            INSERT INTO ZoomSize (Host, ZoomScale)
            VALUES (?, ?)
            """, (host, zoom_scale))

        self._conn.commit()

    def get_entry(self, host):
        return self._conn.execute("""
        SELECT ZoomScale FROM ZoomSize
        WHERE Host=?
        """, (host,))

    def delete_entry(self, host):
        self._conn.execute("""
        DELETE FROM ZoomSize
        WHERE Host=?
        """, (host,))
        self._conn.commit()


