public class Test {
  static int add(int a, int b) {
    return a + b;
  }

  public static void main(String[] args) {
    for (int i = 0; i < 100000; i++) {
      for (int j = 0; j < 100000; j++) {
        add(i, j);
      }
    }
  }
}