import { BrowserRouter, Navigate, NavLink, Route, Routes, useNavigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { setUnauthorizedHandler } from './api/client';
import Login from './features/auth/Login';
import Dashboard from './features/dashboard/Dashboard';
import Products from './features/products/Products';
import Batches from './features/batches/Batches';
import Reservations from './features/reservations/Reservations';
import AuditLog from './features/audit/AuditLog';
import Benchmark from './features/benchmark/Benchmark';
import { ErrorBoundary, Layout } from './components/ui';

const queryClient = new QueryClient({
    defaultOptions: {
        queries: {
            staleTime: 10_000,
            retry: 1
        }
    }
});

function ProtectedApp() {
    const navigate = useNavigate();
    const [authenticated, setAuthenticated] = useState(
        () => Boolean(localStorage.getItem('accessToken'))
    );
    const role = localStorage.getItem('role');

    useEffect(() => {
        setUnauthorizedHandler(() => {
            localStorage.removeItem('accessToken');
            localStorage.removeItem('role');
            setAuthenticated(false);
            navigate('/login', { replace: true });
        });
    }, [navigate]);

    if (!authenticated) {
        return <Navigate to="/login" replace />;
    }

    const logout = () => {
        localStorage.removeItem('accessToken');
        localStorage.removeItem('role');
        queryClient.clear();
        setAuthenticated(false);
        navigate('/login', { replace: true });
    };

    const links = [
        ['Dashboard', '/dashboard'],
        ['Products', '/products'],
        ['Batches', '/batches'],
        ['Reservations', '/reservations'],
        ...(role === 'ADMIN' ? [['Benchmark', '/benchmark'], ['Audit Log', '/audit-log']] : [])
    ];

    return (
        <Layout onLogout={logout}>
            <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
                <nav className="flex flex-wrap gap-2" aria-label="Primary">
                    {links.map(([label, href]) => (
                        <NavLink
                            key={href}
                            to={href}
                            className={({ isActive }) =>
                                `rounded-lg px-3 py-2 text-sm font-medium transition ${
                                    isActive
                                        ? 'bg-slate-900 text-white'
                                        : 'bg-white text-slate-700 hover:bg-slate-100'
                                }`
                            }
                        >
                            {label}
                        </NavLink>
                    ))}
                </nav>
                <span className="rounded-full bg-slate-200 px-3 py-1 text-xs font-semibold text-slate-700">
                    {role ?? 'USER'}
                </span>
            </div>

            <Routes>
                <Route path="/dashboard" element={<Dashboard />} />
                <Route path="/products" element={<Products />} />
                <Route path="/batches" element={<Batches />} />
                <Route path="/reservations" element={<Reservations />} />
                <Route path="/audit-log" element={<AuditLog />} />
                <Route path="/benchmark" element={<Benchmark />} />
                <Route path="*" element={<Navigate to="/dashboard" replace />} />
            </Routes>
        </Layout>
    );
}

function App() {
    const [authenticated, setAuthenticated] = useState(
        () => Boolean(localStorage.getItem('accessToken'))
    );

    return (
        <QueryClientProvider client={queryClient}>
            <BrowserRouter>
                <ErrorBoundary>
                    {authenticated ? (
                        <ProtectedApp />
                    ) : (
                        <Routes>
                            <Route path="/login" element={<Login onLogin={() => setAuthenticated(true)} />} />
                            <Route path="*" element={<Navigate to="/login" replace />} />
                        </Routes>
                    )}
                </ErrorBoundary>
            </BrowserRouter>
        </QueryClientProvider>
    );
}

export default App;
