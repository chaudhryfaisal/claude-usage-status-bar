package com.example.claudebar;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context ctx, Intent intent) {
        if (new TokenStore(ctx).connected()) {
            UsageJobService.schedule(ctx);
            new Thread(() -> Refresher.run(ctx.getApplicationContext())).start();
        }
    }
}
