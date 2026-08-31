public final class Test {

    private static volatile Object escapeSink;

    private static final class Pair {
        final int x;
        final int y;

        Pair(int x, int y) {
            this.x = x;
            this.y = y;
        }
    }

    public static int scalarObject(int value) {
        Pair pair = new Pair(value, value + 1);
        return pair.x + pair.y;
    }

    public static int alwaysEscapes(int value) {
        Pair pair = new Pair(value, value + 2);
        escapeSink = pair;
        return pair.x;
    }

    public static int conditionalEscape(int value) {
        Pair pair = new Pair(value, value + 3);
        if ((value & 1023) == 0) {
            escapeSink = pair;
        }
        return pair.y;
    }

    public static int scalarArray(int value) {
        int[] values = new int[2];
        values[0] = value;
        values[1] = value + 4;
        return values[0] + values[1];
    }

    private static long runLoop(int iterations) {
        long checksum = 0;
        for (int i = 1; i <= iterations; i++) {
            checksum += scalarObject(i);
            checksum += alwaysEscapes(i);
            checksum += conditionalEscape(i);
            checksum += scalarArray(i);
        }
        return checksum;
    }

    public static void main(String[] args) {
        final int iterations = args.length == 0 ? 200_000 : Integer.parseInt(args[0]);
        // warmingup before pea measurement
        long checksum = runLoop(20_000);
        System.out.println("PEA-MEASUREMENT-START");
        checksum += runLoop(iterations);
        System.out.println("PEA-MEASUREMENT-END");
        System.out.println(checksum);
    }
}
