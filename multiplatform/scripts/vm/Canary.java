// 망 봉인 카나리아(G §8-6). JDK 단일 파일 실행: java Canary.java [host] [port]
// 종료 코드: 0 CONNECTED · 3 DENIED(방화벽·샌드박스가 막음) · 4 OTHER(막힘이 아닌 실패: 망 없음·시간 초과·거부) · 2 사용법
// 짝 판정은 winseal.ps1 이 한다: 봉인 JDK = 3, 비봉인 JDK = 3 이 아님(연결 시도가 방화벽에 막히지 않았음).
// IP 로 연결한다 — 이름 풀이는 OS 서비스가 대신하므로 봉인 판정을 흐린다.
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;

public class Canary {
    public static void main(String[] args) {
        String host = args.length > 0 ? args[0] : "1.1.1.1";
        int port;
        try {
            port = args.length > 1 ? Integer.parseInt(args[1]) : 443;
        } catch (NumberFormatException e) {
            System.out.println("{\"result\":\"USAGE\"}");
            System.exit(2);
            return;
        }
        long t0 = System.nanoTime();
        try (Socket s = new Socket()) {
            s.connect(new InetSocketAddress(host, port), 5000);
            emit("CONNECTED", t0, host, port, "");
            System.exit(0);
        } catch (IOException e) {
            String m = String.valueOf(e.getMessage());
            boolean denied = m.contains("Permission denied") || m.contains("10013") || m.contains("Operation not permitted");
            emit(denied ? "DENIED" : "OTHER", t0, host, port, e.toString());
            System.exit(denied ? 3 : 4);
        }
    }

    private static void emit(String result, long t0, String host, int port, String error) {
        long ms = (System.nanoTime() - t0) / 1_000_000;
        String err = error.replace("\\", "\\\\").replace("\"", "\\\"");
        System.out.println("{\"result\":\"" + result + "\",\"ms\":" + ms + ",\"target\":\"" + host + ":" + port
            + "\",\"javaHome\":\"" + System.getProperty("java.home").replace("\\", "\\\\") + "\",\"error\":\"" + err + "\"}");
    }
}
