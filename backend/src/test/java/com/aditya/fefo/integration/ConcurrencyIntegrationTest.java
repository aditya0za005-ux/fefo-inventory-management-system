package com.aditya.fefo.integration;

import com.aditya.fefo.domain.*;
import com.aditya.fefo.dto.ReservationDtos.CreateReservationRequest;
import com.aditya.fefo.repository.*;
import com.aditya.fefo.service.ReservationService;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.*;

import static org.junit.jupiter.api.Assertions.*;

@Testcontainers
@SpringBootTest
class ConcurrencyIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres =
            new PostgreSQLContainer<>("postgres:16-alpine")
                    .withDatabaseName("fefo")
                    .withUsername("fefo")
                    .withPassword("fefo");

    @Container
    static GenericContainer<?> redis =
            new GenericContainer<>("redis:7-alpine")
                    .withExposedPorts(6379);

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", postgres::getJdbcUrl);
        r.add("spring.datasource.username", postgres::getUsername);
        r.add("spring.datasource.password", postgres::getPassword);
        r.add("spring.data.redis.host", redis::getHost);
        r.add("spring.data.redis.port", () -> redis.getMappedPort(6379));
    }

    @Autowired
    ReservationService service;

    @Autowired
    ProductRepository products;

    @Autowired
    BatchRepository batches;

    @Autowired
    UserRepository users;

    @Test
    void twoHundredConcurrentRequestsNeverOversell() throws Exception {

        Product p = new Product(
                "CONC-" + UUID.randomUUID(),
                "Concurrency Test Milk",
                ""
        );

        products.saveAndFlush(p);

        Batch b = new Batch(
                p,
                "CONC-" + UUID.randomUUID(),
                LocalDate.now().plusDays(5),
                10
        );

        batches.saveAndFlush(b);

        UUID actor = users.findByUsername("staff")
                .orElseThrow()
                .getId();

        ExecutorService pool = Executors.newFixedThreadPool(40);

        CountDownLatch start = new CountDownLatch(1);

        List<Future<Boolean>> futures = new ArrayList<>();

        for (int i = 0; i < 200; i++) {
            futures.add(pool.submit(() -> {

                start.await();

                try {
                    service.reserve(
                            new CreateReservationRequest(
                                    p.getId(),
                                    1
                            ),
                            UUID.randomUUID().toString(),
                            actor
                    );

                    return true;

                } catch (Exception e) {
                    return false;
                }
            }));
        }

        start.countDown();

        int success = 0;

        for (Future<Boolean> future : futures) {
            if (future.get()) {
                success++;
            }
        }

        pool.shutdown();

        assertTrue(
                pool.awaitTermination(30, TimeUnit.SECONDS),
                "Worker pool did not terminate"
        );

        Batch after = batches.findById(b.getId())
                .orElseThrow();

        assertEquals(10, success);
        assertEquals(0, after.getAvailableQuantity());
        assertEquals(10, after.getReservedQuantity());
        assertTrue(after.getAvailableQuantity() >= 0);
    }
}