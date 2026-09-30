package com.aditya.fefo.domain.allocator; import java.time.LocalDate; import java.util.UUID; public record Allocation(UUID batchId,String batchNumber,LocalDate expiryDate,long quantity){}
