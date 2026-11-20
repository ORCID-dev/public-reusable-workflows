package org.example.fixture.app;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class AppTest {
    @Test
    void usesLib() {
        assertEquals("Hello, app", App.run());
    }
}
