package com.aditya.fefo.domain;

import jakarta.persistence.*;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "reservations")
public class Reservation {
    @Id
    private UUID id;

    @Column(name = "reservation_number", nullable = false, unique = true)
    private String reservationNumber;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "product_id", nullable = false)
    private Product product;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ReservationStatus status;

    @Column(name = "requested_quantity", nullable = false)
    private long requestedQuantity;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "created_by", nullable = false)
    private User createdBy;

    @Column(name = "created_at")
    private Instant createdAt;

    @Column(name = "updated_at")
    private Instant updatedAt;

    @Version
    private long version;

    protected Reservation() {
    }

    public Reservation(
            String reservationNumber,
            Product product,
            long requestedQuantity,
            Instant expiresAt,
            User createdBy
    ) {
        if (requestedQuantity <= 0) {
            throw new IllegalArgumentException("Requested quantity must be positive");
        }

        this.id = UUID.randomUUID();
        this.reservationNumber = reservationNumber;
        this.product = product;
        this.status = ReservationStatus.RESERVED;
        this.requestedQuantity = requestedQuantity;
        this.expiresAt = expiresAt;
        this.createdBy = createdBy;
        this.createdAt = Instant.now();
        this.updatedAt = this.createdAt;
    }

    public UUID getId() {
        return id;
    }

    public String getReservationNumber() {
        return reservationNumber;
    }

    public Product getProduct() {
        return product;
    }

    public ReservationStatus getStatus() {
        return status;
    }

    public long getRequestedQuantity() {
        return requestedQuantity;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public User getCreatedBy() {
        return createdBy;
    }

    public void confirm() {
        require(ReservationStatus.RESERVED);
        status = ReservationStatus.CONFIRMED;
        touch();
    }

    public void cancel() {
        require(ReservationStatus.RESERVED);
        status = ReservationStatus.CANCELLED;
        touch();
    }

    public void expire() {
        require(ReservationStatus.RESERVED);
        status = ReservationStatus.EXPIRED;
        touch();
    }

    public boolean isHoldExpired(Instant now) {
        return !expiresAt.isAfter(now);
    }

    private void require(ReservationStatus required) {
        if (status != required) {
            throw new IllegalStateException("Reservation is " + status);
        }
    }

    private void touch() {
        updatedAt = Instant.now();
    }
}
