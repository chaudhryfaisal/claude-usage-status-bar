package com.example.claudebar;

import org.json.JSONObject;

import java.net.HttpURLConnection;
import java.net.URL;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.TreeSet;

/** Fetches /api/oauth/usage and parses the limit windows. */
final class UsageClient {
    static final class Window {
        final String id, label;
        final double utilization; // 0-100 used
        final long resetsAtMs;    // 0 if unknown
        Window(String id, String label, double u, long r) { this.id = id; this.label = label; utilization = u; resetsAtMs = r; }
        int remaining() { return (int) Math.max(0, Math.min(100, Math.round(100 - utilization))); }
    }

    static final class AuthExpired extends Exception {}

    private static final String[][] KNOWN = {
            {"five_hour", "Session (5h)"}, {"seven_day", "Weekly"}, {"seven_day_opus", "Weekly Opus"}};

    static List<Window> fetch(TokenStore store) throws Exception {
        if (!store.connected()) throw new AuthExpired();
        if (store.needsRefresh()) OAuth.refresh(store);

        HttpURLConnection c = (HttpURLConnection) new URL("https://api.anthropic.com/api/oauth/usage").openConnection();
        c.setConnectTimeout(15000);
        c.setReadTimeout(15000);
        c.setRequestProperty("Authorization", "Bearer " + store.access());
        c.setRequestProperty("anthropic-beta", "oauth-2025-04-20");
        c.setRequestProperty("User-Agent", "claude-code/1.0.119");
        int code = c.getResponseCode();
        if (code == 401 || code == 403) throw new AuthExpired();
        if (code != 200) throw new Exception("HTTP " + code);
        return parse(new JSONObject(OAuth.read(c.getInputStream())));
    }

    static List<Window> parse(JSONObject json) {
        List<Window> out = new ArrayList<>();
        TreeSet<String> seen = new TreeSet<>();
        for (String[] k : KNOWN) {
            Window w = window(json, k[0], k[1]);
            if (w != null) { out.add(w); seen.add(k[0]); }
        }
        TreeSet<String> keys = new TreeSet<>();
        for (Iterator<String> it = json.keys(); it.hasNext(); ) keys.add(it.next());
        for (String key : keys) {
            if (seen.contains(key)) continue;
            Window w = window(json, key, key.replace('_', ' '));
            if (w != null) out.add(w);
        }
        return out;
    }

    private static Window window(JSONObject json, String key, String label) {
        JSONObject o = json.optJSONObject(key);
        if (o == null || !o.has("utilization") || o.isNull("utilization")) return null;
        long reset = 0;
        String s = o.optString("resets_at", "");
        if (!s.isEmpty() && !o.isNull("resets_at")) {
            try { reset = OffsetDateTime.parse(s).toInstant().toEpochMilli(); } catch (Exception ignored) {}
        }
        return new Window(key, label, o.optDouble("utilization"), reset);
    }
}
