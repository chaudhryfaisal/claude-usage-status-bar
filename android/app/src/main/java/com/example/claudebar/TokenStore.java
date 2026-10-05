package com.example.claudebar;

import android.content.Context;
import android.content.SharedPreferences;

/** Private app storage for the OAuth token and the in-flight PKCE values. */
final class TokenStore {
    private final SharedPreferences sp;

    TokenStore(Context c) { sp = c.getSharedPreferences("claudebar", Context.MODE_PRIVATE); }

    boolean connected() { return sp.getString("refresh", null) != null; }
    String access() { return sp.getString("access", null); }
    String refresh() { return sp.getString("refresh", null); }
    boolean needsRefresh() { return sp.getLong("expires", 0) - System.currentTimeMillis() < 300_000; }

    void save(String access, String refresh, long expiresAtMs) {
        sp.edit().putString("access", access).putString("refresh", refresh)
                .putLong("expires", expiresAtMs).apply();
    }

    void savePending(String verifier, String state) {
        sp.edit().putString("verifier", verifier).putString("state", state).apply();
    }
    String pendingVerifier() { return sp.getString("verifier", null); }
    String pendingState() { return sp.getString("state", null); }

    void clear() { sp.edit().clear().apply(); }
}
