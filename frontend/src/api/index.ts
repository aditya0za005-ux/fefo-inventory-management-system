import { api } from './client';
import type {
    Audit,
    Batch,
    Benchmark,
    Product,
    Reservation,
    Summary
} from '../types';

export const productsApi = {
    list: () => api<Product[]>('/products'),
    create: (request: { sku: string; name: string; description?: string }) =>
        api<Product>('/products', {
            method: 'POST',
            body: JSON.stringify(request)
        })
};

export const batchesApi = {
    list: (productId?: string) =>
        api<Batch[]>(`/batches${productId ? `?productId=${encodeURIComponent(productId)}` : ''}`),
    create: (request: {
        productId: string;
        batchNumber: string;
        expiryDate: string;
        quantity: number;
    }) =>
        api<Batch>('/batches', {
            method: 'POST',
            body: JSON.stringify(request)
        })
};

export const dashboardApi = {
    summary: () => api<Summary>('/dashboard/summary')
};

export const reservationsApi = {
    list: () => api<Reservation[]>('/reservations'),
    get: (id: string) => api<Reservation>(`/reservations/${id}`),
    create: (productId: string, quantity: number, key: string) =>
        api<Reservation>('/reservations', {
            method: 'POST',
            headers: { 'Idempotency-Key': key },
            body: JSON.stringify({ productId, quantity })
        }),
    confirm: (id: string, key: string) =>
        api(`/reservations/${id}/confirm`, {
            method: 'POST',
            headers: { 'Idempotency-Key': key }
        }),
    cancel: (id: string, key: string) =>
        api(`/reservations/${id}/cancel`, {
            method: 'POST',
            headers: { 'Idempotency-Key': key }
        })
};

export const auditApi = {
    list: () => api<Audit[]>('/audit-logs')
};

export const benchmarkApi = {
    run: (productId: string, runs: number, reservationQuantity: number) =>
        api<Benchmark>('/benchmarks/fefo-vs-lifo', {
            method: 'POST',
            body: JSON.stringify({ productId, runs, reservationQuantity })
        })
};
