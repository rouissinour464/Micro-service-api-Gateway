package com.example.gateway;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
class ApiGatewayApplicationTests {

    @Test
    void contextLoads() {
        // ✅ Le test passe si le contexte Spring démarre correctement
        assertThat(true).isTrue();
    }
}
