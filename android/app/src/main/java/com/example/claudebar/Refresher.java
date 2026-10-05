package com.example.claudebar;

import android.content.Context;

import java.util.List;

/** One refresh cycle: fetch usage, update the status-bar notification. Call off the main thread. */
final class Refresher {
    /** @return null on success, otherwise a short message for the UI. */
    static String run(Context ctx) {
        TokenStore store = new TokenStore(ctx);
        if (!store.connected()) { StatusNotifier.clear(ctx); return "Not connected."; }
        try {
            List<UsageClient.Window> w = UsageClient.fetch(store);
            StatusNotifier.show(ctx, w, false);
            return null;
        } catch (UsageClient.AuthExpired e) {
            store.clear();
            StatusNotifier.clear(ctx);
            return "Session expired - reconnect your account.";
        } catch (Exception e) {
            return "Refresh failed: " + e.getMessage(); // keep last notification (it stays as-is)
        }
    }
}
