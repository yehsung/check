// 원본: 없음 (W0-f ⑤ FCM 토큰 탐침 — B§9-1 · B§9-4 · E-U6)
// 규칙: 토큰 원문은 어디에도 내지 않는다(결과 Bundle·logcat·파일 모두). 메모리 안에서 길이·글자 집합·정규식 일치만 낸다.
//       서로 다름 판정용으로 운전 스크립트가 준 소금(salt)을 붙인 SHA-256 앞 16자만 낸다(소금은 그 실행 메모리에만 있다).
package com.yehsung.aingcheck.w0f5;

import android.accounts.AccountManager;
import android.app.Activity;
import android.app.Instrumentation;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.service.notification.StatusBarNotification;

import com.google.android.gms.common.GoogleApiAvailabilityLight;
import com.google.android.gms.tasks.Tasks;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.installations.FirebaseInstallations;
import com.google.firebase.messaging.FcmBroadcastProcessor;
import com.google.firebase.messaging.FirebaseMessaging;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.TreeSet;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

public final class FcmProbe extends Instrumentation {
    // 서버가 쓰는 두 꼴(push-send fcm.ts 의 JS 정규식 · M1 CHECK/RPC 의 Postgres 꼴)
    private static final Pattern JS_FORM = Pattern.compile("^[!-~]{32,4096}$");
    private static final Pattern PG_BODY = Pattern.compile("^[!-~]+$");
    // 오류 글에 토큰 비슷한 긴 덩어리가 섞이면 지운다
    private static final Pattern LONG_RUN = Pattern.compile("[A-Za-z0-9_:\\-]{24,}");

    private Bundle args = new Bundle();

    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        if (arguments != null) args = arguments;
        saltHolder = args.getString("salt", "");
        start();
    }

    @Override
    public void onStart() {
        super.onStart();
        Bundle out = new Bundle();
        String mode = args.getString("mode", "token");
        try {
            if ("token".equals(mode)) {
                tokenProbe(out);
            } else if ("notify".equals(mode)) {
                notifyProbe(out);
            } else {
                out.putString("error", "unknown mode");
            }
        } catch (Throwable t) {
            out.putString("error", safe(t));
        }
        finish(Activity.RESULT_OK, out);
    }

    private FirebaseApp initFirebase(Context ctx, Bundle out) {
        out.putBoolean("defaultAppBeforeInit", !FirebaseApp.getApps(ctx).isEmpty());
        if (!FirebaseApp.getApps(ctx).isEmpty()) return FirebaseApp.getInstance();
        FirebaseOptions o = new FirebaseOptions.Builder()
                .setApplicationId(BuildConfig.FB_APP_ID)
                .setApiKey(BuildConfig.FB_API_KEY)
                .setProjectId(BuildConfig.FB_PROJECT_ID)
                .setGcmSenderId(BuildConfig.FB_SENDER_ID)
                .build();
        return FirebaseApp.initializeApp(ctx, o);
    }

    private void tokenProbe(Bundle out) throws Exception {
        Context ctx = getTargetContext();
        out.putInt("sdk", Build.VERSION.SDK_INT);
        out.putInt("googleAccountsVisible", AccountManager.get(ctx).getAccountsByType("com.google").length);
        out.putInt("gmsAvailability", GoogleApiAvailabilityLight.getInstance().isGooglePlayServicesAvailable(ctx));
        initFirebase(ctx, out);
        FirebaseMessaging fm = FirebaseMessaging.getInstance();
        out.putBoolean("autoInitEnabled", fm.isAutoInitEnabled());

        long t0 = SystemClock.elapsedRealtime();
        String fid = Tasks.await(FirebaseInstallations.getInstance().getId(), 180, TimeUnit.SECONDS);
        long t1 = SystemClock.elapsedRealtime();
        String tok = Tasks.await(fm.getToken(), 300, TimeUnit.SECONDS);
        long t2 = SystemClock.elapsedRealtime();
        String tok2 = Tasks.await(fm.getToken(), 60, TimeUnit.SECONDS);
        out.putLong("fidMs", t1 - t0);
        out.putLong("tokenMs", t2 - t1);
        out.putBoolean("stableWithinInstall", tok != null && tok.equals(tok2));
        out.putInt("fidLen", fid == null ? -1 : fid.length());
        if (tok == null) {
            out.putString("error", "token null");
            return;
        }
        stats(tok, fid, out);
    }

    private static void stats(String tok, String fid, Bundle out) throws Exception {
        int len = tok.length();
        int cps = tok.codePointCount(0, len);
        out.putInt("len", len);
        out.putInt("codePoints", cps);
        out.putBoolean("jsForm", JS_FORM.matcher(tok).matches());
        // Postgres: fcm_token ~ '^[!-~]+$' and char_length(fcm_token) between 32 and 4096
        out.putBoolean("pgForm", PG_BODY.matcher(tok).matches() && cps >= 32 && cps <= 4096);
        // register_device_fcm: btrim(p_fcm_token, E' \t\r\n') 가 아무것도 걷지 않는가
        out.putBoolean("btrimNoop", btrim(tok).equals(tok));
        // push_outbox_complete 의 FCM 비우기 줄은 lower( 를 안 쓴다 — 소문자로 바꾸면 다른 글자열이 되는가
        out.putBoolean("lowerChanges", !tok.toLowerCase(Locale.ROOT).equals(tok));
        boolean up = false, lo = false, dg = false;
        int minC = Integer.MAX_VALUE, maxC = -1;
        TreeSet<Character> punct = new TreeSet<>();
        for (int i = 0; i < len; i++) {
            char c = tok.charAt(i);
            minC = Math.min(minC, c);
            maxC = Math.max(maxC, c);
            if (c >= 'A' && c <= 'Z') up = true;
            else if (c >= 'a' && c <= 'z') lo = true;
            else if (c >= '0' && c <= '9') dg = true;
            else punct.add(c);
        }
        StringBuilder p = new StringBuilder();
        for (char c : punct) p.append(c);
        out.putBoolean("hasUpper", up);
        out.putBoolean("hasLower", lo);
        out.putBoolean("hasDigit", dg);
        out.putString("punct", p.toString());
        out.putInt("minChar", minC);
        out.putInt("maxChar", maxC);
        int colon = tok.indexOf(':');
        int colons = 0;
        for (int i = 0; i < len; i++) if (tok.charAt(i) == ':') colons++;
        out.putInt("colonIndex", colon);
        out.putInt("colonCount", colons);
        out.putBoolean("headEqualsFid", colon > 0 && fid != null && tok.substring(0, colon).equals(fid));
        out.putBoolean("tailStartsAPA91b", colon >= 0 && tok.startsWith("APA91b", colon + 1));
        out.putInt("tailLen", colon >= 0 ? len - colon - 1 : -1);
        String salt = saltHolder == null ? "" : saltHolder;
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        byte[] d = md.digest((salt + "|" + tok).getBytes(StandardCharsets.UTF_8));
        StringBuilder h = new StringBuilder();
        for (int i = 0; i < 8; i++) h.append(String.format(Locale.ROOT, "%02x", d[i]));
        out.putString("h", h.toString());
    }

    private static String saltHolder;

    private static String btrim(String s) {
        int a = 0, b = s.length();
        while (a < b && isTrim(s.charAt(a))) a++;
        while (b > a && isTrim(s.charAt(b - 1))) b--;
        return s.substring(a, b);
    }

    private static boolean isTrim(char c) {
        return c == ' ' || c == '\t' || c == '\r' || c == '\n';
    }

    // B§9-4: 없는 채널로 게시하면 어떻게 되나 — data-only(앱이 직접 게시, K7)와 SDK notification 메시지 두 길
    private void notifyProbe(Bundle out) throws Exception {
        Context ctx = getTargetContext();
        out.putInt("sdk", Build.VERSION.SDK_INT);
        initFirebase(ctx, out);
        NotificationManager nm = ctx.getSystemService(NotificationManager.class);
        out.putBoolean("notificationsEnabled", nm.areNotificationsEnabled());
        nm.cancelAll();
        SystemClock.sleep(500);

        // ① 기준선: 채널을 만든 뒤 게시 → 보여야 한다
        nm.createNotificationChannel(new NotificationChannel("probe_baseline", "baseline", NotificationManager.IMPORTANCE_DEFAULT));
        nm.notify(101, build(ctx, "probe_baseline", "baseline"));
        // ② 없는 채널('message' 를 아직 안 만듦)로 게시
        out.putBoolean("messageChannelExistsBefore", nm.getNotificationChannel("message") != null);
        nm.notify(102, build(ctx, "message", "missing"));
        SystemClock.sleep(1500);
        out.putBoolean("baselinePosted", active(nm, 101));
        out.putBoolean("missingPosted", active(nm, 102));
        out.putBoolean("messageChannelCreatedImplicitly", nm.getNotificationChannel("message") != null);
        // ③ 같은 채널을 만든 뒤 다시 게시 → 보여야 한다(②의 차이가 채널 부재 탓임을 가르는 대조)
        nm.createNotificationChannel(new NotificationChannel("message", "message", NotificationManager.IMPORTANCE_HIGH));
        nm.notify(103, build(ctx, "message", "after-create"));
        SystemClock.sleep(1500);
        out.putBoolean("afterCreatePosted", active(nm, 103));

        // ④ SDK 의 notification 메시지 경로(GMS 가 넘긴 뒤와 같은 처리기: FcmBroadcastProcessor)
        nm.cancelAll();
        SystemClock.sleep(500);
        out.putBoolean("noSuchChannelExistsBefore", nm.getNotificationChannel("no_such_channel") != null);
        out.putBoolean("fallbackExistsBefore", nm.getNotificationChannel("fcm_fallback_notification_channel") != null);
        Intent i = new Intent("com.google.android.c2dm.intent.RECEIVE");
        i.setPackage(ctx.getPackageName());
        i.putExtra("google.message_id", "w0f5-" + SystemClock.elapsedRealtime());
        i.putExtra("from", BuildConfig.FB_SENDER_ID);
        i.putExtra("gcm.n.e", "1");
        i.putExtra("gcm.n.title", "w0f5");
        i.putExtra("gcm.n.body", "channel?");
        i.putExtra("gcm.n.android_channel_id", "no_such_channel");
        Integer rc = Tasks.await(new FcmBroadcastProcessor(ctx).process(i), 30, TimeUnit.SECONDS);
        out.putInt("sdkProcessResult", rc == null ? -1 : rc);
        SystemClock.sleep(2500);
        List<String> chans = new ArrayList<>();
        for (StatusBarNotification sbn : nm.getActiveNotifications()) {
            Notification n = sbn.getNotification();
            chans.add(String.valueOf(n.getChannelId()));
        }
        out.putString("sdkPostedChannels", String.join(",", chans));
        out.putBoolean("noSuchChannelExistsAfter", nm.getNotificationChannel("no_such_channel") != null);
        NotificationChannel fb = nm.getNotificationChannel("fcm_fallback_notification_channel");
        out.putBoolean("fallbackExistsAfter", fb != null);
        if (fb != null) {
            out.putString("fallbackName", String.valueOf(fb.getName()));
            out.putInt("fallbackImportance", fb.getImportance());
        }
        nm.cancelAll();
    }

    private static boolean active(NotificationManager nm, int id) {
        for (StatusBarNotification sbn : nm.getActiveNotifications()) if (sbn.getId() == id) return true;
        return false;
    }

    private static Notification build(Context ctx, String channel, String text) {
        return new Notification.Builder(ctx, channel)
                .setSmallIcon(android.R.drawable.sym_def_app_icon)
                .setContentTitle("w0f5")
                .setContentText(text)
                .build();
    }

    private static String safe(Throwable t) {
        StringBuilder sb = new StringBuilder();
        for (Throwable c = t; c != null && sb.length() < 600; c = c.getCause()) {
            if (sb.length() > 0) sb.append(" <- ");
            String m = c.getMessage() == null ? "" : LONG_RUN.matcher(c.getMessage()).replaceAll("<긴덩어리>");
            sb.append(c.getClass().getName()).append(": ").append(m.length() > 200 ? m.substring(0, 200) : m);
        }
        return sb.toString();
    }

}
