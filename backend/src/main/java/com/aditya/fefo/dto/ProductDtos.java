package com.aditya.fefo.dto;
import jakarta.validation.constraints.*; import java.util.UUID;
public final class ProductDtos { private ProductDtos(){} public record CreateProductRequest(@NotBlank @Size(max=100) String sku,@NotBlank @Size(max=255) String name,@Size(max=2000) String description){} public record ProductResponse(UUID id,String sku,String name,String description,boolean active){} }
