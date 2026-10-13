package com.comitfs.openfire.sessionmonitor;

import org.jivesoftware.openfire.event.SessionEventListener;
import org.jivesoftware.openfire.session.Session;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.UnknownHostException;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Captures XMPP client session lifecycle events.
 * <p>
 * Openfire 5.0.0 SessionEventListener provides:
 * sessionCreated, sessionDestroyed, anonymousSessionCreated,
 * anonymousSessionDestroyed and resourceBound.
 */
public class SessionMonitorListener implements SessionEventListener {


    private static final Logger Log = LoggerFactory.getLogger(SessionMonitorListener.class);

    private static final int MAX_EVENTS = 1000;

    /**
     * Bound on the reverse-DNS cache, to prevent unbounded growth on long-running
     * servers that see many distinct client IP addresses.
     */
    private static final int MAX_HOST_ENTRIES = 2048;

    /**
     * Cache of reverse-DNS lookups, keyed by the client IP address. Reverse DNS can
     * block for seconds, so caching keeps it off both the session-event dispatch
     * path (listeners run on core server threads) and repeated page loads.
     */
    private static final Map<String, String> HOST_NAME_CACHE =
            Collections.synchronizedMap(new LinkedHashMap<>(32, 0.75f, true) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<String, String> eldest) {
                    return size() > MAX_HOST_ENTRIES;
                }
            });

    private final Deque<SessionEvent> events = new ArrayDeque<>();

    @Override
    public synchronized void sessionCreated(Session session) {
        record("SESSION_CREATED", session);
    }

    @Override
    public synchronized void sessionDestroyed(Session session) {
        record("SESSION_DESTROYED", session);
    }

    @Override
    public synchronized void anonymousSessionCreated(Session session) {
        record("ANONYMOUS_SESSION_CREATED", session);
    }

    @Override
    public synchronized void anonymousSessionDestroyed(Session session) {
        record("ANONYMOUS_SESSION_DESTROYED", session);
    }

    @Override
    public synchronized void resourceBound(Session session) {
        record("RESOURCE_BOUND", session);
    }

    private void record(String eventType, Session session) {

        SessionEvent event = SessionEvent.from(eventType, session);

        events.addFirst(event);

        while (events.size() > MAX_EVENTS) {
            events.removeLast();
        }

        Log.debug(
                "SESSION_EVENT type={} jid={} ip={} streamId={} status={} " +
                        "created={} lastActive={} encrypted={} tls={} cipher={} " +
                        "clientPackets={} serverPackets={}",
                event.eventType,
                event.address,
                event.hostAddress,
                event.streamId,
                event.status,
                event.creationDate,
                event.lastActiveDate,
                event.encrypted,
                event.tlsProtocol,
                event.cipherSuite,
                event.clientPackets,
                event.serverPackets
        );
    }

    /**
     * Returns a snapshot of the captured events.
     */
    public synchronized List<SessionEvent> getEvents() {
        return new ArrayList<>(events);
    }

    /**
     * Clears the in-memory event history.
     */
    public synchronized void clear() {
        events.clear();
    }

    /**
     * Resolves the reverse-DNS host name for the IP address of the provided session.
     * <p>
     * Reverse-DNS lookups can block for seconds, so results are cached in a bounded
     * LRU cache keyed by the session's IP address. This keeps DNS traffic off the
     * session-event dispatch path (session listeners run on core server threads) and
     * speeds up repeated admin-console page loads.
     *
     * @param session the session to resolve a host name for.
     * @return the resolved host name, or the string {@code UNKNOWN} when the host
     * could not be determined.
     */
    public static String resolveHostName(Session session) {
        String hostAddress;
        try {
            hostAddress = session.getHostAddress();
        } catch (UnknownHostException e) {
            Log.debug("Unable to resolve host address for session {}", session.getAddress(), e);
            return "UNKNOWN";
        }

        synchronized (HOST_NAME_CACHE) {
            final String cached = HOST_NAME_CACHE.get(hostAddress);
            if (cached != null) {
                return cached;
            }
        }

        String hostName;
        try {
            hostName = session.getHostName();
        } catch (UnknownHostException e) {
            Log.debug("Unable to resolve host name for session {}", session.getAddress(), e);
            return "UNKNOWN";
        }
        if (hostName == null || hostName.isEmpty()) {
            return "UNKNOWN";
        }

        synchronized (HOST_NAME_CACHE) {
            HOST_NAME_CACHE.put(hostAddress, hostName);
        }
        return hostName;
    }

    public static final class SessionEvent {

        public final String eventType;
        public final String timestamp;

        public final String address;
        public final String streamId;

        public final String hostAddress;
        public final String hostName;
        public final String serverName;

        public final String status;

        public final String creationDate;
        public final String lastActiveDate;

        public final String language;
        public final String softwareVersion;

        public final long clientPackets;
        public final long serverPackets;

        public final boolean encrypted;
        public final boolean closed;

        public final String tlsProtocol;
        public final String cipherSuite;

        private SessionEvent(
                String eventType,
                String timestamp,
                String address,
                String streamId,
                String hostAddress,
                String hostName,
                String serverName,
                String status,
                String creationDate,
                String lastActiveDate,
                String language,
                String softwareVersion,
                long clientPackets,
                long serverPackets,
                boolean encrypted,
                boolean closed,
                String tlsProtocol,
                String cipherSuite
        ) {
            this.eventType = eventType;
            this.timestamp = timestamp;
            this.address = address;
            this.streamId = streamId;
            this.hostAddress = hostAddress;
            this.hostName = hostName;
            this.serverName = serverName;
            this.status = status;
            this.creationDate = creationDate;
            this.lastActiveDate = lastActiveDate;
            this.language = language;
            this.softwareVersion = softwareVersion;
            this.clientPackets = clientPackets;
            this.serverPackets = serverPackets;
            this.encrypted = encrypted;
            this.closed = closed;
            this.tlsProtocol = tlsProtocol;
            this.cipherSuite = cipherSuite;
        }

        static SessionEvent from(String eventType, Session s) {

            return new SessionEvent(
                    eventType,
                    format(new Date()),

                    safe(s.getAddress()),
                    safe(s.getStreamID()),

                    safeHostAddress(s),
                    resolveHostName(s),

                    safe(s.getServerName()),
                    safe(s.getStatus()),

                    format(s.getCreationDate()),
                    format(s.getLastActiveDate()),

                    safe(s.getLanguage()),
                    safeMap(s.getSoftwareVersion()),

                    s.getNumClientPackets(),
                    s.getNumServerPackets(),

                    s.isEncrypted(),
                    s.isClosed(),

                    safe(s.getTLSProtocolName()),
                    safe(s.getCipherSuiteName())
            );
        }

        private static String format(Date date) {

            if (date == null) {
                return "";
            }

            return new SimpleDateFormat(
                    "yyyy-MM-dd HH:mm:ss.SSS",
                    Locale.ROOT
            ).format(date);
        }

        private static String safe(Object value) {

            return value == null
                    ? ""
                    : String.valueOf(value);
        }

        /**
         * Session.getHostAddress() can throw UnknownHostException.
         */
        private static String safeHostAddress(Session s) {

            try {
                return safe(s.getHostAddress());

            } catch (UnknownHostException e) {

                Log.debug(
                        "Unable to resolve host address for session {}",
                        safe(s.getAddress()),
                        e
                );

                return "UNKNOWN";
            }
        }

        private static String safeMap(Map<String, String> map) {

            return map == null
                    ? ""
                    : map.toString();
        }
    }
}
