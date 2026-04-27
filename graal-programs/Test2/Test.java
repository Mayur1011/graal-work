class B {
  int x;

  static B s;

  B bar(boolean escape) {
    B tmp = new B();
    tmp.x = 42;
    if (escape) {
      s = tmp; // escapes here should be MATERIALIZED on this path
      return null;
    }
    return null; // doesn't escape should stays virtual on this path
  }
}

public class Test {
  public static void main(String[] args) {
    B b = new B();
    for (int i = 0; i < 100_000; i++) {
      for (int j = 0; j < 100_000; j++) {
        b.bar(i % 10 == 0);
      }
    }
  }
}


/*
In a compiler, an object's state is not a single, global tag.
The compiler tracks the state of the object at every specific point in the control flow graph.

looking at the Loop Header (BCI 10), it is a Merge Point where two distinct paths of the code join together.

The compiler looks at its storage/tracking info for the incoming paths:
1. Path A (outside): "Snapshot says b is VIRTUAL."
2. Path B (loop around): "Snapshot says b is MATERIALIZED."

the exact same object b.
The compiler knows it is the same object because it tracks its unique ID (e.g., virtual object with id 0).

But because the compiler traces timelines (execution paths), it arrives at the loop header with two conflicting timelines for that single object.
*/