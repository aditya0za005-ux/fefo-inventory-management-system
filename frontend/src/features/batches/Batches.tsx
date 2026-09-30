import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { batchesApi, productsApi } from '../../api';
import { DataTable, ExpiryIndicator, Toast } from '../../components/ui';
import type { Batch, Product } from '../../types';

export default function Batches() {
    const queryClient = useQueryClient();
    const isAdmin = localStorage.getItem('role') === 'ADMIN';
    const products = useQuery({ queryKey: ['products'], queryFn: productsApi.list });
    const query = useQuery({ queryKey: ['batches'], queryFn: () => batchesApi.list() });

    const [productId, setProductId] = useState('');
    const [batchNumber, setBatchNumber] = useState('');
    const [expiryDate, setExpiryDate] = useState('');
    const [quantity, setQuantity] = useState(1);
    const [message, setMessage] = useState('');

    const create = useMutation({
        mutationFn: () => batchesApi.create({ productId, batchNumber, expiryDate, quantity }),
        onSuccess: (batch) => {
            setProductId('');
            setBatchNumber('');
            setExpiryDate('');
            setQuantity(1);
            setMessage(`Created batch ${batch.batchNumber}`);
            queryClient.invalidateQueries({ queryKey: ['batches'] });
            queryClient.invalidateQueries({ queryKey: ['summary'] });
        }
    });

    return (
        <div>
            <h1 className="text-2xl font-bold text-slate-900">Batches</h1>
            <p className="mt-1 text-sm text-slate-500">Track stock by batch and expiry date.</p>

            {isAdmin && (
                <form
                    className="mt-5 rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
                    onSubmit={(event) => {
                        event.preventDefault();
                        create.mutate();
                    }}
                >
                    <h2 className="font-semibold text-slate-900">Receive stock</h2>
                    <div className="mt-4 grid gap-4 md:grid-cols-4">
                        <label className="text-sm font-medium">
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
                        <label className="text-sm font-medium">
                            Batch number
                            <input
                                required
                                maxLength={100}
                                value={batchNumber}
                                onChange={(event) => setBatchNumber(event.target.value)}
                                className="mt-1 w-full rounded-lg border border-slate-300 p-2.5"
                            />
                        </label>
                        <label className="text-sm font-medium">
                            Expiry date
                            <input
                                required
                                type="date"
                                min={new Date(Date.now() + 86400000).toISOString().slice(0, 10)}
                                value={expiryDate}
                                onChange={(event) => setExpiryDate(event.target.value)}
                                className="mt-1 w-full rounded-lg border border-slate-300 p-2.5"
                            />
                        </label>
                        <label className="text-sm font-medium">
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
                    </div>
                    <button
                        disabled={create.isPending || products.isLoading}
                        className="mt-4 rounded-lg bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
                    >
                        {create.isPending ? 'Receiving…' : 'Receive stock'}
                    </button>
                    {create.error && <p className="mt-3 text-sm text-red-700">{create.error.message}</p>}
                </form>
            )}

            <div className="mt-5">
                <DataTable<Batch>
                    rows={query.data ?? []}
                    columns={[
                        { key: 'batch', header: 'Batch', render: (batch) => batch.batchNumber },
                        { key: 'product', header: 'Product', render: (batch) => batch.productName },
                        {
                            key: 'expiry',
                            header: 'Expiry',
                            render: (batch) => (
                                <ExpiryIndicator
                                    date={batch.expiryDate}
                                    near7={batch.nearExpiry7}
                                    near30={batch.nearExpiry30}
                                    expired={batch.expired}
                                />
                            )
                        },
                        { key: 'total', header: 'Total', render: (batch) => batch.totalQuantity },
                        { key: 'available', header: 'Available', render: (batch) => batch.availableQuantity },
                        { key: 'reserved', header: 'Reserved', render: (batch) => batch.reservedQuantity }
                    ]}
                    keyFn={(batch) => batch.id}
                    loading={query.isLoading}
                    error={query.error?.message}
                    onRetry={() => query.refetch()}
                    emptyMessage="No batches found."
                />
            </div>

            {message && <Toast message={message} onClose={() => setMessage('')} />}
        </div>
    );
}
