package pea.reasons;

import pea.testing.PEACompilationBarrier;

public final class Test {
    private static final int WARMUP_INVOCATIONS = 50_000;

    private static volatile Object globalSink;
    private static final Holder MATERIALIZED_HOLDER = new Holder(null);
    private static final Object[] MATERIALIZED_ARRAY = new Object[1];

    private static final class Payload {
        final int value;

        Payload(int value) {
            this.value = value;
        }
    }

    private static final class Holder {
        Object value;

        Holder(Object value) {
            this.value = value;
        }
    }

    private static final class TestException extends RuntimeException {
        private static final long serialVersionUID = 1L;

        TestException(String message) {
            super(message);
        }
    }

    private static Object returnEscape(int value) {
        return new Payload(value);
    }

    private static int callEscape(Object value) {
        globalSink = value;
        return System.identityHashCode(value);
    }

    private static int staticFieldEscape(int value) {
        Payload payload = new Payload(value);
        globalSink = payload;
        return payload.value;
    }

    private static int instanceFieldEscape(int value) {
        Payload payload = new Payload(value);
        MATERIALIZED_HOLDER.value = payload;
        return payload.value;
    }

    private static int arrayEscape(int value) {
        Payload payload = new Payload(value);
        MATERIALIZED_ARRAY[0] = payload;
        return payload.value;
    }

    private static int exceptionEscape(int value) {
        try {
            throwException(value);
        } catch (TestException exception) {
            return exception.getMessage().length();
        }
        return 0;
    }

    private static void throwException(int value) {
        throw new TestException(Integer.toString(value));
    }

    private static int objectGraphDependency(int value) {
        Holder holder = new Holder(new Payload(value));
        return callEscape(holder);
    }

    private static int phiEscape(int value) {
        Object result = (value & 1) == 0 ? new Payload(value) : new Holder(value);
        return callEscape(result);
    }

    private static long run(int iterations) {
        long checksum = 0;
        for (int i = 0; i < iterations; i++) {
            checksum += System.identityHashCode(returnEscape(i));
            checksum += callEscape(new Payload(i));
            checksum += staticFieldEscape(i);
            checksum += instanceFieldEscape(i);
            checksum += arrayEscape(i);
            checksum += exceptionEscape(i);
            checksum += objectGraphDependency(i);
            checksum += phiEscape(i);
        }
        return checksum;
    }

    private static long warmup(int invocations) {
        long checksum = 0;
        for (int i = 0; i < invocations; i++) {
            // Warm the normal run(int) entry used by the measured invocation, rather than only
            // producing an OSR compilation of one long-running invocation. Two iterations exercise
            // both branches in phiEscape so profile-driven compilation retains both allocation sites.
            checksum += run(2);
        }
        return checksum;
    }

    public static void main(String[] args) {
        int iterations = args.length == 0 ? 20_000 : Integer.parseInt(args[0]);
        System.out.println("Running PEAMaterializationReasonsTest with " + iterations + " iterations");
        long checksum = warmup(WARMUP_INVOCATIONS);
        PEACompilationBarrier.awaitSites(10, 120_000);
        System.out.println("PEA-MEASUREMENT-START");
        checksum += run(iterations);
        System.out.println("PEA-MEASUREMENT-END");
        System.out.println(checksum);
    }
}
