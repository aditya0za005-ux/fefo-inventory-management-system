package com.aditya.fefo.domain;
import jakarta.persistence.*; import java.time.Instant; import java.util.UUID;
@Entity @Table(name="products") public class Product {
 @Id private UUID id; @Column(nullable=false,unique=true) private String sku; @Column(nullable=false) private String name; private String description; @Column(nullable=false) private boolean active=true; @Column(name="created_at") private Instant createdAt; @Column(name="updated_at") private Instant updatedAt;
 protected Product(){} public Product(String sku,String name,String description){this.id=UUID.randomUUID();this.sku=sku;this.name=name;this.description=description;this.createdAt=Instant.now();this.updatedAt=this.createdAt;} public UUID getId(){return id;} public String getSku(){return sku;} public String getName(){return name;} public String getDescription(){return description;} public boolean isActive(){return active;}
}
