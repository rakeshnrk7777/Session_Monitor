package com.example.openfire.sessionmonitor;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * A dedicated, append-only history of server start/stop timestamps.
 * <p>
 * The plugin writes one record per line to {@code OPENFIRE_HOME/logs/server-info.log}:
 *
 * <pre>
 *   SERVER_START|1785331200000|2026-09-11T16:00:00,000|version=5.0.0|domain=example.org
 *   SERVER_STOP|1785337200000|2026-09-11T17:00:00,000
 * </pre>
 *
 * This keeps the boot/restart history independent from the DEBUG-level session log and
 * readable even after the plugin (or Openfire) restarts. Only the single plain
 * {@code server-info.log} file is ever read &mdash; rolled/compressed archives are not
 * touched &mdash; and reads are bounded to the last {@value #MAX_READ_BYTES} bytes so
 * page loads stay cheap. Results are cached for 60 seconds.
 */
public class ServerInfoLog {

    private static final Logger Log = LoggerFactory.getLogger(ServerInfoLog.class);

    private static final String FILE_NAME = "server-info.log";
    private static final String RECORD_START = "SERVER_START";
    private static final String RECORD_STOP = "SERVER_STOP";

    private static final long CACHE_TTL_MILLIS = 60_000L;
    private static final long MAX_READ_BYTES = 256L * 1024L;

    private static volatile HistorySnapshot cached;

    /**
     * One boot of the Openfire server. {@code stoppedAt} is {@code null} while the
     * boot is (or was) still running without a stop record.
     */
    public static final class ServerBoot {

        public final Date startedAt;
        public final Date stoppedAt;

        private ServerBoot(Date startedAt, Date stoppedAt) {
            this.startedAt = startedAt;
            this.stoppedAt = stoppedAt;
        }
    }

    /** Immutable result of reading {@code server-info.log}. */
    public static final class HistorySnapshot {

        /** Boots, ordered from oldest to newest. */
        public final List<ServerBoot> serverBoots;

        /** Number of start/stop records parsed. */
        public final int recordCount;

        /** Timestamp of the oldest record parsed. */
        public final Date oldestRecord;

        /** True when the file was larger than the read bound, so older records were skipped. */
        public final boolean truncated;

        public final Date scannedAt;

        private HistorySnapshot(
                List<ServerBoot> serverBoots,
                int recordCount,
                Date oldestRecord,
                boolean truncated,
                Date scannedAt) {
            this.serverBoots = serverBoots;
            this.recordCount = recordCount;
            this.oldestRecord = oldestRecord;
            this.truncated = truncated;
            this.scannedAt = scannedAt;
        }
    }

    /**
     * Appends a {@code SERVER_START} record. Called once per plugin load, which is once
     * per server boot under normal circumstances.
     */
    public static void recordStart(Date startedAt, String version, String domain) {
        append(RECORD_START, startedAt,
                "version=" + nullSafe(version) + "|domain=" + nullSafe(domain));
    }

    /**
     * Appends a {@code SERVER_STOP} record. Called when the plugin is destroyed, i.e. on
     * a clean server shutdown or when the plugin is unloaded.
     */
    public static void recordStop() {
        append(RECORD_STOP, new Date(), "");
    }

    /**
     * Returns the boot history, re-reading {@code server-info.log} only if the cached
     * snapshot is stale.
     */
    public static HistorySnapshot getSnapshot() {
        final long now = System.currentTimeMillis();

        HistorySnapshot snap = cached;
        if (snap != null && now - snap.scannedAt.getTime() < CACHE_TTL_MILLIS) {
            return snap;
        }

        synchronized (ServerInfoLog.class) {
            snap = cached;
            if (snap != null && now - snap.scannedAt.getTime() < CACHE_TTL_MILLIS) {
                return snap;
            }

            snap = read();
            cached = snap;
            return snap;
        }
    }

    private static void append(String type, Date stamp, String extra) {
        synchronized (ServerInfoLog.class) {
            final File file = logFile();
            try (OutputStreamWriter writer =
                         new OutputStreamWriter(new FileOutputStream(file, true), StandardCharsets.UTF_8)) {
                writer.write(type);
                writer.write('|');
                writer.write(Long.toString(stamp.getTime()));
                writer.write('|');
                writer.write(new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss,SSS", Locale.ROOT).format(stamp));
                if (extra != null && !extra.isEmpty()) {
                    writer.write('|');
                    writer.write(extra);
                }
                writer.write(System.lineSeparator());
                writer.flush();
            } catch (IOException e) {
                Log.warn("Unable to append to '{}'.", file, e);
            }

            cached = null; // invalidate the cached snapshot
        }
    }

    private static File logFile() {
        return new File(org.jivesoftware.util.Log.getLogDirectory(), FILE_NAME);
    }

    private static HistorySnapshot read() {
        final File file = logFile();

        final List<ServerBoot> boots = new ArrayList<>();
        Date oldestRecord = null;
        int recordCount = 0;

        if (!file.isFile() || file.length() <= 0) {
            return new HistorySnapshot(boots, 0, null, false, new Date());
        }

        final boolean truncated = file.length() > MAX_READ_BYTES;

        try (BufferedReader reader = tailReader(file)) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isEmpty()) {
                    continue;
                }

                final String[] parts = line.split("\\|");
                if (parts.length < 2) {
                    continue;
                }

                final Date stamp = parseEpochMillis(parts[1]);
                if (stamp == null) {
                    continue;
                }
                recordCount++;
                if (oldestRecord == null || stamp.before(oldestRecord)) {
                    oldestRecord = stamp;
                }

                if (RECORD_START.equals(parts[0])) {
                    addBoot(boots, stamp);
                } else if (RECORD_STOP.equals(parts[0])) {
                    stopBoot(boots, stamp);
                }
            }
        } catch (IOException e) {
            Log.warn("Unable to read '{}'.", file, e);
        }

        return new HistorySnapshot(boots, recordCount, oldestRecord, truncated, new Date());
    }

    /**
     * Opens the log file but only exposes its final {@value #MAX_READ_BYTES} bytes
     * (skipping a partial first line), so reading never scans a big history.
     */
    private static BufferedReader tailReader(File file) throws IOException {
        final long size = file.length();
        final long keepFrom = Math.max(0L, size - MAX_READ_BYTES);

        if (keepFrom == 0L) {
            return new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8));
        }

        long start = keepFrom;
        try (RandomAccessFile raf = new RandomAccessFile(file, "r")) {
            raf.seek(start);
            while (start < size) {
                final int b = raf.read();
                start++;
                if (b == -1 || b == '\n') {
                    break;
                }
            }
        }

        final FileInputStream in = new FileInputStream(file);
        in.skipNBytes(start);
        return new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8));
    }

    /**
     * Adds a new boot, deduplicating start records that refer to the same boot (for
     * example when the plugin is reloaded within a single server run).
     */
    private static void addBoot(List<ServerBoot> boots, Date startedAt) {
        if (!boots.isEmpty()) {
            final ServerBoot last = boots.get(boots.size() - 1);
            if (last.stoppedAt == null && Math.abs(last.startedAt.getTime() - startedAt.getTime()) < 2_000L) {
                return;
            }
        }
        boots.add(new ServerBoot(startedAt, null));
    }

    /** Attaches a stop timestamp to the most recent boot that has none yet. */
    private static void stopBoot(List<ServerBoot> boots, Date stoppedAt) {
        for (int i = boots.size() - 1; i >= 0; i--) {
            final ServerBoot boot = boots.get(i);
            if (boot.stoppedAt == null) {
                boots.set(i, new ServerBoot(boot.startedAt, stoppedAt));
                return;
            }
        }
    }

    private static Date parseEpochMillis(String value) {
        try {
            return new Date(Long.parseLong(value));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static String nullSafe(Object value) {
        return value == null ? "" : String.valueOf(value);
    }

    private ServerInfoLog() {
    }
}