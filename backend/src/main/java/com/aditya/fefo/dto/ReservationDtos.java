package com.aditya.fefo.dto;

import com.aditya.fefo.domain.ReservationStatus;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public final class ReservationDtos {
    private ReservationDtos() {
    }

    public record CreateReservationRequest(
            @NotNull UUID productId,
            @Positive long quantity
    ) {
    }

    public record AllocationResponse(
            UUID batchId,
            String batchNumber,
            LocalDate expiryDate,
            long quantity
    ) {
    }

    public record ReservationResponse(
            UUID id,
            String reservationNumber,
            UUID productId,
            String productName,
            ReservationStatus status,
            long requestedQuantity,
            Instant expiresAt,
            Instant createdAt,
            List<AllocationResponse> items
    ) {
    }

    public record ReservationActionResponse(
            UUID id,
            String reservationNumber,
            ReservationStatus status,
            Instant timestamp
    ) {
    }
}
