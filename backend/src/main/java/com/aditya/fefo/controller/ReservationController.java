package com.aditya.fefo.controller;

import com.aditya.fefo.dto.ReservationDtos.CreateReservationRequest;
import com.aditya.fefo.dto.ReservationDtos.ReservationActionResponse;
import com.aditya.fefo.dto.ReservationDtos.ReservationResponse;
import com.aditya.fefo.infrastructure.CurrentUser;
import com.aditya.fefo.service.ReservationService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/reservations")
public class ReservationController {
    private final ReservationService service;

    public ReservationController(ReservationService service) {
        this.service = service;
    }

    @PostMapping
    public ReservationResponse reserve(
            @RequestHeader("Idempotency-Key") String key,
            @Valid @RequestBody CreateReservationRequest request
    ) {
        return service.reserve(request, key, CurrentUser.id());
    }

    @GetMapping
    public List<ReservationResponse> list() {
        return service.list();
    }

    @GetMapping("/{id}")
    public ReservationResponse get(@PathVariable UUID id) {
        return service.get(id);
    }

    @PostMapping("/{id}/confirm")
    public ReservationActionResponse confirm(
            @PathVariable UUID id,
            @RequestHeader("Idempotency-Key") String key
    ) {
        return service.confirm(id, key, CurrentUser.id());
    }

    @PostMapping("/{id}/cancel")
    public ReservationActionResponse cancel(
            @PathVariable UUID id,
            @RequestHeader("Idempotency-Key") String key
    ) {
        return service.cancel(id, key, CurrentUser.id());
    }
}
