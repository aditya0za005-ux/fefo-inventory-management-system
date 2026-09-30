package com.aditya.fefo.dto;
import jakarta.validation.constraints.*; import java.time.LocalDate; import java.util.UUID;
public final class BatchDtos { private BatchDtos(){} public record CreateBatchRequest(@NotNull UUID productId,@NotBlank @Size(max=100) String batchNumber,@NotNull @Future LocalDate expiryDate,@Positive long quantity){} public record BatchResponse(UUID id,UUID productId,String productName,String batchNumber,LocalDate expiryDate,long totalQuantity,long availableQuantity,long reservedQuantity,boolean expired,boolean nearExpiry7,boolean nearExpiry30){} }
