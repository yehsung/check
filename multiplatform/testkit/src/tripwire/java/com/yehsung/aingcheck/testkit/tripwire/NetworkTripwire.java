package com.yehsung.aingcheck.testkit.tripwire;

import java.io.FileWriter;
import java.io.IOException;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.Callable;

/**
 * 망 봉인 ②층(A§4-1): 시험 JVM 안의 이름 풀이 트립와이어.
 *
 * <p>JDK 18+ {@code InetAddressResolverProvider}(JEP 418)를 ServiceLoader 로 등록해 이 JVM 의 모든
 * {@code InetAddress} 이름 풀이를 가로챈다. localhost(와 이 기계의 이름) 밖의 이름은 기록한 뒤
 * {@link java.net.UnknownHostException} 으로 막는다. 어느 HTTP 클라이언트(Ktor·OkHttp·JDK)든
 * 이름 풀이 단계에서 걸린다. 숫자 IP 직접 연결은 이름 풀이를 거치지 않으므로 ③층(OS 봉인)이 막는다.
 *
 * <p>기록은 시스템 속성 {@code aingcheck.tripwire.report} 의 파일에 한 줄씩 덧붙는다. Gradle 시험 작업이
 * 끝날 때 이 파일이 비어 있지 않으면 작업이 실패한다(aingcheck.test-seal). 시험 프레임워크와 무관하게
 * (JUnit5·Robolectric 의 JUnit4) 같은 판정이 된다.
 *
 * <p>Security Manager 는 쓰지 않는다(JDK 24 영구 비활성, JEP 486).
 */
public final class NetworkTripwire {
    private NetworkTripwire() {}

    static final String MESSAGE_PREFIX = "aingcheck tripwire: blocked name lookup ";

    private static volatile boolean installed = false;
    private static final List<String> blocked = Collections.synchronizedList(new ArrayList<>());
    /**
     * 기대 창(전역). 스레드 지역 값이 아니다 — Ktor·OkHttp 는 다른 스레드에서 이름을 푼다(실측).
     * 시험은 한 작업자 안에서 차례로 돈다(JUnit 병렬 실행을 켜지 않는다).
     */
    private static volatile List<String> expectedScope = null;
    private static final ThreadLocal<Boolean> canaryBypass = new ThreadLocal<>();

    /** 제공자가 JDK 에 실제로 올라왔는가(첫 이름 풀이 때 true 가 된다). */
    public static boolean isInstalled() {
        return installed;
    }

    static void markInstalled() {
        installed = true;
    }

    /** 이 실행에서 (예상 범위 밖에서) 막힌 이름 풀이 목록의 사본. */
    public static List<String> blockedSoFar() {
        synchronized (blocked) {
            return new ArrayList<>(blocked);
        }
    }

    /**
     * 트립와이어 자기 시험용: 블록 안에서 막힌 풀이는 실패 기록에 넣지 않고 돌려준다.
     * 블록이 던진 예외는 삼키지 않는다 — 호출자가 예외 모양까지 단언한다.
     */
    public static synchronized List<String> expectBlocked(Runnable body) {
        List<String> previous = expectedScope;
        List<String> scope = Collections.synchronizedList(new ArrayList<>());
        expectedScope = scope;
        try {
            body.run();
        } finally {
            expectedScope = previous;
        }
        synchronized (scope) {
            return new ArrayList<>(scope);
        }
    }

    /**
     * 카나리아 전용 통로: 블록 안에서는 JDK 기본 풀이로 넘긴다(③층 OS 봉인만 재기 위해).
     * 구조 시험이 이 이름을 NetworkCanaryTest 밖에서 쓰지 못하게 막는다.
     */
    public static <T> T canaryBypass(Callable<T> body) throws Exception {
        Boolean previous = canaryBypass.get();
        canaryBypass.set(Boolean.TRUE);
        try {
            return body.call();
        } finally {
            canaryBypass.set(previous);
        }
    }

    static boolean isCanaryBypassActive() {
        return Boolean.TRUE.equals(canaryBypass.get());
    }

    static void record(String what) {
        List<String> scope = expectedScope;
        if (scope != null) {
            scope.add(what);
            return;
        }
        blocked.add(what);
        String report = System.getProperty("aingcheck.tripwire.report");
        if (report == null || report.isEmpty()) {
            return;
        }
        String line = what + " @ " + Thread.currentThread().getName() + System.lineSeparator();
        synchronized (NetworkTripwire.class) {
            try (Writer w = new FileWriter(report, StandardCharsets.UTF_8, true)) {
                w.write(line);
            } catch (IOException ignored) {
                // 기록 실패는 예외로 이미 막힌 풀이에 더할 것이 없다. 작업 판정은 blockedSoFar 로도 할 수 있다.
            }
        }
    }
}
