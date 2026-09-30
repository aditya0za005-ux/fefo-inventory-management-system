package com.aditya.fefo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class FefoApplication {
    public static void main(String[] args) { SpringApplication.run(FefoApplication.class, args); }
}
