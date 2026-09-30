import React, { ReactNode, useEffect, useState } from 'react';

export function StatusBadge({ status }: { status: string }) {
    const normalized = status.toUpperCase();
    const styles: Record<string, string> = {
        RESERVED: 'bg-blue-100 text-blue-800',
        CONFIRMED: 'bg-emerald-100 text-emerald-800',
        CANCELLED: 'bg-slate-100 text-slate-700',
        EXPIRED: 'bg-red-100 text-red-800',
        'NEAR EXPIRY': 'bg-orange-100 text-orange-800',
        OK: 'bg-emerald-100 text-emerald-800',
        ACTIVE: 'bg-emerald-100 text-emerald-800'
    };

    return (
        <span
            className={`inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ${styles[normalized] ?? 'bg-slate-100 text-slate-700'}`}
            aria-label={`Status ${status}`}
        >
            {status}
        </span>
    );
}

export function ExpiryIndicator({
    date,
    near7,
    near30,
    expired
}: {
    date: string;
    near7?: boolean;
    near30?: boolean;
    expired?: boolean;
}) {
    let label = 'Healthy';
    if (expired) label = 'Expired';
    else if (near7) label = 'Expires within 7 days';
    else if (near30) label = 'Expires within 30 days';

    return (
        <span
            title={date}
            className={`text-sm ${
                expired
                    ? 'font-bold text-red-700'
                    : near7
                        ? 'font-bold text-orange-700'
                        : near30
                            ? 'font-semibold text-amber-700'
                            : 'text-slate-600'
            }`}
            aria-label={label}
        >
            {label} · {date}
        </span>
    );
}

export function Skeleton({ className = 'h-5 w-full' }: { className?: string }) {
    return (
        <div
            className={`animate-pulse rounded bg-slate-200 ${className}`}
            aria-hidden="true"
        />
    );
}

export function EmptyState({ message = 'No records found' }: { message?: string }) {
    return (
        <div className="rounded-xl border border-dashed border-slate-300 bg-white p-8 text-center text-slate-500">
            {message}
        </div>
    );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
    return (
        <div role="alert" className="rounded-xl border border-red-200 bg-red-50 p-4 text-red-800">
            <span>{message}</span>
            {onRetry && (
                <button className="ml-3 font-medium underline" onClick={onRetry}>
                    Retry
                </button>
            )}
        </div>
    );
}

interface DataTableProps<T> {
    rows: T[];
    columns: { key: string; header: string; render: (row: T) => ReactNode }[];
    keyFn: (row: T) => string;
    loading?: boolean;
    error?: string;
    onRetry?: () => void;
    emptyMessage?: string;
}

export function DataTable<T>({
    rows,
    columns,
    keyFn,
    loading,
    error,
    onRetry,
    emptyMessage
}: DataTableProps<T>) {
    if (loading) {
        return (
            <div className="space-y-2">
                {[1, 2, 3, 4].map((i) => (
                    <Skeleton key={i} className="h-12" />
                ))}
            </div>
        );
    }

    if (error) {
        return <ErrorState message={error} onRetry={onRetry} />;
    }

    if (!rows.length) {
        return <EmptyState message={emptyMessage} />;
    }

    return (
        <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm">
            <table className="min-w-full text-left text-sm">
                <thead className="bg-slate-50">
                    <tr>
                        {columns.map((column) => (
                            <th key={column.key} scope="col" className="px-4 py-3 font-semibold text-slate-700">
                                {column.header}
                            </th>
                        ))}
                    </tr>
                </thead>
                <tbody>
                    {rows.map((row) => (
                        <tr key={keyFn(row)} className="border-t border-slate-100 hover:bg-slate-50">
                            {columns.map((column) => (
                                <td key={column.key} className="px-4 py-3 text-slate-700">
                                    {column.render(row)}
                                </td>
                            ))}
                        </tr>
                    ))}
                </tbody>
            </table>
        </div>
    );
}

export function ConfirmDialog({
    open,
    title,
    message,
    onConfirm,
    onCancel
}: {
    open: boolean;
    title: string;
    message: string;
    onConfirm: () => void;
    onCancel: () => void;
}) {
    useEffect(() => {
        if (!open) return;

        const handler = (event: KeyboardEvent) => {
            if (event.key === 'Escape') onCancel();
        };

        window.addEventListener('keydown', handler);
        return () => window.removeEventListener('keydown', handler);
    }, [open, onCancel]);

    if (!open) return null;

    return (
        <div className="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4" role="presentation">
            <div
                role="dialog"
                aria-modal="true"
                aria-labelledby="confirm-title"
                className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl"
            >
                <h2 id="confirm-title" className="text-lg font-bold text-slate-900">
                    {title}
                </h2>
                <p className="mt-2 text-slate-600">{message}</p>
                <div className="mt-6 flex justify-end gap-3">
                    <button className="rounded-lg border border-slate-300 px-4 py-2" onClick={onCancel}>
                        Cancel
                    </button>
                    <button className="rounded-lg bg-slate-900 px-4 py-2 text-white" onClick={onConfirm}>
                        Confirm
                    </button>
                </div>
            </div>
        </div>
    );
}

export function Toast({ message, onClose }: { message: string; onClose: () => void }) {
    useEffect(() => {
        const timer = setTimeout(onClose, 4000);
        return () => clearTimeout(timer);
    }, [onClose]);

    return (
        <div role="status" aria-live="polite" className="fixed bottom-4 right-4 z-50 rounded-xl bg-slate-900 px-4 py-3 text-white shadow-lg">
            {message}
            <button className="ml-4" onClick={onClose} aria-label="Close notification">
                ×
            </button>
        </div>
    );
}

interface ErrorBoundaryProps {
    children: ReactNode;
}

interface ErrorBoundaryState {
    error: Error | null;
}

export class ErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
    state: ErrorBoundaryState = { error: null };

    static getDerivedStateFromError(error: Error): ErrorBoundaryState {
        return { error };
    }

    render() {
        if (this.state.error) {
            return (
                <div className="m-8 rounded-xl border border-red-200 bg-red-50 p-6" role="alert">
                    <h1 className="font-bold text-red-900">Something went wrong</h1>
                    <p className="mt-2 text-red-800">{this.state.error.message}</p>
                </div>
            );
        }

        return this.props.children;
    }
}

export function HoldCountdown({ expiresAt }: { expiresAt: string }) {
    const [left, setLeft] = useState(() => Math.max(0, new Date(expiresAt).getTime() - Date.now()));

    useEffect(() => {
        const interval = setInterval(() => {
            setLeft(Math.max(0, new Date(expiresAt).getTime() - Date.now()));
        }, 1000);

        return () => clearInterval(interval);
    }, [expiresAt]);

    const seconds = Math.floor(left / 1000);

    return (
        <span
            aria-label={`Hold expires in ${seconds} seconds`}
            className={seconds < 60 ? 'font-bold text-red-700' : 'text-slate-600'}
        >
            {Math.floor(seconds / 60)}:{String(seconds % 60).padStart(2, '0')}
        </span>
    );
}

export function Layout({ children, onLogout }: { children: ReactNode; onLogout: () => void }) {
    return (
        <div className="min-h-screen bg-slate-50">
            <header className="border-b border-slate-200 bg-white">
                <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-4 md:px-6">
                    <a href="/dashboard" className="text-xl font-bold text-slate-900">
                        FEFO Inventory
                    </a>
                    <button onClick={onLogout} className="rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm font-medium hover:bg-slate-50">
                        Logout
                    </button>
                </div>
            </header>
            <main className="mx-auto max-w-7xl p-4 md:p-6">{children}</main>
        </div>
    );
}
