package com.aditya.fefo.dto;
import jakarta.validation.constraints.*; import java.util.UUID;
public final class BenchmarkDtos { private BenchmarkDtos(){} public record Request(@NotNull UUID productId,@Min(1) @Max(100000) int runs,@Positive long reservationQuantity){} public record Strategy(String name,long nearExpiryRemaining,long totalNearExpiry,long nearExpiryPercentage){} public record Response(Strategy fefo,Strategy lifo){} }
