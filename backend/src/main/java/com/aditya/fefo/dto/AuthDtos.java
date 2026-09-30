package com.aditya.fefo.dto;

import jakarta.validation.constraints.NotBlank;

public final class AuthDtos {
    private AuthDtos() {
    }

    public record LoginRequest(
            @NotBlank String username,
            @NotBlank String password
    ) {
    }

    public record LoginResponse(
            String accessToken,
            String tokenType,
            long expiresIn,
            UserDto user
    ) {
    }

    public record UserDto(
            String id,
            String username,
            String role
    ) {
    }
}
