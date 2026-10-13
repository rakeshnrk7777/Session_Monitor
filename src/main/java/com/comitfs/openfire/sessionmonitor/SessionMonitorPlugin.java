package com.comitfs.openfire.sessionmonitor;

import org.jivesoftware.openfire.XMPPServer;
import org.jivesoftware.openfire.container.Plugin;
import org.jivesoftware.openfire.container.PluginManager;
import org.jivesoftware.openfire.event.SessionEventDispatcher;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * Openfire 5.0.0 client session monitor.
 * <p>
 * Registers a SessionEventListener and keeps a bounded in-memory event history.
 * Current sessions are always read directly from Openfire's SessionManager.
 * <p>
 * The exact moment the plugin was loaded is also tracked, so the admin-console
 * "Server Info" page can show how long both Openfire and this plugin have been up.
 */
public class SessionMonitorPlugin implements Plugin {
    private static final Logger Log = LoggerFactory.getLogger(SessionMonitorPlugin.class);

    private SessionMonitorListener listener;

    /**
     * Epoch millis at which this plugin instance was constructed (i.e. loaded).
     */
    private final long startTimeMillis;

    public SessionMonitorPlugin() {
        this.startTimeMillis = System.currentTimeMillis();
    }

    @Override
    public void initializePlugin(PluginManager pluginManager, File pluginDirectory) {
        this.listener = new SessionMonitorListener();

        SessionEventDispatcher.addListener(listener);

        Log.info(
                "Openfire Session Monitor plugin loaded at {}.",
                format(new Date(startTimeMillis))
        );

        final org.jivesoftware.openfire.XMPPServerInfo serverInfo = XMPPServer.getInstance().getServerInfo();
        final Date serverStarted = serverInfo.getLastStarted();
        if (serverStarted != null) {
            Log.info(
                    "Openfire server started at {} (uptime {}).",
                    format(serverStarted),
                    formatUptime(serverStarted.getTime())
            );
        }
        // Record this boot in the dedicated server-info.log so the restart history
        // survives even after a server or plugin restart. The timestamp of the
        // current boot comes from Openfire itself; the plugin load time is used
        // as a fallback.
        ServerInfoLog.recordStart(
                serverStarted != null ? serverStarted : new Date(startTimeMillis),
                String.valueOf(serverInfo.getVersion()),
                serverInfo.getXMPPDomain()
        );
    }

    @Override
    public void destroyPlugin() {
        if (listener != null) {
            SessionEventDispatcher.removeListener(listener);
            listener.clear();
            listener = null;
        }

        Log.info(
                "Openfire Session Monitor stopped (was loaded for {}).",
                formatUptime(startTimeMillis)
        );
        // Record the boot's stop time in server-info.log (written on clean
        // shutdowns and when the plugin is unloaded).
        ServerInfoLog.recordStop();
    }

    public SessionMonitorListener getListener() {
        return listener;
    }

    /**
     * Returns the moment this plugin was loaded.
     *
     * @return the plugin start time, never {@code null}.
     */
    public Date getStartTime() {
        return new Date(startTimeMillis);
    }

    /**
     * Returns how long this plugin has been loaded, in milliseconds.
     *
     * @return the plugin uptime in milliseconds.
     */
    public long getUptimeMillis() {
        return System.currentTimeMillis() - startTimeMillis;
    }

    private static String format(Date date) {
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT).format(date);
    }

    private static String formatUptime(long startMillis) {
        long seconds = Math.max(0L, (System.currentTimeMillis() - startMillis) / 1000L);
        long days = seconds / 86400L;
        long hours = (seconds % 86400L) / 3600L;
        long minutes = (seconds % 3600L) / 60L;
        long secs = seconds % 60L;
        return String.format("%d days, %02d:%02d:%02d", days, hours, minutes, secs);
    }
}
