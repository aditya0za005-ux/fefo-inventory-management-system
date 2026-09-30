package com.aditya.fefo.dto;
import java.time.Instant; import java.util.UUID;
public final class AuditDtos { private AuditDtos(){} public record AuditResponse(UUID id,UUID actorId,String action,String entityType,UUID entityId,Long quantity,UUID productId,UUID batchId,UUID reservationId,String reason,Instant createdAt){} }
