package com.aditya.fefo.dto;
public final class DashboardDtos { private DashboardDtos(){} public record Summary(long totalProducts,long totalBatches,long totalAvailableUnits,long reservedUnits,long nearExpiry7Days,long nearExpiry30Days,long expiredBatches){} }
