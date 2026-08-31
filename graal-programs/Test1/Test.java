public class Test {

    static int add(int a, int b) {
        return a + b;
    }

    public static void main(String[] args) {
        A a = new A();
        for (int i = 0; i < 100000; i++) {
            for (int j = 0; j < 100000; j++) {
                // add(i, j);
                a.foo(true);
            }
        }
    }
}

class A {

    int x;

    int foo(boolean b) {
        A a = new A(); // BCI ~?
        a.x = 10;

        if (b) {
            return a.x; // no escape
        }
        return 0;
    }
}
