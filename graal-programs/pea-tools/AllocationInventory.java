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
// this code scans the .class and finds the allocation bytecodes and records them in a CSV file
// the reason i am doing this is to get the allocation count, as not all methods will reach PEA. so we cannt get the alloc count from PEA.
public final class AllocationInventory {
    private record Row(String className, String method, String descriptor, int bci, String opcode,
                       String sourceFile, boolean peaSupported) {
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
                for (Path path : paths.filter(path -> path.toString().endsWith(".class")).toList()) {
                    addRows(Files.readAllBytes(path), prefixes, rows);
                }
            }
        } else {
            try (JarFile jar = new JarFile(input.toFile())) {
                var entries = jar.stream().filter(entry -> !entry.isDirectory() && entry.getName().endsWith(".class") && !entry.getName().startsWith("META-INF/versions/")).toList();
                for (var entry : entries) {
                    try (InputStream stream = jar.getInputStream(entry)) {
                        addRows(stream.readAllBytes(), prefixes, rows);
                    }
                }
            }
        }
        rows.sort(Comparator.comparing(Row::className).thenComparing(Row::method).thenComparing(Row::descriptor).thenComparingInt(Row::bci));
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(output))) {
            out.println("record;class;method;descriptor;bci;opcode;source_file;pea_supported");
            for (Row row : rows) {
                out.printf("site;%s;%s;%s;%d;%s;%s;%s%n", row.className, row.method, row.descriptor, row.bci,
                                row.opcode, row.sourceFile, row.peaSupported);
            }
            long supported = rows.stream().filter(Row::peaSupported).count();
            out.printf("summary;total_explicit_allocation_sites;%d%n", rows.size());
            out.printf("summary;pea_supported_allocation_sites;%d%n", supported);
            out.printf("summary;multianewarray_sites;%d%n", rows.size() - supported);
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
            String methodName = method.methodName().stringValue();
            String descriptor = method.methodType().stringValue();
            int bci = 0;
            for (CodeElement element : method.code().get()) {
                if (element instanceof Instruction instruction) {
                    Opcode opcode = instruction.opcode();
                    if (opcode == Opcode.NEW || opcode == Opcode.NEWARRAY || opcode == Opcode.ANEWARRAY || opcode == Opcode.MULTIANEWARRAY) {
                        rows.add(new Row(className, methodName, descriptor, bci, opcode.name(), sourceFile,
                                        opcode != Opcode.MULTIANEWARRAY));
                    }
                    bci += instruction.sizeInBytes();
                }
            }
        }
    }

    private static boolean included(String className, String[] prefixes) {
        for (String prefix : prefixes) {
            if (className.startsWith(prefix.trim())) {
                return true;
            }
        }
        return false;
    }
}
