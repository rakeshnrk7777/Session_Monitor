package com.example.openfire.sessionmonitor;

import org.jivesoftware.openfire.container.Plugin;
import org.jivesoftware.openfire.container.PluginManager;
import org.jivesoftware.openfire.event.SessionEventDispatcher;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;

/**
 * Openfire 5.0.0 client session monitor.
 *
 * Registers a SessionEventListener and keeps a bounded in-memory event history.
 * Current sessions are always read directly from Openfire's SessionManager.
 */
public class SessionMonitorPlugin implements Plugin {
    private static final Logger Log = LoggerFactory.getLogger(SessionMonitorPlugin.class);

    private SessionMonitorListener listener;
    private File pluginDirectory;

    @Override
    public void initializePlugin(PluginManager pluginManager, File pluginDirectory) {
        this.pluginDirectory = pluginDirectory;
        this.listener = new SessionMonitorListener();

        SessionEventDispatcher.addListener(listener);

        Log.info("Openfire Session Monitor started. Plugin directory: {}", pluginDirectory);
    }

    @Override
    public void destroyPlugin() {
        if (listener != null) {
            SessionEventDispatcher.removeListener(listener);
            listener.clear();
            listener = null;
        }

        Log.info("Openfire Session Monitor stopped.");
    }

    public File getPluginDirectory() {
        return pluginDirectory;
    }

    public SessionMonitorListener getListener() {
        return listener;
    }
}
