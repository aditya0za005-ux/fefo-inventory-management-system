package com.aditya.fefo.exception;

import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.net.URI;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log =
            LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private ResponseEntity<ProblemDetail> problem(
            HttpStatus status,
            String title,
            String detail,
            HttpServletRequest request
    ) {
        ProblemDetail problem =
                ProblemDetail.forStatusAndDetail(status, detail);

        problem.setTitle(title);

        problem.setType(
                URI.create(
                        "https://api.fefo.local/problems/" + status.value()
                )
        );

        problem.setInstance(
                URI.create(request.getRequestURI())
        );

        problem.setProperty(
                "timestamp",
                Instant.now()
        );

        return ResponseEntity
                .status(status)
                .body(problem);
    }

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ProblemDetail> api(
            ApiException exception,
            HttpServletRequest request
    ) {
        return problem(
                exception.status(),
                exception.status().getReasonPhrase(),
                exception.getMessage(),
                request
        );
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ProblemDetail> validation(
            MethodArgumentNotValidException exception,
            HttpServletRequest request
    ) {
        ProblemDetail problem =
                ProblemDetail.forStatusAndDetail(
                        HttpStatus.BAD_REQUEST,
                        "Request validation failed"
                );

        problem.setTitle("Validation failed");

        problem.setType(
                URI.create(
                        "https://api.fefo.local/problems/validation"
                )
        );

        Map<String, String> errors =
                new LinkedHashMap<>();

        exception
                .getBindingResult()
                .getFieldErrors()
                .forEach(error ->
                        errors.put(
                                error.getField(),
                                error.getDefaultMessage()
                        )
                );

        problem.setProperty("errors", errors);

        problem.setInstance(
                URI.create(request.getRequestURI())
        );

        return ResponseEntity
                .badRequest()
                .body(problem);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ProblemDetail> generic(
            Exception exception,
            HttpServletRequest request
    ) {
        /*
         * IMPORTANT:
         * Log the complete exception so we can see the real
         * backend failure in Docker logs.
         */
        log.error(
                "Unhandled exception while processing {} {}",
                request.getMethod(),
                request.getRequestURI(),
                exception
        );

        return problem(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "Internal Server Error",
                "An unexpected error occurred.",
                request
        );
    }
}