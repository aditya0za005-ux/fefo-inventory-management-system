export type Role = 'ADMIN' | 'STAFF';
export type ReservationStatus = 'RESERVED' | 'CONFIRMED' | 'CANCELLED' | 'EXPIRED';

export interface User {
    id: string;
    username: string;
    role: Role;
}

export interface LoginResponse {
    accessToken: string;
    tokenType: string;
    expiresIn: number;
    user: User;
}

export interface Product {
    id: string;
    sku: string;
    name: string;
    description?: string;
    active: boolean;
}

export interface Batch {
    id: string;
    productId: string;
    productName: string;
    batchNumber: string;
    expiryDate: string;
    totalQuantity: number;
    availableQuantity: number;
    reservedQuantity: number;
    expired: boolean;
    nearExpiry7: boolean;
    nearExpiry30: boolean;
}

export interface Allocation {
    batchId: string;
    batchNumber: string;
    expiryDate: string;
    quantity: number;
}

export interface Reservation {
    id: string;
    reservationNumber: string;
    productId: string;
    productName: string;
    status: ReservationStatus;
    requestedQuantity: number;
    expiresAt: string;
    createdAt: string;
    items: Allocation[];
}

export interface Summary {
    totalProducts: number;
    totalBatches: number;
    totalAvailableUnits: number;
    reservedUnits: number;
    nearExpiry7Days: number;
    nearExpiry30Days: number;
    expiredBatches: number;
}

export interface Audit {
    id: string;
    actorId?: string;
    action: string;
    entityType: string;
    entityId: string;
    quantity?: number;
    productId?: string;
    batchId?: string;
    reservationId?: string;
    reason?: string;
    createdAt: string;
}

export interface BenchmarkStrategy {
    name: string;
    nearExpiryRemaining: number;
    totalNearExpiry: number;
    nearExpiryPercentage: number;
}

export interface Benchmark {
    fefo: BenchmarkStrategy;
    lifo: BenchmarkStrategy;
}
