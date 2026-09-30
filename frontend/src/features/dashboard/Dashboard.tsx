import { useQuery } from '@tanstack/react-query';
import { batchesApi, dashboardApi } from '../../api';
import { DataTable, ErrorState, ExpiryIndicator, StatusBadge } from '../../components/ui';
import type { Batch } from '../../types';

export default function Dashboard() {
    const summary = useQuery({ queryKey: ['summary'], queryFn: dashboardApi.summary });
    const batches = useQuery({ queryKey: ['batches'], queryFn: () => batchesApi.list() });

    if (summary.isError) {
        return (
            <div>
                <h1 className="text-2xl font-bold text-slate-900">Dashboard</h1>
                <div className="mt-5">
                    <ErrorState message={summary.error.message} onRetry={() => summary.refetch()} />
                </div>
            </div>
        );
    }

    const data = summary.data;

    const cards = [
        ['Products', data?.totalProducts],
        ['Batches', data?.totalBatches],
        ['Available units', data?.totalAvailableUnits],
        ['Reserved units', data?.reservedUnits],
        ['Near expiry · 7 days', data?.nearExpiry7Days],
        ['Near expiry · 30 days', data?.nearExpiry30Days],
        ['Expired batches', data?.expiredBatches]
    ] as const;

    return (
        <div>
            <h1 className="text-2xl font-bold text-slate-900">Dashboard</h1>
            <p className="mt-1 text-sm text-slate-500">Live warehouse inventory overview.</p>

            <div className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                {cards.map(([label, value]) => (
                    <div key={label} className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
                        <p className="text-sm text-slate-500">{label}</p>
                        <p className="mt-2 text-3xl font-bold text-slate-900">
                            {summary.isLoading ? '—' : value ?? '—'}
                        </p>
                    </div>
                ))}
            </div>

            <section className="mt-8">
                <h2 className="mb-3 text-lg font-bold text-slate-900">Stock & expiry</h2>
                <DataTable<Batch>
                    rows={(batches.data ?? []).filter((batch) => batch.nearExpiry30 || batch.expired)}
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
                        { key: 'available', header: 'Available', render: (batch) => batch.availableQuantity },
                        { key: 'reserved', header: 'Reserved', render: (batch) => batch.reservedQuantity },
                        {
                            key: 'status',
                            header: 'Status',
                            render: (batch) => (
                                <StatusBadge
                                    status={batch.expired ? 'EXPIRED' : batch.nearExpiry7 ? 'NEAR EXPIRY' : 'OK'}
                                />
                            )
                        }
                    ]}
                    keyFn={(batch) => batch.id}
                    loading={batches.isLoading}
                    error={batches.error?.message}
                    onRetry={() => batches.refetch()}
                    emptyMessage="No near-expiry batches."
                />
            </section>
        </div>
    );
}
