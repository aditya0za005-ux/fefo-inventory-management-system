package com.aditya.fefo.service;

import com.aditya.fefo.domain.AuditLog;
import com.aditya.fefo.domain.Batch;
import com.aditya.fefo.domain.MovementType;
import com.aditya.fefo.domain.StockMovement;
import com.aditya.fefo.repository.AuditLogRepository;
import com.aditya.fefo.repository.BatchRepository;
import com.aditya.fefo.repository.StockMovementRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;

@Service
public class BatchExpiryService {
    private final BatchRepository batches;
    private final StockMovementRepository movements;
    private final AuditLogRepository audit;

    public BatchExpiryService(
            BatchRepository batches,
            StockMovementRepository movements,
            AuditLogRepository audit
    ) {
        this.batches = batches;
        this.movements = movements;
        this.audit = audit;
    }

    @Transactional
    public int markExpired() {
        int count = 0;

        for (Batch batch : batches.findExpired(LocalDate.now())) {
            long available = batch.getAvailableQuantity();
            batch.markExpired();

            if (available > 0) {
                movements.save(new StockMovement(
                        batch.getProduct().getId(),
                        batch.getId(),
                        null,
                        MovementType.STOCK_EXPIRED,
                        available,
                        null,
                        "Batch expired"
                ));

                audit.save(new AuditLog(
                        null,
                        "BATCH_EXPIRED",
                        "BATCH",
                        batch.getId(),
                        available,
                        batch.getProduct().getId(),
                        batch.getId(),
                        null,
                        "Batch expired"
                ));
            }

            count++;
        }

        return count;
    }
}
