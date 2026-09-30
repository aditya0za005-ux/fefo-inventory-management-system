package com.aditya.fefo.service;

import com.aditya.fefo.domain.Batch;
import com.aditya.fefo.domain.MovementType;
import com.aditya.fefo.domain.Product;
import com.aditya.fefo.domain.StockMovement;
import com.aditya.fefo.dto.BatchDtos.BatchResponse;
import com.aditya.fefo.dto.BatchDtos.CreateBatchRequest;
import com.aditya.fefo.exception.ApiException;
import com.aditya.fefo.repository.BatchRepository;
import com.aditya.fefo.repository.ProductRepository;
import com.aditya.fefo.repository.StockMovementRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@Service
public class BatchService {
    private final BatchRepository batches;
    private final ProductRepository products;
    private final StockMovementRepository movements;

    public BatchService(
            BatchRepository batches,
            ProductRepository products,
            StockMovementRepository movements
    ) {
        this.batches = batches;
        this.products = products;
        this.movements = movements;
    }

    @Transactional
    public BatchResponse create(CreateBatchRequest request, UUID actor) {
        Product product = products.findById(request.productId())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Product not found"));

        if (!product.isActive()) {
            throw new ApiException(HttpStatus.CONFLICT, "Product is inactive");
        }

        Batch batch;
        try {
            batch = new Batch(
                    product,
                    request.batchNumber().trim(),
                    request.expiryDate(),
                    request.quantity()
            );
        } catch (IllegalArgumentException ex) {
            throw new ApiException(HttpStatus.BAD_REQUEST, ex.getMessage());
        }

        if (batches.existsByProduct_IdAndBatchNumberIgnoreCase(product.getId(), batch.getBatchNumber())) {
            throw new ApiException(HttpStatus.CONFLICT, "Batch number already exists for this product");
        }

        batches.save(batch);
        movements.save(new StockMovement(
                product.getId(),
                batch.getId(),
                null,
                MovementType.STOCK_RECEIVED,
                request.quantity(),
                actor,
                "Initial stock receipt"
        ));

        return map(batch);
    }

    @Transactional(readOnly = true)
    public List<BatchResponse> list(UUID productId) {
        List<Batch> result = productId == null
                ? batches.findAll()
                : batches.findByProductIdOrderByExpiryDateAsc(productId);

        return result.stream().map(this::map).toList();
    }

    @Transactional(readOnly = true)
    public BatchResponse get(UUID id) {
        return map(batches.findById(id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Batch not found")));
    }

    private BatchResponse map(Batch batch) {
        LocalDate today = LocalDate.now();

        return new BatchResponse(
                batch.getId(),
                batch.getProduct().getId(),
                batch.getProduct().getName(),
                batch.getBatchNumber(),
                batch.getExpiryDate(),
                batch.getTotalQuantity(),
                batch.getAvailableQuantity(),
                batch.getReservedQuantity(),
                batch.isExpired(),
                !batch.getExpiryDate().isBefore(today)
                        && !batch.getExpiryDate().isAfter(today.plusDays(7)),
                !batch.getExpiryDate().isBefore(today)
                        && !batch.getExpiryDate().isAfter(today.plusDays(30))
        );
    }
}
