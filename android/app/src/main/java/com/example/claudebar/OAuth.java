package com.example.claudebar;

import android.net.Uri;
import android.util.Base64;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.LinkedHashMap;
import java.util.Map;

/** Same public OAuth client + PKCE flow the macOS app (and Claude Code CLI) uses. */
final class OAuth {
    static final String CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
    static final String REDIRECT_URI = "https://platform.claude.com/oauth/code/callback";
    static final String TOKEN_URL = "https://console.anthropic.com/v1/oauth/token";
    static final String SCOPE = "user:profile"; // read-only

    private static String randomUrlSafe() {
        byte[] b = new byte[32];
        new SecureRandom().nextBytes(b);
        return b64url(b);
    }

    static String b64url(byte[] b) {
        return Base64.encodeToString(b, Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING);
    }

    /** Generates PKCE values, persists them, returns the URL to open in the browser. */
    static Uri begin(TokenStore store) throws Exception {
        String verifier = randomUrlSafe();
        String state = randomUrlSafe();
        String challenge = b64url(MessageDigest.getInstance("SHA-256")
                .digest(verifier.getBytes(StandardCharsets.UTF_8)));
        store.savePending(verifier, state);
        return Uri.parse("https://claude.ai/oauth/authorize").buildUpon()
                .appendQueryParameter("code", "true")
                .appendQueryParameter("client_id", CLIENT_ID)
                .appendQueryParameter("response_type", "code")
                .appendQueryParameter("redirect_uri", REDIRECT_URI)
                .appendQueryParameter("scope", SCOPE)
                .appendQueryParameter("code_challenge", challenge)
                .appendQueryParameter("code_challenge_method", "S256")
                .appendQueryParameter("state", state)
                .build();
    }

    /** Callback page shows "code#state". A pasted state must match ours. */
    static void exchange(TokenStore store, String pasted) throws Exception {
        String verifier = store.pendingVerifier(), state = store.pendingState();
        if (verifier == null) throw new Exception("Tap Connect first.");
        String[] parts = pasted.trim().split("#");
        if (parts.length == 0 || parts[0].isEmpty()) throw new Exception("Empty code.");
        if (parts.length > 1 && !parts[1].equals(state)) throw new Exception("State mismatch - restart connect.");
        Map<String, String> body = new LinkedHashMap<>();
        body.put("grant_type", "authorization_code");
        body.put("code", parts[0]);
        body.put("state", state);
        body.put("client_id", CLIENT_ID);
        body.put("redirect_uri", REDIRECT_URI);
        body.put("code_verifier", verifier);
        requestToken(store, body, null);
    }

    static void refresh(TokenStore store) throws Exception {
        Map<String, String> body = new LinkedHashMap<>();
        body.put("grant_type", "refresh_token");
        body.put("refresh_token", store.refresh());
        body.put("client_id", CLIENT_ID);
        requestToken(store, body, store.refresh());
    }

    private static void requestToken(TokenStore store, Map<String, String> body, String oldRefresh) throws Exception {
        String[] r = post(new JSONObject(body).toString(), "application/json");
        if (!r[0].equals("200")) { // some deployments want form-encoded
            StringBuilder sb = new StringBuilder();
            for (Map.Entry<String, String> e : body.entrySet()) {
                if (sb.length() > 0) sb.append('&');
                sb.append(e.getKey()).append('=').append(URLEncoder.encode(e.getValue(), "UTF-8"));
            }
            r = post(sb.toString(), "application/x-www-form-urlencoded");
        }
        if (!r[0].equals("200")) {
            throw new Exception(r[1].substring(0, Math.min(200, r[1].length())));
        }
        JSONObject j = new JSONObject(r[1]);
        String refresh = j.optString("refresh_token", oldRefresh == null ? "" : oldRefresh);
        store.save(j.getString("access_token"), refresh,
                System.currentTimeMillis() + (long) (j.getDouble("expires_in") * 1000));
    }

    private static String[] post(String payload, String contentType) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(TOKEN_URL).openConnection();
        c.setRequestMethod("POST");
        c.setConnectTimeout(15000);
        c.setReadTimeout(15000);
        c.setDoOutput(true);
        c.setRequestProperty("Content-Type", contentType);
        try (OutputStream os = c.getOutputStream()) { os.write(payload.getBytes(StandardCharsets.UTF_8)); }
        int code = c.getResponseCode();
        InputStream is = code >= 400 ? c.getErrorStream() : c.getInputStream();
        return new String[]{String.valueOf(code), is == null ? "" : read(is)};
    }

    static String read(InputStream is) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        for (int n; (n = is.read(buf)) > 0; ) out.write(buf, 0, n);
        return out.toString("UTF-8");
    }
}
