package smi.test;

import pea.testing.PEACompilationBarrier;

/**
 * SMI (speculative method inline) fixture: {@code consume} is deliberately bulked out with a
 * long straight-line arithmetic chain so the priority inliner's default budget does not inline it.
 * With no offline hint, the Holder argument therefore escapes into the call (reason:
 * call_argument). Pointing -Djdk.graal.OfflineEscapeSummaryFile at a .res file naming this call
 * site should make the inliner inline it, after which PEA scalar-replaces the Holder.
 */
public final class Test {
    private static final int WARMUP_INVOCATIONS = 50_000;

    private static final class Holder {
        final int value;

        Holder(int value) {
            this.value = value;
        }
    }

    private static int consume(Holder h) {
        int v = h.value;
        v = v * 31 + 1;
        v = v * 31 + 2;
        v = v * 31 + 3;
        v = v * 31 + 4;
        v = v * 31 + 5;
        v = v * 31 + 6;
        v = v * 31 + 7;
        v = v * 31 + 8;
        v = v * 31 + 9;
        v = v * 31 + 10;
        v = v * 31 + 11;
        v = v * 31 + 12;
        v = v * 31 + 13;
        v = v * 31 + 14;
        v = v * 31 + 15;
        v = v * 31 + 16;
        v = v * 31 + 17;
        v = v * 31 + 18;
        v = v * 31 + 19;
        v = v * 31 + 20;
        v = v * 31 + 21;
        v = v * 31 + 22;
        v = v * 31 + 23;
        v = v * 31 + 24;
        v = v * 31 + 25;
        v = v * 31 + 26;
        v = v * 31 + 27;
        v = v * 31 + 28;
        v = v * 31 + 29;
        v = v * 31 + 30;
        v = v * 31 + 31;
        v = v * 31 + 32;
        v = v * 31 + 33;
        v = v * 31 + 34;
        v = v * 31 + 35;
        v = v * 31 + 36;
        v = v * 31 + 37;
        v = v * 31 + 38;
        v = v * 31 + 39;
        v = v * 31 + 40;
        v = v * 31 + 41;
        v = v * 31 + 42;
        v = v * 31 + 43;
        v = v * 31 + 44;
        v = v * 31 + 45;
        v = v * 31 + 46;
        v = v * 31 + 47;
        v = v * 31 + 48;
        v = v * 31 + 49;
        v = v * 31 + 50;
        v = v * 31 + 51;
        v = v * 31 + 52;
        v = v * 31 + 53;
        v = v * 31 + 54;
        v = v * 31 + 55;
        v = v * 31 + 56;
        v = v * 31 + 57;
        v = v * 31 + 58;
        v = v * 31 + 59;
        v = v * 31 + 60;
        v = v * 31 + 61;
        v = v * 31 + 62;
        v = v * 31 + 63;
        v = v * 31 + 64;
        v = v * 31 + 65;
        v = v * 31 + 66;
        v = v * 31 + 67;
        v = v * 31 + 68;
        v = v * 31 + 69;
        v = v * 31 + 70;
        v = v * 31 + 71;
        v = v * 31 + 72;
        v = v * 31 + 73;
        v = v * 31 + 74;
        v = v * 31 + 75;
        v = v * 31 + 76;
        v = v * 31 + 77;
        v = v * 31 + 78;
        v = v * 31 + 79;
        v = v * 31 + 80;
        v = v * 31 + 81;
        v = v * 31 + 82;
        v = v * 31 + 83;
        v = v * 31 + 84;
        v = v * 31 + 85;
        v = v * 31 + 86;
        v = v * 31 + 87;
        v = v * 31 + 88;
        v = v * 31 + 89;
        v = v * 31 + 90;
        v = v * 31 + 91;
        v = v * 31 + 92;
        v = v * 31 + 93;
        v = v * 31 + 94;
        v = v * 31 + 95;
        v = v * 31 + 96;
        v = v * 31 + 97;
        v = v * 31 + 98;
        v = v * 31 + 99;
        v = v * 31 + 100;
        v = v * 31 + 101;
        v = v * 31 + 102;
        v = v * 31 + 103;
        v = v * 31 + 104;
        v = v * 31 + 105;
        v = v * 31 + 106;
        v = v * 31 + 107;
        v = v * 31 + 108;
        v = v * 31 + 109;
        v = v * 31 + 110;
        v = v * 31 + 111;
        v = v * 31 + 112;
        v = v * 31 + 113;
        v = v * 31 + 114;
        v = v * 31 + 115;
        v = v * 31 + 116;
        v = v * 31 + 117;
        v = v * 31 + 118;
        v = v * 31 + 119;
        v = v * 31 + 120;
        v = v * 31 + 121;
        v = v * 31 + 122;
        v = v * 31 + 123;
        v = v * 31 + 124;
        v = v * 31 + 125;
        v = v * 31 + 126;
        v = v * 31 + 127;
        v = v * 31 + 128;
        v = v * 31 + 129;
        v = v * 31 + 130;
        v = v * 31 + 131;
        v = v * 31 + 132;
        v = v * 31 + 133;
        v = v * 31 + 134;
        v = v * 31 + 135;
        v = v * 31 + 136;
        v = v * 31 + 137;
        v = v * 31 + 138;
        v = v * 31 + 139;
        v = v * 31 + 140;
        v = v * 31 + 141;
        v = v * 31 + 142;
        v = v * 31 + 143;
        v = v * 31 + 144;
        v = v * 31 + 145;
        v = v * 31 + 146;
        v = v * 31 + 147;
        v = v * 31 + 148;
        v = v * 31 + 149;
        v = v * 31 + 150;
        v = v * 31 + 151;
        v = v * 31 + 152;
        v = v * 31 + 153;
        v = v * 31 + 154;
        v = v * 31 + 155;
        v = v * 31 + 156;
        v = v * 31 + 157;
        v = v * 31 + 158;
        v = v * 31 + 159;
        v = v * 31 + 160;
        return v;
    }

    private static long run(int iterations) {
        long checksum = 0;
        for (int i = 0; i < iterations; i++) {
            checksum += consume(new Holder(i));
        }
        return checksum;
    }

    public static void main(String[] args) {
        int iterations = args.length == 0 ? 200_000 : Integer.parseInt(args[0]);
        long checksum = 0;
        for (int i = 0; i < WARMUP_INVOCATIONS; i++) {
            checksum += run(50);
        }
        PEACompilationBarrier.awaitSites(1, 120_000);
        System.out.println("PEA-MEASUREMENT-START");
        checksum += run(iterations);
        System.out.println("PEA-MEASUREMENT-END");
        if (checksum == 0) {
            throw new AssertionError("sanity check failed: checksum must be nonzero");
        }
        System.out.println(checksum);
    }
}
