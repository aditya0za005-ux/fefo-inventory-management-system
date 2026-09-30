package com.aditya.fefo.service;

import com.aditya.fefo.domain.User;
import com.aditya.fefo.dto.AuthDtos.*;
import com.aditya.fefo.exception.ApiException;
import com.aditya.fefo.repository.UserRepository;
import com.aditya.fefo.security.JwtService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
public class AuthService {

    private static final Logger log =
            LoggerFactory.getLogger(AuthService.class);

    private final UserRepository users;
    private final PasswordEncoder encoder;
    private final JwtService jwt;

    public AuthService(
            UserRepository users,
            PasswordEncoder encoder,
            JwtService jwt
    ) {
        this.users = users;
        this.encoder = encoder;
        this.jwt = jwt;
    }

    public LoginResponse login(LoginRequest req) {

        log.info(
                "Login attempt for username='{}'",
                req.username()
        );

        User user = users.findByUsername(req.username())
                .orElseThrow(() -> {
                    log.warn(
                            "Login failed: user '{}' was not found",
                            req.username()
                    );

                    return new ApiException(
                            HttpStatus.UNAUTHORIZED,
                            "Invalid credentials"
                    );
                });

        log.info(
                "User found: username='{}', role='{}', active={}",
                user.getUsername(),
                user.getRole(),
                user.isActive()
        );

        boolean passwordMatches =
                encoder.matches(
                        req.password(),
                        user.getPasswordHash()
                );

        log.info(
                "Password match result for username='{}': {}",
                user.getUsername(),
                passwordMatches
        );

        if (!user.isActive()) {
            log.warn(
                    "Login failed: user '{}' is inactive",
                    user.getUsername()
            );

            throw new ApiException(
                    HttpStatus.UNAUTHORIZED,
                    "Invalid credentials"
            );
        }

        if (!passwordMatches) {
            log.warn(
                    "Login failed: password does not match for user '{}'",
                    user.getUsername()
            );

            throw new ApiException(
                    HttpStatus.UNAUTHORIZED,
                    "Invalid credentials"
            );
        }

        log.info(
                "Authentication successful for username='{}'",
                user.getUsername()
        );

        String accessToken =
                jwt.issue(
                        user.getId(),
                        user.getUsername(),
                        user.getRole().name()
                );

        return new LoginResponse(
                accessToken,
                "Bearer",
                jwt.expiration(),
                new UserDto(
                        user.getId().toString(),
                        user.getUsername(),
                        user.getRole().name()
                )
        );
    }
}