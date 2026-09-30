package com.aditya.fefo.domain;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name="users")
public class User {
 @Id private UUID id; @Column(nullable=false,unique=true) private String username; @Column(name="password_hash",nullable=false) private String passwordHash;
 @Enumerated(EnumType.STRING) @Column(nullable=false) private Role role; @Column(nullable=false) private boolean active=true; @Column(name="created_at",nullable=false) private Instant createdAt;
 protected User(){} public UUID getId(){return id;} public String getUsername(){return username;} public String getPasswordHash(){return passwordHash;} public Role getRole(){return role;} public boolean isActive(){return active;}
}
