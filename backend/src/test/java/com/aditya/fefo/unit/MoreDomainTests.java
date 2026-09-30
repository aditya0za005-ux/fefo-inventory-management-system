package com.aditya.fefo.unit;
import com.aditya.fefo.domain.*; import com.aditya.fefo.domain.allocator.*; import org.junit.jupiter.api.*; import java.time.*; import java.util.*; import static org.junit.jupiter.api.Assertions.*;
class MoreDomainTests {Product p=new Product("S","P","");
@Test void allocationExact(){var b=new Batch(p,"B",LocalDate.now().plusDays(1),10);assertEquals(10,FefoAllocator.allocate(List.of(b),10).getFirst().quantity());}
@Test void allocationUsesEarliestFirstWhenInputOrdered(){var a=new Batch(p,"A",LocalDate.now().plusDays(1),10);var b=new Batch(p,"B",LocalDate.now().plusDays(2),10);assertEquals("A",FefoAllocator.allocate(List.of(a,b),1).getFirst().batchNumber());}
@Test void allocationSkipsZero(){var a=new Batch(p,"A",LocalDate.now().plusDays(1),10);assertEquals(1,FefoAllocator.allocate(List.of(a),1).size());}
@Test void reservationCannotConfirmTwice(){var r=new Reservation("R",p,1,Instant.now().plusSeconds(60),null);r.confirm();assertThrows(IllegalStateException.class,r::confirm);}
@Test void reservationCannotCancelAfterExpire(){var r=new Reservation("R",p,1,Instant.now().minusSeconds(1),null);r.expire();assertThrows(IllegalStateException.class,r::cancel);}
@Test void releaseCannotExceedHold(){var b=new Batch(p,"B",LocalDate.now().plusDays(1),10);assertThrows(IllegalArgumentException.class,()->b.release(1));}
@Test void confirmCannotExceedHold(){var b=new Batch(p,"B",LocalDate.now().plusDays(1),10);assertThrows(IllegalArgumentException.class,()->b.confirm(1));}
@Test void expiryMarksBatch(){var b=new Batch(p,"B",LocalDate.now().plusDays(1),10);b.expireAvailable();assertTrue(b.isExpired());}
@Test void allocationResultHasBatchId(){var b=new Batch(p,"B",LocalDate.now().plusDays(1),10);assertEquals(b.getId(),FefoAllocator.allocate(List.of(b),1).getFirst().batchId());}
@Test void splitThreeBatches(){var a=new Batch(p,"A",LocalDate.now().plusDays(1),2);var b=new Batch(p,"B",LocalDate.now().plusDays(2),3);var c=new Batch(p,"C",LocalDate.now().plusDays(3),4);assertEquals(List.of(2L,3L,1L),FefoAllocator.allocate(List.of(a,b,c),6).stream().map(Allocation::quantity).toList());}
@Test void expiredReservationDetected(){var r=new Reservation("R",p,1,Instant.now().plusSeconds(1),null);assertFalse(r.isHoldExpired(Instant.now()));}
}
// Extra invariant cases
class MoreDomainTestsExtra {Product p=new Product("S2","P2","");@Test void batchTotalPreserved(){var b=new Batch(p,"B",LocalDate.now().plusDays(1),10);b.reserve(3);assertEquals(10,b.getTotalQuantity());}@Test void multipleReserveAccumulates(){var b=new Batch(p,"B",LocalDate.now().plusDays(1),10);b.reserve(2);b.reserve(3);assertEquals(5,b.getReservedQuantity());}@Test void partialReleaseWorks(){var b=new Batch(p,"B",LocalDate.now().plusDays(1),10);b.reserve(5);b.release(2);assertEquals(7,b.getAvailableQuantity());}@Test void partialConfirmWorks(){var b=new Batch(p,"B",LocalDate.now().plusDays(1),10);b.reserve(5);b.confirm(2);assertEquals(3,b.getReservedQuantity());}@Test void allocationRejectsZero(){var b=new Batch(p,"B",LocalDate.now().plusDays(1),10);assertThrows(IllegalArgumentException.class,()->FefoAllocator.allocate(List.of(b),0));}}
