import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { productsApi } from '../../api';
import { DataTable, Toast } from '../../components/ui';
import type { Product } from '../../types';

export default function Products() {
    const queryClient = useQueryClient();
    const query = useQuery({ queryKey: ['products'], queryFn: productsApi.list });
    const isAdmin = localStorage.getItem('role') === 'ADMIN';
    const [sku, setSku] = useState('');
    const [name, setName] = useState('');
    const [description, setDescription] = useState('');
    const [message, setMessage] = useState('');

    const create = useMutation({
        mutationFn: () => productsApi.create({ sku, name, description }),
        onSuccess: (product) => {
            setSku('');
            setName('');
            setDescription('');
            setMessage(`Created ${product.name}`);
            queryClient.invalidateQueries({ queryKey: ['products'] });
        }
    });

    return (
        <div>
            <div>
                <h1 className="text-2xl font-bold text-slate-900">Products</h1>
                <p className="mt-1 text-sm text-slate-500">Manage products stored in the warehouse.</p>
            </div>

            {isAdmin && (
                <form
                    className="mt-5 rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
                    onSubmit={(event) => {
                        event.preventDefault();
                        create.mutate();
                    }}
                >
                    <h2 className="font-semibold text-slate-900">Add product</h2>
                    <div className="mt-4 grid gap-4 md:grid-cols-3">
                        <label className="text-sm font-medium">
                            SKU
                            <input
                                required
                                maxLength={100}
                                value={sku}
                                onChange={(event) => setSku(event.target.value)}
                                className="mt-1 w-full rounded-lg border border-slate-300 p-2.5"
                            />
                        </label>
                        <label className="text-sm font-medium">
                            Name
                            <input
                                required
                                maxLength={255}
                                value={name}
                                onChange={(event) => setName(event.target.value)}
                                className="mt-1 w-full rounded-lg border border-slate-300 p-2.5"
                            />
                        </label>
                        <label className="text-sm font-medium">
                            Description
                            <input
                                maxLength={2000}
                                value={description}
                                onChange={(event) => setDescription(event.target.value)}
                                className="mt-1 w-full rounded-lg border border-slate-300 p-2.5"
                            />
                        </label>
                    </div>
                    <button
                        disabled={create.isPending}
                        className="mt-4 rounded-lg bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
                    >
                        {create.isPending ? 'Creating…' : 'Create product'}
                    </button>
                    {create.error && <p className="mt-3 text-sm text-red-700">{create.error.message}</p>}
                </form>
            )}

            <div className="mt-5">
                <DataTable<Product>
                    rows={query.data ?? []}
                    columns={[
                        { key: 'sku', header: 'SKU', render: (product) => product.sku },
                        { key: 'name', header: 'Name', render: (product) => product.name },
                        { key: 'description', header: 'Description', render: (product) => product.description || '—' },
                        { key: 'active', header: 'Active', render: (product) => product.active ? 'Yes' : 'No' }
                    ]}
                    keyFn={(product) => product.id}
                    loading={query.isLoading}
                    error={query.error?.message}
                    onRetry={() => query.refetch()}
                    emptyMessage="No products found."
                />
            </div>

            {message && <Toast message={message} onClose={() => setMessage('')} />}
        </div>
    );
}
