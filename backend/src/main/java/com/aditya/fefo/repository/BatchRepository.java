package com.aditya.fefo.repository;

import com.aditya.fefo.domain.Batch;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public interface BatchRepository extends JpaRepository<Batch, UUID> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            select b
            from Batch b
            where b.product.id = :productId
              and b.availableQuantity > 0
              and b.expired = false
              and b.expiryDate > :today
            order by b.expiryDate asc, b.id asc
            """)
    List<Batch> findAllocatableForUpdate(
            @Param("productId") UUID productId,
            @Param("today") LocalDate today
    );

    List<Batch> findByProductIdOrderByExpiryDateAsc(UUID productId);

    boolean existsByProduct_IdAndBatchNumberIgnoreCase(UUID productId, String batchNumber);

    @Query("""
            select b
            from Batch b
            where b.expiryDate <= :today
              and b.expired = false
            order by b.expiryDate asc, b.id asc
            """)
    List<Batch> findExpired(@Param("today") LocalDate today);

    long countByExpiredTrue();

    @Query("select coalesce(sum(b.availableQuantity), 0) from Batch b")
    long sumAvailable();

    @Query("select coalesce(sum(b.reservedQuantity), 0) from Batch b")
    long sumReserved();

    long countByExpiryDateBetweenAndExpiredFalse(LocalDate from, LocalDate to);
}
