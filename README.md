# Openfire Session Monitor

Openfire 5.0.0 plugin that provides:

- Current authenticated client session inventory.
- JID, username and resource.
- Stream ID.
- Client IP/hostname and TCP ports.
- Session status.
- Authentication state.
- Encryption/TLS protocol/cipher.
- Creation and last-active timestamps.
- Session duration.
- Client/server packet counters.
- Language.
- XEP-0092 software-version information.
- Presence.
- Detached/closed state.
- Session lifecycle events:
  - SESSION_CREATED
  - SESSION_DESTROYED
  - ANONYMOUS_SESSION_CREATED
  - ANONYMOUS_SESSION_DESTROYED
  - RESOURCE_BOUND
- Lifecycle events are also written to `openfire.log`.
- Last 1000 lifecycle events are retained in memory.
- Server uptime / start time and "who initiated the connection" overview on a
  dedicated Server Info admin page.
- Historical data survives restarts: the plugin appends `SERVER_START` /
  `SERVER_STOP` records to a dedicated `OPENFIRE_HOME/logs/server-info.log` on
  every boot and clean shutdown, and the Server Info page reads that single
  plain file (never rolled `.log.zip` archives) to show the server's
  boot/restart timestamp history (cached for 60 s).

## Build

Requires JDK 17 and Maven.

```bash
mvn clean package
```

The project follows the Openfire plugin layout: `src/main/java` for sources, a compile
output directory of `classes/`, and `web/` for the admin-console JSP page. The Openfire
plugin assembly is generated in `target/`:

```text
target/session-monitor-openfire-plugin-assembly.jar
```

Rename the generated plugin assembly to:

```text
session-monitor.jar
```

and copy it to:

```text
OPENFIRE_HOME/plugins/
```

Restart Openfire or use the Openfire plugin manager.

> The Maven artifact is `session-monitor`; the `plugin.name` build property (used by the
> Openfire parent POM for the precompiled-JSP servlet package) is `sessionmonitor`,
> because Java package names may not contain dashes.

## Admin Console

The plugin adds:

```text
Server -> Server Settings -> Session Monitor
```

The page is:

```text
/plugins/session-monitor/session-monitor.jsp
```

## Logging

Openfire 5.0.0 detects a per-plugin Log4j2 configuration at `classes/log4j2.xml`
(bundled with this plugin) and uses it as a dedicated logger context for the
plugin's classes. This plugin therefore writes to:

```text
OPENFIRE_HOME/logs/session-monitor.log
```

Session lifecycle events are logged at DEBUG level (they are demoted from INFO
so they do not flood the server's main log). The log file rolls at 10 MB and up
to 50 rolled files are kept, mirroring the Openfire XML debugger configuration.

To make the plugin log through the server's default logging configuration
instead, delete `classes/log4j2.xml` from the installed plugin directory and
restart Openfire.

## Important

The SessionManager current-session inventory is transient and is not historical. The plugin's event history is also in-memory and intentionally bounded to 1000 events.

For a persistent audit trail, the next version should write lifecycle events to a database or JSON/CSV log.

## Openfire 5.0.0 note

Openfire 5.0.0 upgraded its embedded web server to Jetty 12. The project therefore uses the Openfire 5.0.0 parent POM and the `org.eclipse.jetty.ee8:jetty-ee8-jspc-maven-plugin` JSP compiler.
