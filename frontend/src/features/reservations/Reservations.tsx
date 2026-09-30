import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { productsApi, reservationsApi } from '../../api';
import { DataTable, HoldCountdown, StatusBadge, Toast } from '../../components/ui';
import type { Product, Reservation } from '../../types';

const newKey = () => crypto.randomUUID();

export default function Reservations() {
    const queryClient = useQueryClient();
    const products = useQuery({ queryKey: ['products'], queryFn: productsApi.list });
    const reservations = useQuery({ queryKey: ['reservations'], queryFn: reservationsApi.list });

    const [productId, setProductId] = useState('');
    const [quantity, setQuantity] = useState(1);
    const [message, setMessage] = useState('');

    const create = useMutation({
        mutationFn: () => reservationsApi.create(productId, quantity, newKey()),
        onSuccess: (reservation) => {
            setProductId('');
            setQuantity(1);
            setMessage(`Reserved ${reservation.requestedQuantity} units as ${reservation.reservationNumber}`);
            queryClient.invalidateQueries({ queryKey: ['reservations'] });
            queryClient.invalidateQueries({ queryKey: ['batches'] });
            queryClient.invalidateQueries({ queryKey: ['summary'] });
        }
    });

    const action = useMutation({
        mutationFn: ({ id, type }: { id: string; type: 'confirm' | 'cancel' }) =>
            type === 'confirm'
                ? reservationsApi.confirm(id, newKey())
                : reservationsApi.cancel(id, newKey()),
        onSuccess: (_, variables) => {
            setMessage(`Reservation ${variables.type}ed`);
            queryClient.invalidateQueries({ queryKey: ['reservations'] });
            queryClient.invalidateQueries({ queryKey: ['batches'] });
            queryClient.invalidateQueries({ queryKey: ['summary'] });
        }
    });

    return (
        <div>
            <h1 className="text-2xl font-bold text-slate-900">Reservations</h1>
            <p className="mt-1 text-sm text-slate-500">Reserve stock using First-Expiry-First-Out allocation.</p>

            <form
                className="mt-5 max-w-xl rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
                onSubmit={(event) => {
                    event.preventDefault();
                    create.mutate();
                }}
            >
                <h2 className="font-semibold text-slate-900">Create reservation</h2>
                <label className="mt-4 block text-sm font-medium">
                    Product
                    <select
                        required
                        value={productId}
                        onChange={(event) => setProductId(event.target.value)}
                        className="mt-1 w-full rounded-lg border border-slate-300 p-2.5"
                    >
                        <option value="">Select product</option>
                        {(products.data ?? []).map((product: Product) => (
                            <option key={product.id} value={product.id}>
                                {product.name} ({product.sku})
                            </option>
                        ))}
                    </select>
                </label>
                <label className="mt-4 block text-sm font-medium">
                    Quantity
                    <input
                        required
                        min={1}
                        type="number"
                        value={quantity}
                        onChange={(event) => setQuantity(Number(event.target.value))}
                        className="mt-1 w-full rounded-lg border border-slate-300 p-2.5"
                    />
                </label>
                <button
                    disabled={create.isPending || !productId}
                    className="mt-5 rounded-lg bg-slate-900 px-4 py-2 font-medium text-white disabled:opacity-50"
                >
                    {create.isPending ? 'Reserving…' : 'Reserve with FEFO'}
                </button>
                {create.error && <p className="mt-3 text-sm text-red-700">{create.error.message}</p>}
            </form>

            <div className="mt-6">
                <DataTable<Reservation>
                    rows={reservations.data ?? []}
                    columns={[
                        { key: 'number', header: 'Reservation', render: (reservation) => reservation.reservationNumber },
                        { key: 'product', header: 'Product', render: (reservation) => reservation.productName },
                        { key: 'quantity', header: 'Quantity', render: (reservation) => reservation.requestedQuantity },
                        { key: 'status', header: 'Status', render: (reservation) => <StatusBadge status={reservation.status} /> },
                        {
                            key: 'hold',
                            header: 'Hold',
                            render: (reservation) => reservation.status === 'RESERVED'
                                ? <HoldCountdown expiresAt={reservation.expiresAt} />
                                : '—'
                        },
                        {
                            key: 'allocation',
                            header: 'FEFO allocation',
                            render: (reservation) => (
                                <div className="space-y-1">
                                    {reservation.items.map((item) => (
                                        <div key={item.batchId} className="text-xs">
                                            {item.batchNumber}: {item.quantity} · {item.expiryDate}
                                        </div>
                                    ))}
                                </div>
                            )
                        },
                        {
                            key: 'actions',
                            header: 'Actions',
                            render: (reservation) => reservation.status === 'RESERVED' ? (
                                <div className="flex gap-2">
                                    <button
                                        disabled={action.isPending}
                                        onClick={() => action.mutate({ id: reservation.id, type: 'confirm' })}
                                        className="rounded-lg bg-emerald-700 px-3 py-1.5 text-xs font-medium text-white disabled:opacity-50"
                                    >
                                        Confirm
                                    </button>
                                    <button
                                        disabled={action.isPending}
                                        onClick={() => action.mutate({ id: reservation.id, type: 'cancel' })}
                                        className="rounded-lg border border-slate-300 px-3 py-1.5 text-xs font-medium disabled:opacity-50"
                                    >
                                        Cancel
                                    </button>
                                </div>
                            ) : '—'
                        }
                    ]}
                    keyFn={(reservation) => reservation.id}
                    loading={reservations.isLoading}
                    error={reservations.error?.message}
                    onRetry={() => reservations.refetch()}
                    emptyMessage="No reservations yet."
                />
            </div>

            {action.error && <p className="mt-3 text-sm text-red-700">{action.error.message}</p>}
            {message && <Toast message={message} onClose={() => setMessage('')} />}
        </div>
    );
}
