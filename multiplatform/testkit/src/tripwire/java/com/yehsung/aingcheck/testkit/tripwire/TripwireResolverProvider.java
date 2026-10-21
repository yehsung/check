package com.yehsung.aingcheck.testkit.tripwire;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.net.spi.InetAddressResolver;
import java.net.spi.InetAddressResolverProvider;
import java.util.Locale;
import java.util.stream.Stream;

/** {@link NetworkTripwire} 의 JEP 418 제공자. META-INF/services 로 등록된다. */
public final class TripwireResolverProvider extends InetAddressResolverProvider {
    @Override
    public InetAddressResolver get(Configuration configuration) {
        NetworkTripwire.markInstalled();
        return new TripwireResolver(configuration.builtinResolver(), configuration.lookupLocalHostName());
    }

    @Override
    public String name() {
        return "aingcheck-tripwire";
    }

    static final class TripwireResolver implements InetAddressResolver {
        private final InetAddressResolver builtin;
        private final String localHostName;

        TripwireResolver(InetAddressResolver builtin, String localHostName) {
            this.builtin = builtin;
            this.localHostName = localHostName == null ? "" : localHostName.toLowerCase(Locale.ROOT);
        }

        @Override
        public Stream<InetAddress> lookupByName(String host, LookupPolicy lookupPolicy) throws UnknownHostException {
            String name = host == null ? "" : host.toLowerCase(Locale.ROOT);
            if (NetworkTripwire.isCanaryBypassActive() || isLocal(name)) {
                return builtin.lookupByName(host, lookupPolicy);
            }
            NetworkTripwire.record("lookup " + host);
            throw new UnknownHostException(NetworkTripwire.MESSAGE_PREFIX + host);
        }

        @Override
        public String lookupByAddress(byte[] addr) throws UnknownHostException {
            if (NetworkTripwire.isCanaryBypassActive() || isLoopback(addr)) {
                return builtin.lookupByAddress(addr);
            }
            String what = InetAddress.getByAddress(addr).getHostAddress();
            NetworkTripwire.record("reverse " + what);
            throw new UnknownHostException(NetworkTripwire.MESSAGE_PREFIX + "(reverse) " + what);
        }

        private boolean isLocal(String name) {
            return name.equals("localhost")
                || name.endsWith(".localhost")
                || (!localHostName.isEmpty() && name.equals(localHostName));
        }

        private static boolean isLoopback(byte[] addr) {
            if (addr.length == 4) {
                return (addr[0] & 0xff) == 127;
            }
            if (addr.length == 16) {
                for (int i = 0; i < 15; i++) {
                    if (addr[i] != 0) return false;
                }
                return addr[15] == 1;
            }
            return false;
        }
    }
}
