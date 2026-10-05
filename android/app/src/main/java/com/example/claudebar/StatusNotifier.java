package com.example.claudebar;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.drawable.Icon;

import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Android has no menu bar; the status-bar equivalent is an ongoing notification
 * whose small icon is drawn at runtime to show the remaining % as a number.
 */
final class StatusNotifier {
    private static final String CHANNEL = "usage";
    private static final int ID = 1;

    static void show(Context ctx, List<UsageClient.Window> windows, boolean stale) {
        NotificationManager nm = ctx.getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, "Claude usage", NotificationManager.IMPORTANCE_LOW));

        UsageClient.Window session = find(windows, "five_hour");
        UsageClient.Window weekly = find(windows, "seven_day");
        UsageClient.Window primary = session != null ? session : (weekly != null ? weekly : (windows.isEmpty() ? null : windows.get(0)));
        if (primary == null) { nm.cancel(ID); return; }

        StringBuilder body = new StringBuilder();
        for (UsageClient.Window w : windows) {
            body.append(w.label).append(": ").append(w.remaining()).append("% left");
            if (w.resetsAtMs > 0) body.append(" (resets ").append(resetText(w.resetsAtMs)).append(")");
            body.append('\n');
        }
        String title = "Claude " + primary.label + ": " + primary.remaining() + "% left" + (stale ? " (stale)" : "");
        String summary = weekly != null && weekly != primary ? "Weekly: " + weekly.remaining() + "% left" : "";

        PendingIntent open = PendingIntent.getActivity(ctx, 0, new Intent(ctx, MainActivity.class),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        Notification n = new Notification.Builder(ctx, CHANNEL)
                .setSmallIcon(numberIcon(primary.remaining()))
                .setContentTitle(title)
                .setContentText(summary)
                .setStyle(new Notification.BigTextStyle().bigText(body.toString().trim()))
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .build();
        nm.notify(ID, n);
    }

    static void clear(Context ctx) { ctx.getSystemService(NotificationManager.class).cancel(ID); }

    private static UsageClient.Window find(List<UsageClient.Window> l, String id) {
        for (UsageClient.Window w : l) if (w.id.equals(id)) return w;
        return null;
    }

    private static String resetText(long ms) {
        Date d = new Date(ms);
        boolean today = new SimpleDateFormat("yyyyMMdd", Locale.US).format(d)
                .equals(new SimpleDateFormat("yyyyMMdd", Locale.US).format(new Date()));
        return (today ? DateFormat.getTimeInstance(DateFormat.SHORT) : new SimpleDateFormat("EEE HH:mm", Locale.getDefault())).format(d);
    }

    /** Status-bar icons are alpha masks: draw white text on a transparent bitmap. */
    private static Icon numberIcon(int value) {
        int size = 96;
        Bitmap bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bmp);
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(Color.WHITE);
        p.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        p.setTextAlign(Paint.Align.CENTER);
        String text = String.valueOf(value);
        p.setTextSize(size);
        float w = p.measureText(text);
        p.setTextSize(Math.min(size * 0.95f, size * 0.95f * size / w)); // fit width ("100" shrinks)
        float y = size / 2f - (p.descent() + p.ascent()) / 2f;
        canvas.drawText(text, size / 2f, y, p);
        return Icon.createWithBitmap(bmp);
    }
}
