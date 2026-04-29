class G {
  int count;

  void loopTest() {
    G acc = new G();
    for (int i = 0; i < 100; i++) {
      acc.count += i; // mutated across loop iterations
    }
    G.sink = acc;
  }

  static G sink;
}

public class Test {
  public static void main(String[] args) {
    G g = new G();
    for (int i = 0; i < 100_000; i++) {
      for (int j = 0; j < 100_000; j++) {
        g.loopTest();
      }
    }
  }
}

/*
 * Compiler Logs:
 * CompileCommand: dontinline G.loopTest bool dontinline = true
 * HotSpotGraalCompiler created with options:
 * {CompilationFailureAction=Diagnose, DumpOnError=true,
 * ObjdumpExecutables=objdump,gobjdump, PartialEscapeAnalysis=true,
 * PrintGraph=Network, ShowDumpFiles=true, TrackNodeSourcePosition=true}
 * ==========================================================
 * [PartialEscapePhase.java] Running on: G.loopTest()
 * ==========================================================
 * [PartialEscapePhase.java] Running on: G.loopTest()
 * -------------------------------------------------
 * [VirtualizerToolImpl.java] Creating virtual object with id: 0 in class: G
 * [VirtualizerToolImpl.java] Current node: 3|NewInstance
 * [VirtualizerToolImpl.java] Source position of current node: at
 * G.loopTest(Test.java:5) [bci: 0]
 * -------------------------------------------------
 * -------------------------------------------------
 * [PartialEscapeClosure.java]: Materializing virtual object with id: 0 in
 * method: loopTest (class: G)
 * [PartialEscapeClosure.java]: 25|StoreField#sink at BCI: 33
 * [PartialEscapeClosure.java]: Virtual object source position: at
 * G.loopTest(Test.java:5) [bci: 0] at BCI: 0
 * -------------------------------------------------
 * -------------------------------------------------
 * [VirtualizerToolImpl.java] Creating virtual object with id: 0 in class: G
 * [VirtualizerToolImpl.java] Current node: 2034|CommitAllocation
 * [VirtualizerToolImpl.java] Source position of current node: at G.loopTest()
 * [bci: -6] Placeholder
 * -------------------------------------------------
 * -------------------------------------------------
 * [PartialEscapeClosure.java]: Materializing virtual object with id: 0 in
 * method: loopTest (class: G)
 * [PartialEscapeClosure.java]: 25|StoreField#sink at BCI: 33
 * [PartialEscapeClosure.java]: Virtual object source position: at
 * G.loopTest(Test.java:5) [bci: 0] at BCI: 0
 * -------------------------------------------------
 * ==========================================================
 * [PartialEscapePhase.java] Running on: Test.main(String[])
 */