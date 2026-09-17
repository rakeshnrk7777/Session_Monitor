<%@ page import="java.text.SimpleDateFormat" %>
<%@ page import="java.util.*" %>
<%@ page import="org.jivesoftware.openfire.SessionManager" %>
<%@ page import="org.jivesoftware.openfire.session.ClientSession" %>
<%@ page import="org.jivesoftware.openfire.session.Session" %>
<%@ page import="com.example.openfire.sessionmonitor.SessionMonitorListener" %>
<%@ taglib uri="admin" prefix="admin" %>

<%!
    private String esc(Object value) {
        if (value == null) return "";
        String s = String.valueOf(value);
        return s.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String fmt(Date value) {
        if (value == null) return "";
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS").format(value);
    }

    private String hostName(Session session) {
        return SessionMonitorListener.resolveHostName(session);
    }

    private String hostAddress(Session session) {
        try {
            return session.getHostAddress();
        } catch (Exception e) {
            return "";
        }
    }

    private String duration(Date created) {
        if (created == null) return "";
        long seconds = Math.max(0L, (System.currentTimeMillis() - created.getTime()) / 1000L);
        long h = seconds / 3600;
        long m = (seconds % 3600) / 60;
        long s = seconds % 60;
        return String.format("%02d:%02d:%02d", h, m, s);
    }

    private String presenceInfo(ClientSession session) {
        try {
            Object presence = session.getPresence();
            return presence == null ? "" : presence.toString();
        } catch (Exception e) {
            return "";
        }
    }

    private String username(ClientSession session) {
        try {
            return session.getUsername();
        } catch (Exception e) {
            return "";
        }
    }
%>

<%
    SessionMonitorListener monitor = null;

    // Obtain the plugin listener from the running plugin instance.
    try {
        for (org.jivesoftware.openfire.container.Plugin plugin :
                org.jivesoftware.openfire.XMPPServer.getInstance()
                        .getPluginManager().getPlugins()) {
            if (plugin instanceof com.example.openfire.sessionmonitor.SessionMonitorPlugin) {
                monitor = ((com.example.openfire.sessionmonitor.SessionMonitorPlugin) plugin).getListener();
                break;
            }
        }
    } catch (Exception ignored) {
        // The current-session table remains available even if event history
        // cannot be obtained.
    }

    Collection<ClientSession> sessions =
            SessionManager.getInstance().getSessions();

    List<ClientSession> sortedSessions = new ArrayList<>(sessions);
    sortedSessions.sort(Comparator.comparing(
            s -> String.valueOf(s.getAddress()),
            String.CASE_INSENSITIVE_ORDER));

    List<SessionMonitorListener.SessionEvent> events =
            monitor == null ? Collections.emptyList() : monitor.getEvents();
%>

<!DOCTYPE html>
<html>
<head>
    <meta name="pageID" content="session-monitor"/>
    <meta charset="UTF-8"/>
    <title>Session Monitor</title>
    <style>
        body {
            font-family: Arial, sans-serif;
        }

        .summary {
            margin: 12px 0;
            padding: 12px;
            background: #f5f5f5;
            border: 1px solid #ddd;
        }

        .table-wrap {
            overflow-x: auto;
        }

        table {
            border-collapse: collapse;
            width: 100%;
            font-size: 12px;
        }

        th, td {
            border: 1px solid #ddd;
            padding: 6px;
            vertical-align: top;
            white-space: nowrap;
        }

        th {
            background: #eee;
            position: sticky;
            top: 0;
        }

        .small {
            font-size: 11px;
            color: #666;
        }

        .event-created {
            background: #eef8ee;
        }

        .event-destroyed {
            background: #fff0f0;
        }

        .event-other {
            background: #fffbea;
        }
    </style>
</head>
<body>

<h2>Openfire Client Session Monitor</h2>

<div class="summary">
    <strong>Current authenticated client sessions:</strong>
    <%= sortedSessions.size() %>
    &nbsp;&nbsp;|&nbsp;&nbsp;
    <strong>Captured lifecycle events:</strong>
    <%= events.size() %>
    <div class="small">
        SessionManager state is transient and represents current server state.
        Lifecycle history in this plugin is bounded to the last 1000 events.
    </div>
</div>

<h3>Current Client Sessions</h3>

<div class="table-wrap">
    <table>
        <thead>
        <tr>
            <th>#</th>
            <th>JID</th>
            <th>Username</th>
            <th>Resource</th>
            <th>Stream ID</th>
            <th>Client IP</th>
            <th>Client Host</th>
            <th>Status</th>
            <th>Authenticated</th>
            <th>Encrypted</th>
            <th>TLS Protocol</th>
            <th>Cipher</th>
            <th>Created</th>
            <th>Last Active</th>
            <th>Duration</th>
            <th>Language</th>
            <th>Client Packets</th>
            <th>Server Packets</th>
            <th>Software Version</th>
            <th>Presence</th>
            <th>Closed</th>
            <th>Detached</th>
        </tr>
        </thead>
        <tbody>
        <%
            int row = 0;
            for (ClientSession clientSession : sortedSessions) {
                String jid = String.valueOf(clientSession.getAddress());
                String resource = "";
                try {
                    resource = clientSession.getAddress().getResource();
                } catch (Exception ignored) {
                }

                String software = "";
                try {
                    software = String.valueOf(clientSession.getSoftwareVersion());
                } catch (Exception ignored) {
                }

                String rowClass = clientSession.isClosed() ? "event-destroyed" : "";
        %>
        <tr class="<%= rowClass %>">
            <td><%= ++row %>
            </td>
            <td><%= esc(jid) %>
            </td>
            <td><%= esc(username(clientSession)) %>
            </td>
            <td><%= esc(resource) %>
            </td>
            <td><%= esc(clientSession.getStreamID()) %>
            </td>
            <td><%= esc(hostAddress(clientSession)) %>
            </td>
            <td><%= esc(hostName(clientSession)) %>
            </td>
            <td><%= esc(clientSession.getStatus()) %>
            </td>
            <td><%= clientSession.isAuthenticated() %>
            </td>
            <td><%= clientSession.isEncrypted() %>
            </td>
            <td><%= esc(clientSession.getTLSProtocolName()) %>
            </td>
            <td><%= esc(clientSession.getCipherSuiteName()) %>
            </td>
            <td><%= esc(fmt(clientSession.getCreationDate())) %>
            </td>
            <td><%= esc(fmt(clientSession.getLastActiveDate())) %>
            </td>
            <td><%= esc(duration(clientSession.getCreationDate())) %>
            </td>
            <td><%= esc(clientSession.getLanguage()) %>
            </td>
            <td><%= clientSession.getNumClientPackets() %>
            </td>
            <td><%= clientSession.getNumServerPackets() %>
            </td>
            <td><%= esc(software) %>
            </td>
            <td style="max-width:400px; white-space:normal"><%= esc(presenceInfo(clientSession)) %>
            </td>
            <td><%= clientSession.isClosed() %>
            </td>
            <td><%= clientSession.isDetached() %>
            </td>
        </tr>
        <%
            }
            if (sortedSessions.isEmpty()) {
        %>
        <tr>
            <td colspan="22">No authenticated client sessions are currently connected.</td>
        </tr>
        <%
            }
        %>
        </tbody>
    </table>
</div>

<h3>Recent Session Lifecycle Events</h3>

<div class="table-wrap">
    <table>
        <thead>
        <tr>
            <th>Time</th>
            <th>Event</th>
            <th>JID</th>
            <th>IP</th>
            <th>Stream ID</th>
            <th>Status</th>
            <th>Created</th>
            <th>Last Active</th>
            <th>Encrypted</th>
            <th>TLS</th>
            <th>Cipher</th>
            <th>Client Packets</th>
            <th>Server Packets</th>
            <th>Software Version</th>
        </tr>
        </thead>
        <tbody>
        <%
            for (SessionMonitorListener.SessionEvent event : events) {
                String cls = event.eventType.contains("DESTROYED")
                        ? "event-destroyed"
                        : event.eventType.contains("CREATED")
                        ? "event-created"
                        : "event-other";
        %>
        <tr class="<%= cls %>">
            <td><%= esc(event.timestamp) %>
            </td>
            <td><strong><%= esc(event.eventType) %>
            </strong></td>
            <td><%= esc(event.address) %>
            </td>
            <td><%= esc(event.hostAddress) %>
            </td>
            <td><%= esc(event.streamId) %>
            </td>
            <td><%= esc(event.status) %>
            </td>
            <td><%= esc(event.creationDate) %>
            </td>
            <td><%= esc(event.lastActiveDate) %>
            </td>
            <td><%= event.encrypted %>
            </td>
            <td><%= esc(event.tlsProtocol) %>
            </td>
            <td><%= esc(event.cipherSuite) %>
            </td>
            <td><%= event.clientPackets %>
            </td>
            <td><%= event.serverPackets %>
            </td>
            <td><%= esc(event.softwareVersion) %>
            </td>
        </tr>
        <%
            }
            if (events.isEmpty()) {
        %>
        <tr>
            <td colspan="14">No lifecycle events have been captured since the plugin started.</td>
        </tr>
        <%
            }
        %>
        </tbody>
    </table>
</div>

<p class="small">
    Refresh the page to obtain a new snapshot. Event history is kept in memory only
    and is cleared when the plugin or Openfire restarts.
</p>

</body>
</html>