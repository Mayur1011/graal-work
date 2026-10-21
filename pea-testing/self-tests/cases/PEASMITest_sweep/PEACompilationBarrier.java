package pea.testing;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/** Keeps self-test compilation synchronization outside the application package being measured. */
public final class PEACompilationBarrier {
    private static final String EFFECTIVENESS_REPORT_PROPERTY = "jdk.graal.PEAEffectivenessReportFile";

    private PEACompilationBarrier() {
    }

    /**
     * Waits for an atomically published PEA snapshot containing the expected application sites. All
     * polling occurs before the caller prints its runtime measurement start marker.
     */
    public static void awaitSites(int expectedSites, long timeoutMillis) {
        String reportFile = System.getProperty(EFFECTIVENESS_REPORT_PROPERTY);
        if (reportFile == null || reportFile.isBlank()) {
            return;
        }

        Path report = Path.of(reportFile);
        long deadline = System.nanoTime() + timeoutMillis * 1_000_000L;
        int observedSites = -1;
        while (System.nanoTime() < deadline) {
            observedSites = readObservedSiteCount(report);
            if (observedSites >= expectedSites) {
                sleep(250, "PEA code installation");
                System.out.println("PEA compilation ready: " + observedSites + " allocation sites observed");
                return;
            }
            sleep(25, "PEA compilation");
        }

        System.err.println("Timed out waiting for PEA compilation: observed " + observedSites +
                        " of at least " + expectedSites + " allocation sites in " + report);
        System.exit(4);
    }

    private static int readObservedSiteCount(Path report) {
        try {
            String contents = Files.readString(report);
            String key = "summary;total_candidates;";
            int start = contents.indexOf(key);
            if (start < 0) {
                return -1;
            }
            start += key.length();
            int end = contents.indexOf('\n', start);
            String value = (end < 0 ? contents.substring(start) : contents.substring(start, end)).trim();
            return Integer.parseInt(value);
        } catch (IOException | NumberFormatException ignored) {
            return -1;
        }
    }

    private static void sleep(long milliseconds, String activity) {
        try {
            Thread.sleep(milliseconds);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            System.err.println("Interrupted while waiting for " + activity);
            System.exit(3);
        }
    }
}
