package com.aditya.fefo.service;

import com.aditya.fefo.domain.AuditLog;
import com.aditya.fefo.domain.Batch;
import com.aditya.fefo.domain.MovementType;
import com.aditya.fefo.domain.Product;
import com.aditya.fefo.domain.Reservation;
import com.aditya.fefo.domain.ReservationItem;
import com.aditya.fefo.domain.ReservationStatus;
import com.aditya.fefo.domain.StockMovement;
import com.aditya.fefo.domain.User;
import com.aditya.fefo.domain.allocator.Allocation;
import com.aditya.fefo.domain.allocator.FefoAllocator;
import com.aditya.fefo.dto.ReservationDtos.AllocationResponse;
import com.aditya.fefo.dto.ReservationDtos.CreateReservationRequest;
import com.aditya.fefo.dto.ReservationDtos.ReservationActionResponse;
import com.aditya.fefo.dto.ReservationDtos.ReservationResponse;
import com.aditya.fefo.exception.ApiException;
import com.aditya.fefo.infrastructure.RedisLockService;
import com.aditya.fefo.repository.AuditLogRepository;
import com.aditya.fefo.repository.BatchRepository;
import com.aditya.fefo.repository.IdempotencyRepository;
import com.aditya.fefo.repository.ProductRepository;
import com.aditya.fefo.repository.ReservationItemRepository;
import com.aditya.fefo.repository.ReservationRepository;
import com.aditya.fefo.repository.StockMovementRepository;
import com.aditya.fefo.repository.UserRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;

@Service
public class ReservationService {

    private final ProductRepository products;
    private final BatchRepository batches;
    private final UserRepository users;
    private final ReservationRepository reservations;
    private final ReservationItemRepository items;
    private final StockMovementRepository movements;
    private final AuditLogRepository audit;
    private final IdempotencyRepository idempotency;
    private final RedisLockService locks;
    private final TransactionTemplate tx;
    private final ObjectMapper mapper;
    private final long holdMinutes;

    public ReservationService(
            ProductRepository products,
            BatchRepository batches,
            UserRepository users,
            ReservationRepository reservations,
            ReservationItemRepository items,
            StockMovementRepository movements,
            AuditLogRepository audit,
            IdempotencyRepository idempotency,
            RedisLockService locks,
            TransactionTemplate tx,
            ObjectMapper mapper,
            @Value("${app.reservation.hold-minutes}") long holdMinutes
    ) {
        this.products = products;
        this.batches = batches;
        this.users = users;
        this.reservations = reservations;
        this.items = items;
        this.movements = movements;
        this.audit = audit;
        this.idempotency = idempotency;
        this.locks = locks;
        this.tx = tx;
        this.mapper = mapper;
        this.holdMinutes = holdMinutes;
    }

    public ReservationResponse reserve(
            CreateReservationRequest request,
            String idempotencyKey,
            UUID actor
    ) {
        requireIdempotencyKey(idempotencyKey);

        String endpoint = "POST:/api/v1/reservations";
        String requestHash = hash(request.productId() + ":" + request.quantity());

        try (var ignored = locks.acquire(
                "lock:inventory:product:" + request.productId(),
                Duration.ofSeconds(10)
        )) {
            return tx.execute(status -> {

                IdempotencyKeyRecord record =
                        getOrCreateIdempotencyRecord(
                                idempotencyKey,
                                endpoint,
                                requestHash
                        );

                ReservationResponse existing =
                        readStoredReservation(record.entity(), requestHash);

                if (existing != null) {
                    return existing;
                }

                Product product = products.findById(request.productId())
                        .orElseThrow(() ->
                                new ApiException(
                                        HttpStatus.NOT_FOUND,
                                        "Product not found"
                                ));

                User user = users.findById(actor)
                        .orElseThrow(() ->
                                new ApiException(
                                        HttpStatus.UNAUTHORIZED,
                                        "User not found"
                                ));

                List<Batch> eligible = batches.findAllocatableForUpdate(
                        request.productId(),
                        LocalDate.now()
                );

                List<Allocation> allocations;

                try {
                    allocations = FefoAllocator.allocate(
                            eligible,
                            request.quantity()
                    );
                } catch (IllegalArgumentException ex) {
                    throw new ApiException(
                            HttpStatus.CONFLICT,
                            ex.getMessage()
                    );
                }

                Reservation reservation = new Reservation(
                        "RSV-" + UUID.randomUUID()
                                .toString()
                                .substring(0, 8)
                                .toUpperCase(),
                        product,
                        request.quantity(),
                        Instant.now().plus(
                                holdMinutes,
                                ChronoUnit.MINUTES
                        ),
                        user
                );

                reservations.save(reservation);

                for (Allocation allocation : allocations) {

                    Batch batch = eligible.stream()
                            .filter(candidate ->
                                    candidate.getId()
                                            .equals(allocation.batchId()))
                            .findFirst()
                            .orElseThrow();

                    batch.reserve(allocation.quantity());

                    items.save(
                            new ReservationItem(
                                    reservation,
                                    batch,
                                    allocation.quantity()
                            )
                    );

                    movements.save(
                            new StockMovement(
                                    product.getId(),
                                    batch.getId(),
                                    reservation.getId(),
                                    MovementType.STOCK_RESERVED,
                                    allocation.quantity(),
                                    actor,
                                    "FEFO reservation"
                            )
                    );

                    audit.save(
                            new AuditLog(
                                    actor,
                                    "STOCK_RESERVED",
                                    "RESERVATION",
                                    reservation.getId(),
                                    allocation.quantity(),
                                    product.getId(),
                                    batch.getId(),
                                    reservation.getId(),
                                    "FEFO reservation"
                            )
                    );
                }

                ReservationResponse response =
                        toResponse(reservation, allocations);

                completeIdempotency(
                        record,
                        201,
                        response
                );

                return response;
            });
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();

            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "Could not acquire inventory lock"
            );
        }
    }

    public ReservationActionResponse confirm(
            UUID id,
            String key,
            UUID actor
    ) {
        return action(
                id,
                key,
                actor,
                "CONFIRM",
                true
        );
    }

    public ReservationActionResponse cancel(
            UUID id,
            String key,
            UUID actor
    ) {
        return action(
                id,
                key,
                actor,
                "CANCEL",
                false
        );
    }

    private ReservationActionResponse action(
            UUID id,
            String key,
            UUID actor,
            String action,
            boolean confirm
    ) {
        requireIdempotencyKey(key);

        String endpoint =
                "POST:/api/v1/reservations/"
                        + id
                        + "/"
                        + action.toLowerCase();

        String requestHash = hash(id + ":" + action);

        try (var ignored = locks.acquire(
                "lock:reservation:" + id,
                Duration.ofSeconds(10)
        )) {
            return tx.execute(status -> {

                IdempotencyKeyRecord record =
                        getOrCreateIdempotencyRecord(
                                key,
                                endpoint,
                                requestHash
                        );

                ReservationActionResponse existing =
                        readStoredAction(
                                record.entity(),
                                requestHash
                        );

                if (existing != null) {
                    return existing;
                }

                Reservation reservation =
                        reservations.findByIdForUpdate(id)
                                .orElseThrow(() ->
                                        new ApiException(
                                                HttpStatus.NOT_FOUND,
                                                "Reservation not found"
                                        ));

                if (reservation.getStatus()
                        == ReservationStatus.RESERVED
                        && reservation.isHoldExpired(Instant.now())) {

                    releaseReservation(
                            reservation,
                            actor,
                            true
                    );

                    ReservationActionResponse response =
                            new ReservationActionResponse(
                                    reservation.getId(),
                                    reservation.getReservationNumber(),
                                    reservation.getStatus(),
                                    Instant.now()
                            );

                    completeIdempotency(
                            record,
                            409,
                            response
                    );

                    return response;
                }

                try {
                    if (confirm) {
                        reservation.confirm();
                    } else {
                        reservation.cancel();
                    }
                } catch (IllegalStateException ex) {
                    throw new ApiException(
                            HttpStatus.CONFLICT,
                            ex.getMessage()
                    );
                }

                for (ReservationItem item :
                        items.findByReservationId(id)) {

                    Batch batch = item.getBatch();

                    if (confirm) {

                        batch.confirm(item.getQuantity());

                        movements.save(
                                new StockMovement(
                                        reservation.getProduct().getId(),
                                        batch.getId(),
                                        id,
                                        MovementType.STOCK_CONFIRMED,
                                        item.getQuantity(),
                                        actor,
                                        "Reservation confirmed"
                                )
                        );

                        audit.save(
                                new AuditLog(
                                        actor,
                                        "STOCK_CONFIRMED",
                                        "RESERVATION",
                                        id,
                                        item.getQuantity(),
                                        reservation.getProduct().getId(),
                                        batch.getId(),
                                        id,
                                        "Reservation confirmed"
                                )
                        );

                    } else {

                        batch.release(item.getQuantity());

                        movements.save(
                                new StockMovement(
                                        reservation.getProduct().getId(),
                                        batch.getId(),
                                        id,
                                        MovementType.STOCK_RELEASED,
                                        item.getQuantity(),
                                        actor,
                                        "Reservation cancelled"
                                )
                        );

                        audit.save(
                                new AuditLog(
                                        actor,
                                        "STOCK_RELEASED",
                                        "RESERVATION",
                                        id,
                                        item.getQuantity(),
                                        reservation.getProduct().getId(),
                                        batch.getId(),
                                        id,
                                        "Reservation cancelled"
                                )
                        );
                    }
                }

                ReservationActionResponse response =
                        new ReservationActionResponse(
                                reservation.getId(),
                                reservation.getReservationNumber(),
                                reservation.getStatus(),
                                Instant.now()
                        );

                completeIdempotency(
                        record,
                        200,
                        response
                );

                return response;
            });
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();

            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "Could not acquire reservation lock"
            );
        }
    }

    @org.springframework.transaction.annotation.Transactional(readOnly = true)
    public List<ReservationResponse> list() {
        return reservations
                .findTop100ByOrderByCreatedAtDesc()
                .stream()
                .map(this::toResponse)
                .toList();
    }

    @org.springframework.transaction.annotation.Transactional(readOnly = true)
    public ReservationResponse get(UUID id) {
        Reservation reservation =
                reservations.findById(id)
                        .orElseThrow(() ->
                                new ApiException(
                                        HttpStatus.NOT_FOUND,
                                        "Reservation not found"
                                ));

        return toResponse(reservation);
    }

    public void expireHolds() {

        while (true) {

            List<Reservation> expired =
                    reservations
                            .findTop100ByStatusAndExpiresAtLessThanEqualOrderByExpiresAtAsc(
                                    ReservationStatus.RESERVED,
                                    Instant.now()
                            );

            if (expired.isEmpty()) {
                return;
            }

            for (Reservation candidate : expired) {

                try (var ignored = locks.acquire(
                        "lock:reservation:" + candidate.getId(),
                        Duration.ofSeconds(5)
                )) {

                    tx.execute(status -> {

                        Reservation fresh =
                                reservations
                                        .findByIdForUpdate(candidate.getId())
                                        .orElse(null);

                        if (fresh != null
                                && fresh.getStatus()
                                == ReservationStatus.RESERVED
                                && fresh.isHoldExpired(Instant.now())) {

                            releaseReservation(
                                    fresh,
                                    null,
                                    true
                            );
                        }

                        return null;
                    });

                } catch (Exception ignored) {
                    // Another worker can own the lock.
                    // The next scheduler pass will retry it.
                }
            }
        }
    }

    private void releaseReservation(
            Reservation reservation,
            UUID actor,
            boolean expired
    ) {

        for (ReservationItem item :
                items.findByReservationId(reservation.getId())) {

            Batch batch = item.getBatch();

            batch.release(item.getQuantity());

            movements.save(
                    new StockMovement(
                            reservation.getProduct().getId(),
                            batch.getId(),
                            reservation.getId(),
                            MovementType.STOCK_RELEASED,
                            item.getQuantity(),
                            actor,
                            expired
                                    ? "Reservation hold expired"
                                    : "Reservation cancelled"
                    )
            );

            audit.save(
                    new AuditLog(
                            actor,
                            expired
                                    ? "RESERVATION_EXPIRED"
                                    : "STOCK_RELEASED",
                            "RESERVATION",
                            reservation.getId(),
                            item.getQuantity(),
                            reservation.getProduct().getId(),
                            batch.getId(),
                            reservation.getId(),
                            expired
                                    ? "Reservation hold expired"
                                    : "Reservation cancelled"
                    )
            );
        }

        if (expired) {
            reservation.expire();
        }
    }

    private ReservationResponse toResponse(
            Reservation reservation
    ) {

        List<Allocation> allocations =
                items.findByReservationId(reservation.getId())
                        .stream()
                        .map(item ->
                                new Allocation(
                                        item.getBatch().getId(),
                                        item.getBatch().getBatchNumber(),
                                        item.getBatch().getExpiryDate(),
                                        item.getQuantity()
                                )
                        )
                        .toList();

        return toResponse(
                reservation,
                allocations
        );
    }

    private ReservationResponse toResponse(
            Reservation reservation,
            List<Allocation> allocations
    ) {

        return new ReservationResponse(
                reservation.getId(),
                reservation.getReservationNumber(),
                reservation.getProduct().getId(),
                reservation.getProduct().getName(),
                reservation.getStatus(),
                reservation.getRequestedQuantity(),
                reservation.getExpiresAt(),
                reservation.getCreatedAt(),
                allocations.stream()
                        .map(allocation ->
                                new AllocationResponse(
                                        allocation.batchId(),
                                        allocation.batchNumber(),
                                        allocation.expiryDate(),
                                        allocation.quantity()
                                )
                        )
                        .toList()
        );
    }

    private void requireIdempotencyKey(String key) {

        if (key == null || key.isBlank()) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "Idempotency-Key header is required"
            );
        }
    }

    private IdempotencyKeyRecord getOrCreateIdempotencyRecord(
            String key,
            String endpoint,
            String requestHash
    ) {

        var existing =
                idempotency.findByIdempotencyKeyAndEndpoint(
                        key,
                        endpoint
                );

        if (existing.isPresent()) {

            var entity = existing.get();

            if (!entity.getRequestHash().equals(requestHash)) {
                throw new ApiException(
                        HttpStatus.CONFLICT,
                        "Idempotency key reused with different request"
                );
            }

            return new IdempotencyKeyRecord(entity);
        }

        var entity =
                new com.aditya.fefo.domain.IdempotencyKey(
                        key,
                        endpoint,
                        requestHash,
                        Instant.now().plus(
                                24,
                                ChronoUnit.HOURS
                        )
                );

        idempotency.save(entity);

        return new IdempotencyKeyRecord(entity);
    }

    private ReservationResponse readStoredReservation(
            com.aditya.fefo.domain.IdempotencyKey entity,
            String requestHash
    ) {

        if (!entity.getRequestHash().equals(requestHash)) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "Idempotency key reused with different request"
            );
        }

        if (entity.getResponseBody() == null) {
            return null;
        }

        try {
            return mapper.readValue(
                    entity.getResponseBody(),
                    ReservationResponse.class
            );
        } catch (Exception ex) {
            throw new IllegalStateException(
                    "Could not restore idempotent reservation response",
                    ex
            );
        }
    }

    private ReservationActionResponse readStoredAction(
            com.aditya.fefo.domain.IdempotencyKey entity,
            String requestHash
    ) {

        if (!entity.getRequestHash().equals(requestHash)) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "Idempotency key reused with different request"
            );
        }

        if (entity.getResponseBody() == null) {
            return null;
        }

        try {
            return mapper.readValue(
                    entity.getResponseBody(),
                    ReservationActionResponse.class
            );
        } catch (Exception ex) {
            throw new IllegalStateException(
                    "Could not restore idempotent action response",
                    ex
            );
        }
    }

    private void completeIdempotency(
            IdempotencyKeyRecord record,
            int status,
            Object response
    ) {

        try {
            record.entity().complete(
                    status,
                    mapper.writeValueAsString(response)
            );

            idempotency.save(record.entity());
            idempotency.flush();

        } catch (Exception ex) {
            throw new IllegalStateException(
                    "Could not store idempotent response",
                    ex
            );
        }
    }

    private String hash(String value) {

        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256")
                            .digest(
                                    value.getBytes(
                                            StandardCharsets.UTF_8
                                    )
                            )
            );
        } catch (Exception ex) {
            throw new IllegalStateException(ex);
        }
    }

    private record IdempotencyKeyRecord(
            com.aditya.fefo.domain.IdempotencyKey entity
    ) {
    }
}
