import { FormEvent, useState } from 'react';
import { authApi } from '../../api/client';

export default function Login({ onLogin }: { onLogin: () => void }) {
    const [username, setUsername] = useState('staff');
    const [password, setPassword] = useState('password');
    const [error, setError] = useState('');
    const [busy, setBusy] = useState(false);

    async function submit(event: FormEvent<HTMLFormElement>) {
        event.preventDefault();
        setBusy(true);
        setError('');

        try {
            const response = await authApi.login(username.trim(), password);
            localStorage.setItem('accessToken', response.accessToken);
            localStorage.setItem('role', response.user.role);
            onLogin();
        } catch (reason) {
            setError(reason instanceof Error ? reason.message : 'Login failed');
        } finally {
            setBusy(false);
        }
    }

    return (
        <main className="grid min-h-screen place-items-center bg-slate-950 p-4">
            <form
                onSubmit={submit}
                className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-7 shadow-2xl"
            >
                <div>
                    <p className="text-sm font-semibold uppercase tracking-wider text-blue-600">Warehouse</p>
                    <h1 className="mt-1 text-3xl font-bold text-slate-900">FEFO Inventory</h1>
                    <p className="mt-2 text-sm text-slate-500">Sign in to manage inventory and reservations.</p>
                </div>

                {error && (
                    <div role="alert" className="mt-5 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
                        {error}
                    </div>
                )}

                <label className="mt-6 block text-sm font-medium text-slate-700">
                    Username
                    <input
                        required
                        autoComplete="username"
                        value={username}
                        onChange={(event) => setUsername(event.target.value)}
                        className="mt-1 w-full rounded-lg border border-slate-300 p-2.5 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
                    />
                </label>

                <label className="mt-4 block text-sm font-medium text-slate-700">
                    Password
                    <input
                        required
                        type="password"
                        autoComplete="current-password"
                        value={password}
                        onChange={(event) => setPassword(event.target.value)}
                        className="mt-1 w-full rounded-lg border border-slate-300 p-2.5 outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
                    />
                </label>

                <button
                    disabled={busy}
                    className="mt-6 w-full rounded-lg bg-slate-900 p-2.5 font-semibold text-white hover:bg-slate-800 disabled:opacity-50"
                >
                    {busy ? 'Signing in…' : 'Sign in'}
                </button>

                <div className="mt-5 rounded-lg bg-slate-50 p-3 text-xs text-slate-500">
                    <p className="font-semibold text-slate-700">Development accounts</p>
                    <p className="mt-1">staff / password</p>
                    <p>admin / password</p>
                </div>
            </form>
        </main>
    );
}
