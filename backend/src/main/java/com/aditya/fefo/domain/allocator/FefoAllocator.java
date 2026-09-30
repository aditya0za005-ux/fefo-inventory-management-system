package com.aditya.fefo.domain.allocator;
import com.aditya.fefo.domain.Batch; import java.time.LocalDate; import java.util.*;
public final class FefoAllocator {
 private FefoAllocator(){}
 public static List<Allocation> allocate(List<Batch> batches,long requested){ if(requested<=0) throw new IllegalArgumentException("Requested quantity must be positive"); long remaining=requested; List<Allocation> out=new ArrayList<>(); for(Batch b:batches){ if(b.isExpired()||!b.getExpiryDate().isAfter(LocalDate.now())||b.getAvailableQuantity()<=0) continue; long take=Math.min(remaining,b.getAvailableQuantity()); out.add(new Allocation(b.getId(),b.getBatchNumber(),b.getExpiryDate(),take)); remaining-=take; if(remaining==0) break; } if(remaining>0) throw new IllegalArgumentException("Insufficient stock"); return out; }
}
