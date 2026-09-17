<%@ page import="java.lang.management.ManagementFactory" %>
<%@ page import="java.text.SimpleDateFormat" %>
<%@ page import="java.util.*" %>
<%@ page import="org.jivesoftware.openfire.RoutingTable" %>
<%@ page import="org.jivesoftware.openfire.SessionManager" %>
<%@ page import="org.jivesoftware.openfire.XMPPServer" %>
<%@ page import="org.jivesoftware.openfire.session.ComponentSession" %>
<%@ page import="org.jivesoftware.openfire.session.DomainPair" %>
<%@ page import="org.jivesoftware.openfire.session.IncomingServerSession" %>
<%@ page import="org.jivesoftware.openfire.session.OutgoingServerSession" %>
<%@ page import="org.jivesoftware.openfire.session.ServerSession" %>
<%@ page import="org.jivesoftware.openfire.session.Session" %>
<%@ page import="com.example.openfire.sessionmonitor.ServerInfoLog" %>
<%@ page import="com.example.openfire.sessionmonitor.SessionMonitorPlugin" %>
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

    private String duration(Date start, Date end) {
        if (start == null || end == null) return "";
        long seconds = Math.max(0L, (end.getTime() - start.getTime()) / 1000L);
        long days = seconds / 86400L;
        long hours = (seconds % 86400L) / 3600L;
        long minutes = (seconds % 3600L) / 60L;
        long secs = seconds % 60L;
        if (days > 0) {
            return String.format("%dd %02d:%02d:%02d", days, hours, minutes, secs);
        }
        return String.format("%02d:%02d:%02d", hours, minutes, secs);
    }

    private String durationUntilNow(Date start) {
        return duration(start, new Date());
    }

    private String durationMillis(long millis) {
        long seconds = Math.max(0L, millis / 1000L);
        long days = seconds / 86400L;
        long hours = (seconds % 86400L) / 3600L;
        long minutes = (seconds % 3600L) / 60L;
        long secs = seconds % 60L;
        if (days > 0) {
            return String.format("%dd %02d:%02d:%02d", days, hours, minutes, secs);
        }
        return String.format("%02d:%02d:%02d", hours, minutes, secs);
    }

    private String peerAddress(Session session) {
        try {
            return session.getHostAddress();
        } catch (Exception e) {
            return "";
        }
    }

    private String collectionToString(Collection<?> values) {
        if (values == null || values.isEmpty()) return "";
        List<String> sorted = new ArrayList<>();
        for (Object value : values) {
            if (value != null && !String.valueOf(value).isEmpty()) {
                sorted.add(String.valueOf(value));
            }
        }
        sorted.sort(String.CASE_INSENSITIVE_ORDER);
        return String.join(", ", sorted);
    }
%>

<%
    XMPPServer server = XMPPServer.getInstance();
    org.jivesoftware.openfire.XMPPServerInfo serverInfo = server.getServerInfo();
    Date serverStarted = serverInfo.getLastStarted();
    Date now = new Date();
    Date jvmStart = new Date(System.currentTimeMillis() - ManagementFactory.getRuntimeMXBean().getUptime());

    SessionManager sessionManager = SessionManager.getInstance();
    RoutingTable routingTable = server.getRoutingTable();

    int clientSessionCount = sessionManager.getSessions().size();

    // Outgoing server-to-server sessions. These connections are initiated by
    // THIS server and are used only to send packets to remote servers.
    Map<String, OutgoingServerSession> outgoing = new LinkedHashMap<>();
    Map<String, TreeSet<String>> outgoingRemoteDomains = new LinkedHashMap<>();
    for (DomainPair routePair : routingTable.getServerRoutes()) {
        try {
            OutgoingServerSession outgoingSession = sessionManager.getOutgoingServerSession(routePair);
            if (outgoingSession == null) {
                continue;
            }
            String outgoingStreamId = String.valueOf(outgoingSession.getStreamID());
            if (!outgoing.containsKey(outgoingStreamId)) {
                outgoing.put(outgoingStreamId, outgoingSession);
            }
            outgoingRemoteDomains.computeIfAbsent(outgoingStreamId, key -> new TreeSet<>()).add(routePair.getRemote());
        } catch (Exception ignoredLookup) {
        }
    }

    // Incoming server-to-server sessions. These connections are initiated by
    // remote servers and are used only to receive packets from them.
    Map<String, IncomingServerSession> incoming = new LinkedHashMap<>();
    for (String remoteHost : routingTable.getServerHostnames()) {
        try {
            List<IncomingServerSession> remoteSessions = sessionManager.getIncomingServerSessions(remoteHost);
            if (remoteSessions == null) {
                continue;
            }
            for (IncomingServerSession inboundSession : remoteSessions) {
                if (inboundSession != null) {
                    incoming.putIfAbsent(String.valueOf(inboundSession.getStreamID()), inboundSession);
                }
            }
        } catch (Exception ignoredEnumeration) {
        }
    }

    // External component sessions hosted by this server. The external component
    // dials in to the server and then behaves as a server-side service.
    List<ComponentSession> components = new ArrayList<>(sessionManager.getComponentSessions());
    components.sort(Comparator.comparing(
            c -> String.valueOf(c.getAddress()),
            String.CASE_INSENSITIVE_ORDER));

    // Obtain the running plugin instance, if available.
    SessionMonitorPlugin plugin = null;
    try {
        for (org.jivesoftware.openfire.container.Plugin candidatePlugin : server.getPluginManager().getPlugins()) {
            if (candidatePlugin instanceof SessionMonitorPlugin) {
                plugin = (SessionMonitorPlugin) candidatePlugin;
                break;
            }
        }
    } catch (Exception ignoredPlugin) {
    }

    // Boot/restart history reconstructed from the dedicated server-info.log file.
    // The plugin appends one SERVER_START record on every boot and one SERVER_STOP
    // record on a clean shutdown, so the history survives Openfire restarts.
    ServerInfoLog.HistorySnapshot history = ServerInfoLog.getSnapshot();
    List<ServerInfoLog.ServerBoot> historyBoots = history.serverBoots;

    // Whether the recorded history already contains the boot that is running right now.
    boolean logsHaveCurrentBoot = false;
    if (serverStarted != null && !historyBoots.isEmpty()) {
        ServerInfoLog.ServerBoot lastLoggedBoot = historyBoots.get(historyBoots.size() - 1);
        logsHaveCurrentBoot = lastLoggedBoot.startedAt != null
                && Math.abs(lastLoggedBoot.startedAt.getTime() - serverStarted.getTime()) < 60_000L;
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta name="pageID" content="server-info"/>
    <meta charset="UTF-8"/>
    <title>Server Info</title>
    <style>
        body {
            font-family: Arial, sans-serif;
        }

        .summary {
            margin: 12px 0;
            padding: 12px;
            background: #f5f5f5;
            border: 1px solid #ddd;
            font-size: 14px;
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

        .kv-table td:first-child {
            font-weight: bold;
            background: #fbfbfb;
            width: 260px;
        }

        .small {
            font-size: 11px;
            color: #666;
        }

        .init-server {
            background: #eef8ee;
        }

        .init-remote {
            background: #fffbea;
        }
    </style>
</head>
<body>

<h2>Openfire Server Info &amp; Uptime</h2>

<div class="summary">
    <strong>Server uptime:</strong>
    <%= esc(durationUntilNow(serverStarted)) %>
    &nbsp;&nbsp;|&nbsp;&nbsp;
    <strong>Started at:</strong>
    <%= esc(fmt(serverStarted)) %>
    &nbsp;&nbsp;|&nbsp;&nbsp;
    <strong>Openfire:</strong>
    <%= esc(serverInfo.getVersion()) %>
    &nbsp;&nbsp;|&nbsp;&nbsp;
    <strong>Domain:</strong>
    <%= esc(serverInfo.getXMPPDomain()) %>
    <div class="small">
        Boot/restart history below is read from a dedicated
        <strong>server-info.log</strong> file that the plugin appends to on every start and
        stop. <%= history.recordCount %> record(s) found
        <%= history.truncated ? "&mdash; only the last 256&#8202;KB of the file is read, older records are not shown." : "." %>
        Snapshot cached at <%= esc(fmt(history.scannedAt)) %>.
    </div>
</div>

<h3>Server Details</h3>

<div class="table-wrap">
    <table class="kv-table">
        <tbody>
        <tr>
            <td>XMPP Domain</td>
            <td><%= esc(serverInfo.getXMPPDomain()) %></td>
        </tr>
        <tr>
            <td>Server Hostname</td>
            <td><%= esc(serverInfo.getHostname()) %></td>
        </tr>
        <tr>
            <td>Openfire Version</td>
            <td><%= esc(serverInfo.getVersion()) %></td>
        </tr>
        <tr>
            <td>Server Started At</td>
            <td><%= esc(fmt(serverStarted)) %></td>
        </tr>
        <tr>
            <td>Server Uptime</td>
            <td><strong><%= esc(durationUntilNow(serverStarted)) %></strong></td>
        </tr>
        <tr>
            <td>Current Server Time</td>
            <td><%= esc(fmt(now)) %></td>
        </tr>
        <tr>
            <td>Plugin Loaded At</td>
            <td><%= plugin == null ? "n/a" : esc(fmt(plugin.getStartTime())) %></td>
        </tr>
        <tr>
            <td>Plugin Uptime</td>
            <td><%= plugin == null ? "n/a" : esc(durationMillis(plugin.getUptimeMillis())) %></td>
        </tr>
        <tr>
            <td>Java Version</td>
            <td><%= esc(System.getProperty("java.version")) %></td>
        </tr>
        <tr>
            <td>Java Vendor</td>
            <td><%= esc(System.getProperty("java.vendor")) %></td>
        </tr>
        <tr>
            <td>JVM</td>
            <td><%= esc(System.getProperty("java.vm.name")) %> <%= esc(System.getProperty("java.vm.version")) %></td>
        </tr>
        <tr>
            <td>Operating System</td>
            <td><%= esc(System.getProperty("os.name")) %> <%= esc(System.getProperty("os.version")) %>
                (<%= esc(System.getProperty("os.arch")) %>)
            </td>
        </tr>
        <tr>
            <td>Available Processors</td>
            <td><%= Runtime.getRuntime().availableProcessors() %></td>
        </tr>
        <tr>
            <td>JVM Uptime</td>
            <td><%= esc(duration(jvmStart, now)) %></td>
        </tr>
        <tr>
            <td>Process ID</td>
            <td><%= ProcessHandle.current().pid() %></td>
        </tr>
        </tbody>
    </table>
</div>

<h3>Connection Summary</h3>

<div class="table-wrap">
    <table>
        <thead>
        <tr>
            <th>Connection Type</th>
            <th>Initiated By</th>
            <th>Count</th>
        </tr>
        </thead>
        <tbody>
        <tr>
            <td>Client sessions</td>
            <td>Client</td>
            <td><%= clientSessionCount %></td>
        </tr>
        <tr>
            <td>Outgoing server-to-server sessions (outbound federation)</td>
            <td><strong>This server</strong></td>
            <td><%= outgoing.size() %></td>
        </tr>
        <tr>
            <td>Incoming server-to-server sessions (inbound federation)</td>
            <td>Remote server</td>
            <td><%= incoming.size() %></td>
        </tr>
        <tr>
            <td>External component sessions</td>
            <td>External component</td>
            <td><%= components.size() %></td>
        </tr>
        </tbody>
    </table>
</div>

<h3>Server Restart History (from server-info.log)</h3>

<p class="small">
    The plugin appends a <code>SERVER_START</code> record to
    <code>OPENFIRE_HOME/logs/server-info.log</code> on every server boot and a
    <code>SERVER_STOP</code> record on a clean shutdown. This history therefore survives
    Openfire restarts. Only the single plain <code>server-info.log</code> file is read
    &mdash; rolled/compressed archives are never touched.
</p>

<div class="table-wrap">
    <table>
        <thead>
        <tr>
            <th>#</th>
            <th>Started At</th>
            <th>Uptime</th>
            <th>Stopped At</th>
            <th>Notes</th>
        </tr>
        </thead>
        <tbody>
        <%
            int bootRow = 0;
            if (!logsHaveCurrentBoot && serverStarted != null) {
                bootRow++;
        %>
        <tr>
            <td><%= bootRow %>
            </td>
            <td><%= esc(fmt(serverStarted)) %>
            </td>
            <td><%= esc(durationUntilNow(serverStarted)) %>
            </td>
            <td>&mdash; (running)</td>
            <td>Current boot &mdash; from live Openfire server info</td>
        </tr>
        <%
            }
            for (int bootIndex = historyBoots.size() - 1; bootIndex >= 0; bootIndex--) {
                ServerInfoLog.ServerBoot bootInstance = historyBoots.get(bootIndex);
                Date bootStart = bootInstance.startedAt;
                Date bootStop = bootInstance.stoppedAt;
                boolean bootIsLive = logsHaveCurrentBoot && bootIndex == historyBoots.size() - 1;
                String bootNote = bootIsLive ? "Current boot"
                        : (bootStop == null ? "No stop marker (crash or hard stop)" : "Restarted");
        %>
        <tr>
            <td><%= ++bootRow %>
            </td>
            <td><%= esc(fmt(bootStart)) %>
            </td>
            <td><%= esc(bootIsLive ? durationUntilNow(bootStart)
                    : (bootStop == null ? "n/a" : duration(bootStart, bootStop))) %>
            </td>
            <td><%= bootIsLive ? "&mdash; (running)" : esc(fmt(bootStop)) %>
            </td>
            <td><%= esc(bootNote) %>
            </td>
        </tr>
        <%
            }
            if (bootRow == 0) {
        %>
        <tr>
            <td colspan="5">No server start records found in the logs yet. The current boot
                (from Openfire's live server info) will appear here.
            </td>
        </tr>
        <%
            }
        %>
        </tbody>
    </table>
</div>

<h3>Server-Initiated Connections (Outgoing Server-To-Server)</h3>

<p class="small">
    Sessions on the left-hand "sending" connection of XMPP federation &mdash; this server dialed
    out to these remote servers.
</p>

<div class="table-wrap">
    <table>
        <thead>
        <tr>
            <th>#</th>
            <th>Remote Domain</th>
            <th>Initiated By</th>
            <th>Started At</th>
            <th>Duration</th>
            <th>Status</th>
            <th>Auth Method</th>
            <th>TLS</th>
            <th>Cipher</th>
            <th>Peer IP</th>
            <th>Client Packets</th>
            <th>Server Packets</th>
        </tr>
        </thead>
        <tbody>
        <%
            int row = 0;
            for (Map.Entry<String, OutgoingServerSession> routeEntry : outgoing.entrySet()) {
                OutgoingServerSession outgoingRow = routeEntry.getValue();
                TreeSet<String> remoteDomains = outgoingRemoteDomains.get(routeEntry.getKey());
                ServerSession.AuthenticationMethod authOut = outgoingRow.getAuthenticationMethod();
        %>
        <tr class="init-server">
            <td><%= ++row %>
            </td>
            <td><%= esc(collectionToString(remoteDomains)) %>
            </td>
            <td><strong>This server</strong></td>
            <td><%= esc(fmt(outgoingRow.getCreationDate())) %>
            </td>
            <td><%= esc(durationUntilNow(outgoingRow.getCreationDate())) %>
            </td>
            <td><%= esc(outgoingRow.getStatus()) %>
            </td>
            <td><%= esc(authOut) %>
            </td>
            <td><%= outgoingRow.isEncrypted() %>
            </td>
            <td><%= esc(outgoingRow.getCipherSuiteName()) %>
            </td>
            <td><%= esc(peerAddress(outgoingRow)) %>
            </td>
            <td><%= outgoingRow.getNumClientPackets() %>
            </td>
            <td><%= outgoingRow.getNumServerPackets() %>
            </td>
        </tr>
        <%
            }
            if (outgoing.isEmpty()) {
        %>
        <tr>
            <td colspan="12">No outgoing server-to-server sessions. This server
                has not initiated any outbound federation connections.
            </td>
        </tr>
        <%
            }
        %>
        </tbody>
    </table>
</div>

<h3>Remote-Initiated Connections (Incoming Server-To-Server)</h3>

<p class="small">
    Sessions on the right-hand "receiving" connection of XMPP federation &mdash; remote servers
    dialed in to this server. Note: Openfire only tracks these for remote hosts that are known in
    the routing table, so a purely inbound federation peer may not be listed here.
</p>

<div class="table-wrap">
    <table>
        <thead>
        <tr>
            <th>#</th>
            <th>Remote Server</th>
            <th>Local Domain</th>
            <th>Initiated By</th>
            <th>Status</th>
            <th>Auth Method</th>
            <th>Validated Domains</th>
            <th>Started At</th>
            <th>Duration</th>
            <th>Peer IP</th>
            <th>TLS</th>
            <th>Client Packets</th>
            <th>Server Packets</th>
        </tr>
        </thead>
        <tbody>
        <%
            row = 0;
            for (IncomingServerSession incomingRow : incoming.values()) {
                ServerSession.AuthenticationMethod authIn = incomingRow.getAuthenticationMethod();
        %>
        <tr class="init-remote">
            <td><%= ++row %>
            </td>
            <td><%= esc(incomingRow.getAddress()) %>
            </td>
            <td><%= esc(incomingRow.getLocalDomain()) %>
            </td>
            <td><strong>Remote server</strong></td>
            <td><%= esc(incomingRow.getStatus()) %>
            </td>
            <td><%= esc(authIn) %>
            </td>
            <td><%= esc(collectionToString(incomingRow.getValidatedDomains())) %>
            </td>
            <td><%= esc(fmt(incomingRow.getCreationDate())) %>
            </td>
            <td><%= esc(durationUntilNow(incomingRow.getCreationDate())) %>
            </td>
            <td><%= esc(peerAddress(incomingRow)) %>
            </td>
            <td><%= incomingRow.isEncrypted() %>
            </td>
            <td><%= incomingRow.getNumClientPackets() %>
            </td>
            <td><%= incomingRow.getNumServerPackets() %>
            </td>
        </tr>
        <%
            }
            if (incoming.isEmpty()) {
        %>
        <tr>
            <td colspan="13">No incoming server-to-server sessions are currently established.</td>
        </tr>
        <%
            }
        %>
        </tbody>
    </table>
</div>

<h3>External Component Sessions (Hosted by This Server)</h3>

<p class="small">
    External components (e.g. transports, gateways) that connected to this server and are now
    served by it. The connection itself is established by the external component.
</p>

<div class="table-wrap">
    <table>
        <thead>
        <tr>
            <th>#</th>
            <th>Component Name</th>
            <th>JID</th>
            <th>Category</th>
            <th>Type</th>
            <th>Subdomains</th>
            <th>Initiated By</th>
            <th>Status</th>
            <th>Started At</th>
            <th>Duration</th>
            <th>Peer IP</th>
            <th>TLS</th>
            <th>Client Packets</th>
            <th>Server Packets</th>
        </tr>
        </thead>
        <tbody>
        <%
            row = 0;
            for (ComponentSession componentRow : components) {
                ComponentSession.ExternalComponent external = componentRow.getExternalComponent();
        %>
        <tr>
            <td><%= ++row %>
            </td>
            <td><%= external == null ? "" : esc(external.getName()) %>
            </td>
            <td><%= esc(componentRow.getAddress()) %>
            </td>
            <td><%= external == null ? "" : esc(external.getCategory()) %>
            </td>
            <td><%= external == null ? "" : esc(external.getType()) %>
            </td>
            <td><%= external == null ? "" : esc(collectionToString(external.getSubdomains())) %>
            </td>
            <td><strong>External component</strong></td>
            <td><%= esc(componentRow.getStatus()) %>
            </td>
            <td><%= esc(fmt(componentRow.getCreationDate())) %>
            </td>
            <td><%= esc(durationUntilNow(componentRow.getCreationDate())) %>
            </td>
            <td><%= esc(peerAddress(componentRow)) %>
            </td>
            <td><%= componentRow.isEncrypted() %>
            </td>
            <td><%= componentRow.getNumClientPackets() %>
            </td>
            <td><%= componentRow.getNumServerPackets() %>
            </td>
        </tr>
        <%
            }
            if (components.isEmpty()) {
        %>
        <tr>
            <td colspan="14">No external component sessions are currently established.</td>
        </tr>
        <%
            }
        %>
        </tbody>
    </table>
</div>

<p class="small">
    Refresh the page to obtain a new snapshot. Session counts are a point-in-time view of the
    current server state and reflect local cluster node data only.
    &nbsp;<a href="session-monitor.jsp">View Session Monitor &raquo;</a>
</p>

</body>
</html>