class Point {
  int x;
  int y;

  static Point p;

  Point() {
    this.x = 0;
    this.y = 0;
  }

  Point(int x, int y) {
    this.x = x;
    this.y = y;
  }

  int add(int a, int b, boolean escape) {
    Point p = new Point(a, b);
    if (escape) {
      Point.p = p;
      return 0;
    }
    int sum = p.x + p.y;
    return sum;
  }
}

public class Test {
  public static void main(String[] args) {
    Point p = new Point();
    for (int i = 0; i < 100_000; i++) {
      for (int j = 0; j < 100_000; j++) {
        p.add(i, j, i % 10 == 0);
      }
    }
  }
}
