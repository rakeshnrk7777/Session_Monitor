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

## Build

Requires JDK 17 and Maven.

```bash
mvn clean package
```

The Openfire plugin assembly is generated in `target/`. The exact assembly filename depends on the Openfire parent build.

Rename the generated plugin assembly to:

```text
session-monitor.jar
```

and copy it to:

```text
OPENFIRE_HOME/plugins/
```

Restart Openfire or use the Openfire plugin manager.

## Admin Console

The plugin adds:

```text
Server -> Server Settings -> Session Monitor
```

The page is:

```text
/plugins/session-monitor/session-monitor.jsp
```

## Important

The SessionManager current-session inventory is transient and is not historical. The plugin's event history is also in-memory and intentionally bounded to 1000 events.

For a persistent audit trail, the next version should write lifecycle events to a database or JSON/CSV log.

## Openfire 5.0.0 note

Openfire 5.0.0 upgraded its embedded web server to Jetty 12. The project therefore uses the Openfire 5.0.0 parent POM and the `org.eclipse.jetty.ee8:jetty-ee8-jspc-maven-plugin` JSP compiler.
