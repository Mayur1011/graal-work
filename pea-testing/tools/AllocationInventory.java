import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.lang.classfile.Attributes;
import java.lang.classfile.ClassFile;
import java.lang.classfile.ClassModel;
import java.lang.classfile.CodeElement;
import java.lang.classfile.Instruction;
import java.lang.classfile.MethodModel;
import java.lang.classfile.Opcode;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.jar.JarFile;

/** Inventories explicit Java allocation bytecodes in a class directory or JAR. Requires JDK 24+. */
public final class AllocationInventory {
    private record Row(String className, String method, String descriptor, int bci, String opcode,
                    String sourceFile, boolean peaEligible) {
    }

    private AllocationInventory() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 6 || !"--input".equals(args[0]) || !"--include".equals(args[2]) || !"--output".equals(args[4])) {
            throw new IllegalArgumentException("Usage: AllocationInventory --input <jar|classes> --include <prefix[,prefix]> --output <csv>");
        }
        Path input = Path.of(args[1]);
        String[] prefixes = args[3].split(",");
        Path output = Path.of(args[5]);
        List<Row> rows = new ArrayList<>();
        if (Files.isDirectory(input)) {
            try (var paths = Files.walk(input)) {
                for (Path path : paths.filter(Files::isRegularFile).toList()) {
                    if (path.toString().endsWith(".class")) {
                        addRows(Files.readAllBytes(path), prefixes, rows);
                    } else if (path.toString().endsWith(".jar")) {
                        addJarRows(path, prefixes, rows);
                    }
                }
            }
        } else {
            addJarRows(input, prefixes, rows);
        }
        rows.sort(Comparator.comparing(Row::className).thenComparing(Row::method).thenComparing(Row::descriptor).thenComparingInt(Row::bci));
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(output))) {
            out.println("record;class;method;descriptor;bci;opcode;source_file;pea_eligible_by_opcode");
            for (Row row : rows) {
                out.printf("site;%s;%s;%s;%d;%s;%s;%s%n", field(row.className), field(row.method), field(row.descriptor), row.bci,
                                row.opcode, field(row.sourceFile), row.peaEligible);
            }
            long eligible = rows.stream().filter(Row::peaEligible).count();
            out.printf("summary;total_explicit_allocation_sites;%d%n", rows.size());
            out.printf("summary;pea_eligible_allocation_sites;%d%n", eligible);
            out.printf("summary;multianewarray_sites;%d%n", rows.size() - eligible);
        }
    }

    private static void addJarRows(Path path, String[] prefixes, List<Row> rows) throws IOException {
        try (JarFile jar = new JarFile(path.toFile())) {
            var entries = jar.stream().filter(entry -> !entry.isDirectory() && entry.getName().endsWith(".class") &&
                            !entry.getName().startsWith("META-INF/versions/") && includedEntry(entry.getName(), prefixes)).toList();
            for (var entry : entries) {
                try (InputStream stream = jar.getInputStream(entry)) {
                    addRows(stream.readAllBytes(), prefixes, rows);
                }
            }
        }
    }

    private static void addRows(byte[] bytes, String[] prefixes, List<Row> rows) throws IOException {
        ClassModel classFile = ClassFile.of().parse(bytes);
        String className = classFile.thisClass().asInternalName().replace('/', '.');
        if (!included(className, prefixes)) {
            return;
        }
        String sourceFile = classFile.findAttribute(Attributes.sourceFile()).map(attribute -> attribute.sourceFile().stringValue()).orElse("");
        for (MethodModel method : classFile.methods()) {
            if (method.code().isEmpty()) {
                continue;
            }
            int bci = 0;
            for (CodeElement element : method.code().get()) {
                if (element instanceof Instruction instruction) {
                    Opcode opcode = instruction.opcode();
                    if (opcode == Opcode.NEW || opcode == Opcode.NEWARRAY || opcode == Opcode.ANEWARRAY || opcode == Opcode.MULTIANEWARRAY) {
                        rows.add(new Row(className, method.methodName().stringValue(), method.methodType().stringValue(), bci,
                                        opcode.name(), sourceFile, opcode != Opcode.MULTIANEWARRAY));
                    }
                    bci += instruction.sizeInBytes();
                }
            }
        }
    }

    private static boolean included(String className, String[] prefixes) {
        for (String prefix : prefixes) {
            if (!prefix.isBlank() && className.startsWith(prefix.trim())) {
                return true;
            }
        }
        return false;
    }

    /** Avoids decompressing unrelated classes when a DaCapo library directory contains many JARs. */
    private static boolean includedEntry(String entryName, String[] prefixes) {
        String className = entryName.substring(0, entryName.length() - ".class".length()).replace('/', '.');
        return included(className, prefixes);
    }

    private static String field(String value) {
        return value.replace("%", "%25").replace(";", "%3B").replace("\r", "%0D").replace("\n", "%0A");
    }
}
