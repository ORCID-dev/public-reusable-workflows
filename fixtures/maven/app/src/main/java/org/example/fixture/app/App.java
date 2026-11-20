package org.example.fixture.app;

import org.example.fixture.lib.Greeter;

public final class App {
    private App() {
    }

    public static String run() {
        return Greeter.greet("app");
    }
}
