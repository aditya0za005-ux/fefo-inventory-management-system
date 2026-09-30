package com.aditya.fefo.domain;

import jakarta.persistence.*;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

@Entity
@Table(name = "batches")
public class Batch {
    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "product_id")
    private Product product;

    @Column(name = "batch_number", nullable = false)
    private String batchNumber;

    @Column(name = "expiry_date", nullable = false)
    private LocalDate expiryDate;

    @Column(name = "total_quantity", nullable = false)
    private long totalQuantity;

    @Column(name = "available_quantity", nullable = false)
    private long availableQuantity;

    @Column(name = "reserved_quantity", nullable = false)
    private long reservedQuantity;

    @Column(nullable = false)
    private boolean expired;

    @Column(name = "created_at")
    private Instant createdAt;

    @Column(name = "updated_at")
    private Instant updatedAt;

    protected Batch() {
    }

    public Batch(Product product, String batchNumber, LocalDate expiryDate, long quantity) {
        if (quantity <= 0) {
            throw new IllegalArgumentException("Batch quantity must be positive");
        }
        if (expiryDate == null || expiryDate.isBefore(LocalDate.now())) {
            throw new IllegalArgumentException("Expiry date cannot be in the past");
        }

        this.id = UUID.randomUUID();
        this.product = product;
        this.batchNumber = batchNumber;
        this.expiryDate = expiryDate;
        this.totalQuantity = quantity;
        this.availableQuantity = quantity;
        this.reservedQuantity = 0;
        this.expired = false;
        this.createdAt = Instant.now();
        this.updatedAt = this.createdAt;
    }

    public UUID getId() {
        return id;
    }

    public Product getProduct() {
        return product;
    }

    public String getBatchNumber() {
        return batchNumber;
    }

    public LocalDate getExpiryDate() {
        return expiryDate;
    }

    public long getTotalQuantity() {
        return totalQuantity;
    }

    public long getAvailableQuantity() {
        return availableQuantity;
    }

    public long getReservedQuantity() {
        return reservedQuantity;
    }

    public boolean isExpired() {
        return expired;
    }

    public void reserve(long quantity) {
        if (quantity <= 0) {
            throw new IllegalArgumentException("Reservation quantity must be positive");
        }
        if (expired || !expiryDate.isAfter(LocalDate.now())) {
            throw new IllegalArgumentException("Batch is expired or expiring today");
        }
        if (availableQuantity < quantity) {
            throw new IllegalArgumentException("Insufficient batch stock");
        }

        availableQuantity -= quantity;
        reservedQuantity += quantity;
        touch();
    }

    public void confirm(long quantity) {
        if (quantity <= 0 || reservedQuantity < quantity) {
            throw new IllegalArgumentException("Invalid reserved quantity");
        }

        reservedQuantity -= quantity;
        touch();
    }

    public void release(long quantity) {
        if (quantity <= 0 || reservedQuantity < quantity) {
            throw new IllegalArgumentException("Invalid reserved quantity");
        }

        reservedQuantity -= quantity;
        availableQuantity += quantity;
        touch();
    }

    public long expireAvailable() {
        long quantity = availableQuantity;
        availableQuantity = 0;
        expired = true;
        touch();
        return quantity;
    }

    public void markExpired() {
        expired = true;
        availableQuantity = 0;
        touch();
    }

    private void touch() {
        updatedAt = Instant.now();
    }
}
