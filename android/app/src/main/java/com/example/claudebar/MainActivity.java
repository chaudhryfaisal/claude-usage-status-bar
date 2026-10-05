package com.example.claudebar;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity {
    private TokenStore store;
    private TextView status;
    private EditText codeInput;
    private Button connect, submit, refresh, disconnect;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        store = new TokenStore(this);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (20 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        status = new TextView(this);
        status.setTextSize(16);
        connect = button("Connect Claude Account", v -> connect());
        codeInput = new EditText(this);
        codeInput.setHint("Paste code from the callback page");
        codeInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        submit = button("Submit code", v -> submit());
        refresh = button("Refresh now", v -> refresh());
        disconnect = button("Disconnect", v -> disconnect());

        for (View v : new View[]{status, connect, codeInput, submit, refresh, disconnect}) root.addView(v);
        setContentView(root);

        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        }
    }

    @Override protected void onResume() {
        super.onResume();
        updateUi(store.connected() ? "Connected." : "Not connected.");
        if (store.connected()) refresh();
    }

    private Button button(String text, View.OnClickListener l) {
        Button x = new Button(this);
        x.setText(text);
        x.setOnClickListener(l);
        return x;
    }

    private void updateUi(String msg) {
        boolean c = store.connected();
        status.setText(msg);
        connect.setVisibility(c ? View.GONE : View.VISIBLE);
        codeInput.setVisibility(c ? View.GONE : View.VISIBLE);
        submit.setVisibility(c ? View.GONE : View.VISIBLE);
        refresh.setVisibility(c ? View.VISIBLE : View.GONE);
        disconnect.setVisibility(c ? View.VISIBLE : View.GONE);
    }

    private void connect() {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, OAuth.begin(store)));
            updateUi("Approve in the browser, copy the code shown, paste it below.");
        } catch (Exception e) { updateUi("Error: " + e.getMessage()); }
    }

    private void submit() {
        String code = codeInput.getText().toString();
        updateUi("Connecting...");
        new Thread(() -> {
            String err = null;
            try { OAuth.exchange(store, code); } catch (Exception e) { err = e.getMessage(); }
            final String msg = err;
            if (msg == null) {
                UsageJobService.schedule(this);
                String r = Refresher.run(this);
                runOnUiThread(() -> { codeInput.setText(""); updateUi(r == null ? "Connected. Check your status bar." : r); });
            } else {
                runOnUiThread(() -> updateUi("Error: " + msg));
            }
        }).start();
    }

    private void refresh() {
        new Thread(() -> {
            String r = Refresher.run(this);
            runOnUiThread(() -> updateUi(r == null ? "Updated." : r));
        }).start();
    }

    private void disconnect() {
        UsageJobService.cancel(this);
        StatusNotifier.clear(this);
        store.clear();
        updateUi("Disconnected.");
    }
}
